import WidgetKit
import SwiftUI

struct KoiEntry: TimelineEntry {
  let date: Date
  let title: String
  let completed: Int
}
struct KoiProvider: TimelineProvider {
  func placeholder(in context: Context) -> KoiEntry { KoiEntry(date: Date(), title: "Workspace", completed: 0) }
  func getSnapshot(in context: Context, completion: @escaping (KoiEntry) -> Void) { completion(read()) }
  func getTimeline(in context: Context, completion: @escaping (Timeline<KoiEntry>) -> Void) {
    completion(Timeline(entries: [read()], policy: .never))
  }
  private func read() -> KoiEntry {
    guard let value = UserDefaults(suiteName: "group.com.example.platformLab")?.string(forKey: "koi_snapshot"),
          let data = value.data(using: .utf8),
          let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          json["version"] as? Int == 1 else { return KoiEntry(date: Date(), title: "Open workspace", completed: 0) }
    return KoiEntry(date: Date(), title: json["title"] as? String ?? "Workspace", completed: json["completed"] as? Int ?? 0)
  }
}
struct KoiWidgetView: View {
  let entry: KoiEntry
  private var content: some View {
    VStack(alignment: .leading) { Text(entry.title).font(.headline); Text("\(entry.completed)").font(.title) }
      .padding().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      .widgetURL(URL(string: "koi-workspace://home-widget"))
  }
  var body: some View {
    if #available(iOSApplicationExtension 17.0, *) {
      content.containerBackground(for: .widget) { Color(white: 0.96) }
    } else { content.background(Color(white: 0.96)) }
  }
}
@main
struct KoiHomeWidget: Widget {
  let kind = "KoiHomeWidget"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: KoiProvider()) { entry in KoiWidgetView(entry: entry) }
      .configurationDisplayName("Workspace").description("Latest workspace snapshot").supportedFamilies([.systemSmall, .systemMedium])
  }
}
