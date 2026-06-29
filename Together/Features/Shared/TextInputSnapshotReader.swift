import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum TextInputSnapshotReader {
    @MainActor
    static func resolvedText(fallback: String) -> String {
        #if canImport(UIKit)
        guard let text = UIResponder.currentTextInputText, text.isEmpty == false else {
            return fallback
        }
        return text
        #else
        return fallback
        #endif
    }
}

#if canImport(UIKit)
private enum FirstResponderStore {
    @MainActor static weak var responder: UIResponder?
}

private extension UIResponder {
    @MainActor
    static var currentTextInputText: String? {
        FirstResponderStore.responder = nil
        UIApplication.shared.sendAction(
            #selector(UIResponder.captureCurrentFirstResponder(_:)),
            to: nil,
            from: nil,
            for: nil
        )

        guard let responder = FirstResponderStore.responder else { return nil }
        if let textField = responder as? UITextField {
            return textField.text
        }
        if let textView = responder as? UITextView {
            return textView.text
        }
        guard let textInput = responder as? UITextInput,
              let range = textInput.textRange(
                from: textInput.beginningOfDocument,
                to: textInput.endOfDocument
              )
        else {
            return nil
        }
        return textInput.text(in: range)
    }

    @objc
    @MainActor
    func captureCurrentFirstResponder(_ sender: Any) {
        FirstResponderStore.responder = self
    }
}
#endif
