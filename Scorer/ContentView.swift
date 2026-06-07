import SwiftUI
import Combine
import Foundation
import UIKit

// MARK: - Models

struct Turn: Identifiable, Equatable {
    let id = UUID()
    let entered: Int
    let before: Int
    let after: Int
    let isBust: Bool
    var finishDarts: Int?
    let createdAt: Date = Date()
}

struct Player: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var remaining: Int
    var turns: [Turn]
}

struct GameAction: Identifiable, Equatable {
    let id = UUID()
    let playerIndex: Int
    let turn: Turn
}

// MARK: - ViewModel

@MainActor
final class GameViewModel: ObservableObject {
    private let playerNamesKey = "players.names"
    private var cancellables = Set<AnyCancellable>()
    private let startScoreKey = "settings.startScore"
    private let gameOutKey = "settings.gameOut"
    private let matchModeKey = "settings.matchMode"
    private let legsKey = "settings.legs"
    private let setsKey = "settings.sets"

    enum Phase: Equatable {
        case setup
        case inGame
        case awaitingFinishDarts(winnerIndex: Int)
        case finished(FinishReason)
    }

    enum FinishReason: Equatable {
        case legWon(winnerIndex: Int)
        case setWon(winnerIndex: Int)
        case matchWon(winnerIndex: Int)
    }

    enum MatchMode: String, CaseIterable, Identifiable, Equatable {
        case firstTo = "First to"
        case bestOf = "Best of"
        var id: String { rawValue }
    }

    enum GameOut: String, CaseIterable, Identifiable, Equatable {
        case straight = "Straight Out"
        case double = "Double Out"
        case master = "Master Out"
        var id: String { rawValue }
    }

    // Settings
    @Published var startScore: Int = 501
    @Published var gameOut: GameOut = .double
    @Published var matchMode: MatchMode = .firstTo
    @Published var legs: Int = 1
    @Published var sets: Int = 1

    // Game State
    @Published var phase: Phase = .setup
    @Published var players: [Player] = [
        Player(name: "Player 1", remaining: 501, turns: []),
        Player(name: "Player 2", remaining: 501, turns: [])
    ]
    @Published var currentPlayerIndex: Int = 0
    @Published private(set) var startingPlayerIndex: Int = 0
    @Published private(set) var legStartingPlayerIndex: Int = 0
    @Published private(set) var legsWon: [Int] = []
    @Published private(set) var setsWon: [Int] = []

    var legsToWinSet: Int {
        switch matchMode {
        case .firstTo: return legs
        case .bestOf: return (legs + 1) / 2
        }
    }

    var setsToWinMatch: Int {
        switch matchMode {
        case .firstTo: return sets
        case .bestOf: return (sets + 1) / 2
        }
    }

    var matchFormatDescription: String {
        let mode = NSLocalizedString(matchMode.rawValue, comment: "Match mode name")
        if sets > 1 {
            let format = NSLocalizedString("%@ %lld Sets, %lld Legs", comment: "Match format description with mode, sets count, legs count")
            return String(format: format, mode, sets, legs)
        } else if legs > 1 {
            let format = NSLocalizedString("%@ %lld Legs", comment: "Match format description with mode and legs count")
            return String(format: format, mode, legs)
        }
        return ""
    }

    init() {
        let defaults = UserDefaults.standard

        // Load saved settings first so we can initialize players with the correct remaining
        if defaults.object(forKey: startScoreKey) != nil {
            let savedStart = defaults.integer(forKey: startScoreKey)
            self.startScore = savedStart
        }
        if let savedOut = defaults.string(forKey: gameOutKey), let out = GameOut(rawValue: savedOut) {
            self.gameOut = out
        }
        if let savedMode = defaults.string(forKey: matchModeKey), let mode = MatchMode(rawValue: savedMode) {
            self.matchMode = mode
        }
        if defaults.object(forKey: legsKey) != nil {
            let savedLegs = defaults.integer(forKey: legsKey)
            if savedLegs >= 1 { self.legs = savedLegs }
        }
        if defaults.object(forKey: setsKey) != nil {
            let savedSets = defaults.integer(forKey: setsKey)
            if savedSets >= 1 { self.sets = savedSets }
        }

        // Load saved player names if available (preserves order)
        if let savedNames = defaults.array(forKey: playerNamesKey) as? [String], !savedNames.isEmpty {
            self.players = savedNames.map { name in
                Player(name: name, remaining: startScore, turns: [])
            }
        }

        // Persist settings and names whenever they change
        $startScore
            .removeDuplicates()
            .sink { [weak self] value in
                guard let self else { return }
                defaults.set(value, forKey: self.startScoreKey)
            }
            .store(in: &cancellables)

        $gameOut
            .removeDuplicates()
            .sink { [weak self] out in
                guard let self else { return }
                defaults.set(out.rawValue, forKey: self.gameOutKey)
            }
            .store(in: &cancellables)

        $players
            .map { $0.map { $0.name } }
            .removeDuplicates()
            .sink { [weak self] names in
                guard let self else { return }
                defaults.set(names, forKey: self.playerNamesKey)
            }
            .store(in: &cancellables)

        $matchMode
            .removeDuplicates()
            .sink { [weak self] mode in
                guard let self else { return }
                defaults.set(mode.rawValue, forKey: self.matchModeKey)
            }
            .store(in: &cancellables)

        $legs
            .removeDuplicates()
            .sink { [weak self] val in
                guard let self else { return }
                defaults.set(val, forKey: self.legsKey)
            }
            .store(in: &cancellables)

        $sets
            .removeDuplicates()
            .sink { [weak self] val in
                guard let self else { return }
                defaults.set(val, forKey: self.setsKey)
            }
            .store(in: &cancellables)
    }

