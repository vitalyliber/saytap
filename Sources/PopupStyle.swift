import Cocoa

// How the pop-up looks. A style with a material blurs what's behind it; one without paints its background colours.
struct PopupStyle {
    let title: String
    let material: NSVisualEffectView.Material?
    // Top to bottom; one colour paints it flat.
    let background: [NSColor]
    let border: NSColor?
    let cornerRadius: CGFloat
    let design: NSFontDescriptor.SystemDesign
    let wordSize: CGFloat
    let text: NSColor
    let secondary: NSColor
    let accent: NSColor
    let speakerSymbol: String
    let phonetic: (prefix: String, suffix: String)
    let italicPartOfSpeech: Bool
    // The pop-up fades in without moving; only its speaker icon animates.
    let fadeIn: TimeInterval
}

extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(srgbRed: CGFloat(rgb >> 16 & 0xFF) / 255, green: CGFloat(rgb >> 8 & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

// From playful to prim; the menu lists them in this order.
let POPUP_STYLES = [
    PopupStyle(title: "Playful", material: nil, background: [NSColor(rgb: 0x7B5CFF), NSColor(rgb: 0xFF5FA2)], border: nil,
               cornerRadius: 20, design: .rounded, wordSize: 21, text: .white, secondary: .white.withAlphaComponent(0.78),
               accent: .white, speakerSymbol: "speaker.wave.3.fill", phonetic: ("[", "]"), italicPartOfSpeech: false,
               fadeIn: POPUP_QUICK_FADE),
    PopupStyle(title: "Standard", material: .popover, background: [], border: nil,
               cornerRadius: 12, design: .default, wordSize: 18, text: .labelColor, secondary: .secondaryLabelColor,
               accent: .controlAccentColor, speakerSymbol: "speaker.wave.2.fill", phonetic: ("[", "]"), italicPartOfSpeech: false,
               fadeIn: POPUP_QUICK_FADE),
    PopupStyle(title: "Minimal", material: nil, background: [.windowBackgroundColor], border: .separatorColor,
               cornerRadius: 8, design: .default, wordSize: 17, text: .labelColor, secondary: .secondaryLabelColor,
               accent: .secondaryLabelColor, speakerSymbol: "speaker.wave.1.fill", phonetic: ("", ""), italicPartOfSpeech: false,
               fadeIn: POPUP_QUICK_FADE),
    PopupStyle(title: "Formal", material: nil, background: [NSColor(rgb: 0xFBF7EE), NSColor(rgb: 0xF3ECDC)], border: NSColor(rgb: 0xC9BC9C),
               cornerRadius: 3, design: .serif, wordSize: 20, text: NSColor(rgb: 0x2B2620), secondary: NSColor(rgb: 0x7D705B),
               accent: NSColor(rgb: 0x7A5A2E), speakerSymbol: "speaker.wave.1", phonetic: ("/", "/"), italicPartOfSpeech: true,
               fadeIn: POPUP_SLOW_FADE),
]
let DEFAULT_POPUP_STYLE = "Playful"
let POPUP_STYLE_KEY = "popupStyle"
let POPUP_BORDER_WIDTH: CGFloat = 1

// Paints a style's background colours, with its corners and border. Dynamic colours follow light and dark mode.
final class PopupBackground: NSView {
    private let style: PopupStyle

    init(style: PopupStyle) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func makeBackingLayer() -> CALayer { CAGradientLayer() }

    override func viewDidMoveToWindow() {
        paint()
    }

    override func viewDidChangeEffectiveAppearance() {
        paint()
    }

    private func paint() {
        guard let layer = layer as? CAGradientLayer else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let colors = style.background.count == 1 ? style.background + style.background : style.background
            layer.colors = colors.map(\.cgColor)
            layer.borderColor = style.border?.cgColor
        }
        // The layer's y axis points up, so the first colour starts at the top.
        layer.startPoint = CGPoint(x: 0.5, y: 1)
        layer.endPoint = CGPoint(x: 0.5, y: 0)
        layer.borderWidth = style.border == nil ? 0 : POPUP_BORDER_WIDTH
        layer.cornerRadius = style.cornerRadius
        layer.masksToBounds = true
    }
}

// A blurred background clipped to rounded corners. Its layer's corner radius doesn't clip the blur, which then shows
// square corners; a mask image does.
func roundedEffectView(material: NSVisualEffectView.Material, cornerRadius: CGFloat) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = material
    view.state = .active
    let edge = 2 * cornerRadius + 1
    let mask = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
        NSColor.black.setFill()
        NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
        return true
    }
    mask.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
    mask.resizingMode = .stretch
    view.maskImage = mask
    return view
}
