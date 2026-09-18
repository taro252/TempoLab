import SwiftUI

struct LaunchBrandOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = true

    var body: some View {
        ZStack {
            Color("AppBackground")
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image("AppIconWizoutBg")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 112, height: 112)

                Text("TempoLab")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            // Storyboard側の画像中心（画面中央から-36pt）と揃える。
            .offset(y: -26)
        }
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            let animation: Animation = reduceMotion
                ? .linear(duration: 0.1)
                : .easeOut(duration: 0.3).delay(0.5)

            withAnimation(animation) {
                isVisible = false
            }
        }
    }
}

#Preview {
    LaunchBrandOverlay()
}
