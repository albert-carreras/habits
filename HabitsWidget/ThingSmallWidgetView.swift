import SwiftUI
import WidgetKit

struct ThingsSmallWidget: Widget {
    let kind = "ThingsSmallWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: ThingWidgetProvider()
        ) { entry in
            ThingSmallWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Things")
        .description("Your next things to do")
        .supportedFamilies([.systemSmall])
    }
}

struct ThingSmallWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme

    let entry: ThingWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WidgetTheme.accent(for: colorScheme))

                Text("Things")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WidgetTheme.accent(for: colorScheme))
                    .textCase(.uppercase)
            }
            .padding(.bottom, 10)

            if entry.things.isEmpty {
                Spacer()
                Text("All clear")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WidgetTheme.muted(for: colorScheme))
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(entry.things) { thing in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(WidgetTheme.accent(for: colorScheme).opacity(0.5))
                                .frame(width: 6, height: 6)

                            Text(thing.title)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding()
    }
}
