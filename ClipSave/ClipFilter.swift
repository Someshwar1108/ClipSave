import SwiftUI

/// Type filter applied on top of the Temporary/Permanent tab and the search
/// field. Links are carved out of text rather than overlapping it, so the chip
/// counts always add up to the `all` count.
nonisolated enum ClipFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case text
    case images
    case links
    case files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .text: return "Text"
        case .images: return "Images"
        case .links: return "Links"
        case .files: return "Files"
        }
    }

    func matches(_ clip: Clip) -> Bool {
        switch self {
        case .all:
            return true
        case .images:
            if case .image = clip.content { return true }
            return false
        case .files:
            if case .file = clip.content { return true }
            return false
        case .links:
            return clip.content.plainText != nil && clip.detectedURL != nil
        case .text:
            // Everything textual that isn't a bare link — including colour
            // literals, which are still text as far as the user is concerned.
            return clip.content.plainText != nil && clip.detectedURL == nil
        }
    }
}

/// Horizontal row of filter pills with live counts.
struct FilterChipsView: View {
    @Binding var selection: ClipFilter
    let counts: [ClipFilter: Int]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 5) {
                ForEach(ClipFilter.allCases) { filter in
                    chip(filter)
                }
            }
            .padding(.horizontal, 12)
        }
        .scrollIndicators(.hidden)
        .frame(height: 22)
    }

    private func chip(_ filter: ClipFilter) -> some View {
        let count = counts[filter] ?? 0
        let isSelected = selection == filter
        // `All` always carries its count; the others only once they have
        // something in them, which keeps the row short in the common case.
        let showsCount = filter == .all || count > 0

        return Button {
            selection = filter
        } label: {
            HStack(spacing: 4) {
                Text(filter.title)
                    .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
                if showsCount {
                    Text(verbatim: "\(count)")
                        .font(.system(size: 9.5))
                        .opacity(isSelected ? 0.85 : 0.65)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(isSelected ? Color.accentColor : Color.clear)
            )
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? Color.clear : Color.primary.opacity(0.18),
                    lineWidth: 1
                )
            )
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            // Empty categories stay tappable — selecting one and seeing the
            // empty state is clearer than a control that silently does nothing.
            .opacity(count == 0 && !isSelected ? 0.45 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(filter.title), \(count) clips")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
