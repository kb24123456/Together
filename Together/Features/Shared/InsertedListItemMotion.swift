import SwiftUI

struct InsertedListItemMotionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isInserted: Bool
    let onAnimationCompleted: () -> Void

    @State private var isSettled = true
    @State private var hasAnimatedCurrentInsertion = false
    @State private var completionTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .opacity(isSettled ? 1 : reducedOpacity)
            .offset(y: isSettled ? 0 : reducedOffset)
            .scaleEffect(isSettled ? 1 : reducedScale, anchor: .center)
            .onAppear {
                startAnimationIfNeeded()
            }
            .onChange(of: isInserted) { _, _ in
                startAnimationIfNeeded()
            }
            .onDisappear {
                completionTask?.cancel()
                completionTask = nil
            }
    }

    private var reducedOpacity: Double {
        reduceMotion ? 0.92 : 0
    }

    private var reducedOffset: CGFloat {
        reduceMotion ? 0 : 18
    }

    private var reducedScale: CGFloat {
        reduceMotion ? 1 : 0.992
    }

    private var insertionAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.14)
            : .spring(response: 0.32, dampingFraction: 0.88)
    }

    private func startAnimationIfNeeded() {
        guard isInserted else {
            completionTask?.cancel()
            completionTask = nil
            hasAnimatedCurrentInsertion = false
            isSettled = true
            return
        }

        guard hasAnimatedCurrentInsertion == false else { return }

        hasAnimatedCurrentInsertion = true
        isSettled = false
        completionTask?.cancel()
        completionTask = Task { @MainActor in
            await Task.yield()
            withAnimation(insertionAnimation) {
                isSettled = true
            }

            let completionDelay: Duration = reduceMotion ? .milliseconds(180) : .milliseconds(520)
            try? await Task.sleep(for: completionDelay)
            guard Task.isCancelled == false else { return }
            onAnimationCompleted()
        }
    }
}

extension View {
    func insertedListItemMotion(
        isInserted: Bool,
        onAnimationCompleted: @escaping () -> Void
    ) -> some View {
        modifier(
            InsertedListItemMotionModifier(
                isInserted: isInserted,
                onAnimationCompleted: onAnimationCompleted
            )
        )
    }
}
