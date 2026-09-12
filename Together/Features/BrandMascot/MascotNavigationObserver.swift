import SwiftUI
import UIKit

/// Observes the editor's existing modal transition without taking over navigation.
struct MascotNavigationObserver: UIViewControllerRepresentable {
    let mascot: MascotEditorHandle

    func makeUIViewController(context: Context) -> ObserverController {
        ObserverController(mascot: mascot)
    }

    func updateUIViewController(_ controller: ObserverController, context: Context) {
        controller.mascot = mascot
    }

    final class ObserverController: UIViewController {
        var mascot: MascotEditorHandle
        private var hasAppeared = false

        init(mascot: MascotEditorHandle) {
            self.mascot = mascot
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { nil }

        override func loadView() {
            view = UIView(frame: .zero)
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
            view.accessibilityElementsHidden = true
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            guard !hasAppeared, let coordinator = transitionCoordinator else { return }
            let ancestors = ancestorControllers
            guard ancestors.contains(where: { $0.isBeingPresented }),
                  ancestors.contains(where: { $0 === coordinator.viewController(forKey: .to) }),
                  !ancestors.contains(where: { $0 === coordinator.viewController(forKey: .from) })
            else { return }

            mascot.session.coordinateEditorTransition(
                id: mascot.id, returning: false, coordinator: coordinator, observer: self
            )
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            guard let coordinator = transitionCoordinator else { return }
            let ancestors = ancestorControllers
            let hasCommittedReturn = mascot.session.ownership.editorID == mascot.id
                && mascot.session.ownership.isReturning
            guard ancestors.contains(where: { $0.isBeingDismissed }) || hasCommittedReturn,
                  ancestors.contains(where: { $0 === coordinator.viewController(forKey: .from) }),
                  !ancestors.contains(where: { $0 === coordinator.viewController(forKey: .to) })
            else { return }

            mascot.session.coordinateEditorTransition(
                id: mascot.id, returning: true, coordinator: coordinator, observer: self
            )
        }

        override func viewIsAppearing(_ animated: Bool) {
            super.viewIsAppearing(animated)
            mascot.session.editorLayoutDidChange(id: mascot.id, observer: self)
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            mascot.session.editorLayoutDidChange(id: mascot.id, observer: self)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            hasAppeared = true
            mascot.session.editorDidAppear(id: mascot.id)
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            mascot.session.editorDidDisappear(id: mascot.id)
        }

        private var ancestorControllers: [UIViewController] {
            var ancestors: [UIViewController] = []
            var current: UIViewController? = self
            while let controller = current {
                ancestors.append(controller)
                current = controller.parent
            }
            return ancestors
        }
    }
}