    // Input
    @Published var scoreInput: String = ""
    var isValidScoreInput: Bool {
        guard let v = Int(scoreInput) else { return false }
        return (0...180).contains(v)
    }

    // Undo
    @Published private(set) var actionStack: [GameAction] = []

    var canStart: Bool {
        let trimmed = players.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
        return players.count >= 1 && !trimmed.contains(where: { $0.isEmpty })
    }

    var currentPlayer: Player {
        players[currentPlayerIndex]
    }

    func addPlayer() {
        players.append(Player(name: "Player \(players.count + 1)", remaining: startScore, turns: []))
    }

    func removePlayers(at offsets: IndexSet) {
        players.remove(atOffsets: offsets)
    }
    
    func movePlayers(from source: IndexSet, to destination: Int) {
        players.move(fromOffsets: source, toOffset: destination)
    }

    func startGame() {
        guard canStart else { return }
        // Rotate starting player only when starting a new match from a completed one
        let nextStart: Int
        if case .finished(.matchWon) = phase {
            nextStart = (startingPlayerIndex + 1) % max(players.count, 1)
        } else {
            nextStart = startingPlayerIndex
        }

        startingPlayerIndex = nextStart
        legStartingPlayerIndex = nextStart
        currentPlayerIndex = nextStart

        // Initialize match state
        legsWon = Array(repeating: 0, count: players.count)
        setsWon = Array(repeating: 0, count: players.count)

        actionStack.removeAll()
        scoreInput = ""
        for i in players.indices {
            players[i].remaining = startScore
            players[i].turns.removeAll()
        }
        phase = .inGame
    }

    func startNewLeg() {
        // Rotate the leg starting player
        legStartingPlayerIndex = (legStartingPlayerIndex + 1) % max(players.count, 1)
        currentPlayerIndex = legStartingPlayerIndex

        // Reset leg-level state only
        actionStack.removeAll()
        scoreInput = ""
        for i in players.indices {
            players[i].remaining = startScore
            players[i].turns.removeAll()
        }
        phase = .inGame
    }

    func startNewSet() {
        // Reset legs counters for the new set
        legsWon = Array(repeating: 0, count: players.count)
        startNewLeg()
    }

    func resetToSetup() {
        phase = .setup
        scoreInput = ""
        actionStack.removeAll()
        currentPlayerIndex = 0
        startingPlayerIndex = 0
        legStartingPlayerIndex = 0
        legsWon = []
        setsWon = []
        for i in players.indices {
            players[i].remaining = startScore
            players[i].turns.removeAll()
        }
    }

    func setStartScore(_ value: Int) {
        startScore = value
        // keep players in sync while in setup
        if phase == .setup {
            for i in players.indices {
                players[i].remaining = startScore
            }
        }
    }

    func appendDigit(_ digit: Int) {
        guard (0...9).contains(digit) else { return }
        if scoreInput == "0" { scoreInput = "" }
        if scoreInput.count >= 3 { return } // max 180
        scoreInput.append(String(digit))
    }

    func deleteDigit() {
        guard !scoreInput.isEmpty else { return }
        scoreInput.removeLast()
    }

    func clearInput() {
        scoreInput = ""
    }


    // MARK: - Stats / Checkouts

    func threeDartAverage(for player: Player) -> Double {
        guard !player.turns.isEmpty else { return 0 }
        let totalScored = player.turns.reduce(0) { partial, t in
            partial + (t.isBust ? 0 : t.entered)
        }
        // Average per turn (per visit). Do not multiply by 3.
        return Double(totalScored) / Double(player.turns.count)
    }

    func averageText(for player: Player) -> String {
        String(format: "%.1f", threeDartAverage(for: player))
    }

    func finishSegments(for remaining: Int) -> [String] {
        guard remaining > 1 else { return [] }
        // Helper to split and prefix single-dart numeric segments with "S"
        func segments(from finish: String) -> [String] {
            return finish
                .components(separatedBy: " – ")
                .map { part in
                    let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                    if Int(trimmed) != nil {
                        return "S\(trimmed)"
                    } else {
                        return trimmed
                    }
                }
        }

        switch gameOut {
        case .double:
            guard let finish = Self.doubleOutFinishes[remaining] else { return [] }
            return segments(from: finish)
        case .master:
            guard let finish = Self.masterOutFinishes[remaining] else { return [] }
            return segments(from: finish)
        case .straight:
            return []
        }
    }

