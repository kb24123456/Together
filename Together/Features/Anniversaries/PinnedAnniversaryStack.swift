import SwiftUI

/// Multi-capsule stacked layout for the Today area when ≥2 events are
/// pinned to today. Mirrors iOS Lock Screen notification stack:
/// top capsule fully visible, bottom 1-2 capsules peek out via offset+scale.
/// Tapping the stack expands to a vertical list inline (no sheet, no
/// scroll-container exit). Tapping the top capsule when expanded folds
/// back to the stacked state.
///
/// Spec §5.2.
struct PinnedAnniversaryStack: View {
    let events: [ImportantDate]              // sorted by displayAnchorDate ascending
    let viewerSupabaseUserID: UUID?
    let partnerDisplayName: String?
    let onTapEvent: (ImportantDate) -> Void

    @State private var isExpanded = false

    /// Spec §5.2: render at most 3 in the stacked z-stack. The rest hide
    /// behind a "+N" badge until the user expands.
    private static let stackedRenderLimit = 3

    var body: some View {
        if isExpanded {
            VStack(spacing: AppTheme.spacing.sm) {
                ForEach(events) { event in
                    AnniversaryCapsuleView(
                        nextEvent: event,
                        viewerSupabaseUserID: viewerSupabaseUserID,
                        partnerDisplayName: partnerDisplayName,
                        onTap: { handleCapsuleTap(event: event, isTopOfStack: event.id == events.first?.id) }
                    )
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        } else {
            collapsedStack
                .transition(.opacity)
        }
    }

    private var collapsedStack: some View {
        ZStack(alignment: .top) {
            ForEach(Array(visibleStackedSlice.enumerated().reversed()), id: \.element.id) { idx, event in
                AnniversaryCapsuleView(
                    nextEvent: event,
                    viewerSupabaseUserID: viewerSupabaseUserID,
                    partnerDisplayName: partnerDisplayName,
                    onTap: { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { isExpanded = true } }
                )
                .scaleEffect(scale(forIndex: idx))
                .offset(y: offsetY(forIndex: idx))
                .zIndex(Double(visibleStackedSlice.count - idx))
                .allowsHitTesting(idx == 0)
            }
        }
        .overlay(alignment: .topTrailing) {
            if events.count > Self.stackedRenderLimit {
                Text("+\(events.count - Self.stackedRenderLimit)")
                    .font(AppTheme.typography.sized(11, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.rose)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(AppTheme.colors.rose.opacity(0.18)))
                    .offset(x: -8, y: -6)
            }
        }
        .padding(.bottom, CGFloat(visibleStackedSlice.count - 1) * 6)
    }

    private var visibleStackedSlice: [ImportantDate] {
        Array(events.prefix(Self.stackedRenderLimit))
    }

    private func scale(forIndex idx: Int) -> CGFloat {
        max(0.88, 1.0 - CGFloat(idx) * 0.04)
    }

    private func offsetY(forIndex idx: Int) -> CGFloat {
        CGFloat(idx) * 6
    }

    private func handleCapsuleTap(event: ImportantDate, isTopOfStack: Bool) {
        if isTopOfStack {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isExpanded = false
            }
        } else {
            onTapEvent(event)
        }
    }
}
