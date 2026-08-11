import AppIntents
import SwiftUI
import WidgetKit

/// Recent notes, on the Home Screen and the Lock Screen.
///
/// Reads the app-group store directly. Locked and hidden notes never reach it —
/// the filtering is `VaultPolicy`'s, the same call the library and Spotlight
/// make, so a widget cannot drift into showing something the app would not.
public struct RecentNotesWidget: Widget {

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RecentNotes", provider: RecentNotesProvider()) { entry in
            RecentNotesView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Recent Notes")
        .description("The notes you've touched most recently.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryRectangular,
        ])
    }
}

struct RecentNotesEntry: TimelineEntry {
    var date: Date
    var notes: [NoteEntity.Snapshot]
}

struct RecentNotesProvider: TimelineProvider {

    func placeholder(in context: Context) -> RecentNotesEntry {
        RecentNotesEntry(
            date: Date(),
            notes: (0..<3).map {
                NoteEntity.Snapshot(
                    id: UUID(),
                    title: String(localized: "A note"),
                    summary: String(localized: "Something written down"),
                    modifiedAt: Date().addingTimeInterval(TimeInterval(-$0 * 3600))
                )
            }
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (RecentNotesEntry) -> Void) {
        Task {
            completion(RecentNotesEntry(date: Date(), notes: await load(limit: 6)))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentNotesEntry>) -> Void) {
        Task {
            let entry = RecentNotesEntry(date: Date(), notes: await load(limit: 6))
            // Notes change when the user changes them, not on a clock. A
            // half-hourly refresh keeps the widget honest without spending the
            // budget the system would rather it saved.
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(1_800))))
        }
    }

    private func load(limit: Int) async -> [NoteEntity.Snapshot] {
        await IntentDataSource(modelContainer: VersoIntentContainer.shared).notes(limit: limit)
    }
}

struct RecentNotesView: View {
    let entry: RecentNotesEntry

    @Environment(\.widgetFamily) private var family

    private var visibleCount: Int {
        switch family {
        case .systemSmall: 2
        case .systemMedium: 3
        case .systemLarge: 6
        case .accessoryRectangular: 1
        default: 3
        }
    }

    var body: some View {
        if entry.notes.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: family == .accessoryRectangular ? 2 : 8) {
                ForEach(entry.notes.prefix(visibleCount)) { note in
                    row(note)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func row(_ note: NoteEntity.Snapshot) -> some View {
        Link(destination: VersoURL.note(note.id)) {
            VStack(alignment: .leading, spacing: 1) {
                Text(note.title.isEmpty ? String(localized: "Untitled") : note.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                if family != .accessoryRectangular, !note.summary.isEmpty {
                    Text(note.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(family == .systemSmall ? 1 : 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "book.closed")
                .foregroundStyle(.secondary)
            Text("No notes yet")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One button that opens capture. The Lock Screen case, where the whole value
/// is the number of taps between having a thought and having written it down.
public struct QuickCaptureWidget: Widget {

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickCapture", provider: CaptureProvider()) { _ in
            Link(destination: VersoURL.capture) {
                VStack(spacing: 4) {
                    Image(systemName: "square.and.pencil")
                        .font(.title2)
                    Text("Capture")
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick Capture")
        .description("Start a note in one tap.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct CaptureEntry: TimelineEntry {
    var date: Date
}

struct CaptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaptureEntry { CaptureEntry(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (CaptureEntry) -> Void) {
        completion(CaptureEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CaptureEntry>) -> Void) {
        // A button has nothing to keep up to date.
        completion(Timeline(entries: [CaptureEntry(date: Date())], policy: .never))
    }
}