    static let doubleOutFinishes: [Int: String] = [
        2: "D1",
        3: "1 – D1",
        4: "D2",
        5: "1 – D2",
        6: "D3",
        7: "T1 – D2",
        8: "D4",
        9: "1 – D4",
        10: "D5",
        11: "T1 – D4",
        12: "D6",
        13: "1 – D6",
        14: "D7",
        15: "T1 – D6",
        16: "D8",
        17: "1 – D8",
        18: "D9",
        19: "T1 – D8",
        20: "D10",
        21: "1 – D10",
        22: "D11",
        23: "T1 – D10",
        24: "D12",
        25: "5 – D10",
        26: "D13",
        27: "7 – D10",
        28: "D14",
        29: "T3 – D10",
        30: "D15",
        31: "11 – D10",
        32: "D16",
        33: "1 – D16",
        34: "D17",
        35: "3 – D16",
        36: "D18",
        37: "5 – D16",
        38: "D19",
        39: "7 – D16",
        40: "D20",
        41: "1 – D20",
        42: "10 – D16",
        43: "3 – D20",
        44: "12 – D16",
        45: "5 – D20",
        46: "6 – D20",
        47: "7 – D20",
        48: "8 – D20",
        49: "9 – D20",
        50: "Bull",
        51: "11 – D20",
        52: "12 – D20",
        53: "13 – D20",
        54: "14 – D20",
        55: "15 – D20",
        56: "16 – D20",
        57: "17 – D20",
        58: "18 – D20",
        59: "19 – D20",
        60: "20 – D20",
        61: "T11 – D14",
        62: "T10 – D16",
        63: "T13 – D12",
        64: "T16 – D8",
        65: "25 – D20",
        66: "T10 – D18",
        67: "T17 – D8",
        68: "T20 – D4",
        69: "T15 – D12",
        70: "T10 – D20",
        71: "T13 – D16",
        72: "T20 – D6",
        73: "T19 – D8",
        74: "T14 – D16",
        75: "T17 – D12",
        76: "T20 – D8",
        77: "T19 – D10",
        78: "T18 – D12",
        79: "T19 – D11",
        80: "T20 – D10",
        81: "T19 – D12",
        82: "T14 – D20",
        83: "T17 – D16",
        84: "T20 – D12",
        85: "T15 – D20",
        86: "T18 – D16",
        87: "T17 – D18",
        88: "T20 – D14",
        89: "T19 – D16",
        90: "T20 – D15",
        91: "T17 – D20",
        92: "T20 – D16",
        93: "T19 – D18",
        94: "T18 – D20",
        95: "T19 – D19",
        96: "T20 – D18",
        97: "T19 – D20",
        98: "T20 – D19",
        99: "T19 – 10 – D16",
        100: "T20 – D20",
        101: "T20 – 9 – D16",
        102: "T20 – 10 – D16",
        103: "T20 – 3 – D20",
        104: "T20 – 12 – D16",
        105: "T20 – 13 – D16",
        106: "T20 – 14 – D16",
        107: "T19 – 10 – D20",
        108: "T20 – 16 – D16",
        109: "T20 – 9 – D20",
        110: "T20 – 10 – D20",
        111: "T20 – 11 – D20",
        112: "T20 – 12 – D20",
        113: "T20 – 13 – D20",
        114: "T20 – 14 – D20",
        115: "T20 – 15 – D20",
        116: "T20 – 16 – D20",
        117: "T20 – 17 – D20",
        118: "T20 – 18 – D20",
        119: "T20 – 19 – D20",
        120: "T20 – 20 – D20",
        121: "T20 – 11 – Bull",
        122: "T18 – 18 – Bull",
        123: "T20 – T13 – D12",
        124: "T20 – T16 – D8",
        125: "T20 – T15 – D10",
        126: "T19 – 19 – Bull",
        127: "T20 – T17 – D8",
        128: "T18 – T14 – D16",
        129: "T19 – T16 – D12",
        130: "T20 – T20 – D5",
        131: "T20 – T13 – Bull",
        132: "T20 – T16 – D12",
        133: "T20 – T19 – D8",
        134: "T20 – T14 – D16",
        135: "T20 – T17 – D12",
        136: "T20 – T20 – D8",
        137: "T20 – T19 – D10",
        138: "T20 – T18 – D12",
        139: "T20 – T19 – D11",
        140: "T20 – T20 – D10",
        141: "T20 – T19 – D12",
        142: "T20 – T14 – Bull",
        143: "T20 – T17 – D16",
        144: "T20 – T20 – D12",
        145: "T20 – T15 – Bull",
        146: "T20 – T18 – D16",
        147: "T20 – T17 – D18",
        148: "T20 – T20 – D14",
        149: "T20 – T19 – D16",
        150: "T20 – T18 – Bull",
        151: "T20 – T17 – Bull",
        152: "T20 – T20 – D16",
        153: "T20 – T19 – D18",
        154: "T20 – T18 – Bull",
        155: "T20 – T19 – Bull",
        156: "T20 – T20 – D18",
        157: "T20 – T19 – Bull",
        158: "T20 – T20 – D19",
        160: "T20 – T20 – D20",
        161: "T20 – T17 – Bull",
        164: "T20 – T18 – Bull",
        167: "T20 – T19 – Bull",
        170: "T20 – T20 – Bull"
    ]

