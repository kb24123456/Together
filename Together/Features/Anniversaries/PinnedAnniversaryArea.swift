import SwiftUI

/// Today-region wrapper that picks the right rendering for the current
/// pinned set:
/// - 0 pinned → renders nothing (caller should not allocate space)
/// - 1 pinned → single AnniversaryCapsuleView
/// - 2+ pinned → PinnedAnniversaryStack with stack-then-expand UX
///
/// Spec §5.1.
struct PinnedAnniversaryArea: View {
    /// Already filtered to isPinnedToToday=true and sorted by displayAnchorDate ascending.
    let pinnedEvents: [ImportantDate]
    let viewerSupabaseUserID: UUID?
    let partnerDisplayName: String?
    let onTapEvent: (ImportantDate) -> Void

    var body: some View {
        switch pinnedEvents.count {
        case 0:
            EmptyView()
        case 1:
            AnniversaryCapsuleView(
                nextEvent: pinnedEvents[0],
                viewerSupabaseUserID: viewerSupabaseUserID,
                partnerDisplayName: partnerDisplayName,
                onTap: { onTapEvent(pinnedEvents[0]) }
            )
        default:
            PinnedAnniversaryStack(
                events: pinnedEvents,
                viewerSupabaseUserID: viewerSupabaseUserID,
                partnerDisplayName: partnerDisplayName,
                onTapEvent: onTapEvent
            )
        }
    }
}
