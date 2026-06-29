# WWDC26 / Xcode 27 SwiftUI Baseline

Last verified: 2026-06-25 from Apple official developer pages.

## Primary Apple Sources

- What's new in SwiftUI: https://developer.apple.com/videos/play/wwdc2026/269/
- Code-along: Build powerful drag and drop in SwiftUI: https://developer.apple.com/videos/play/wwdc2026/271/
- What's new in Xcode 27: https://developer.apple.com/videos/play/wwdc2026/258/
- Use SwiftUI with AppKit and UIKit: https://developer.apple.com/videos/play/wwdc2026/272/
- Adopting Liquid Glass: https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- AsyncImage: https://developer.apple.com/documentation/SwiftUI/AsyncImage

## SwiftUI Updates To Consider

- Document API is a first-class SwiftUI direction for document-based workflows.
- Lists, grids, and sections gained newer reordering capabilities. For Together row sorting, evaluate native reordering before custom gesture code.
- Toolbar behavior includes visibility priority and automatic minimization. Prefer system toolbar behavior where it matches Together's layout.
- Swipe actions can apply beyond traditional List rows. For `ScrollView + LazyVStack` timelines, consider native swipe support and `swipeActionsContainer()` before custom swipe mechanics.
- `AsyncImage` has improved HTTP caching behavior in the iOS 27 generation. Use `URLRequest` or custom `URLSession` when cache policy matters.
- `@State` can lazily initialize Observable class values. Use it where it simplifies local view-owned observable state, but do not move business state into Views.

## Xcode 27 Workflow Notes

- Use Device Hub and modern Xcode run destinations for real-device validation.
- Use Instruments Top Functions and Organizer Metric Goals when animation or scrolling feels slow.
- Use Xcode issue output seriously under Swift 6.2+ and iOS 27 SDKs; warnings may represent future errors.
- Use editor agent planning or `/plan` style workflows for larger UI migrations, but still validate with local build/test.

## Together-Specific Guidance

- Homepage timeline rows are visually one list but may be separate data sections. Do not let active-row feedback, completed-row insertion, section visibility, and global timeline reordering all animate the same user event.
- Completion interactions should use:
  1. local same-row feedback for the checkmark state;
  2. one lightweight smooth list transition for migration;
  3. no extra bouncy cascade on the inserted completed row.
- Expanded inline detail should keep row identity stable. Use height/opacity/offset transitions and avoid rebuilding text inputs during composition.
- For future-dated tasks visible in today's list, make ViewModel animation decisions match timeline display semantics, not only `Item.isCompleted(on: selectedDate)`.
- Use Reduce Motion fallbacks for custom animation: skip blur, large bounce, and chained sleeps when possible.

## Verification Checklist

- For animation changes: test same-day tasks, future-dated tasks, recurring tasks, first completed item, and completed-section already-visible cases.
- For list identity changes: confirm business IDs remain stable while presentation IDs can change by section/state.
- For input views: verify Chinese IME composition on device, especially WeChat input method.
- For Xcode 27 beta behavior: distinguish real failures from existing actor-isolation warnings, but do not introduce new warnings.
