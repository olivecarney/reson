import SwiftUI
import AppKit

// Small shared conventions; native materials and semantic colours handle appearance.
enum InterfaceStyle {
    static let panelPadding: CGFloat = 16
    static let sidebarMinimum: CGFloat = 150
    static let inspectorMinimum: CGFloat = 210
    static let windowMinimum = NSSize(width: 820, height: 520)
    static let background = Color(nsColor: .textBackgroundColor)
    static let controlSize: CGFloat = 28
    static let heading = Font.system(size: 18, weight: .medium)
    static let tableFont = NSFont.systemFont(ofSize: 13, weight: .regular)
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 28, weight: .light)).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Keep glass on controls, with one shared container for nearby effects.
struct ChromeGlassGroup: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            GlassEffectContainer(spacing: 6) { content }
        } else { content }
    }
}

struct ControlGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content.background(Color(nsColor: .controlBackgroundColor), in: Capsule())
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}

// AppKit chooses the native sidebar/title-bar material and responds to system appearance.
// Accessibility gets an opaque semantic surface rather than another translucent layer.
struct NativeBarMaterial: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func makeNSView(context: Context) -> NativeMaterialSurface { NativeMaterialSurface() }
    func updateNSView(_ view: NativeMaterialSurface, context: Context) {
        view.configure(material: material, opaque: reduceTransparency || contrast == .increased)
    }
}

final class NativeMaterialSurface: NSView {
    private let effect = NSVisualEffectView()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        effect.frame = bounds
        effect.autoresizingMask = [.width, .height]
        effect.state = .followsWindowActiveState
        addSubview(effect)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(material: NSVisualEffectView.Material, opaque: Bool) {
        effect.material = material
        effect.blendingMode = material == .sidebar ? .behindWindow : .withinWindow
        effect.isHidden = opaque
        wantsLayer = true
        layer?.backgroundColor = opaque ? NSColor.windowBackgroundColor.cgColor : nil
    }
}
