# Native Rive runtime frame verification

`sequence.swift` loads the exported `.riv` with the official Apple Runtime 6.25.1, advances the real state machine by a fixed time step, renders every frame through Rive's Metal renderer into a shared `MTLTexture`, waits for the GPU completion callback, and writes PNGs plus an H.264 `.mov`. It does not set shape properties manually, use screenshots as animation frames, modify the Rive document, or launch an iOS Simulator.

## Reproduce

The currently downloaded framework container is:

```
/private/tmp/together-rive-apple-audit.9TAn8W/.build/artifacts/rive-ios/RiveRuntime/RiveRuntime.xcframework/macos-arm64_x86_64
```

Compile with `zsh build-renderer.sh <framework-container> <output-executable>`. Then run:

```
/private/tmp/together-rive-frame-probe/render-sequence <asset.riv> <story.json> <new-output-directory>
```

The tool refuses an existing output directory so evidence is not silently overwritten. Each output contains the exact story, PNGs, `preview.mov`, and `evidence.json`, including the asset SHA256, every rendered-frame pixel hash, and GPU draw/unchanged-skip counts. A successful render alone is not a visual-quality pass.

## Story format

```json
{
  "name": "example",
  "fps": 60,
  "frames": 180,
  "width": 512,
  "height": 512,
  "pngEvery": 15,
  "pngFrames": [12, 27],
  "video": true,
  "backgroundARGB": "FFFAFAFA",
  "events": [
    {"frame": 0, "numbers": {"mode": 0, "expression": 2}},
    {"frame": 30, "triggers": ["celebrateMotion"]},
    {"frame": 90, "numbers": {"reaction": 6}, "triggers": ["react"]}
  ]
}
```

Events may contain `numbers`, `booleans`, `triggers`, and `colors`. Color values are eight-digit ARGB strings with an optional `#`. All property names are checked against the actual exported view model before rendering. The default artboard is `TogetherSphere`, state machine `Mascot`, and view model `TogetherSphereModel`; JSON fields can override those names. `pngEvery: 1` writes every frame; `0` writes only explicit `pngFrames` and the final frame. Input is applied before advancing its numbered frame by `1/fps` seconds.

## Trace boundary

The public Worker/Metal `StateMachine` API in 6.25.1 does **not** expose state changes. Its listener exposes errors, deletion, settled events, and semantic differences. Therefore `inspectionReplayStateChanges` comes from a separate official legacy inspection instance replaying the same input timeline. Its state names are actual runtime reports, but random branches can differ from the rendering instance. The evidence never labels this separate trace as a per-frame trace of the video instance.

`renderedInstanceInputEvents`, pixel hashes, and GPU completion records belong to the actual rendered instance. The renderer completes one frame before queuing the next, preventing asynchronous frame coalescing from dropping intermediate animation steps. An unchanged frame retains the preceding texture and is included in the video.

## Evidence versions

- `representative-quick-v1`: first representative export, 1,530 real frames; suitable for first visual comparison, predates the two state-transition fixes.
- `rapid-v2`, `reaction-restore-v2`: corrected representative export; 600 and 480 real frames. Manual sampled-frame checks confirmed local poke indentation and recovery, absence of leftover mouth/sweat after returning to legacy idle, old writing/concern appearance, and return from a temporary emotion to the selected persistent expression.
- `candidate-all-28-*`: superseded candidate before the final sweat-position and short-tear-loop adjustments; retained as intermediate evidence only.
- `before-contour-*`: superseded 321e83b6 export. Native rendering revealed missing eyes for presets 15, 19, and 23; reversed path winding was corrected before the final 5253c970 export and all ten final scenarios were rerun. These older folders are failure evidence, not accepted final previews.
- `final-*`: runs against the frozen deliverable, identified by the SHA256 in each evidence file. See `review-results.json` for completed checks and limits rather than inferring acceptance from folder existence.

For `final-48pt-*` and `final-80pt-*`, rendering is native at 3× pixel density: 144×144 and 240×240 pixels respectively. Display these images at 48×48 or 80×80 CSS points to evaluate apparent size; viewing the image enlarged is only a geometry inspection. `displayPointSize` and `backingScale` are recorded in the original story JSON. These are intended full-artboard sizes, not the body diameter.

## Retrieval evidence

Skill: `apple-dev-patterns`. Query: `Metal offscreen render MTLTexture storageMode shared readback after MTLCommandBuffer completion AVAssetWriter deterministic animation frame capture`. Result: `无需 Expert Delta`; no hit keys or adopted records. Exact rendering behavior was verified against the downloaded official Runtime 6.25.1 headers, source, renderer tests, and compiled execution.

The obsolete `RiveRenderer(context:)` declaration is present in a public header but its class symbol is absent from the downloaded binary; that failed probe is not used. The working path is `Worker` → `File` → `Rive` → `makeRenderer()` → `RiveUIRendererConfiguration` → `draw(... to: MTLTexture ...)`.

No device layout, frame-rate, battery, or physical-device acceptance is implied by this offline renderer.
