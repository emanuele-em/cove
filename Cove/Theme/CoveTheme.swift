import SwiftUI
import AppKit

enum CoveTheme {
    static let bg         = Color(nsColor: .windowBackgroundColor)
    static let bgAlt      = Color(nsColor: .controlBackgroundColor)
    static let bgSubtle   = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    static let bgHover    = Color(nsColor: .quaternaryLabelColor)
    static let bgSelected = Color(nsColor: .selectedContentBackgroundColor)

    static let fg         = Color.primary
    static let fgDim      = Color.secondary

    static let border     = Color(nsColor: .separatorColor)
    static let accent     = Color.accentColor
    static let error      = Color.red
    static let overlayBg  = Color.black.opacity(0.5)

    // SQL highlight colors (adaptive)
    static let sqlKeyword = Color(nsColor: .systemBlue)
    static let sqlString  = Color(nsColor: .systemOrange)
    static let sqlNumber  = Color(nsColor: .systemGreen)
    static let sqlComment = Color(nsColor: .systemGray)

    // Row status backgrounds (adaptive tints)
    static let bgPending  = Color.green.opacity(0.1)
    static let bgDeleted  = Color.red.opacity(0.1)

    static let accentHex = Color.accentColor.hexString
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    var hexString: String {
        let nsColor = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let r = Int(round(nsColor.redComponent * 255))
        let g = Int(round(nsColor.greenComponent * 255))
        let b = Int(round(nsColor.blueComponent * 255))
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}
