//
//  BugReportPresenter.swift
//  Miroir enchanté
//

import UIKit

final class BugReportPresenter {
    private static let reportRecipient = "Miroir enchanté support"

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
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        let screenshot = captureScreenshot()

        var textLines = [
            L10n.text("bug.report.header"),
            "",
            String(format: L10n.text("bug.report.email_hint"), reportRecipient),
            "",
            L10n.text("bug.report.description"),
            "",
            "\(L10n.text("bug.report.device")): \(device.model)",
            "\(L10n.text("bug.report.ios")): \(device.systemVersion)",
            "\(L10n.text("bug.report.app_version")): \(appVersion) (\(buildNumber))"
        ]

        if screenshot != nil {
            textLines.append(L10n.text("bug.report.screenshot_attached"))
        }

        var items: [Any] = [textLines.joined(separator: "\n")]

        if let screenshot {
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
