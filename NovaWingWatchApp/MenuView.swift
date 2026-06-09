import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var engine: GameEngine
    @State private var stars: [CGPoint] = []

    private let green = Color(.sRGB, red: 0.4, green: 1.0, blue: 0.6, opacity: 1)

    var body: some View {
        ZStack {
            Canvas { ctx, size in
                for s in stars {
                    let p = CGPoint(x: s.x * size.width, y: s.y * size.height)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: 1.6, height: 1.6)),
                             with: .color(.white.opacity(0.5)))
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 3) {
                Text("NOVA")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("WING")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .tracking(8)
                    .foregroundStyle(green)

                if engine.hiScore > 0 {
                    Text("HI \(engine.hiScore)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(.sRGB, red: 1, green: 0.85, blue: 0.3, opacity: 1))
                        .padding(.top, 3)
                }

                Button {
                    Haptic.uiTap()
                    engine.start()
                } label: {
                    Text("INSERT COIN")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(.sRGB, red: 0.2, green: 0.78, blue: 0.5, opacity: 1))
                .padding(.top, 8)

                Text("Crown to fly · Tap = smart bomb")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 3)
            }
            .padding(.horizontal, 14)
        }
        .onAppear {
            if stars.isEmpty {
                stars = (0..<50).map { _ in CGPoint(x: .random(in: 0...1), y: .random(in: 0...1)) }
            }
        }
    }
}
