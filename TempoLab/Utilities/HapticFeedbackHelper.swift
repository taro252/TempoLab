#if os(iOS)
import UIKit

@MainActor
enum HapticFeedbackHelper {
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let strongGenerator = UIImpactFeedbackGenerator(style: .medium)

    static func prepare() {
        lightGenerator.prepare()
        strongGenerator.prepare()
    }

    static func play(_ strength: BPMHapticStrength) {
        switch strength {
        case .light:
            lightGenerator.impactOccurred()
            lightGenerator.prepare()
        case .strong:
            strongGenerator.impactOccurred()
            strongGenerator.prepare()
        }
    }
}
#endif
