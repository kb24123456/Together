import Foundation
import CoreGraphics
import Testing
@testable import Together

struct MascotNoticeTests {
    @Test func newerResultSurvivesOldDismissalAndCompletion() {
        var state = MascotNoticeState()
        let first = MascotNoticeRequest(id: UUID(), message: "已更新标题", announcement: "任务，已更新标题")
        let second = MascotNoticeRequest(id: UUID(), message: "已更新备注", announcement: "任务，已更新备注")
        state.replace(with: first)
        #expect(state.dismiss(id: first.id) == true)
        state.replace(with: second)
        #expect(state.finish(id: first.id) == false)
        #expect(state.dismiss(id: first.id) == false)
        #expect(state.request == second)
        #expect(!state.isDismissing)
        #expect(state.finish(id: second.id) == false)
        #expect(state.dismiss(id: second.id) == true)
        #expect(state.dismiss(id: second.id) == false)
        #expect(state.finish(id: second.id) == true)
        #expect(state.request == nil)
    }

    @Test func cancellationDiscardsWaitingAndClosingResults() {
        for dismissFirst in [false, true] {
            var state = MascotNoticeState()
            let request = MascotNoticeRequest(id: UUID(), message: "已更新", announcement: "已更新")
            state.replace(with: request)
            if dismissFirst { state.dismiss(id: request.id) }
            state.cancel()
            #expect(state.request == nil)
            #expect(!state.isDismissing)
            #expect(state.dismiss(id: request.id) == false)
            #expect(state.finish(id: request.id) == false)
        }
    }

    @Test func capsuleUsesBodyHeightAndVerticalPositionInsteadOfCanvasSize() {
        let canvas = CGRect(x: 300, y: 60, width: 512, height: 512)
        let body = MascotNoticeGeometry.body(in: canvas)
        #expect(body == CGRect(x: 372, y: 116, width: 368, height: 368))
        let home = CGRect(x: 336, y: 66, width: 40, height: 40)
        let window = CGRect(x: 0, y: 0, width: 390, height: 844)
        let short = MascotNoticeGeometry.expanded(from: home, in: window, safeInsets: 28, contentWidth: 139)
        let long = MascotNoticeGeometry.expanded(from: home, in: window, safeInsets: 28, contentWidth: 900)
        #expect(short.height == 40 && long.height == 40)
        #expect(short.midY == home.midY && long.midY == home.midY)
        #expect(short.midX == window.midX && long.midX == window.midX)
        #expect(short.width == 139)
        #expect(long.minX == 28 && long.maxX == 362)
    }

    @Test func geometryHonorsLandscapeInsetsAndNonzeroWindowOrigin() {
        let body = CGRect(x: 700, y: 50, width: 40, height: 40)
        let window = CGRect(x: 10, y: 0, width: 800, height: 390)
        let result = MascotNoticeGeometry.expanded(from: body, in: window, safeInsets: 60, contentWidth: 1000)
        #expect(result.midX == window.midX)
        #expect(result.minX == 70 && result.maxX == 750)
        #expect(result.minY == 50 && result.height == 40)
    }
}

#if canImport(UIKit)
import UIKit

@MainActor
struct MascotNativeNoticeTests {
    @Test func sameArtworkExpandsAtLeftAndReturnsToNativeAnchor() throws {
        let fixture = try NoticeFixture()
        defer { fixture.remove() }
        let artwork = fixture.visual.artwork
        let source = artwork.convert(artwork.bounds, to: fixture.window)
        let body = MascotNoticeGeometry.body(in: source)
        var announced: [UUID] = []
        fixture.visual.onNoticePresented = { announced.append($0.id) }
        let request = MascotNoticeRequest(id: UUID(), message: "已更新备注", announcement: "任务，已更新备注")
        fixture.visual.showNotice(request)
        let notice = artwork.superview as? TaskUpdateNotice
        #expect(notice != nil)
        #expect(fixture.visual.artwork === artwork)
        #expect(abs((notice?.frame.midX ?? 0) - fixture.window.bounds.midX) < 0.01)
        #expect(abs((notice?.frame.midY ?? 0) - body.midY) < 0.01)
        #expect(abs((notice?.frame.height ?? 0) - body.height) < 0.01)
        let movedBody = MascotNoticeGeometry.body(in: artwork.convert(artwork.bounds, to: fixture.window))
        #expect(abs(movedBody.minX - (notice?.frame.minX ?? 0)) < 0.01)
        #expect(announced == [request.id])
        #expect(notice?.accessibilityLabel == request.announcement)
        fixture.visual.dismissNotice(id: request.id)
        #expect(artwork.superview === fixture.home)
        #expect(artwork.convert(artwork.bounds, to: fixture.window) == source)
    }

