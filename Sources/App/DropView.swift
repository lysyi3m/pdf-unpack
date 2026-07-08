import SwiftUI
import AppKit

struct DropView: View {
    @EnvironmentObject var state: AppState
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(targeted ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                    .frame(width: 92, height: 92)
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 38, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(targeted ? Color.accentColor : Color.secondary)
            }

            VStack(spacing: 6) {
                Text("Drop a PDF here")
                    .font(.title2.weight(.semibold))
                Text("or click to choose · ⌘O")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(targeted ? Color.accentColor.opacity(0.06) : Color.clear)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            targeted ? Color.accentColor : Color.secondary.opacity(0.35),
                            style: StrokeStyle(lineWidth: 1.5, dash: [7, 6])
                        )
                }
        }
        .padding(24)
        // Whole padded area is clickable, not just the text/icon.
        .contentShape(Rectangle())
        .onTapGesture { state.presentOpenPanel() }
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .animation(.easeInOut(duration: 0.15), value: targeted)
        .dropDestination(for: URL.self) { urls, _ in
            guard let pdf = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) else { return false }
            state.load(url: pdf)
            return true
        } isTargeted: { targeted = $0 }
    }
}
