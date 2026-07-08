import SwiftUI
import AppKit

struct DropView: View {
    @EnvironmentObject var state: AppState
    @State private var targeted = false

    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
            .foregroundStyle(targeted ? Color.accentColor : Color.secondary)
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: "doc.badge.plus").font(.system(size: 40))
                    Text("Drop a PDF here").font(.title3)
                    Text("or click to choose · ⌘O").foregroundStyle(.secondary)
                }
            }
            .padding(30)
            // Whole padded area is clickable, not just the text/border.
            .contentShape(Rectangle())
            .onTapGesture { state.presentOpenPanel() }
            .onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let pdf = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) else { return false }
                state.load(url: pdf)
                return true
            } isTargeted: { targeted = $0 }
    }
}
