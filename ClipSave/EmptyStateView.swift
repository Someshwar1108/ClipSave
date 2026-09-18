import SwiftUI

/// Empty states for the clip list.
///
/// The "nothing yet" case doubles as the app's discovery surface: ⌘⇧V and
/// ⌘1–⌘9 are otherwise only documented in Settings, which a menu-bar app's
/// users rarely open.
struct EmptyStateView: View {
    enum Kind: Equatable {
        case noTemporaryClips
        case noPermanentClips
        case noSearchMatches(query: String)
        case noFilterMatches(ClipFilter)
    }

    let kind: Kind
    let shortcutDisplay: String
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbolName)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 8)

            Text(title)
                .font(.system(size: 14, weight: .semibold))

            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            switch kind {
            case .noTemporaryClips, .noPermanentClips:
                cheatSheet.padding(.top, 16)
            case .noSearchMatches, .noFilterMatches:
                Button(resetTitle, action: onReset)
                    .buttonStyle(.link)
                    .font(.system(size: 11.5))
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }

    private var symbolName: String {
        switch kind {
        case .noTemporaryClips: return "list.clipboard"
        case .noPermanentClips: return "pin"
        case .noSearchMatches: return "magnifyingglass"
        case .noFilterMatches: return "line.3.horizontal.decrease.circle"
        }
    }

    private var title: String {
        switch kind {
        case .noTemporaryClips: return "Nothing copied yet"
        case .noPermanentClips: return "No pinned clips"
        case .noSearchMatches: return "No matches"
        case .noFilterMatches(let filter): return "No \(filter.title.lowercased())"
        }
    }

    private var message: String {
        switch kind {
        case .noTemporaryClips:
            return "Copy anything and it lands here automatically."
        case .noPermanentClips:
            return "Pin a temporary clip to keep it here for good."
        case .noSearchMatches(let query):
            return "Nothing matches “\(query)”."
        case .noFilterMatches(let filter):
            return "This tab has no \(filter.title.lowercased()) clips."
        }
    }

    private var resetTitle: String {
        switch kind {
        case .noSearchMatches: return "Clear search"
        default: return "Show all clips"
        }
    }

    private var cheatSheet: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(shortcutRows, id: \.0) { keys, description in
                HStack(spacing: 8) {
                    Text(keys)
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .frame(minWidth: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(0.11))
                        )
                    Text(description)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var shortcutRows: [(String, String)] {
        [
            (shortcutDisplay, "Open ClipSave anywhere"),
            ("↑ ↓", "Move selection"),
            ("↩", "Copy & close"),
            ("⌘1–9", "Copy by number"),
            ("⌘⇧4", "Screenshot → auto-captured")
        ]
    }
}
