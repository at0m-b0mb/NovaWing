import SwiftUI

struct GamePlayView: View {
    @EnvironmentObject private var engine: GameEngine

    /// Digital Crown → horizontal position. 0 = left edge, 1 = right edge.
    @State private var crown: Double = 0.5

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                engine.targetXFrac = CGFloat(crown)
                engine.advance(to: timeline.date, size: size)
                NovaRenderer.draw(engine: engine, context: &context, size: size)
            }
        }
        .background(Color.black)
        .focusable(true)
        .digitalCrownRotation(
            $crown,
            from: 0, through: 1, by: 0.008,
            sensitivity: .high,
            isContinuous: false,
            isHapticFeedbackEnabled: false
        )
        .contentShape(Rectangle())
        .onTapGesture { engine.dropBomb() }
        .ignoresSafeArea()
    }
}
