import SwiftUI
import UIKit

/// Поворот экрана: всё приложение — портрет, «Побродить» — ещё и горизонтально (15A, 16.11.2026).
final class QuestlynAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}

enum OrientationLock {
    private(set) static var mask: UIInterfaceOrientationMask = .portrait

    static func set(_ mask: UIInterfaceOrientationMask) {
        guard self.mask != mask else { return }
        self.mask = mask
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                var controller = window.rootViewController
                while let current = controller {
                    current.setNeedsUpdateOfSupportedInterfaceOrientations()
                    controller = current.presentedViewController
                }
            }
            if mask == .portrait { scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) }
        }
    }
}
