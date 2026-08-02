import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    override init() {
        if ProcessInfo.processInfo.arguments.contains("--app-store-landscape") {
            Self.orientationLock = .landscapeLeft
            UIDevice.current.setValue(
                UIInterfaceOrientation.landscapeLeft.rawValue,
                forKey: "orientation"
            )
        }
        super.init()
    }

    static var orientationLock = UIInterfaceOrientationMask.all {
        didSet {
            for scene in UIApplication.shared.connectedScenes {
                if let windowScene = scene as? UIWindowScene {
                    windowScene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                    windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientationLock))
                }
            }
        }
    }

    static func requestCurrentGeometryUpdate() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            windowScene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientationLock))
        }
    }

    static func lockToCurrentOrientation() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            orientationLock = .all
            return
        }
        switch scene.interfaceOrientation {
        case .portrait:
            orientationLock = .portrait
        case .portraitUpsideDown:
            orientationLock = .portraitUpsideDown
        case .landscapeLeft:
            orientationLock = .landscapeLeft
        case .landscapeRight:
            orientationLock = .landscapeRight
        case .unknown:
            orientationLock = .all
        @unknown default:
            orientationLock = .all
        }
    }

    func application(_: UIApplication, supportedInterfaceOrientationsFor _: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientationLock
    }

    func application(
        _: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == DownloadManager.backgroundSessionIdentifier else {
            completionHandler()
            return
        }

        Task { @MainActor in
            guard let downloadManager = DownloadManager.shared else {
                completionHandler()
                return
            }
            downloadManager.setBackgroundEventsCompletionHandler(completionHandler)
        }
    }
}
