---
name: xcode27-swiftui-modernization
description: Apply WWDC26 / Xcode 27 / iOS 27 SwiftUI guidance in the Together app. Use when working on SwiftUI UI, animation, Liquid Glass, toolbar behavior, ScrollView or List rows, swipe actions, drag and drop, reordering, AsyncImage, UIKit/AppKit interop, preview/build/test workflows, or when the user asks about latest Apple SwiftUI/Xcode capabilities.
---

# Xcode 27 SwiftUI Modernization

Use this skill before changing Together SwiftUI code when the work touches UI structure, row identity, animation, list behavior, toolbars, image loading, Liquid Glass, UIKit interop, or Xcode 27 verification.

## Workflow

1. Read `references/wwdc26-xcode27-swiftui.md` for the relevant topic.
2. Verify current code before applying the guidance; do not assume existing architecture matches the latest APIs.
3. Prefer Apple native SwiftUI APIs and project design guidelines over custom interaction code.
4. Keep behavior testable: ViewModel state and data decisions stay outside Views; Views own only local visual state.
5. Validate with the narrowest useful checks, then build or test with Xcode 27 when the change affects compile-time or runtime UI behavior.

## Default Decisions

- For task rows and timeline interactions, avoid stacking multiple transitions on the same event. Use one local feedback animation plus one lightweight list transition.
- For drag, drop, and reordering, evaluate SwiftUI's WWDC26 APIs before keeping custom gesture state.
- For swipe actions on non-List rows, prefer the new SwiftUI support for arbitrary views before rebuilding row layout.
- For Liquid Glass, use system controls and glass behavior first; do not hand-roll high-saturation fake glass.
- For AsyncImage or remote image work, account for iOS 27 cache behavior and use URLRequest or custom URLSession only when policy control is needed.
- For UIKit interop, keep bridges narrow and let Observation drive updates where it reduces adapter state.

## Source Handling

When the user asks for "latest", "WWDC", "Xcode 27", "iOS 27", or exact API availability, re-check Apple official docs or videos before making claims. This skill captures the current project baseline, not a substitute for live API verification.
