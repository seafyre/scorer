import CloudKit
import Combine
import Foundation

struct GameSettings: Equatable {
    var startScore: Int
    var gameOut: GameViewModel.GameOut
    var matchMode: GameViewModel.MatchMode
    var legs: Int
    var sets: Int
}

struct OnlineGameState: Codable, Equatable {
    var version: Int
    var currentPlayerIndex: Int
    var startingPlayerIndex: Int
    var legStartingPlayerIndex: Int
    var players: [OnlinePlayerState]
    var legsWon: [Int]
    var setsWon: [Int]
    var phaseTag: String
    var actionStack: [OnlineGameAction]
}

struct OnlinePlayerState: Codable, Equatable {
    var name: String
    var remaining: Int
    var turns: [OnlineTurn]
}

struct OnlineTurn: Codable, Equatable {
    var entered: Int
    var before: Int
    var after: Int
    var isBust: Bool
    var finishDarts: Int?
    var createdAt: Date
}

struct OnlineGameAction: Codable, Equatable {
    var playerIndex: Int
    var turn: OnlineTurn
}

extension Notification.Name {
    static let cloudKitRemoteNotification = Notification.Name("cloudKitRemoteNotification")
}

@MainActor
final class OnlineGameManager: ObservableObject {
    enum SessionRole: Equatable {
        case host
        case guest
    }

    enum OnlineStatus: Equatable {
        case idle
        case hosting(code: String)
        case joining
        case active(role: SessionRole)
        case error(String)
    }

    @Published var status: OnlineStatus = .idle
    @Published var remotePlayerName: String = ""
    @Published var rematchRequested = false

    private let publicDB = CKContainer.default().publicCloudDatabase
    private var sessionRecordID: CKRecord.ID?
    private var lobbyCode: String?
    private var latestVersion = 0
    private weak var vm: GameViewModel?

