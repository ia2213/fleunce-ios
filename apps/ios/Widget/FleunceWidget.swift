import WidgetKit
import SwiftUI

struct FleunceWidgetEntry: TimelineEntry {
    let date: Date
    let language: String
    let streak: Int
    let wordCount: Int
    let recentWords: [String]
    let levelLabel: String
    let nextGoal: String
}

struct FleunceWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FleunceWidgetEntry {
        FleunceWidgetEntry(
            date: Date(),
            language: "Spanish",
            streak: 5,
            wordCount: 42,
            recentWords: ["hola - hello", "gracias - thank you", "amigo - friend"],
            levelLabel: "Finding your pace",
            nextGoal: "Building vocabulary"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (FleunceWidgetEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FleunceWidgetEntry>) -> Void) {
        let entry = loadEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadEntry() -> FleunceWidgetEntry {
        let defaults = UserDefaults(suiteName: "group.no.william.fleunce") ?? UserDefaults.standard
        let language = defaults.string(forKey: "widget_language") ?? "Spanish"
        let streak = defaults.integer(forKey: "widget_streak")
        let wordCount = defaults.integer(forKey: "widget_word_count")
        let recentWords = defaults.stringArray(forKey: "widget_recent_words") ?? []
        let levelLabel = defaults.string(forKey: "widget_level_label") ?? "Getting to know you"
        let nextGoal = defaults.string(forKey: "widget_next_goal") ?? "Building vocabulary"

        return FleunceWidgetEntry(
            date: Date(),
            language: language,
            streak: streak > 0 ? streak : 3,
            wordCount: wordCount > 0 ? wordCount : 12,
            recentWords: recentWords.isEmpty ? ["hola - hello", "gracias - thank you", "bueno - good"] : recentWords,
            levelLabel: levelLabel,
            nextGoal: nextGoal
        )
    }
}

struct SmallWidgetView: View {
    var entry: FleunceWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "waveform")
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.96, green: 0.45, blue: 0.22))
                Text(entry.language)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.14))
                Spacer()
            }

            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(Color(red: 0.96, green: 0.45, blue: 0.22))
                    Text("\(entry.streak) session streak")
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }

                HStack(spacing: 6) {
                    Image(systemName: "book.fill")
                        .font(.caption2)
                        .foregroundStyle(Color(red: 0.35, green: 0.55, blue: 0.45))
                    Text("\(entry.wordCount) words")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.14))
                }
            }
        }
        .padding(14)
        .background(Color(red: 0.98, green: 0.96, blue: 0.93))
    }
}

struct MediumWidgetView: View {
    var entry: FleunceWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .foregroundStyle(Color(red: 0.96, green: 0.45, blue: 0.22))
                    Text(entry.language)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(Color(red: 0.96, green: 0.45, blue: 0.22))
                    Text("\(entry.streak) streak")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(red: 0.99, green: 0.93, blue: 0.81), in: Capsule())
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(entry.wordCount)")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.14))
                    Text("Words Learned")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 5) {
                    Text("Recent Words")
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.secondary)

                    ForEach(entry.recentWords.prefix(3), id: \.self) { word in
                        Text(word)
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.14))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(red: 0.98, green: 0.96, blue: 0.93))
    }
}

struct LargeWidgetView: View {
    var entry: FleunceWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FLEUNCE")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(Color(red: 0.96, green: 0.45, blue: 0.22))
                    Text(entry.language)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.14))
                }
                Spacer()
                Text(entry.levelLabel)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.99, green: 0.93, blue: 0.81), in: Capsule())
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(Color(red: 0.96, green: 0.45, blue: 0.22))
                        Text("\(entry.streak)")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                    }
                    Text("Sessions Streak")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "book.fill")
                            .foregroundStyle(Color(red: 0.35, green: 0.55, blue: 0.45))
                        Text("\(entry.wordCount)")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                    }
                    Text("Words Learned")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Recent Vocabulary")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entry.recentWords.prefix(4), id: \.self) { item in
                        HStack {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .foregroundStyle(Color(red: 0.96, green: 0.45, blue: 0.22))
                            Text(item)
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.14))
                                .lineLimit(1)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
            }

            Spacer()
        }
        .padding(18)
        .background(Color(red: 0.98, green: 0.96, blue: 0.93))
    }
}

struct FleunceWidgetEntryView: View {
    var entry: FleunceWidgetProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        @unknown default:
            SmallWidgetView(entry: entry)
        }
    }
}

@main
struct FleunceWidget: Widget {
    let kind: String = "FleunceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FleunceWidgetProvider()) { entry in
            FleunceWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Fleunce Progress")
        .description("Track your language learning streak, learned words, and progress.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
