import Cocoa
import SwiftUI
import Translation

// Shows macOS's own dialog that downloads a language for Apple's on-device translation. The dialog belongs to a window,
// so a tiny invisible one hosts the SwiftUI view that asks for it.
final class TranslationPackDownloader {
    private var window: NSWindow?

    func download(_ language: String, completion: @escaping () -> Void) {
        window?.close()
        let configuration = TranslationSession.Configuration(source: Locale.Language(identifier: SOURCE_LANGUAGE),
                                                             target: Locale.Language(identifier: language))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.contentView = NSHostingView(rootView: TranslationPackRequest(configuration: configuration) { [weak self, weak window] in
            window?.close()
            if self?.window === window { self?.window = nil }
            completion()
        })
        window.center()
        NSApp.activate()
        window.orderFrontRegardless()
        self.window = window
    }
}

private struct TranslationPackRequest: View {
    let configuration: TranslationSession.Configuration
    let onFinish: () -> Void

    var body: some View {
        Color.clear.frame(width: 1, height: 1).translationTask(configuration) { session in
            // Throws when the person cancels the dialog; the status check afterwards tells either way.
            try? await session.prepareTranslation()
            await MainActor.run { onFinish() }
        }
    }
}
