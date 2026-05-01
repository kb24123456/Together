import SwiftUI

struct ImportantDateCapsulePagerView: View {
    let candidates: [ImportantDateCapsuleCandidate]
    var viewerSupabaseUserID: UUID? = nil
    var partnerDisplayName: String? = nil
    let onPrimaryTap: () -> Void

    @AppStorage("together.importantDateCapsule.selectedID") private var selectedIDStorage = ""
    @AppStorage("together.importantDateCapsule.countModesByDateID") private var countModesStorage = "{}"

    var body: some View {
        Group {
            if candidates.isEmpty {
                emptyCapsule
            } else if candidates.count == 1, let candidate = candidates.first {
                page(for: candidate)
            } else {
                pager
            }
        }
        .task {
            normalizeSelectedID()
        }
        .onChange(of: candidateIDs) { _, _ in
            normalizeSelectedID()
        }
    }

    private var emptyCapsule: some View {
        AnniversaryCapsuleView(
            event: nil,
            countMode: .next,
            daysUntilOrToday: nil,
            isToday: false,
            viewerSupabaseUserID: viewerSupabaseUserID,
            partnerDisplayName: partnerDisplayName,
            onPrimaryTap: onPrimaryTap,
            onCountTap: onPrimaryTap
        )
    }

    private var pager: some View {
        VStack(spacing: AppTheme.spacing.xs) {
            Group {
                if let candidate = selectedCandidate {
                    page(for: candidate)
                        .id(candidate.id)
                        .transition(pageTransition)
                }
            }
            .frame(height: 56)
            .animation(.snappy(duration: 0.24), value: selectedCandidate?.id)

            pageIndicator
        }
        .contentShape(Rectangle())
        .simultaneousGesture(pageSwipeGesture, including: .all)
    }

    private var pageIndicator: some View {
        HStack(spacing: 5) {
            ForEach(candidates) { candidate in
                Circle()
                    .fill(indicatorColor(for: candidate))
                    .frame(width: 4, height: 4)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }

    private func page(for candidate: ImportantDateCapsuleCandidate) -> some View {
        AnniversaryCapsuleView(
            event: candidate.event,
            countMode: countMode(for: candidate),
            daysUntilOrToday: candidate.daysUntilOrToday,
            isToday: candidate.isToday,
            viewerSupabaseUserID: viewerSupabaseUserID,
            partnerDisplayName: partnerDisplayName,
            onPrimaryTap: onPrimaryTap,
            onCountTap: { toggleCountMode(for: candidate) }
        )
    }

    private var selectedCandidate: ImportantDateCapsuleCandidate? {
        guard let selectedID = normalizedSelectedID else { return candidates.first }
        return candidates.first { $0.id == selectedID } ?? candidates.first
    }

    private var selectedIndex: Int? {
        guard let selectedID = selectedCandidate?.id else { return nil }
        return candidates.firstIndex { $0.id == selectedID }
    }

    private var normalizedSelectedID: UUID? {
        guard let first = candidates.first else { return nil }
        guard let selectedID = ImportantDateCapsulePreferences.selectedID(from: selectedIDStorage),
              candidates.contains(where: { $0.id == selectedID }) else {
            return first.id
        }
        return selectedID
    }

    private var candidateIDs: [UUID] {
        candidates.map(\.id)
    }

    private func normalizeSelectedID() {
        guard let first = candidates.first else {
            if selectedIDStorage.isEmpty == false {
                selectedIDStorage = ""
            }
            return
        }

        guard let selectedID = ImportantDateCapsulePreferences.selectedID(from: selectedIDStorage),
              candidates.contains(where: { $0.id == selectedID }) else {
            selectedIDStorage = ImportantDateCapsulePreferences.storageString(for: first.id)
            return
        }
    }

    private func countMode(for candidate: ImportantDateCapsuleCandidate) -> ImportantDateCapsuleCountMode {
        guard canShowElapsedDays(for: candidate.event) else { return .next }
        return decodedCountModes()[candidate.id] ?? .next
    }

    private func toggleCountMode(for candidate: ImportantDateCapsuleCandidate) {
        guard canShowElapsedDays(for: candidate.event) else { return }

        var modes = decodedCountModes()
        modes[candidate.id] = countMode(for: candidate) == .next ? .elapsed : .next

        HomeInteractionFeedback.selection()
        withAnimation(.snappy(duration: 0.22)) {
            countModesStorage = ImportantDateCapsulePreferences.encodeCountModes(modes)
        }
    }

    private func decodedCountModes() -> [UUID: ImportantDateCapsuleCountMode] {
        ImportantDateCapsulePreferences.decodeCountModes(countModesStorage)
    }

    private var pageSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height),
                      abs(value.translation.width) >= 36,
                      let selectedIndex else { return }

                let nextIndex = value.translation.width < 0
                    ? min(selectedIndex + 1, candidates.count - 1)
                    : max(selectedIndex - 1, 0)
                guard nextIndex != selectedIndex else { return }

                HomeInteractionFeedback.selection()
                selectedIDStorage = ImportantDateCapsulePreferences.storageString(for: candidates[nextIndex].id)
            }
    }

    private var pageTransition: AnyTransition {
        .opacity.combined(with: .move(edge: .trailing))
    }

    private func canShowElapsedDays(for event: ImportantDate) -> Bool {
        event.supportsElapsedDaysDisplay && event.showsElapsedDays
    }

    private func indicatorColor(for candidate: ImportantDateCapsuleCandidate) -> Color {
        candidate.id == normalizedSelectedID
            ? AppTheme.colors.rose.opacity(0.72)
            : AppTheme.colors.rose.opacity(0.24)
    }
}
