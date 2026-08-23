import SwiftUI
import UIKit
import VersoKit

/// The extension target holds the principal class and nothing else.
///
/// Same arrangement as `VersoWidgetBundle`: everything the sheet is —  the
/// store, the theme, the note writer — lives in `VersoKit`, so the share sheet
/// and the app cannot drift apart.
///
/// A `UIViewController` rather than SwiftUI's `@main`, because a share
/// extension's entry point is `NSExtensionPrincipalClass` and the system needs
/// an Objective-C class to instantiate. `@objc` names it explicitly so the
/// Info.plist entry does not depend on the module name surviving a rename.
@objc(ShareViewController)
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []

        let host = UIHostingController(
            rootView: ShareCaptureView(
                items: items,
                onSaved: { [weak self] in self?.finish() },
                onCancel: { [weak self] in self?.cancel() }
            )
        )

        // Clear, so the sheet's own themed canvas is what shows through rather
        // than a system background behind it — the host controller's default
        // fill is the one place the app's paper would lose to UIKit's.
        host.view.backgroundColor = .clear

        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: [])
    }

    /// `cancelRequest` rather than `completeRequest`, so the host app is told
    /// the share was declined. Completing instead makes Safari believe it
    /// succeeded, and some hosts then dismiss their own UI as if it had.
    private func cancel() {
        extensionContext?.cancelRequest(
            withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        )
    }
}
