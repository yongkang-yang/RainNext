// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Combine
import Foundation
import os
import RainNextKit
import UserNotifications

/// Delivers rain alerts. Off until asked for: an app that demands notification
/// permission on first launch, before it has shown anyone anything useful,
/// mostly teaches them to say no.
@MainActor
final class NotificationService: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var authorizationDenied = false

    private let log = Logger(subsystem: "nl.yongkang.rainnext", category: "notifications")
    private let defaults: UserDefaults
    private let enabledKey = "RainNext.notificationsEnabled"
    private let ledgerKey = "RainNext.alertLedger"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: enabledKey)
    }

    /// Survives a relaunch, so restarting the app is not a way to hear about
    /// the same shower twice.
    var ledger: RainAlertPlanner.Ledger {
        get {
            guard let data = defaults.data(forKey: ledgerKey),
                  let stored = try? JSONDecoder().decode(StoredLedger.self, from: data)
            else { return .init() }
            return .init(lastNotifiedAt: stored.lastNotifiedAt, coveredThrough: stored.coveredThrough)
        }
        set {
            let stored = StoredLedger(lastNotifiedAt: newValue.lastNotifiedAt, coveredThrough: newValue.coveredThrough)
            guard let data = try? JSONEncoder().encode(stored) else { return }
            defaults.set(data, forKey: ledgerKey)
        }
    }

    func resetLedger() {
        defaults.removeObject(forKey: ledgerKey)
    }

    func setEnabled(_ enabled: Bool) async {
        guard enabled else {
            isEnabled = false
            defaults.set(false, forKey: enabledKey)
            return
        }

        // An accessory app is never frontmost on its own, and the system will
        // not put a permission prompt in front of an inactive app. In the real
        // flow the popover already has focus; this makes the request work from
        // anywhere, including the test hook.
        NSApp.activate(ignoringOtherApps: true)

        var granted = false
        do {
            granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            // Swallowing this was hiding the reason the bell did nothing.
            let nserror = error as NSError
            trace("requestAuthorization threw: \(nserror.domain) \(nserror.code) — \(nserror.localizedDescription)")
            log.error("requestAuthorization failed: \(error.localizedDescription, privacy: .public)")
        }

        isEnabled = granted
        authorizationDenied = !granted
        defaults.set(granted, forKey: enabledKey)
    }

    /// Rain cannot be summoned on demand, so this is how the delivery path
    /// gets exercised: `RAINNEXT_TEST_ALERT=1` on launch.
    func sendTestAlert() async {
        trace("entered sendTestAlert")
        let settingsBefore = await UNUserNotificationCenter.current().notificationSettings()
        trace("settings before: authorization=\(settingsBefore.authorizationStatus.rawValue)")
        await setEnabled(true)
        trace("setEnabled returned, isEnabled=\(isEnabled)")
        guard isEnabled else {
            trace("authorization refused")
            return
        }
        deliver(RainAlert(
            title: "Rain in 15 min",
            body: "About 30 min, until 21:15. (test)",
            episodeStart: Date().addingTimeInterval(900),
            episodeEnd: Date().addingTimeInterval(2700)
        ))
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        trace("sent; authorization=\(settings.authorizationStatus.rawValue) alertSetting=\(settings.alertSetting.rawValue)")
    }

    /// Only used by the test hook. Crude on purpose: `open` detaches stdio and
    /// os_log came back empty while diagnosing this, so a file is the one
    /// channel that definitely survives.
    private func trace(_ message: String) {
        log.notice("\(message, privacy: .public)")
        let line = "\(Date()) \(message)\n"
        let url = URL(fileURLWithPath: "/tmp/rainnext_alert.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func deliver(_ alert: RainAlert) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        // Deliberately not .timeSensitive: rain is not an emergency, and this
        // is what lets Focus and Do Not Disturb hold it back. That is the whole
        // quiet-hours story — the system already has one, better than ours.
        content.interruptionLevel = .active

        let request = UNNotificationRequest(
            identifier: "rain-\(alert.episodeStart.timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { [log] error in
            if let error { log.error("delivery failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    private struct StoredLedger: Codable {
        let lastNotifiedAt: Date?
        let coveredThrough: Date?
    }
}
