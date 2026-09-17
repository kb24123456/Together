import AppKit
import SwiftUI

// macOS-only framework regression harness. Opens a temporary native window for 5 seconds.
// It checks SwiftUI target geometry; it does not validate the iOS Sheet or gestures.
struct Probe: View {
    @Namespace private var viewport
    @State private var scrollID: Int? = 183
    @State private var requested = 183
    @State private var centered = -1
    @State private var viewportWidth: CGFloat = 384
    var body: some View {
        VStack {
            Text("Isolated ruler geometry check").font(.caption)
            GeometryReader { outer in
                let width = outer.size.width
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(0..<288, id: \.self) { index in
                            VStack {
                                Text(String(index)).font(.system(size: 8)).fixedSize()
                                Capsule().frame(width: 2.6, height: 34)
                            }
                            .frame(width: 20, height: 70)
                            .id(index)
                            .onGeometryChange(for: Bool.self) { cell in
                                let center = cell.frame(in: .named(viewport)).midX
                                return center >= width / 2 - 10 && center < width / 2 + 10
                            } action: { isCentered in
                                if isCentered {
                                    centered = index
                                    print("CENTER requested=\(requested) actual=\(index)")
                                }
                            }
                        }
                    }.scrollTargetLayout()
                .padding(.horizontal, (width - 20) / 2)
                }
                .scrollTargetBehavior(.viewAligned(limitBehavior: .never, anchor: .center))
                .scrollPosition(id: $scrollID, anchor: .center)
                .onScrollGeometryChange(for: String.self) { g in
                    "offset=\(g.contentOffset.x) inset=\(g.contentInsets.leading) index=\(Int(((g.contentOffset.x + g.contentInsets.leading) / 20).rounded()))"
                } action: { _, value in print("OFFSET requested=\(requested) \(value)") }
                .overlay { Rectangle().fill(.red).frame(width: 1).allowsHitTesting(false) }
            }.coordinateSpace(name: viewport).frame(height: 100)
            Text("requested \(requested) / centered \(centered)")
        }
        .padding(24)
        .frame(width: viewportWidth, height: 200)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { viewportWidth = 320 }
            for (delay, index) in [(0.6, 183), (1.6, 0), (2.6, 287), (3.6, 135), (4.8, 135)] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    precondition(centered == index, "Expected centered index \(index), got \(centered)")
                    print("PASS centered index \(index)")
                }
            }
            for (delay, index) in [(1.0, 0), (2.0, 287), (3.0, 135)] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    requested = index
                    scrollID = index
                }
            }
        }
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 384, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
window.title = "Together ruler geometry verification"
window.contentView = NSHostingView(rootView: Probe())
window.orderFront(nil)
DispatchQueue.main.asyncAfter(deadline: .now() + 5.3) {
    window.orderOut(nil)
    print("PROBE COMPLETE")
    exit(0)
}
app.run()
