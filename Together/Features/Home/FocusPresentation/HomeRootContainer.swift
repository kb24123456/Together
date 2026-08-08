import SwiftUI
import UIKit

@MainActor
final class HomeRootContainerController<Content: View>: UIViewController {
    let backdropController = UIHostingController(rootView: GradientGridBackground())
    let backgroundController: UIHostingController<Content>
    let focusPresentationController = HomeFocusPresentationController()

    private let focusModel: HomeFocusPresentationModel
    private var focusCoordinator: HomeFocusPresentationCoordinator?
    private weak var registeredWindow: UIWindow?
    private var registeredWindowID = UUID()
    private var lastLaidOutBounds: CGRect = .zero

    init(rootView: Content, focusView: AnyView, focusModel: HomeFocusPresentationModel) {
        backgroundController = UIHostingController(rootView: rootView)
        self.focusModel = focusModel
        super.init(nibName: nil, bundle: nil)
        focusPresentationController.configure(model: focusModel, focusView: focusView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = UIView(frame: .zero)
        root.backgroundColor = UIColor.systemBackground
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        backdropController.view.backgroundColor = .clear
        backgroundController.view.backgroundColor = .clear
        install(backdropController)
        install(backgroundController)
        install(focusPresentationController)
        focusPresentationController.deactivate()

        let coordinator = HomeFocusPresentationCoordinator(
            backgroundView: backgroundController.view,
            presentationController: focusPresentationController,
            model: focusModel
        )
        focusCoordinator = coordinator
        focusModel.driver = coordinator
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let window = view.window else { return }
        if lastLaidOutBounds != .zero,
           lastLaidOutBounds.size != view.bounds.size,
           focusModel.isActive {
            focusModel.recover()
        }
        lastLaidOutBounds = view.bounds
        if registeredWindow !== window {
            registeredWindow = window
            registeredWindowID = UUID()
            focusModel.replaceWindow(with: registeredWindowID)
        }
        let availableFrame = HomeFocusGeometryPolicy.availableFrame(
            in: view.bounds,
            safeAreaInsets: view.safeAreaInsets
        )
        focusModel.recordAvailableFrame(availableFrame)
        focusModel.recordViewportFrame(availableFrame)
    }

    override var childForStatusBarStyle: UIViewController? { backgroundController }
    override var childForStatusBarHidden: UIViewController? { backgroundController }

    func update(rootView: Content, focusView: AnyView) {
        backgroundController.rootView = rootView
        focusPresentationController.configure(model: focusModel, focusView: focusView)
        setNeedsStatusBarAppearanceUpdate()
    }

    private func install(_ child: UIViewController) {
        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            child.view.topAnchor.constraint(equalTo: view.topAnchor),
            child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        child.didMove(toParent: self)
    }
}

struct HomeRootContainer<Content: View>: UIViewControllerRepresentable {
    let rootView: Content
    let focusView: AnyView
    let focusModel: HomeFocusPresentationModel

    func makeUIViewController(context: Context) -> HomeRootContainerController<Content> {
        HomeRootContainerController(rootView: rootView, focusView: focusView, focusModel: focusModel)
    }

    func updateUIViewController(
        _ controller: HomeRootContainerController<Content>,
        context: Context
    ) {
        controller.update(rootView: rootView, focusView: focusView)
    }
}
