import SwiftUI

struct ImportantDateCapsulePagerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let candidates: [ImportantDateCapsuleCandidate]
    var autoHighlightCandidateID: UUID?
    var viewerSupabaseUserID: UUID? = nil
    var partnerDisplayName: String? = nil
    let onPrimaryTap: () -> Void

    @State private var scrollPositionID: UUID?
    @State private var isSyncingScrollPosition = false
    @AppStorage("together.importantDateCapsule.userSelectedID") private var selectedIDStorage = ""
    @AppStorage("together.importantDateCapsule.suppressedAutoHighlightID") private var suppressedAutoHighlightIDStorage = ""
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
            normalizeSuppressedAutoHighlightID()
            syncScrollPositionToDisplayedCandidate(animated: false)
        }
        .onChange(of: candidateIDs) { _, _ in
            normalizeSelectedID()
            normalizeSuppressedAutoHighlightID()
            syncScrollPositionToDisplayedCandidate(animated: false)
        }
        .onChange(of: autoHighlightCandidateID) { _, _ in
            normalizeSuppressedAutoHighlightID()
            syncScrollPositionToDisplayedCandidate(animated: true)
        }
        .onChange(of: displayedCandidateID) { _, _ in
            syncScrollPositionToDisplayedCandidate(animated: true)
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
        let shouldReduceMotion = reduceMotion

        return VStack(spacing: AppTheme.spacing.xs) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(candidates) { candidate in
                        page(for: candidate)
                            .containerRelativeFrame(.horizontal)
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content
                                    .scaleEffect(
                                        shouldReduceMotion ? 1 : 1 - (0.024 * min(abs(phase.value), 1)),
                                        anchor: .center
                                    )
                                    .opacity(
                                        shouldReduceMotion ? 1 : 1 - (0.12 * Double(min(abs(phase.value), 1)))
                                    )
                            }
                    }
                }
                .scrollTargetLayout()
            }
            .frame(height: 56)
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrollPositionID)
            .onChange(of: scrollPositionID) { _, newID in
                handleScrollPositionChange(newID)
            }

            pageIndicator
        }
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

    private var displayedCandidateID: UUID? {
        ImportantDateCapsuleSelection.displayedID(
            candidateIDs: candidateIDs,
            userSelectedID: normalizedSelectedID,
            autoHighlightID: autoHighlightCandidateID,
            suppressedAutoHighlightID: suppressedAutoHighlightID
        )
    }

    private var visibleCandidateID: UUID? {
        guard let scrollPositionID,
              candidates.contains(where: { $0.id == scrollPositionID }) else {
            return displayedCandidateID
        }
        return scrollPositionID
    }

    private var normalizedSelectedID: UUID? {
        guard let selectedID = ImportantDateCapsulePreferences.selectedID(from: selectedIDStorage),
              candidates.contains(where: { $0.id == selectedID }) else {
            return nil
        }
        return selectedID
    }

    private var suppressedAutoHighlightID: UUID? {
        ImportantDateCapsulePreferences.selectedID(from: suppressedAutoHighlightIDStorage)
    }

    private var candidateIDs: [UUID] {
        candidates.map(\.id)
    }

    private func normalizeSelectedID() {
        guard candidates.isEmpty == false else {
            if selectedIDStorage.isEmpty == false {
                selectedIDStorage = ""
            }
            return
        }

        guard let selectedID = ImportantDateCapsulePreferences.selectedID(from: selectedIDStorage),
              candidates.contains(where: { $0.id == selectedID }) else {
            if selectedIDStorage.isEmpty == false {
                selectedIDStorage = ""
            }
            return
        }
    }

    private func normalizeSuppressedAutoHighlightID() {
        let shouldClear = ImportantDateCapsuleSelection.shouldClearSuppressedAutoHighlightID(
            suppressedAutoHighlightID,
            currentAutoHighlightID: autoHighlightCandidateID
        )
        if shouldClear {
            suppressedAutoHighlightIDStorage = ""
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

    private func syncScrollPositionToDisplayedCandidate(animated: Bool) {
        guard candidates.count > 1 else { return }
        guard let displayedCandidateID else { return }
        guard scrollPositionID != displayedCandidateID else { return }

        isSyncingScrollPosition = true
        let update = {
            scrollPositionID = displayedCandidateID
        }

        if animated, reduceMotion == false {
            withAnimation(.snappy(duration: 0.28)) {
                update()
            }
        } else {
            update()
        }

        Task { @MainActor in
            await Task.yield()
            isSyncingScrollPosition = false
        }
    }

    private func handleScrollPositionChange(_ newID: UUID?) {
        guard candidates.count > 1,
              isSyncingScrollPosition == false,
              let newID,
              candidates.contains(where: { $0.id == newID }) else { return }

        let newStorageString = ImportantDateCapsulePreferences.storageString(for: newID)
        guard selectedIDStorage != newStorageString else { return }

        HomeInteractionFeedback.selection()
        selectedIDStorage = newStorageString

        if let autoHighlightCandidateID {
            suppressedAutoHighlightIDStorage = newID == autoHighlightCandidateID
                ? ""
                : ImportantDateCapsulePreferences.storageString(for: autoHighlightCandidateID)
        }
    }

    private func canShowElapsedDays(for event: ImportantDate) -> Bool {
        event.supportsElapsedDaysDisplay && event.showsElapsedDays
    }

    private func indicatorColor(for candidate: ImportantDateCapsuleCandidate) -> Color {
        candidate.id == visibleCandidateID
            ? AppTheme.colors.rose.opacity(0.72)
            : AppTheme.colors.rose.opacity(0.24)
    }
}
