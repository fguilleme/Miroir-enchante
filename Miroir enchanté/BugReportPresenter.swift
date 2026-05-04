//
//  BugReportPresenter.swift
//  Miroir enchanté
//

import UIKit

final class BugReportPresenter {
    static func captureScreenshot() -> UIImage? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else {
            return nil
        }

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    static func present(from viewController: UIViewController, sourceView: UIView? = nil) {
        let device = UIDevice.current

        let text = """
        Bug report - Miroir enchanté

        Décris le problème ici:

        Device: \(device.model)
        iOS: \(device.systemVersion)
        """

        var items: [Any] = [text]

        if let screenshot = captureScreenshot() {
            items.insert(screenshot, at: 0)
        }

        let activityVC = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        activityVC.popoverPresentationController?.sourceView = sourceView ?? viewController.view
        activityVC.popoverPresentationController?.sourceRect = sourceView?.bounds ?? viewController.view.bounds

        viewController.present(activityVC, animated: true)
    }
}
