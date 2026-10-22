import Foundation
import UserNotifications
import TidemarkCore

/// Mac notifications for switch advice, a plan running low and a claude.ai sign-out, each only when
/// its switch in Settings → Notifications is on. Only works from the bundled app (an unbundled
/// binary has no notification identity).
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// A notification was clicked: which kind, and the plan's name when it is about one.
    var onClick: ((ShellCopy.NoticeKind, String?) -> Void)?
    /// Asks the user, with the "Get notified?" sheet, before macOS's own prompt; calls back with their
    /// answer. Nothing is posted, and macOS isn't asked, until they've said yes.
    var askFirst: ((@escaping (Bool) -> Void) -> Void)?
    private var asking = false
    private var declined = false
    private let settings: Settings

    init(settings: Settings) {
        self.settings = settings
        super.init()
    }

    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    /// Listens for clicks. Permission is asked for the first time there's something to say (or when
    /// the user says yes in Settings), not at launch, where it would stack on top of other windows.
    func start() {
        center?.delegate = self
    }

    /// Whether `kind` may be posted right now, by the three switches.
    func mayPost(_ kind: ShellCopy.NoticeKind) -> Bool {
        ShellCopy.mayPost(kind, notifySwitch: settings.notifySwitch, notifyRed: settings.notifyRed,
                          notifySignedOut: settings.notifySignedOut)
    }

    /// Posts `notice` if its switch is on. The first time (macOS hasn't been asked), the "Get notified?"
    /// sheet comes first; macOS's prompt only follows its Continue.
    func post(_ notice: Notice, kind: ShellCopy.NoticeKind) {
        guard mayPost(kind), let center else { return }
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.userInfo = ["kind": Self.key(kind), "plan": notice.plan ?? ""]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        Task {
            switch await center.notificationSettings().authorizationStatus {
            case .notDetermined:
                guard !asking, !declined, let askFirst else { return }
                asking = true
                askFirst { yes in
                    guard yes else { self.asking = false; self.declined = true; return }
                    Task {
                        await self.requestPermission()
                        self.asking = false
                        if await center.notificationSettings().authorizationStatus != .denied { try? await center.add(request) }
                    }
                }
            case .denied:
                return
            default:
                try? await center.add(request)
            }
        }
    }

    /// What macOS says about permission, for Settings → Notifications.
    func permission() async -> SettingsHub.NotificationPermission {
        guard let center else { return .unavailable }
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: return .notAsked
        case .denied: return .denied
        default: return .allowed
        }
    }

    /// Shows macOS's own prompt (the "Continue" of the Get notified? sheet).
    func requestPermission() async {
        _ = try? await center?.requestAuthorization(options: [.alert, .sound])
    }

    private static func key(_ kind: ShellCopy.NoticeKind) -> String {
        switch kind {
        case .switchAdvice: "switch"
        case .nearlyOut: "nearlyOut"
        case .signedOut: "signedOut"
        }
    }

    private static func kind(_ key: String?) -> ShellCopy.NoticeKind {
        switch key {
        case "switch": .switchAdvice
        case "signedOut": .signedOut
        default: .nearlyOut
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let kind = info["kind"] as? String
        let plan = (info["plan"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        await MainActor.run { onClick?(Self.kind(kind), plan) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner]
    }
}
