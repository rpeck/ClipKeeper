import Foundation
import Testing
@testable import ClipKeeper

@Suite struct CropModelTests {
    let size = CGSize(width: 640, height: 360)

    @Test func startsWhole() {
        let m = CropModel(imageSize: size)
        #expect(m.isWhole)
        #expect(!m.canCrop)
        #expect(m.rect == CGRect(x: 0, y: 0, width: 640, height: 360))
    }

    @Test func dragOnWholeImageDrawsARectangle() {
        var m = CropModel(imageSize: size)
        let mode = m.dragMode(at: CGPoint(x: 100, y: 50))
        #expect(mode == .draw(origin: CGPoint(x: 100, y: 50)))
        m.drag(mode, to: CGPoint(x: 300, y: 250))
        #expect(m.rect == CGRect(x: 100, y: 50, width: 200, height: 200))
        #expect(m.canCrop)
    }

    @Test func drawingBackwardsNormalizes() {
        var m = CropModel(imageSize: size)
        let mode = m.dragMode(at: CGPoint(x: 300, y: 250))
        m.drag(mode, to: CGPoint(x: 100, y: 50))
        #expect(m.rect == CGRect(x: 100, y: 50, width: 200, height: 200))
    }

    @Test func drawingIsClampedToTheImage() {
        var m = CropModel(imageSize: size)
        let mode = m.dragMode(at: CGPoint(x: 600, y: 300))
        m.drag(mode, to: CGPoint(x: 900, y: 500))
        #expect(m.rect == CGRect(x: 600, y: 300, width: 40, height: 60))
    }

    @Test func dragInsidePartialRectangleMovesIt() {
        var m = CropModel(imageSize: size)
        m.drag(m.dragMode(at: CGPoint(x: 100, y: 50)), to: CGPoint(x: 300, y: 250))
        let mode = m.dragMode(at: CGPoint(x: 150, y: 100))
        #expect(mode == .move(original: CGRect(x: 100, y: 50, width: 200, height: 200), grab: CGPoint(x: 150, y: 100)))
        m.drag(mode, to: CGPoint(x: 250, y: 120))
        #expect(m.rect == CGRect(x: 200, y: 70, width: 200, height: 200))
    }

    @Test func movingStopsAtTheEdges() {
        var m = CropModel(imageSize: size)
        m.drag(m.dragMode(at: CGPoint(x: 100, y: 50)), to: CGPoint(x: 300, y: 250))
        let mode = m.dragMode(at: CGPoint(x: 150, y: 100))
        m.drag(mode, to: CGPoint(x: 900, y: 900))
        #expect(m.rect == CGRect(x: 440, y: 160, width: 200, height: 200))
    }

    @Test func dragOutsidePartialRectangleDrawsANewOne() {
        var m = CropModel(imageSize: size)
        m.drag(m.dragMode(at: CGPoint(x: 100, y: 50)), to: CGPoint(x: 300, y: 250))
        let mode = m.dragMode(at: CGPoint(x: 400, y: 300))
        #expect(mode == .draw(origin: CGPoint(x: 400, y: 300)))
        m.drag(mode, to: CGPoint(x: 500, y: 350))
        #expect(m.rect == CGRect(x: 400, y: 300, width: 100, height: 50))
    }

    @Test func cornerHandleResizesFromTheWholeImage() {
        var m = CropModel(imageSize: size)
        m.resize(.topLeft, from: m.rect, to: CGPoint(x: 40, y: 30))
        #expect(m.rect == CGRect(x: 40, y: 30, width: 600, height: 330))
        m.resize(.bottomRight, from: m.rect, to: CGPoint(x: 600, y: 300))
        #expect(m.rect == CGRect(x: 40, y: 30, width: 560, height: 270))
    }

    @Test func edgeHandlesMoveOneSide() {
        var m = CropModel(imageSize: size)
        m.resize(.right, from: m.rect, to: CGPoint(x: 320, y: 999))
        #expect(m.rect == CGRect(x: 0, y: 0, width: 320, height: 360))
        m.resize(.top, from: m.rect, to: CGPoint(x: -50, y: 100))
        #expect(m.rect == CGRect(x: 0, y: 100, width: 320, height: 260))
    }

    @Test func handleDraggedPastTheOppositeSideFlips() {
        var m = CropModel(imageSize: size)
        m.drag(m.dragMode(at: CGPoint(x: 100, y: 100)), to: CGPoint(x: 200, y: 200))
        m.resize(.left, from: m.rect, to: CGPoint(x: 260, y: 150))
        #expect(m.rect == CGRect(x: 200, y: 100, width: 60, height: 100))
    }

    @Test func resetRestoresTheWholeImage() {
        var m = CropModel(imageSize: size)
        m.drag(m.dragMode(at: CGPoint(x: 10, y: 10)), to: CGPoint(x: 50, y: 50))
        m.reset()
        #expect(m.isWhole)
    }
}
