import Foundation
import SwiftUI

@MainActor
class FreeTierLimits: ObservableObject {
    static let shared = FreeTierLimits()
    
    private let maxFreeMessagesPerDay = 15
    private let defaults = UserDefaults.standard
    private let keyDate = "freeTierDate"
    private let keyCount = "freeTierCount"
    
    @Published var messagesToday: Int = 0
    
    init() {
        checkAndResetIfNeeded()
    }
    
    func checkAndResetIfNeeded() {
        let lastDateString = defaults.string(forKey: keyDate)
        let todayString = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
        
        if lastDateString != todayString {
            defaults.set(todayString, forKey: keyDate)
            defaults.set(0, forKey: keyCount)
            messagesToday = 0
        } else {
            messagesToday = defaults.integer(forKey: keyCount)
        }
    }
    
    func incrementMessageCount() {
        checkAndResetIfNeeded()
        messagesToday += 1
        defaults.set(messagesToday, forKey: keyCount)
    }
    
    var canSendFreeMessage: Bool {
        checkAndResetIfNeeded()
        return messagesToday < maxFreeMessagesPerDay
    }
    
    var remainingMessages: Int {
        checkAndResetIfNeeded()
        return max(0, maxFreeMessagesPerDay - messagesToday)
    }
}