    static let masterOutFinishes: [Int: String] = [
        180: "T20 – T20 – T20",
        177: "T19 – T20 – T20",
        174: "T20 – T20 – T18",
        171: "T19 – T19 – T19",
        170: "Bull – T20 – T20",
        168: "T20 – T20 – T16",
        167: "Bull – T19 – T20",
        165: "T19 – T19 – T17",
        164: "Bull – T19 – T19",
        162: "T18 – T18 – T18",
        161: "Bull – T17 – T20",
        160: "T20 – T20 – D20",
        159: "T19 – T17 – T17",
        158: "T20 – T20 – D19",
        157: "T19 – T20 – D20",
        156: "T20 – T20 – D18",
        155: "T20 – T19 – D19",
        154: "T19 – T19 – D20",
        153: "T19 – T20 – D18",
        152: "T20 – T20 – D16",
        151: "T17 – T20 – D20",
        150: "T19 – T19 – D18",
        149: "T20 – T19 – D16",
        148: "T20 – T20 – D14",
        147: "T19 – T18 – D18",
        146: "T19 – T19 – D16",
        145: "Bull – T19 – D19",
        144: "T18 – T18 – D18",
        143: "T18 – T19 – D16",
        142: "Bull – T20 – D16",
        141: "T19 – T20 – D12",
        140: "T20 – T20 – D10",
        139: "T19 – Bull – D16",
        138: "T18 – T20 – D12",
        137: "T20 – T17 – D13",
        136: "T19 – T19 – D11",
        135: "T15 – T18 – D18",
        134: "T20 – T14 – D16",
        133: "T19 – T16 – D14",
        132: "T18 – T18 – D12",
        131: "T17 – T20 – D10",
        130: "T19 – T19 – D8",
        129: "T18 – T15 – D15",
        128: "T20 – T20 – D4",
        127: "T19 – T10 – D20",
        126: "T18 – T12 – D18",
        125: "T17 – T14 – D16",
        124: "T16 – T16 – D14",
        123: "T15 – T18 – D12",
        122: "T14 – T20 – D10",
        121: "T19 – T16 – D8",
        120: "T20 – T20",
        119: "T20 – 19 – D20",
        118: "T20 – 18 – D20",
        117: "T19 – T20",
        116: "T20 – 16 – D20",
        115: "T20 – 15 – D20",
        114: "T19 – T19",
        113: "T20 – 17 – D18",
        112: "T18 – 18 – D20",
        111: "T19 – T18",
        110: "Bull – T20",
        109: "T18 – 15 – D20",
        108: "T18 – T18",
        107: "Bull – T19",
        106: "T20 – 6 – D20",
        105: "T19 – T16",
        104: "Bull – T18",
        103: "T19 – 6 – D20",
        102: "T20 – T14",
        101: "Bull – T17",
        100: "T20 – D20",
        99: "T19 – T14",
        98: "T20 – D19",
        97: "T19 – D20",
        96: "T20 – D18",
        95: "T19 – D19",
        94: "T18 – D20",
        93: "T19 – D18",
        92: "T20 – D16",
        91: "T17 – D20",
        90: "T18 – D18",
        89: "T19 – D16",
        88: "T16 – D20",
        87: "T17 – D18",
        86: "T18 – D16",
        85: "T15 – D20",
        84: "T20 – D12",
        83: "T17 – D16",
        82: "Bull – D16",
        81: "T19 – D12",
        80: "T20 – D10",
        79: "T19 – D11",
        78: "T18 – D12",
        77: "T17 – D13",
        76: "T16 – D14",
        75: "T15 – D15",
        74: "T14 – D16",
        73: "T19 – D8",
        72: "T12 – D18",
        71: "T17 – D10",
        70: "T10 – D20",
        69: "T15 – D12",
        68: "T20 – D4",
        67: "T13 – D14",
        66: "T10 – D18",
        65: "T11 – D16",
        64: "T16 – D8",
        63: "T9 – D18",
        62: "T14 – D10",
        61: "T7 – D20",
        60: "T20",
        59: "19 – D20",
        58: "18 – D20",
        57: "T19",
        56: "16 – D20",
        55: "15 – D20",
        54: "T18",
        53: "17 – D18",
        52: "16 – D18",
        51: "T17",
        50: "14 – D18",
        49: "13 – D18",
        48: "T16",
        47: "11 – D18",
        46: "6 – D20"
    ]

    func submitTurn() {
        guard phase == .inGame else { return }
        guard let entered = Int(scoreInput), (0...180).contains(entered) else { return }

        let before = players[currentPlayerIndex].remaining
        let proposed = before - entered

        let isBust = bust(before: before, entered: entered, proposed: proposed)
        let after = isBust ? before : proposed

        let turn = Turn(entered: entered, before: before, after: after, isBust: isBust)
        players[currentPlayerIndex].turns.insert(turn, at: 0)
        players[currentPlayerIndex].remaining = after
        actionStack.append(GameAction(playerIndex: currentPlayerIndex, turn: turn))

        scoreInput = ""

        if after == 0 {
            phase = .awaitingFinishDarts(winnerIndex: currentPlayerIndex)
            return
        }

        // next player
        currentPlayerIndex = (currentPlayerIndex + 1) % players.count
    }

