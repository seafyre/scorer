import SwiftUI
import UIKit

struct HomeView: View {
    @State private var currentPage: Int = 1
    @GestureState private var dragOffset: CGFloat = 0

    var width = UIScreen.main.bounds.width

    var currentOffset: CGFloat {
        CGFloat(1 - currentPage) * width
    }
    
    func hapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    var drag: some Gesture {
        DragGesture()
            .updating($dragOffset) { value, state, _ in
                state = value.translation.width
            }
            .onEnded { value in
                withAnimation {
                    let oldPage = currentPage
                    if value.translation.width > 50 {
                        currentPage = max(0, currentPage - 1)
                    } else if value.translation.width < -50 {
                        currentPage = min(2, currentPage + 1)
                    }
                    if currentPage != oldPage {
                        hapticFeedback()
                    }
                }
            }
    }

    var body: some View {
        HStack(spacing: 0) {
            SettingsView(onClose: {
                hapticFeedback()
                withAnimation {
                    currentPage = 1
                }
            })
                .frame(width: width)

            HomeContentView(
                showSettings: Binding(
                    get: { currentPage == 0 },
                    set: { newValue in
                        withAnimation {
                            currentPage = newValue ? 0 : 1
                        }
                    }
                ),
                showPlayers: Binding(
                    get: { currentPage == 2 },
                    set: { newValue in
                        withAnimation {
                            currentPage = newValue ? 2 : 1
                        }
                    }
                )
            )
                .frame(width: width)

            PlayerListView(onClose: {
                hapticFeedback()
                withAnimation {
                    currentPage = 1
                }
            })
                .frame(width: width)
        }
        .offset(x: currentOffset + dragOffset)
        .animation(.easeInOut, value: currentPage)
        .gesture(drag)
    }
}

struct HomeContentView: View {
    @Binding var showSettings: Bool
    @Binding var showPlayers: Bool

    var body: some View {
        VStack {
            HStack {
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    withAnimation {
                        showSettings.toggle()
                    }
                }) {
                    Image(systemName: "gearshape")
                        .font(.title)
                        .padding()
                }
                Spacer()
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    withAnimation {
                        showPlayers.toggle()
                    }
                }) {
                    Image(systemName: "line.3.horizontal")
                        .font(.title)
                        .padding()
                }
            }

            Spacer()

            Text("welcome  back!")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.bottom, 40)

            VStack(spacing: 24) {
                StatView(value: "35.4", label: "average")
                StatView(value: "129", label: "total games")
                StatView(value: "160", label: "highest finish")
            }

            Spacer()

            Button(action: {
                // start new game
            }) {
                Text("new  game")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
                    .cornerRadius(20)
                    .padding(.horizontal)
            }

            Spacer(minLength: 40)
        }
        .padding()
    }
}

struct StatView: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title)
                .fontWeight(.semibold)
                .foregroundColor(.black)
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

struct SettingsView: View {
    var onClose: () -> Void
    
    func hapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: {
                    hapticFeedback()
                    onClose()
                }) {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .padding()
                }
            }
            Text("Settings")
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}

struct PlayerListView: View {
    var onClose: () -> Void
    
    func hapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    var body: some View {
        VStack {
            HStack {
                Button(action: {
                    hapticFeedback()
                    onClose()
                }) {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .padding()
                }
                Spacer()
            }
            Text("Players Overview")
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    HomeView()
}
