import SwiftUI
import AppKit

// Small shared conventions; native materials and semantic colours handle appearance.
enum InterfaceStyle {
    static let panelPadding: CGFloat = 16
    static let sidebarMinimum: CGFloat = 150
    static let inspectorMinimum: CGFloat = 210
    static let windowMinimum = NSSize(width: 820, height: 520)
    static let background = Color(nsColor: .windowBackgroundColor)
    static let controlSize: CGFloat = 28
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
