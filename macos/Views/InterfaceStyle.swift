import SwiftUI
import AppKit

// Shared conventions. System text styles, semantic colours and Liquid Glass (macOS 26+)
// carry the appearance; older systems fall back to the equivalent native materials.
enum InterfaceStyle {
    static let sidebarMinimum: CGFloat = 170
    static let inspectorMinimum: CGFloat = 230
    static let detailMinimum: CGFloat = 320
    static let windowMinimum = NSSize(width: 820, height: 520)
    static let controlSize: CGFloat = 28
    /// Corner radius of the floating player and status cards, matching system popovers/panels.
    static let floatingRadius: CGFloat = 20
    /// Gap between floating chrome and the window edges.
    static let floatingMargin: CGFloat = 12
    // AppKit tables use the standard 13 pt body size so they match Finder, Music and Mail.
    static let tableFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    static let tableHeaderFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
    static let timeFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
}

/// User-selectable app appearance (IINA-style), persisted with the other preferences.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Native empty/placeholder content. A thin wrapper so call sites stay concise.
struct EmptyState<Actions: View>: View {
    let symbol: String
    let title: String
    let detail: String
    @ViewBuilder var actions: () -> Actions
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(detail)
        } actions: {
            actions()
        }
    }
}
extension EmptyState where Actions == EmptyView {
    init(symbol: String, title: String, detail: String) {
        self.init(symbol: symbol, title: title, detail: detail) { EmptyView() }
    }
}

/// A floating surface: Liquid Glass on macOS 26+, a vibrant material before that, and an
/// opaque semantic surface when Reduce Transparency or Increase Contrast is enabled.
struct FloatingGlass: ViewModifier {
    var radius: CGFloat = InterfaceStyle.floatingRadius
    var tint: Color?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if reduceTransparency || contrast == .increased {
            content
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay { shape.strokeBorder(Color(nsColor: .separatorColor)) }
        } else if #available(macOS 26.0, *) {
            content.glassEffect(tint.map { .regular.tint($0) } ?? .regular, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .background { if let tint { shape.fill(tint) } }
                .overlay { shape.strokeBorder(.primary.opacity(0.08)) }
                .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        }
    }
}
extension View {
    func floatingGlass(radius: CGFloat = InterfaceStyle.floatingRadius, tint: Color? = nil) -> some View {
        modifier(FloatingGlass(radius: radius, tint: tint))
    }
}

/// Compact floating card for import progress, notices and recoverable errors.
struct StatusBanner<Actions: View>: View {
    let symbol: String?
    let text: String
    var tint: Color?
    var progress = false
    @ViewBuilder var actions: () -> Actions
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if progress {
                ProgressView().controlSize(.small).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            } else if let symbol {
                Image(systemName: symbol).foregroundStyle(tint ?? .secondary).accessibilityHidden(true)
            }
            Text(text).font(.callout).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            actions().controlSize(.small)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .floatingGlass(radius: 14, tint: tint?.opacity(0.18))
    }
}
