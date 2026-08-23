import SwiftUI
import VisionKit

/// The document camera, as a SwiftUI view.
///
/// VisionKit does the whole job — edge detection, perspective correction,
/// shadow removal, multi-page capture — so there is nothing here but the
/// bridge. Rolling a camera by hand would mean reimplementing all of that
/// worse, and it is the corrected page, not the photograph, that makes a
/// scanned receipt readable a year later.
///
/// The controller owns its own presentation: it is a full-screen camera with
/// its own Cancel and Save, so there is no chrome to add and nothing to
/// configure. It reports once, through `onFinish`, and the caller dismisses.
struct DocumentScannerView: UIViewControllerRepresentable {

    enum Outcome {
        /// Pages in the order they were shot.
        case scanned([UIImage])
        case cancelled
        case failed(any Error)
    }

    /// Called exactly once, on the main actor, whichever way the camera ends.
    let onFinish: (Outcome) -> Void

    /// False in the simulator and on anything without a usable camera. Callers
    /// must check it: presenting the controller anyway puts up a black screen
    /// with a Cancel button, which looks like a bug rather than a limitation.
    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    /// Nothing to update: the controller is modal and finishes once. Re-reading
    /// `onFinish` here would also be pointless, since by the time anything
    /// could change the camera has already reported.
    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    /// `VNDocumentCameraViewControllerDelegate` is not annotated for
    /// concurrency, so Swift 6 refuses a plain main-actor conformance. It is
    /// nonetheless called from the presented view controller and only ever on
    /// the main thread, which is exactly what `@preconcurrency` states — and it
    /// keeps the coordinator isolated, so `onFinish` can touch view state.
    @MainActor
    final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {

        private let onFinish: (Outcome) -> Void
        /// The delegate can fire more than once in principle — a failure after
        /// a cancel, say — and the caller replaces a block payload on the back
        /// of it. Reporting twice would attach the scan twice.
        private var hasFinished = false

        init(onFinish: @escaping (Outcome) -> Void) {
            self.onFinish = onFinish
        }

        private func finish(_ outcome: Outcome) {
            guard !hasFinished else { return }
            hasFinished = true
            onFinish(outcome)
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            // `scan` is only valid for the duration of this call, so the images
            // are pulled out here rather than handed on as a scan object.
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            finish(.scanned(pages))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            finish(.cancelled)
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: any Error
        ) {
            DocumentStore.logger.error("Document scan failed: \(error.localizedDescription, privacy: .public)")
            finish(.failed(error))
        }
    }
}
