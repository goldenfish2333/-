import Foundation

struct CategoryStat: Identifiable {
    var id: String { name }
    let name: String
    let total: Double
    let count: Int
    let share: Double
}

struct MonthlyReport {
    let month: Date
    let expenseTotal: Double
    let incomeTotal: Double
    let balance: Double
    let count: Int
    let categories: [CategoryStat]
    let largest: Transaction?

    var topCategory: CategoryStat? { categories.first }
    /// 日均。当月按「已经过了几天」算，历史月份按整月天数算。
    /// 如果一律除以整月天数，每月 3 号打开 App 会看到被严重摊薄的日均，等于这笔数字没法用。
    var averagePerDay: Double {
        let calendar = Calendar.current
        let daysInMonth = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let now = Date()
        let isCurrentMonth = calendar.isDate(month, equalTo: now, toGranularity: .month)
        let divisor = isCurrentMonth
            ? max(1, calendar.component(.day, from: now))
            : daysInMonth
        return expenseTotal / Double(divisor)
    }

    /// 一句话结论，直接用于月报通知和卡片头部
    var headline: String {
        guard count > 0 else { return "这个月还没有账目" }
        let money = Self.yuan(expenseTotal)
        guard let top = topCategory else { return "支出 \(money)" }
        let percent = Int((top.share * 100).rounded())
        var text = "支出 \(money)，\(top.name)最多占 \(percent)%"
        if let largest {
            text += "，最大一笔 \(Self.yuan(largest.amount))"
            if !largest.merchant.isEmpty && largest.merchant != "未知商户" {
                text += "（\(largest.merchant)）"
            }
        }
        return text
    }

    /// 推送给用户的那一句。和 headline 的区别只有空账本时的说法。
    var notificationText: String {
        count == 0 ? "上月没有账目记录" : headline
    }

    static func yuan(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        let number = formatter.string(from: NSNumber(value: abs(value))) ?? "\(Int(abs(value)))"
        // 负数写成 -¥123，别写成 ¥-123
        return (value < 0 ? "-¥" : "¥") + number
    }

    static func build(from transactions: [Transaction], month: Date) -> MonthlyReport {
        let expenses = transactions.filter { $0.flow == .expense }
        let expenseTotal = expenses.reduce(0) { $0 + $1.amount }
        let incomeTotal = transactions.filter { $0.flow == .income }.reduce(0) { $0 + $1.amount }

        var byCategory: [String: (Double, Int)] = [:]
        for item in expenses {
            var entry = byCategory[item.category] ?? (0, 0)
            entry.0 += item.amount
            entry.1 += 1
            byCategory[item.category] = entry
        }

        let stats = byCategory
            .map { CategoryStat(
                name: $0.key,
                total: $0.value.0,
                count: $0.value.1,
                share: expenseTotal > 0 ? $0.value.0 / expenseTotal : 0
            ) }
            .sorted { $0.total > $1.total }

        return MonthlyReport(
            month: month,
            expenseTotal: expenseTotal,
            incomeTotal: incomeTotal,
            balance: incomeTotal - expenseTotal,
            count: transactions.count,
            categories: stats,
            largest: expenses.max { $0.amount < $1.amount }
        )
    }
}