    @Test func replacementAndNavigationNeverLeaveAnOrphanCapsule() throws {
        let fixture = try NoticeFixture()
        defer { fixture.remove() }
        let first = MascotNoticeRequest(id: UUID(), message: "已更新标题", announcement: "标题")
        let next = MascotNoticeRequest(id: UUID(), message: "已更新日期、时间和提醒", announcement: "日期")
        fixture.visual.showNotice(first)
        let surface = fixture.visual.artwork.superview
        fixture.visual.showNotice(next)
        #expect(fixture.visual.artwork.superview === surface)
        fixture.visual.dismissNotice(id: first.id)
        #expect(fixture.visual.artwork.superview === surface)
        fixture.visual.prepare(from: .home, to: .editor(UUID()))
        #expect(surface?.superview == nil)
        #expect(!(fixture.visual.artwork.superview is TaskUpdateNotice))
        fixture.visual.dismissNotice(id: next.id)
        #expect(!(fixture.visual.artwork.superview is TaskUpdateNotice))
    }

    @Test func hiddenSurfaceDiscardsPendingRequest() throws {
        let fixture = try NoticeFixture()
        defer { fixture.remove() }
        fixture.visual.showNotice(MascotNoticeRequest(id: UUID(), message: "已更新", announcement: "已更新"))
        let surface = fixture.visual.artwork.superview
        fixture.visual.update(rive: nil, animatedArtwork: false, staticAsset: "MascotIdle",
                              playbackAllowed: false, motionAllowed: false, visible: false)
        #expect(surface?.superview == nil)
        fixture.visual.update(rive: nil, animatedArtwork: false, staticAsset: "MascotIdle",
                              playbackAllowed: false, motionAllowed: false, visible: true)
        #expect(fixture.visual.artwork.superview === fixture.home)
    }

    @Test func pendingResultWaitsForTheNativeReturnToHome() throws {
        let fixture = try NoticeFixture()
        defer { fixture.remove() }
        let editor = MascotAnchorView(surface: .editor(UUID()))
        editor.frame = CGRect(x: 130, y: 70, width: 42, height: 42)
        fixture.window.addSubview(editor)
        fixture.visual.register(editor)
        fixture.visual.prepare(from: .home, to: editor.surface)
        fixture.visual.arrive(at: editor.surface)
        fixture.visual.prepare(from: editor.surface, to: .home)
        let request = MascotNoticeRequest(id: UUID(), message: "已更新备注", announcement: "备注")
        fixture.visual.showNotice(request)
        #expect(!(fixture.visual.artwork.superview is TaskUpdateNotice))
        fixture.visual.arrive(at: .home)
        #expect(fixture.visual.artwork.superview is TaskUpdateNotice)
        fixture.visual.dismissNotice(id: request.id)
        #expect(fixture.visual.artwork.superview === fixture.home)
    }
}

@MainActor
private struct NoticeFixture {
    let window: UIWindow
    let home = MascotAnchorView(surface: .home)
    let visual = MascotVisualTransfer()

    init() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        home.frame = CGRect(x: 328, y: 60, width: MascotArtworkView.canvasSide, height: MascotArtworkView.canvasSide)
        window.addSubview(home)
        visual.update(rive: nil, animatedArtwork: false, staticAsset: "MascotIdle",
                      playbackAllowed: false, motionAllowed: false, visible: true)
        visual.register(home)
    }

    func remove() {
        visual.cancelNotice()
        for view in window.subviews { view.removeFromSuperview() }
    }
}
#endif
