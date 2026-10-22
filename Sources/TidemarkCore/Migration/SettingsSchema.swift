import Foundation

/// The saved settings' version, and the one-time move from earlier versions' keys.
public enum SettingsSchema {
    public static let version = 1
    public static let removedKeys = ["showCrab", "lookStyle", "weekFile", "compact", "widgetOffset", "dockAccessAsked", "loginItemOffered"]

    /// Pure: returns the values after migrating. Never deletes a key it doesn't know, and
    /// leaves values saved at this version (or a newer one) as they are. Converts before
    /// removing: `widgetOffset` → `widgetSpot`, `compact` → `widgetWidth`/`stripWidth`.
    public static func migrate(_ values: [String: Any], from version: Int?) -> [String: Any] {
        if let version, version >= Self.version { return values }
        var out = values

        // Earlier versions saved only a dragged-to offset. A saved spot wins.
        if out["widgetSpot"] == nil, let data = out["widgetOffset"] as? Data,
           let offset = try? JSONDecoder().decode(WidgetOffset.self, from: data),
           let spot = try? JSONEncoder().encode(WidgetSpot.free(offset)) {
            out["widgetSpot"] = spot
        }
        // Earlier versions had a compact and a full widget instead of a width. Saved widths win.
        if let compact = out["compact"] as? Bool {
            let widths = WidgetSizing.migratedWidths(compact: compact)
            if out["widgetWidth"] == nil { out["widgetWidth"] = widths.width }
            if out["stripWidth"] == nil { out["stripWidth"] = widths.strip }
        }
        for key in removedKeys { out[key] = nil }

        // An install that finished first run before this setting existed has already chosen its sources.
        if out["sourcesChosen"] == nil, out["firstRunDone"] as? Bool == true { out["sourcesChosen"] = true }

        for key in ["wallpaperDay", "wallpaperNight"] {
            if let path = out[key] as? String {
                out[key] = path.replacingOccurrences(of: "/ClaudeDock/wallpapers/", with: "/Tidemark/wallpapers/")
            }
        }
        out["settingsVersion"] = Self.version
        return out
    }
}
