import SwiftUI

// MARK: - Subtask Checkbox (shared between Projects & Routines)

struct SubtaskCheckbox: View {
    let isCompleted: Bool
    let onToggle: () -> Void

    @State private var isAnimating = false
    @State private var animationCount = 0
    @State private var badgeScale: CGFloat = 1
    @State private var fillScale: CGFloat = 1
    @State private var fillOpacity: CGFloat = 0

    var body: some View {
        Button {
            if isCompleted {
                HomeInteractionFeedback.selection()
            } else {
                HomeInteractionFeedback.soft()
            }
            onToggle()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(AppTheme.colors.coral.opacity(0.14))
                    .scaleEffect(fillScale)
                    .opacity(isCompleted ? 0 : fillOpacity)

                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        isCompleted
                            ? Color.clear
                            : (isAnimating ? AppTheme.colors.body.opacity(0.32) : AppTheme.colors.body.opacity(0.44)),
                        style: StrokeStyle(lineWidth: 1.5, dash: [3.2, 4.0])
                    )

                Image(systemName: "checkmark")
                    .font(AppTheme.typography.sized(13, weight: .bold))
                    .foregroundStyle(AppTheme.colors.coral)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, options: .speed(1.15), value: animationCount)
                    .opacity(isCompleted ? 1 : 0)
                    .offset(
                        x: AppTheme.metrics.checkmarkVisualOffset.width,
                        y: AppTheme.metrics.checkmarkVisualOffset.height
                    )
            }
            .frame(width: 28, height: 28)
            .scaleEffect(isAnimating ? badgeScale : 1)
            .shadow(
                color: AppTheme.colors.coral.opacity(isAnimating ? 0.18 : 0),
                radius: isAnimating ? 8 : 0,
                y: isAnimating ? 4 : 0
            )
        }
        .buttonStyle(.plain)
        .onChange(of: isCompleted) { _, newValue in
            guard newValue else { return }
            triggerAnimation()
        }
    }

    private func triggerAnimation() {
        animationCount += 1
        isAnimating = true
        fillScale = 1; fillOpacity = 0
        withAnimation(.spring(response: 0.28, dampingFraction: 0.52)) {
            badgeScale = 1.2; fillScale = 1.4; fillOpacity = 1
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.52).delay(0.1)) {
            badgeScale = 1; fillOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            isAnimating = false; fillScale = 1
        }
    }
}

// MARK: - Subtask Cascade Row (shared between Projects & Routines)

struct SubtaskCascadeRow<Content: View>: View {
    @State private var isVisible = false
    let index: Int
    let animationBatch: Int
    let reduceMotion: Bool
    @ViewBuilder let content: Content

    init(
        index: Int,
        animationBatch: Int,
        reduceMotion: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.index = index
        self.animationBatch = animationBatch
        self.reduceMotion = reduceMotion
        self.content = content()
    }

    var body: some View {
        content
            .id("\(animationBatch)-\(index)")
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 18)
            .scaleEffect(isVisible ? 1 : 0.965, anchor: .center)
            .onAppear {
                isVisible = false
                withAnimation(animation) {
                    isVisible = true
                }
            }
    }

    private var animation: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.16)
        }
        return .snappy(duration: 0.32, extraBounce: 0.03).delay(Double(index) * 0.075)
    }
}
