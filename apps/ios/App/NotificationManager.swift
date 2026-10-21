import Foundation
import UserNotifications
import UIKit
import FluenceCore

// MARK: - Daily Notification Settings

public struct NotificationSettings: Codable, Sendable {
    public var isEnabled: Bool
    public var notificationsPerDay: Int // 1 or 2
    public var morningHour: Int
    public var morningMinute: Int
    public var eveningHour: Int
    public var eveningMinute: Int
    
    public init(
        isEnabled: Bool = true,
        notificationsPerDay: Int = 2,
        morningHour: Int = 9,
        morningMinute: Int = 0,
        eveningHour: Int = 19,
        eveningMinute: Int = 30
    ) {
        self.isEnabled = isEnabled
        self.notificationsPerDay = notificationsPerDay
        self.morningHour = morningHour
        self.morningMinute = morningMinute
        self.eveningHour = eveningHour
        self.eveningMinute = eveningMinute
    }
}

// MARK: - Notification Manager

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    
    private let settingsKey = "FluenceNotificationSettings"
    private(set) var settings: NotificationSettings
    
    override init() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let saved = try? JSONDecoder().decode(NotificationSettings.self, from: data) {
            self.settings = saved
        } else {
            self.settings = NotificationSettings()
        }
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    
    func saveSettings(_ newSettings: NotificationSettings) {
        self.settings = newSettings
        if let data = try? JSONEncoder().encode(newSettings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
        scheduleNotifications()
    }
    
    // MARK: - Permission Request & Status Check
    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }
    
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                scheduleNotifications()
            }
            return granted
        } catch {
            return false
        }
    }
    
    // MARK: - Test Notification
    func sendTestNotification() async {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Fluence Professeur 🇩🇪"
        content.body = "Hé oh ! C'est l'heure de pratiquer ton allemand en vocal avec Fluence 🎙️"
        content.sound = .default
        content.userInfo = ["action": "open_voice_session"]
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let request = UNNotificationRequest(identifier: "fluence_test_notification_\(UUID().uuidString)", content: content, trigger: trigger)
        try? await center.add(request)
    }
    
    // MARK: - Notification Scheduling
    func scheduleNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        
        guard settings.isEnabled else { return }
        
        let dueItems = FSRSStoreManager.shared.getDueItems(limit: 5)
        
        // Morning Notification
        let morningContent = buildNotificationContent(
            title: "Fluence Professeur 🇩🇪",
            dueItems: dueItems,
            period: .morning
        )
        var morningComponents = DateComponents()
        morningComponents.hour = settings.morningHour
        morningComponents.minute = settings.morningMinute
        let morningTrigger = UNCalendarNotificationTrigger(dateMatching: morningComponents, repeats: true)
        let morningRequest = UNNotificationRequest(identifier: "fluence_daily_morning", content: morningContent, trigger: morningTrigger)
        center.add(morningRequest)
        
        // Evening Notification (if 2 notifications per day enabled)
        if settings.notificationsPerDay >= 2 {
            let eveningContent = buildNotificationContent(
                title: "Fluence Professeur 🎙️",
                dueItems: dueItems,
                period: .evening
            )
            var eveningComponents = DateComponents()
            eveningComponents.hour = settings.eveningHour
            eveningComponents.minute = settings.eveningMinute
            let eveningTrigger = UNCalendarNotificationTrigger(dateMatching: eveningComponents, repeats: true)
            let eveningRequest = UNNotificationRequest(identifier: "fluence_daily_evening", content: eveningContent, trigger: eveningTrigger)
            center.add(eveningRequest)
        }
    }
    
    private enum DayPeriod { case morning, evening }
    
    private func buildNotificationContent(title: String, dueItems: [FSRSItem], period: DayPeriod) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.sound = .default
        
        let humanMessages: [String]
        
        if let firstDue = dueItems.first {
            // Contextual message based on actual FSRS due term
            if period == .morning {
                humanMessages = [
                    "Hé oh ! C'est l'heure de réviser 😉 Tu te rappelles comment on utilise « \(firstDue.term) » ? Viens me dire une phrase en vocal !",
                    "Bonjour ! Petit défi matinal : formule une phrase avec « \(firstDue.term) » en allemand. Je t'écoute !",
                    "Prêt pour 2 minutes d'allemand ? Viens me parler de « \(firstDue.term) » en direct !"
                ]
            } else {
                humanMessages = [
                    "Hé oh ! Petite pause du soir : tu te souviens du sens de « \(firstDue.term) » ? Viens discuter 2 minutes en vocal 🎙️",
                    "Défi du soir : utilise « \(firstDue.term) » dans une phrase en allemand avant de dormir ! Lance la voix.",
                    "Un instant pour ton allemand : comment tu dirais « \(firstDue.meaning) » ? Dis-le moi à l'oral !"
                ]
            }
        } else {
            // Friendly natural prompt
            if period == .morning {
                humanMessages = [
                    "Hé oh ! 2 minutes de discussion en allemand avec moi pour démarrer la journée en pleine forme ?",
                    "Guten Morgen ! Viens faire un tour en vocal pour dérouiller ton allemand aujourd'hui 😉",
                    "C'est l'heure de ta petite séance vocale allemande quotidienne !"
                ]
            } else {
                humanMessages = [
                    "Hé oh ! Tu as 2 minutes avant la fin de journée ? Viens me raconter ta journée en allemand 🎙️",
                    "Guten Abend ! Un petit échange vocal rapide pour consolider tes réflexes d'allemand ?",
                    "Prêt pour une discussion relax en allemand ce soir ?"
                ]
            }
        }
        
        content.body = humanMessages.randomElement() ?? "Hé oh ! C'est l'heure de réviser un peu d'allemand en vocal !"
        content.userInfo = ["action": "open_voice_session"]
        return content
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .badge]
    }
    
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // Notification tapped -> open vocal session
        await MainActor.run {
            NotificationCenter.default.post(name: NSNotification.Name("FluenceOpenVoiceSession"), object: nil)
        }
    }
}
