import Foundation
import Testing
@testable import TidemarkCore

/// The settings version and its one-time migration from the ClaudeDock-era keys.
struct SettingsSchemaTests {
    private func offsetData(right: Double, bottom: Double) throws -> Data {
        try JSONEncoder().encode(WidgetOffset(right: right, bottom: bottom))
    }

    private func spot(_ values: [String: Any]) throws -> WidgetSpot? {
        try (values["widgetSpot"] as? Data).map { try JSONDecoder().decode(WidgetSpot.self, from: $0) }
    }

    @Test func keepsTheWidgetsPlaceAndWidth() throws {
        let old: [String: Any] = ["widgetOffset": try offsetData(right: 240, bottom: 12), "compact": false]
        let new = SettingsSchema.migrate(old, from: nil)
        #expect(try spot(new) == .free(WidgetOffset(right: 240, bottom: 12)))
        #expect(new["widgetWidth"] as? Double == 520)
        #expect(new["stripWidth"] as? Double == 104)
        let compact = SettingsSchema.migrate(["compact": true], from: nil)
        #expect(compact["widgetWidth"] as? Double == 280)
        #expect(compact["stripWidth"] as? Double == 68)
        // A widget that was never marked compact or full takes the compact default only when `compact` was saved.
        #expect(SettingsSchema.migrate([:], from: nil)["widgetWidth"] == nil)
    }

    @Test func existingNewKeysWinOverOldOnes() throws {
        let snapped = try JSONEncoder().encode(WidgetSpot.snapped(.topLeft))
        let old: [String: Any] = ["widgetOffset": try offsetData(right: 1, bottom: 2), "widgetSpot": snapped,
                                  "compact": false, "widgetWidth": 333.0]
        let new = SettingsSchema.migrate(old, from: nil)
        #expect(try spot(new) == .snapped(.topLeft))
        #expect(new["widgetWidth"] as? Double == 333)
        #expect(new["stripWidth"] as? Double == 104)
    }

    @Test func anExistingInstallHasAlreadyChosenItsSources() {
        #expect(SettingsSchema.migrate(["firstRunDone": true], from: nil)["sourcesChosen"] as? Bool == true)
        // A new install, or one that never left first run's step 2, has not.
        #expect(SettingsSchema.migrate([:], from: nil)["sourcesChosen"] == nil)
        #expect(SettingsSchema.migrate(["firstRunDone": false], from: nil)["sourcesChosen"] == nil)
        // Only the first migration decides; a saved choice stays, and later launches add nothing.
        #expect(SettingsSchema.migrate(["firstRunDone": true, "sourcesChosen": false], from: nil)["sourcesChosen"] as? Bool == false)
        #expect(SettingsSchema.migrate(["firstRunDone": true], from: 1)["sourcesChosen"] == nil)
    }

    @Test func migratesFromNoVersion() {
        var old: [String: Any] = ["wallpaperDay": "/home/me/Support/ClaudeDock/wallpapers/x.jpg",
                                  "wallpaperNight": "/elsewhere/n.jpg"]
        for key in SettingsSchema.removedKeys { old[key] = true }
        let new = SettingsSchema.migrate(old, from: nil)
        for key in SettingsSchema.removedKeys { #expect(new[key] == nil, "\(key)") }
        #expect(new["settingsVersion"] as? Int == 1)
        #expect(new["wallpaperDay"] as? String == "/home/me/Support/Tidemark/wallpapers/x.jpg")
        #expect(new["wallpaperNight"] as? String == "/elsewhere/n.jpg")
    }

    @Test func keepsUnknownKeys() {
        let new = SettingsSchema.migrate(["somethingNew": 7, "themeChoice": "dark"], from: nil)
        #expect(new["somethingNew"] as? Int == 7)
        #expect(new["themeChoice"] as? String == "dark")
    }

    @Test func idempotentAtCurrentVersion() throws {
        let old: [String: Any] = ["compact": false, "weekFile": "/x.json", "widgetOffset": try offsetData(right: 1, bottom: 2)]
        let once = SettingsSchema.migrate(old, from: nil)
        let twice = SettingsSchema.migrate(once, from: 1)
        #expect(NSDictionary(dictionary: once) == NSDictionary(dictionary: twice))
        // At the current version, even an old key someone put back is left alone.
        let same: [String: Any] = ["settingsVersion": 1, "compact": true]
        #expect(NSDictionary(dictionary: SettingsSchema.migrate(same, from: 1)) == NSDictionary(dictionary: same))
    }

    @Test func thresholdsSurviveAnAddedField() throws {
        let saved = #"{"redWeekLeft":20,"redSession":90,"yellowSession":70,"onPaceUnused":4,"eligibleWeekLeft":8,"eligibleSessionBelow":75,"aFieldFromTheFuture":1}"#
        let t = try JSONDecoder().decode(Thresholds.self, from: Data(saved.utf8))
        #expect(t.redWeekLeft == 20 && t.redSession == 90 && t.yellowSession == 70)
        #expect(t.onPaceUnused == 4 && t.eligibleWeekLeft == 8 && t.eligibleSessionBelow == 75)
        #expect(t.primaryReserveWeekLeft == Thresholds().primaryReserveWeekLeft)
    }

    @Test func oldRedRunsOutEarlyIgnored() throws {
        let saved = #"{"redWeekLeft":20,"redRunsOutEarlyHours":3}"#
        let t = try JSONDecoder().decode(Thresholds.self, from: Data(saved.utf8))
        #expect(t.redWeekLeft == 20)
        let out = String(decoding: try JSONEncoder().encode(t), as: UTF8.self)
        #expect(!out.contains("redRunsOutEarlyHours"))
    }
}
