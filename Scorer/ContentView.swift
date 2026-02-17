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
    enum Phase: Equatable {
        case setup
        case inGame
        case finished(winnerIndex: Int)
    }

    // Settings
    @Published var startScore: Int = 501
    @Published var doubleOut: Bool = false

    // Game State
    @Published var phase: Phase = .setup
    @Published var players: [Player] = [
        Player(name: "Player 1", remaining: 501, turns: []),
        Player(name: "Player 2", remaining: 501, turns: [])
    ]
    @Published var currentPlayerIndex: Int = 0

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

    func startGame() {
        guard canStart else { return }
        actionStack.removeAll()
        scoreInput = ""
        currentPlayerIndex = 0
        for i in players.indices {
            players[i].remaining = startScore
            players[i].turns.removeAll()
        }
        phase = .inGame
    }

    func resetToSetup() {
        phase = .setup
        scoreInput = ""
        actionStack.removeAll()
        currentPlayerIndex = 0
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
        guard remaining > 1, let finish = Self.doubleOutFinishes[remaining] else { return [] }
        return finish.components(separatedBy: " – ")
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
            phase = .finished(winnerIndex: currentPlayerIndex)
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

        // if we were finished, go back to in-game
        if case .finished = phase {
            phase = .inGame
        }
    }

    // MARK: - Rules

    private func bust(before: Int, entered: Int, proposed: Int) -> Bool {
        // Standard bust: score over, negative, or leaves 1.
        if entered > before { return true }
        if proposed < 0 { return true }
        if proposed == 1 { return true }

        // Double-out (simplified): only allow finishing on a single double or bull.
        if doubleOut && proposed == 0 {
            return !isValidSimpleDoubleOut(before: before, entered: entered)
        }

        return false
    }

    private func isValidSimpleDoubleOut(before: Int, entered: Int) -> Bool {
        // Bull finish
        if before == 50 && entered == 50 { return true }

        // Simple single-dart double finish: remaining must be an even number <= 40
        if before <= 40, before % 2 == 0, entered == before {
            return true
        }

        return false
    }
}

// MARK: - Haptics

struct Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    static func selectionChanged() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}

// MARK: - Views

struct ContentView: View {
    @StateObject private var vm = GameViewModel()

    var body: some View {
        NavigationStack {
            switch vm.phase {
            case .setup:
                SetupView(vm: vm)
            case .inGame:
                GameView(vm: vm)
            case .finished(let winnerIndex):
                GameView(vm: vm)
                    .overlay {
                        FinishedOverlay(
                            winnerName: vm.players[winnerIndex].name,
                            onNewGame: { vm.startGame() },
                            onBackToSetup: { vm.resetToSetup() }
                        )
                    }
            }
        }
    }
}

private struct SetupView: View {
    @ObservedObject var vm: GameViewModel

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

                Toggle("Double-Out (Simplified)", isOn: $vm.doubleOut)
            }

            Section("Players") {
                ForEach(vm.players.indices, id: \.self) { i in
                    TextField("Name", text: $vm.players[i].name)
                        .textInputAutocapitalization(.words)
                }
                .onDelete(perform: vm.removePlayers)

                Button("Add Player") {
                    vm.addPlayer()
                }
            }

            Section {
                Button("Start Game") {
                    vm.startGame()
                }
                .disabled(!vm.canStart)
            }
        }
        .navigationTitle("Darts 501")
    }
}


private struct GameView: View {
    @ObservedObject var vm: GameViewModel
    @State private var showQuitConfirm = false

    private let gridCols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(spacing: 18) {
            scoreTiles

            finishRow

            scoreInputDisplay

            keypad

            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.top)
        .navigationTitle("In Game")
        .toolbar {
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
            Text("This will end the current game and return to setup.")
        }
    }

    // MARK: - Top Tiles

    private var scoreTiles: some View {
        LazyVGrid(columns: gridCols, spacing: 12) {
            ForEach(vm.players.indices, id: \.self) { i in
                let p = vm.players[i]
                PlayerTile(
                    name: p.name,
                    averageText: vm.averageText(for: p),
                    remaining: p.remaining,
                    isActive: i == vm.currentPlayerIndex
                )
                .onTapGesture {
                    vm.currentPlayerIndex = i
                }
            }
        }
    }

    private var finishRow: some View {
        let remaining = vm.players[vm.currentPlayerIndex].remaining
        let parts = vm.finishSegments(for: remaining)

        return ZStack {
            // Invisible placeholder to reserve consistent height and spacing
            HStack(spacing: 10) {
                Text(" ")
                    .font(.headline)
                    .opacity(0)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .hidden() // keep layout space but not visible

            if !parts.isEmpty {
                HStack(spacing: 10) {
                    ForEach(parts, id: \.self) { part in
                        Text(part)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .transition(.opacity)
            }
        }
        // Reserve a consistent height so content below doesn't move when parts appear/disappear
        .frame(height: 44)
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
                background: .gray,
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

    private var keypad: some View {
        VStack(spacing: 14) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach([1,2,3,4,5,6,7,8,9], id: \.self) { n in
                    KeyButton(title: "\(n)") {
                        Haptics.impact(.light)
                        vm.appendDigit(n)
                    }
                }
            }

            HStack(spacing: 14) {
                KeyIconButton(
                    systemName: "arrow.uturn.left",
                    background: .red
                ) {
                    Haptics.impact(.rigid)
                    vm.undo()
                }
                .disabled(vm.actionStack.isEmpty)

                Text("0")
                    .monospacedDigit()
                    .font(.system(size: 28, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Haptics.impact(.light)
                        vm.appendDigit(0)
                    }

                KeyIconButton(
                    systemName: "chevron.right",
                    background: .blue
                ) {
                    Haptics.impact(.medium)
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
    let remaining: Int
    let isActive: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(name)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Ø\(averageText)")
                .font(.subheadline)
                .foregroundStyle(isActive ? .white.opacity(0.85) : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(remaining)")
                .monospacedDigit()
                .font(.system(size: 44, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(isActive ? Color.black : Color.secondary.opacity(0.10))
        .foregroundStyle(isActive ? .white : .primary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct KeyButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .monospacedDigit()
                .font(.system(size: 28, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
        }
        .buttonStyle(.plain)
    }
}

private struct KeyIconButton: View {
    let systemName: String
    let background: Color
    let fillsWidth: Bool
    let action: () -> Void

    init(systemName: String, background: Color, fillsWidth: Bool = true, action: @escaping () -> Void) {
        self.systemName = systemName
        self.background = background
        self.fillsWidth = fillsWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .frame(width: fillsWidth ? nil : 56, height: 56)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

private struct FinishedOverlay: View {
    let winnerName: String
    let onNewGame: () -> Void
    let onBackToSetup: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()

            VStack(spacing: 14) {
                Text("Winner")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text(winnerName)
                    .font(.largeTitle)
                    .fontWeight(.semibold)

                HStack(spacing: 10) {
                    Button("New Game") { onNewGame() }
                        .buttonStyle(.borderedProminent)

                    Button("Setup") { onBackToSetup() }
                        .buttonStyle(.bordered)
                }
            }
            .padding(18)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding()
        }
    }
}

#Preview {
    ContentView()
}
