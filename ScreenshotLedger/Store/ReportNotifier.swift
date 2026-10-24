import Foundation
import UserNotifications

/// 每月 1 号上午 9 点推一条上月统计。不用服务器，本地通知就够。
enum ReportNotifier {

    static let identifier = "monthly.report"

    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .denied:
            return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    /// 查权限但不弹框：已授权才返回 true，没问过也算 false。
    static func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        default:
            return false
        }
    }

    /// 排一条「下个月 1 号 9 点」的一次性通知，内容用**当前这个月**的账本算。
    ///
    /// 不能用 repeats: true —— 本地通知的文案在排程时就固定了，
    /// 重复触发只会把同一句话一直推下去（10 月排的「9 月支出」会在 11 月 1 号再推一次）。
    /// 所以每次打开 App 都重新排一条，把当月的数字带进去。
    static func scheduleMonthlyRecap(reportProvider: @escaping () -> String) async {
        guard await requestPermission() else { return }

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let calendar = Calendar.current
        guard let firstOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())),
              let firstOfNextMonth = calendar.date(byAdding: .month, value: 1, to: firstOfThisMonth),
              let fireDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: firstOfNextMonth)
        else { return }

        var components = calendar.dateComponents([.year, .month, .day], from: fireDate)
        components.hour = 9
        components.minute = 0
        components.second = 0

        let content = UNMutableNotificationContent()
        content.title = "上月账本"
        content.body = reportProvider()
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
