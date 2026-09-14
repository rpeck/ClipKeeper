import Testing
@testable import ClipKeeper

@Suite struct ColorParserTests {
    @Test func hex6() {
        let c = ColorParser.parse("#4cb39a")
        #expect(c != nil)
        #expect(c?.hex == "#4CB39A")
        #expect(c?.rgbString == "rgb(76, 179, 154)")
    }

    @Test func hex3() {
        #expect(ColorParser.parse("#fff")?.hex == "#FFFFFF")
    }

    @Test func hex8Alpha() {
        let c = ColorParser.parse("#FF000080")
        #expect(c?.hex == "#FF000080")
        #expect(c.map { Int($0.alpha * 100) } == 50)
    }

    @Test func rgb() {
        #expect(ColorParser.parse("rgb(76, 179, 154)")?.hex == "#4CB39A")
        #expect(ColorParser.parse("rgba(255, 0, 0, 0.5)")?.hex == "#FF000080")
    }

    @Test func hsl() {
        #expect(ColorParser.parse("hsl(0, 100%, 50%)")?.hex == "#FF0000")
        #expect(ColorParser.parse("hsl(120, 100%, 50%)")?.hex == "#00FF00")
    }

    @Test func notColors() {
        #expect(ColorParser.parse("#hashtag") == nil)
        #expect(ColorParser.parse("rgb(300, 0, 0)") == nil)
        #expect(ColorParser.parse("hello") == nil)
        #expect(ColorParser.parse("#12") == nil)
        #expect(ColorParser.parse("#abc def") == nil)
    }
}