    func undo() {
        guard let last = actionStack.popLast() else { return }

        // restore
        let idx = last.playerIndex
        if let turnIndex = players[idx].turns.firstIndex(of: last.turn) {
            players[idx].turns.remove(at: turnIndex)
        } else {
            // fallback: remove first if not found
            if !players[idx].turns.isEmpty { players[idx].turns.removeFirst() }
        }
        players[idx].remaining = last.turn.before
        currentPlayerIndex = idx
        scoreInput = ""

        // Revert awaiting or finished states
        switch phase {
        case .awaitingFinishDarts:
            phase = .inGame
        case .finished(let reason):
            switch reason {
            case .matchWon(let winnerIndex):
                setsWon[winnerIndex] -= 1
                legsWon[winnerIndex] -= 1
            case .setWon(let winnerIndex):
                setsWon[winnerIndex] -= 1
                legsWon[winnerIndex] -= 1
            case .legWon(let winnerIndex):
                legsWon[winnerIndex] -= 1
            }
            phase = .inGame
        default:
            break
        }
    }

    // MARK: - Finishing Darts

    func confirmFinishDarts(_ count: Int) {
        guard case .awaitingFinishDarts(let winnerIndex) = phase else { return }
        // Set finishDarts on the winning turn (first in the array, since turns are inserted at 0)
        if !players[winnerIndex].turns.isEmpty {
            players[winnerIndex].turns[0].finishDarts = count
        }
        handleLegWon(by: winnerIndex)
    }

    // MARK: - Leg Stats

    func totalDarts(for playerIndex: Int) -> Int {
        let turns = players[playerIndex].turns
        var darts = 0
        for turn in turns {
            if let finish = turn.finishDarts {
                darts += finish
            } else {
                darts += 3
            }
        }
        return darts
    }

    func legAverage(for playerIndex: Int) -> Double {
        let turns = players[playerIndex].turns
        guard !turns.isEmpty else { return 0 }
        let totalScored = turns.reduce(0) { $0 + ($1.isBust ? 0 : $1.entered) }
        return Double(totalScored) / Double(turns.count)
    }

    func legAverageText(for playerIndex: Int) -> String {
        String(format: "%.1f", legAverage(for: playerIndex))
    }

    func topScore(for playerIndex: Int) -> Int {
        players[playerIndex].turns
            .filter { !$0.isBust }
            .map(\.entered)
            .max() ?? 0
    }

    // MARK: - Leg / Set / Match Cascade

    private func handleLegWon(by playerIndex: Int) {
        legsWon[playerIndex] += 1

        if legsWon[playerIndex] >= legsToWinSet {
            handleSetWon(by: playerIndex)
            return
        }

        phase = .finished(.legWon(winnerIndex: playerIndex))
    }

    private func handleSetWon(by playerIndex: Int) {
        setsWon[playerIndex] += 1

        if setsWon[playerIndex] >= setsToWinMatch {
            phase = .finished(.matchWon(winnerIndex: playerIndex))
            return
        }

        phase = .finished(.setWon(winnerIndex: playerIndex))
    }

    // MARK: - Rules

    private func bust(before: Int, entered: Int, proposed: Int) -> Bool {
        // Standard bust: score over, negative, or leaves 1.
        if entered > before { return true }
        if proposed < 0 { return true }
        if proposed == 1 { return true }

        // Double-out (simplified): only allow finishing on a single double or bull.
        if gameOut != .straight && proposed == 0 {
            return !isValidFinish(before: before, entered: entered)
        }

        return false
    }

    private func isValidFinish(before: Int, entered: Int) -> Bool {
        switch gameOut {
        case .straight:
            // Straight out: any exact finish is allowed
            return true
        case .double, .master:
            // Existing double-out validation for now; master logic to be refined later
            if Self.doubleOutFinishes[before] != nil {
                return true
            }
            if before == 50 && entered == 50 { return true }
            if before <= 40, before % 2 == 0, entered == before {
                return true
            }
            return false
        }
    }
}

// MARK: - Haptics

struct Haptics {
    private static let hapticsModeKey = "settings.hapticsMode"

    private static func currentMode() -> String {
        UserDefaults.standard.string(forKey: hapticsModeKey) ?? "medium"
    }

