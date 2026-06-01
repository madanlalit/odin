import SwiftUI

/// A compact, clickable disclosure row for the WhisperLog. Lives just
/// above the log and shows the entry count plus a chevron. Tapping
/// toggles expansion. Used to collapse traces after a run completes.
struct WhisperLogDisclosure: View {
    let entryCount: Int
    let isExpanded: Bool
    var onToggle: () -> Void

    @SwiftUI.State private var hovering: Bool = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: OdinTokens.Space.s8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(OdinTokens.Color.ink3)
                Text(label)
                    .font(OdinTokens.Font.bodyEm)
                    .foregroundStyle(OdinTokens.Color.ink2)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hovering ? OdinTokens.Color.amber : OdinTokens.Color.ink3)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .padding(.horizontal, OdinTokens.Space.s20)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Hide traces" : "Show traces")
        .onHover { hovering = $0 }
        .animation(OdinMotion.current.snap, value: hovering)
        .animation(OdinMotion.current.rise, value: isExpanded)
    }

    private var label: String {
        if entryCount == 0 { return "No traces yet" }
        if entryCount == 1 { return "1 step" }
        return "\(entryCount) steps"
    }
}

/// The WhisperLog — a vertical list of the agent's recent actions.
/// Each entry shows the time, an action verb, and (when known) a target.
/// Rows with a long `detail` are clickable to expand in place.
struct WhisperLog: View {
    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let timestamp: Date
        let title: String
        let detail: String?
        let level: Level
        enum Level { case info, success, warning, error }
    }

    let entries: [Entry]
    var maxVisible: Int = OdinTokens.Size.whisperMaxLines

    // One row at a time. Avoids a log that grows without bound when
    // every step has a long detail the user is investigating.
    @SwiftUI.State private var expandedID: UUID? = nil

    private var visible: [Entry] {
        Array(entries.suffix(maxVisible))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if visible.isEmpty {
                emptyState
            } else {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
                    WhisperRow(
                        entry: entry,
                        isFirst: index == 0,
                        isLast: index == visible.count - 1,
                        isCurrent: index == visible.count - 1,
                        isExpanded: expandedID == entry.id,
                        isExpandable: hasExpandableDetail(entry),
                        onTap: { toggle(entry.id) }
                    )
                }
            }
        }
    }

    private func hasExpandableDetail(_ entry: Entry) -> Bool {
        guard let detail = entry.detail, !detail.isEmpty else { return false }
        // Heuristic: a detail is expandable if it's long enough that
        // a single line wouldn't show it all. 60 chars is roughly the
        // width of a row with the timeline rail + time + title.
        return detail.count > 60
    }

    private func toggle(_ id: UUID) {
        expandedID = (expandedID == id) ? nil : id
    }

    private var emptyState: some View {
        HStack(spacing: OdinTokens.Space.s8) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(OdinTokens.Color.ink4)
            Text("Odin hasn't acted yet — your activity will appear here.")
                .font(OdinTokens.Font.body)
                .foregroundStyle(OdinTokens.Color.ink3)
            Spacer()
        }
        .padding(.horizontal, OdinTokens.Space.s20)
        .frame(height: 36)
    }
}

private struct WhisperRow: View {
    let entry: WhisperLog.Entry
    let isFirst: Bool
    let isLast: Bool
    let isCurrent: Bool
    let isExpanded: Bool
    let isExpandable: Bool
    let onTap: () -> Void

    @SwiftUI.State private var hovering: Bool = false

    var body: some View {
        // Only the row's content area is tappable. The timeline rail
        // stays passive so the user can still hover the dot for context
        // (e.g. a tooltip with the full timestamp) without triggering
        // expand on every stray click.
        HStack(alignment: .top, spacing: OdinTokens.Space.s12) {
            timelineRail
            content
                .contentShape(Rectangle())
                .onTapGesture(perform: isExpandable ? onTap : {})
        }
        .padding(.horizontal, OdinTokens.Space.s20)
        .padding(.vertical, isExpanded ? OdinTokens.Space.s8 : OdinTokens.Space.s4)
        .background(
            Rectangle()
                .fill(hovering ? OdinTokens.Color.surfaceHover : .clear)
        )
        .animation(OdinMotion.current.snap, value: hovering)
        .animation(OdinMotion.current.rise, value: isExpanded)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: OdinTokens.Space.s6) {
                Text(timeLabel)
                    .font(OdinTokens.Font.mono)
                    .foregroundStyle(OdinTokens.Color.ink4)
                Text(entry.title)
                    .font(OdinTokens.Font.bodyEm)
                    .foregroundStyle(OdinTokens.Color.ink)
                    .lineLimit(1)
                if !isExpanded, let detail = entry.detail, !detail.isEmpty {
                    Text(detail)
                        .font(OdinTokens.Font.body)
                        .foregroundStyle(OdinTokens.Color.ink2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
                if isExpandable {
                    // Explicit "Show more / Show less" affordance on
                    // each row. The whole row is still clickable as a
                    // convenience, but the button is the discoverable
                    // action — it makes clear that something can be
                    // expanded, which a chevron alone doesn't.
                    Button(isExpanded ? "Show less" : "Show more") {
                        onTap()
                    }
                    .buttonStyle(.odinText)
                }
            }
            if isExpanded, let detail = entry.detail, !detail.isEmpty {
                Text(detail)
                    .font(OdinTokens.Font.body)
                    .foregroundStyle(OdinTokens.Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var timelineRail: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(OdinTokens.Color.hairline)
                .frame(width: 1, height: 4)
                .opacity(isFirst ? 0 : 1)
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
                .overlay(
                    Circle()
                        .stroke(isCurrent ? OdinTokens.Color.amber.opacity(0.4) : .clear, lineWidth: 3)
                        .frame(width: 14, height: 14)
                )
            Rectangle()
                .fill(OdinTokens.Color.hairline)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
                .opacity(isLast ? 0 : 1)
        }
        .frame(width: 14)
        .padding(.top, 6)  // aligns the dot with the row's text baseline
    }

    private var dotColor: Color {
        switch entry.level {
        case .info:    return OdinTokens.Color.ink4
        case .success: return OdinTokens.Color.success
        case .warning: return OdinTokens.Color.amberBright
        case .error:   return OdinTokens.Color.danger
        }
    }

    private var timeLabel: String {
        let s = Self.formatter.string(from: entry.timestamp)
        return s
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
