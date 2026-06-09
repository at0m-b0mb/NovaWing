import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var engine: GameEngine

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch engine.phase {
            case .menu:     MenuView()
            case .playing:  GamePlayView()
            case .gameOver: GameOverView()
            }
        }
    }
}