    static func impact() {
        let mode = currentMode()
        guard mode != "off" else { return }

        let style: UIImpactFeedbackGenerator.FeedbackStyle
        switch mode {
        case "light": style = .light
        case "medium": style = .medium
        case "heavy": style = .heavy
        case "soft": style = .soft
        case "rigid": style = .rigid
        default: style = .medium
        }

        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    static func selectionChanged() {
        guard currentMode() != "off" else { return }
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard currentMode() != "off" else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}

struct ThemeApplier {
    static func apply(theme: String) {
        let style: UIUserInterfaceStyle
        switch theme {
        case "light": style = .light
        case "dark": style = .dark
        default: style = .unspecified
        }
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .forEach { scene in
                scene.windows.forEach { $0.overrideUserInterfaceStyle = style }
            }
    }
}

// MARK: - Views

struct ContentView: View {
    @StateObject private var vm = GameViewModel()
    @State private var showSettings = false
    @AppStorage("settings.theme") private var appTheme: String = "system"

    var body: some View {
        NavigationStack {
            switch vm.phase {
            case .setup:
                SetupView(vm: vm, showSettings: $showSettings)
            case .inGame:
                GameView(vm: vm, showSettings: $showSettings)
            case .awaitingFinishDarts(let winnerIndex):
                GameView(vm: vm, showSettings: $showSettings)
                    .overlay {
                        FinishDartsPrompt(
                            winnerName: vm.players[winnerIndex].name,
                            onSelect: { darts in vm.confirmFinishDarts(darts) }
                        )
                    }
            case .finished(let reason):
                GameView(vm: vm, showSettings: $showSettings)
                    .overlay {
                        FinishedOverlay(
                            reason: reason,
                            players: vm.players,
                            legsWon: vm.legsWon,
                            setsWon: vm.setsWon,
                            showSets: vm.sets > 1,
                            showScoreline: vm.legs > 1 || vm.sets > 1,
                            playerDarts: vm.players.indices.map { vm.totalDarts(for: $0) },
                            playerAverage: vm.players.indices.map { vm.legAverageText(for: $0) },
                            playerTopScore: vm.players.indices.map { vm.topScore(for: $0) },
                            onContinue: {
                                switch reason {
                                case .legWon: vm.startNewLeg()
                                case .setWon: vm.startNewSet()
                                case .matchWon: vm.startGame()
                                }
                            },
                            onBackToSetup: { vm.resetToSetup() }
                        )
                    }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear { ThemeApplier.apply(theme: appTheme) }
        .onChange(of: appTheme) { oldValue, newValue in ThemeApplier.apply(theme: newValue) }
    }
}

private struct SetupView: View {
    @ObservedObject var vm: GameViewModel
    @Binding var showSettings: Bool

    var body: some View {
        List {
            Section("Game") {
                Picker("Start", selection: Binding(
                    get: { vm.startScore },
                    set: { vm.setStartScore($0) }
                )) {
                    Text("301").tag(301)
                    Text("501").tag(501)
                    Text("701").tag(701)
                }

                Picker("Game Out", selection: $vm.gameOut) {
                    Text(GameViewModel.GameOut.straight.rawValue).tag(GameViewModel.GameOut.straight)
                    Text(GameViewModel.GameOut.double.rawValue).tag(GameViewModel.GameOut.double)
                    Text(GameViewModel.GameOut.master.rawValue).tag(GameViewModel.GameOut.master)
                }
            }

            Section("Format") {
                Picker("Mode", selection: $vm.matchMode) {
                    ForEach(GameViewModel.MatchMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Stepper("Legs: \(vm.legs)", value: $vm.legs, in: 1...13)
                Stepper("Sets: \(vm.sets)", value: $vm.sets, in: 1...13)
            }

            Section("Players") {
                ForEach($vm.players) { $player in
                    TextField("Name", text: $player.name)
                        .textInputAutocapitalization(.words)
                }
                .onDelete(perform: vm.removePlayers)
                .onMove(perform: vm.movePlayers)
                
                Button("Add Player") {
                    vm.addPlayer()
                }
            }

        }
        .safeAreaInset(edge: .bottom) {
            Button {
                vm.startGame()
            } label: {
                Text("Start Game")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.glassProminent)
            .disabled(!vm.canStart)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .navigationTitle("Scorer 🎯 ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
    }
}

private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("settings.hapticsMode") private var hapticsMode: String = "medium"
    @AppStorage("settings.theme") private var theme: String = "system"
    @AppStorage("settings.language") private var language: String = "system"
    @State private var showRestartAlert = false

    private let hapticOptions: [(title: String, value: String)] = [
        ("Off", "off"),
        ("Light", "light"),
        ("Medium", "medium"),
        ("Heavy", "heavy"),
        ("Soft", "soft"),
        ("Rigid", "rigid")
    ]

    private let languageOptions: [(title: String, value: String)] = [
        ("System", "system"),
        ("English", "en"),
        ("Deutsch", "de")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Haptic Feedback") {
                    Picker("Intensity", selection: $hapticsMode) {
                        ForEach(hapticOptions, id: \.value) { option in
                            Text(option.title).tag(option.value)
                        }
                    }
                }

                Section("Theme") {
                    Picker("Appearance", selection: $theme) {
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                        Text("System").tag("system")
                    }
                    .pickerStyle(.segmented)
                }

                Section("Language") {
                    Picker("Language", selection: Binding(
                        get: { language },
                        set: { newValue in
                            guard newValue != language else { return }
                            language = newValue
                            applyLanguage(newValue)
                            Haptics.selectionChanged()
                            showRestartAlert = true
                        }
                    )) {
                        ForEach(languageOptions, id: \.value) { option in
                            Text(option.title).tag(option.value)
                        }
                    }
                }

                Section("Links") {
                    Link("My Website", destination: URL(string: "https://nickringelmann.com")!)
                    Link("GitHub", destination: URL(string: "https://github.com/seafyre/scorer")!)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Language Changed", isPresented: $showRestartAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The new language will take effect when you restart the app.")
            }
            .onAppear { syncLanguageFromSystem() }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active { syncLanguageFromSystem() }
            }
        }
    }

    private func applyLanguage(_ value: String) {
        let defaults = UserDefaults.standard
        if value == "system" {
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set([value], forKey: "AppleLanguages")
        }
    }

    private func syncLanguageFromSystem() {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let appDefaults = UserDefaults.standard.persistentDomain(forName: bundleID)
        let langs = appDefaults?["AppleLanguages"] as? [String]
        guard let first = langs?.first else {
            language = "system"
            return
        }
        if first.hasPrefix("de") {
            language = "de"
        } else if first.hasPrefix("en") {
            language = "en"
        } else {
            language = "system"
        }
    }
}

private struct GameView: View {
    @ObservedObject var vm: GameViewModel
    @Binding var showSettings: Bool
    @State private var showQuitConfirm = false

    private var gameOutTitle: String {
        vm.gameOut.rawValue
    }

    private var inGameTitle: String {
        "\(vm.startScore) (\(gameOutTitle))"
    }

    var body: some View {
        VStack(spacing: 18) {
            if !vm.matchFormatDescription.isEmpty {
                Text(vm.matchFormatDescription)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            scoreTiles

            Spacer()

            scoreInputDisplay

            keypad
        }
        .padding(.horizontal)
        .padding(.top)
        .background { Color(UIColor.systemGroupedBackground).ignoresSafeArea() }
        .navigationTitle(inGameTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showQuitConfirm = true
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Close Game")
            }
        }
        .alert("Quit Game?", isPresented: $showQuitConfirm) {
            Button("Quit", role: .destructive) {
                vm.resetToSetup()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will end the current game & return to main page.")
        }
    }

    // MARK: - Top Tiles

    private var scoreTiles: some View {
        Group {
            if vm.players.count <= 2 {
                HStack(spacing: 12) {
                    ForEach(vm.players.indices, id: \.self) { i in
                        playerTile(for: i)
                    }
                }
            } else if vm.players.count <= 4 {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(vm.players.indices, id: \.self) { i in
                        playerTile(for: i)
                    }
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(vm.players.indices, id: \.self) { i in
                                playerTile(for: i)
                                    .containerRelativeFrame(.horizontal, count: 43, span: 20, spacing: 0)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .contentMargins(.horizontal, 16)
                    .padding(.horizontal, -16)
                    .onChange(of: vm.currentPlayerIndex) { _, newIndex in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func playerTile(for i: Int) -> some View {
        let p = vm.players[i]
        let checkoutParts = vm.finishSegments(for: p.remaining)
        let checkoutText = checkoutParts.isEmpty ? nil : checkoutParts.joined(separator: " ")
        return PlayerTile(
            name: p.name,
            averageText: vm.averageText(for: p),
            checkoutText: checkoutText,
            remaining: p.remaining,
            isActive: i == vm.currentPlayerIndex,
            legsWon: i < vm.legsWon.count ? vm.legsWon[i] : 0,
            setsWon: i < vm.setsWon.count ? vm.setsWon[i] : 0,
            showSets: vm.sets > 1,
            showLegs: vm.legs > 1 || vm.sets > 1
        )
        .id(i)
    }

    private var scoreInputDisplay: some View {
        HStack {
            Spacer(minLength: 0)
            Text(vm.scoreInput.isEmpty ? "—" : vm.scoreInput)
                .monospacedDigit()
                .font(.system(size: 34, weight: .semibold))
            Spacer(minLength: 0)
        }
        .overlay(alignment: .trailing) {
            KeyIconButton(
                systemName: "delete.left",
                background: Color(.systemGray3),
                fillsWidth: false
            ) {
                Haptics.selectionChanged()
                vm.deleteDigit()
            }
            .disabled(vm.scoreInput.isEmpty)
            .accessibilityLabel("Delete last digit")
            .onLongPressGesture {
                Haptics.notify(.warning)
                vm.clearInput()
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: - Keypad

    private let keyHeight: CGFloat = 48
    private let keySpacing: CGFloat = 10

    private var keypad: some View {
        VStack(spacing: keySpacing) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: keySpacing), count: 3), spacing: keySpacing) {
                ForEach([1,2,3,4,5,6,7,8,9], id: \.self) { n in
                    KeyButton(title: "\(n)", height: keyHeight) {
                        Haptics.impact()
                        vm.appendDigit(n)
                    }
                }
            }

            HStack(spacing: keySpacing) {
                KeyIconButton(
                    systemName: "arrow.uturn.left",
                    background: .red,
                    height: keyHeight
                ) {
                    Haptics.impact()
                    vm.undo()
                }
                .disabled(vm.actionStack.isEmpty)

                KeyButton(title: "0", height: keyHeight) {
                    Haptics.impact()
                    vm.appendDigit(0)
                }

                KeyIconButton(
                    systemName: "chevron.right",
                    background: .blue,
                    height: keyHeight
                ) {
                    Haptics.impact()
                    vm.submitTurn()
                }
                .disabled(!vm.isValidScoreInput)
            }
        }
    }
}

private struct PlayerTile: View {
    let name: String
    let averageText: String
    let checkoutText: String?
    let remaining: Int
    let isActive: Bool
    let legsWon: Int
    let setsWon: Int
    let showSets: Bool
    let showLegs: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top) {
                Text(name)
                    .font(.headline)
                Spacer()
                Text("Ø\(averageText)")
                    .font(.subheadline)
                    .foregroundStyle(isActive ? Color.primary.opacity(0.85) : Color.secondary)
            }

            if showSets {
                Text("Sets: \(setsWon) · Legs: \(legsWon)")
                    .font(.subheadline)
                    .foregroundStyle(isActive ? Color.primary.opacity(0.85) : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if showLegs {
                Text("Legs: \(legsWon)")
                    .font(.subheadline)
                    .foregroundStyle(isActive ? Color.primary.opacity(0.85) : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(checkoutText ?? " ")
                .font(.subheadline)
                .foregroundStyle(isActive ? Color.primary.opacity(0.85) : Color.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            Text("\(remaining)")
                .monospacedDigit()
                .font(.system(size: 44, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(UIColor.secondarySystemGroupedBackground))
            }
        }
        .foregroundStyle(.primary)
    }
}

private struct KeyButton: View {
    let title: String
    let height: CGFloat
    let action: () -> Void

    init(title: String, height: CGFloat = 56, action: @escaping () -> Void) {
        self.title = title
        self.height = height
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .monospacedDigit()
                .font(.system(size: 28, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.glass)
    }
}

private struct KeyIconButton: View {
    let systemName: String
    let background: Color
    let fillsWidth: Bool
    let height: CGFloat
    let action: () -> Void

    init(systemName: String, background: Color, fillsWidth: Bool = true, height: CGFloat = 56, action: @escaping () -> Void) {
        self.systemName = systemName
        self.background = background
        self.fillsWidth = fillsWidth
        self.height = height
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .semibold))
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .frame(width: fillsWidth ? nil : 56, height: height)
                .contentShape(Rectangle())
        }
        .tint(background)
        .buttonStyle(.glassProminent)
    }
}

private struct FinishDartsPrompt: View {
    let winnerName: String
    let onSelect: (Int) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()

            VStack(spacing: 14) {
                Text("Finishing Dart?")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text(winnerName)
                    .font(.largeTitle)
                    .fontWeight(.semibold)

                HStack(spacing: 12) {
                    ForEach([1, 2, 3], id: \.self) { n in
                        Button {
                            onSelect(n)
                        } label: {
                            Text(n == 1 ? "1st" : n == 2 ? "2nd" : "3rd")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(18)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding()
        }
    }
}

private struct FinishedOverlay: View {
    let reason: GameViewModel.FinishReason
    let players: [Player]
    let legsWon: [Int]
    let setsWon: [Int]
    let showSets: Bool
    let showScoreline: Bool
    let playerDarts: [Int]
    let playerAverage: [String]
    let playerTopScore: [Int]
    let onContinue: () -> Void
    let onBackToSetup: () -> Void

    private var winnerIndex: Int {
        switch reason {
        case .legWon(let i), .setWon(let i), .matchWon(let i): return i
        }
    }

    private var headline: String {
        switch reason {
        case .legWon: return "Leg Won"
        case .setWon: return "Set Won"
        case .matchWon: return "Match Winner"
        }
    }

    private var continueLabel: String {
        switch reason {
        case .legWon: return "Next Leg"
        case .setWon: return "Next Set"
        case .matchWon: return "New Match"
        }
    }

    private var winnerDisplayName: String {
        let name = players[winnerIndex].name
        switch reason {
        case .matchWon: return "🏆 \(name)"
        case .legWon, .setWon: return name
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()

            VStack(spacing: 16) {
                Text(headline)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text(winnerDisplayName)
                    .font(.largeTitle)
                    .fontWeight(.semibold)

                // Leg stats for all players
                VStack(spacing: 12) {
                    ForEach(players.indices, id: \.self) { i in
                        VStack(spacing: 6) {
                            if players.count > 1 {
                                Text(players[i].name)
                                    .font(.subheadline)
                                    .fontWeight(i == winnerIndex ? .semibold : .regular)
                                    .foregroundStyle(i == winnerIndex ? .primary : .secondary)
                            }
                            HStack(spacing: 0) {
                                statItem(label: "Darts", value: "\(playerDarts[i])")
                                Divider().frame(height: 32)
                                statItem(label: "Average", value: playerAverage[i])
                                Divider().frame(height: 32)
                                statItem(label: "Top Score", value: "\(playerTopScore[i])")
                            }
                        }
                    }
                }
                .padding(.vertical, 4)

                // Buttons
                VStack(spacing: 10) {
                    Button {
                        onContinue()
                    } label: {
                        Text(continueLabel)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        onBackToSetup()
                    } label: {
                        Text("Quit")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.bordered)
                }

                // Overall scoreline (only for multi-leg/set)
                if showScoreline {
                    Divider()

                    VStack(spacing: 4) {
                        ForEach(players.indices, id: \.self) { i in
                            HStack {
                                Text(players[i].name)
                                    .fontWeight(i == winnerIndex ? .semibold : .regular)
                                Spacer()
                                if showSets {
                                    Text("\(setsWon[i])S \(legsWon[i])L")
                                        .monospacedDigit()
                                } else {
                                    Text("\(legsWon[i]) Legs")
                                        .monospacedDigit()
                                }
                            }
                            .font(.subheadline)
                            .foregroundStyle(i == winnerIndex ? .primary : .secondary)
                        }
                    }
                }
            }
            .padding(18)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding()
        }
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ContentView()
}
