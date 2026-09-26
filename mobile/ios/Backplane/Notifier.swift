import UIKit
import UserNotifications

// Turn-end alerts. While the app is in front it posts the alerts Bend
// raises; while it sleeps the hub's APNs pushes carry them. A remote one
// arriving in front is dropped, since the local one already showed.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    var open: (String) -> Void = { _ in }
    var viewing: (String) -> Bool = { _ in false }

    func setUp() {
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        c.requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
            if ok { DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() } }
        }
    }

    // one notification per key ("turn-<thread>", or "room-<room>" for a room
    // exchange, the same on every paired hub): a newer alert replaces the last
    func post(thread: String, key: String, title: String, body: String) {
        let n = UNMutableNotificationContent()
        n.title = title
        n.body = body
        n.sound = .default
        let id = key.isEmpty ? "turn-" + thread : key
        n.threadIdentifier = id
        n.userInfo = ["thread": thread]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: n, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent n: UNNotification) async -> UNNotificationPresentationOptions {
        let thread = n.request.content.userInfo["thread"] as? String ?? ""
        let remote = n.request.trigger is UNPushNotificationTrigger
        return await MainActor.run { remote || viewing(thread) ? [] : [.banner, .sound, .list] }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive r: UNNotificationResponse) async {
        let thread = r.notification.request.content.userInfo["thread"] as? String ?? ""
        await MainActor.run { if !thread.isEmpty { open(thread) } }
    }
}