    init() {
        NotificationCenter.default.addObserver(
            forName: .cloudKitRemoteNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshFromCloud()
            }
        }
    }

    func attach(to vm: GameViewModel) {
        self.vm = vm
    }

    func createSession(hostName: String, settings: GameSettings) async throws -> String {
        let code = try await uniqueLobbyCode()
        let record = CKRecord(recordType: "GameSession")
        record["lobbyCode"] = code as CKRecordValue
        record["hostName"] = hostName as CKRecordValue
        record["status"] = "waiting" as CKRecordValue
        record["startScore"] = settings.startScore as CKRecordValue
        record["gameOut"] = settings.gameOut.rawValue as CKRecordValue
        record["matchMode"] = settings.matchMode.rawValue as CKRecordValue
        record["legs"] = settings.legs as CKRecordValue
        record["sets"] = settings.sets as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue

        let saved = try await publicDB.save(record)
        sessionRecordID = saved.recordID
        lobbyCode = code
        status = .hosting(code: code)
        try await subscribeToChanges(lobbyCode: code)
        return code
    }

    func joinSession(code: String, guestName: String) async throws {
        status = .joining
        let record = try await fetchSession(lobbyCode: code)
        guard (record["status"] as? String) == "waiting" else {
            throw OnlineGameError.sessionUnavailable
        }

        record["guestName"] = guestName as CKRecordValue
        record["status"] = "active" as CKRecordValue
        let saved = try await publicDB.save(record)
        sessionRecordID = saved.recordID
        lobbyCode = code.uppercased()
        remotePlayerName = saved["hostName"] as? String ?? "Host"
        status = .active(role: .guest)
        applySettings(from: saved, localName: guestName, remoteName: remotePlayerName, localPlayerIndex: 1)
        try await subscribeToChanges(lobbyCode: code.uppercased())
        if let state = decodeState(from: saved) {
            vm?.applyOnlineState(state)
        }
    }

    func startHostedGame(hostName: String) async throws {
        guard let vm, let recordID = sessionRecordID else { return }
        let record = try await publicDB.record(for: recordID)
        guard let guestName = record["guestName"] as? String, !guestName.isEmpty else {
            throw OnlineGameError.waitingForGuest
        }

        remotePlayerName = guestName
        status = .active(role: .host)
        vm.configureOnlineMatch(
            localName: hostName,
            remoteName: guestName,
            localPlayerIndex: 0,
            settings: currentSettings
        )
        vm.startOnlineMatch()
    }

    func publishGameState(_ state: OnlineGameState) async throws {
        guard let recordID = sessionRecordID else { return }
        var state = state
        state.version = max(state.version, latestVersion + 1)
        let record = try await publicDB.record(for: recordID)
        record["gameStateData"] = try JSONEncoder().encode(state) as CKRecordValue
        record["status"] = state.phaseTag.hasPrefix("finished:match") ? "finished" as CKRecordValue : "active" as CKRecordValue
        record["rematchRequested"] = 0 as CKRecordValue
        _ = try await publicDB.save(record)
        latestVersion = state.version
        rematchRequested = false
    }

    func requestRematch() async throws {
        guard let recordID = sessionRecordID else { return }
        let record = try await publicDB.record(for: recordID)
        record["rematchRequested"] = 1 as CKRecordValue
        _ = try await publicDB.save(record)
    }

    func disconnect() {
        sessionRecordID = nil
        lobbyCode = nil
        latestVersion = 0
        remotePlayerName = ""
        rematchRequested = false
        status = .idle
    }

    func refreshFromCloud() async {
        guard let recordID = sessionRecordID else { return }
        do {
            let record = try await publicDB.record(for: recordID)
            if let guestName = record["guestName"] as? String, !guestName.isEmpty, remotePlayerName != guestName {
                remotePlayerName = guestName
            }
            if case .hosting = status, record["status"] as? String == "active" {
                status = .hosting(code: lobbyCode ?? "")
            }
            rematchRequested = (record["rematchRequested"] as? Int ?? 0) == 1
            if let state = decodeState(from: record), state.version > latestVersion {
                latestVersion = state.version
                vm?.applyOnlineState(state)
            }
        } catch {
            status = .error(error.localizedDescription)
            vm?.resetToSetup()
        }
    }

    private var currentSettings: GameSettings {
        guard let vm else {
            return GameSettings(startScore: 501, gameOut: .double, matchMode: .firstTo, legs: 1, sets: 1)
        }
        return GameSettings(startScore: vm.startScore, gameOut: vm.gameOut, matchMode: vm.matchMode, legs: vm.legs, sets: vm.sets)
    }

    private func applySettings(from record: CKRecord, localName: String, remoteName: String, localPlayerIndex: Int) {
        let settings = GameSettings(
            startScore: record["startScore"] as? Int ?? 501,
            gameOut: GameViewModel.GameOut(rawValue: record["gameOut"] as? String ?? "") ?? .double,
            matchMode: GameViewModel.MatchMode(rawValue: record["matchMode"] as? String ?? "") ?? .firstTo,
            legs: record["legs"] as? Int ?? 1,
            sets: record["sets"] as? Int ?? 1
        )
        vm?.configureOnlineMatch(
            localName: localName,
            remoteName: remoteName,
            localPlayerIndex: localPlayerIndex,
            settings: settings
        )
    }

    private func fetchSession(lobbyCode: String) async throws -> CKRecord {
        let predicate = NSPredicate(format: "lobbyCode == %@", lobbyCode.uppercased())
        let query = CKQuery(recordType: "GameSession", predicate: predicate)
        let result: (matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)], queryCursor: CKQueryOperation.Cursor?)
        do {
            result = try await publicDB.records(matching: query, resultsLimit: 1)
        } catch let error as CKError where error.code == .unknownItem {
            throw OnlineGameError.sessionNotFound
        }
        guard let match = result.matchResults.first else {
            throw OnlineGameError.sessionNotFound
        }
        return try match.1.get()
    }

    private func uniqueLobbyCode() async throws -> String {
        for _ in 0..<12 {
            let code = Self.generateLobbyCode()
            do {
                _ = try await fetchSession(lobbyCode: code)
            } catch OnlineGameError.sessionNotFound {
                return code
            } catch {
                throw error
            }
        }
        throw OnlineGameError.couldNotCreateCode
    }

    private func subscribeToChanges(lobbyCode: String) async throws {
        let subscriptionID = "game-session-\(lobbyCode)"
        let predicate = NSPredicate(format: "lobbyCode == %@", lobbyCode)
        let subscription = CKQuerySubscription(
            recordType: "GameSession",
            predicate: predicate,
            subscriptionID: subscriptionID,
            options: [.firesOnRecordUpdate]
        )
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try? await publicDB.deleteSubscription(withID: subscriptionID)
        _ = try await publicDB.save(subscription)
    }

    private func decodeState(from record: CKRecord) -> OnlineGameState? {
        guard let data = record["gameStateData"] as? Data else { return nil }
        return try? JSONDecoder().decode(OnlineGameState.self, from: data)
    }

    private static func generateLobbyCode() -> String {
        let characters = Array("0123456789")
        return String((0..<6).compactMap { _ in characters.randomElement() })
    }
}

enum OnlineGameError: LocalizedError {
    case sessionNotFound
    case sessionUnavailable
    case couldNotCreateCode
    case waitingForGuest

    var errorDescription: String? {
        switch self {
        case .sessionNotFound:
            return "No lobby was found for that code."
        case .sessionUnavailable:
            return "That lobby is no longer available."
        case .couldNotCreateCode:
            return "Could not create a unique lobby code. Try again."
        case .waitingForGuest:
            return "Waiting for an opponent to join."
        }
    }
}
