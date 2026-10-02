import Foundation

final class DemoFrameSource: FrameSource {
    func makeFrame(time: TimeInterval, drawableWidth: Int, drawableHeight: Int) -> FramebufferImage {
        let width = max(320, min(1280, drawableWidth))
        let height = max(180, min(720, drawableHeight))
        var bytes = [UInt8](repeating: 0, count: width * height * 4)

        let wave = Float((sin(time * 1.2) + 1.0) * 0.5)
        let pulse = Float((sin(time * 2.4) + 1.0) * 0.5)

        for y in 0 ..< height {
            for x in 0 ..< width {
                let offset = (y * width + x) * 4
                let fx = Float(x) / Float(max(1, width - 1))
                let fy = Float(y) / Float(max(1, height - 1))
                let grid = ((x / 24) + (y / 24)) % 2 == 0

                let redValue = (0.20 + 0.55 * fx + 0.20 * wave) * 255.0
                let greenValue = (0.18 + 0.45 * fy + 0.22 * pulse) * 255.0
                let blueBase: Float = grid ? 0.32 : 0.16
                let blueValue = (blueBase + 0.25 * (1.0 - fy)) * 255.0
                let red = UInt8(max(0, min(255, Int(redValue))))
                let green = UInt8(max(0, min(255, Int(greenValue))))
                let blue = UInt8(max(0, min(255, Int(blueValue))))

                bytes[offset + 0] = red
                bytes[offset + 1] = green
                bytes[offset + 2] = blue
                bytes[offset + 3] = 255
            }
        }

        drawInsetPanel(into: &bytes, width: width, height: height, title: "OpenBOR Mac V2 Host")
        return FramebufferImage(width: width, height: height, bytes: bytes)
    }

    private func drawInsetPanel(into bytes: inout [UInt8], width: Int, height: Int, title: String) {
        let panelX = max(24, width / 12)
        let panelY = max(24, height / 10)
        let panelW = min(width - panelX * 2, max(220, width / 3))
        let panelH = min(height - panelY * 2, max(92, height / 5))

        for y in panelY ..< panelY + panelH {
            for x in panelX ..< panelX + panelW {
                let offset = (y * width + x) * 4
                let border = x == panelX || x == panelX + panelW - 1 || y == panelY || y == panelY + panelH - 1
                bytes[offset + 0] = border ? 250 : 24
                bytes[offset + 1] = border ? 194 : 28
                bytes[offset + 2] = border ? 92 : 36
                bytes[offset + 3] = 255
            }
        }

        drawLabel(title, into: &bytes, width: width, originX: panelX + 18, originY: panelY + 18)
        drawLabel("Native AppKit + Metal runtime scaffold", into: &bytes, width: width, originX: panelX + 18, originY: panelY + 44, scale: 1)
    }

    private func drawLabel(_ text: String, into bytes: inout [UInt8], width: Int, originX: Int, originY: Int, scale: Int = 2) {
        let glyphs = Glyphs.data
        var cursorX = originX

        for character in text.uppercased() {
            guard let glyph = glyphs[character] else {
                cursorX += 4 * scale
                continue
            }

            for (row, pattern) in glyph.enumerated() {
                for column in 0 ..< 5 {
                    if pattern & (1 << (4 - column)) == 0 { continue }
                    for sy in 0 ..< scale {
                        for sx in 0 ..< scale {
                            let x = cursorX + column * scale + sx
                            let y = originY + row * scale + sy
                            let offset = (y * width + x) * 4
                            guard offset >= 0, offset + 3 < bytes.count else { continue }
                            bytes[offset + 0] = 240
                            bytes[offset + 1] = 236
                            bytes[offset + 2] = 220
                            bytes[offset + 3] = 255
                        }
                    }
                }
            }

            cursorX += 6 * scale
        }
    }
}

private enum Glyphs {
    static let data: [Character: [UInt8]] = [
        " ": [0, 0, 0, 0, 0, 0, 0],
        "+": [0, 4, 4, 31, 4, 4, 0],
        "-": [0, 0, 0, 31, 0, 0, 0],
        "2": [14, 17, 1, 6, 8, 16, 31],
        "A": [14, 17, 17, 31, 17, 17, 17],
        "B": [30, 17, 17, 30, 17, 17, 30],
        "C": [14, 17, 16, 16, 16, 17, 14],
        "D": [30, 17, 17, 17, 17, 17, 30],
        "E": [31, 16, 16, 30, 16, 16, 31],
        "F": [31, 16, 16, 30, 16, 16, 16],
        "G": [14, 17, 16, 23, 17, 17, 15],
        "H": [17, 17, 17, 31, 17, 17, 17],
        "I": [31, 4, 4, 4, 4, 4, 31],
        "K": [17, 18, 20, 24, 20, 18, 17],
        "L": [16, 16, 16, 16, 16, 16, 31],
        "M": [17, 27, 21, 21, 17, 17, 17],
        "N": [17, 25, 21, 19, 17, 17, 17],
        "O": [14, 17, 17, 17, 17, 17, 14],
        "P": [30, 17, 17, 30, 16, 16, 16],
        "R": [30, 17, 17, 30, 20, 18, 17],
        "S": [15, 16, 16, 14, 1, 1, 30],
        "T": [31, 4, 4, 4, 4, 4, 4],
        "U": [17, 17, 17, 17, 17, 17, 14],
        "V": [17, 17, 17, 17, 17, 10, 4],
        "W": [17, 17, 17, 21, 21, 21, 10],
        "Y": [17, 17, 10, 4, 4, 4, 4]
    ]
}
