import ActivityKit
import SwiftUI
import WidgetKit

@main
struct IslandBundle: WidgetBundle {
    var body: some Widget {
        IslandWidget()
    }
}

private struct Mark: View {
    let running: Int

    var body: some View {
        Image(systemName: running > 0 ? "cpu" : "checkmark.circle.fill")
            .foregroundStyle(running > 0 ? Color.green : Color.secondary)
    }
}

private struct Lines: View {
    let lines: [IslandAttributes.Line]
    let titles: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(lines, id: \.thread) { l in
                VStack(alignment: .leading, spacing: 1) {
                    if titles { Text(l.title).font(.caption.weight(.semibold)).lineLimit(1) }
                    Text(l.doing).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func link(_ s: IslandAttributes.ContentState) -> URL? {
    URL(string: "backplane://open?thread=" + (s.lines.first?.thread ?? ""))
}

struct IslandWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: IslandAttributes.self) { ctx in
            let s = ctx.state
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Mark(running: s.running)
                    Text(s.headline).font(.headline).lineLimit(1)
                    Spacer()
                    if s.running > 1 { Text("\(s.running)").font(.headline.monospacedDigit()) }
                }
                Lines(lines: Array(s.lines.prefix(3)), titles: s.running > 1)
            }
            .padding()
            .widgetURL(link(s))
        } dynamicIsland: { ctx in
            let s = ctx.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Mark(running: s.running).font(.title3).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(s.running)").font(.title3.monospacedDigit().bold()).padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(s.headline).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Lines(lines: Array(s.lines.prefix(2)), titles: s.running > 1)
                }
            } compactLeading: {
                Mark(running: s.running)
            } compactTrailing: {
                Text("\(s.running)").monospacedDigit()
            } minimal: {
                Mark(running: s.running)
            }
            .widgetURL(link(s))
        }
    }
}
