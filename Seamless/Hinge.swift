import SwiftUI
import UIKit

/// How far a foldable is open. Stays `.none` on devices without a hinge.
enum Openness { case none, closed, partial, open }

@MainActor
@Observable
final class HingeState {
    var openness = Openness.none

    @available(iOS 27.1, *)
    func apply(_ hinge: UIHinge?) {
        switch hinge?.status {
        case .closed: openness = .closed
        case .partiallyOpen: openness = .partial
        case .fullyOpen: openness = .open
        default: openness = .none
        }
    }
}

/// Watches the hinge of a foldable (iPhone Duo) and reports it to `state`.
struct HingeReader: UIViewRepresentable {
    var state: HingeState

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        if #available(iOS 27.1, *) {
            view.addInteraction(UIHingeInteraction { _, update in
                state.apply(update.hinge)
            })
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
