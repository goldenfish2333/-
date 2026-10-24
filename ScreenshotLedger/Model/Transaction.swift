import Foundation

enum MoneyFlow: String, Codable, CaseIterable, Identifiable {
    case expense
    case income

    var id: String { rawValue }
    var label: String { self == .expense ? "支出" : "收入" }
    var sign: Double { self == .expense ? -1 : 1 }
}

struct Transaction: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var amount: Double
    var flow: MoneyFlow = .expense
    var merchant: String = ""
    var category: String = "其他"
    var date: Date = Date()
    var note: String = ""
    /// 来源相册资源的 localIdentifier，用来避免同一张截图被重复记账
    var assetID: String? = nil
    var rawText: String? = nil
    var createdAt: Date = Date()

    var signedAmount: Double { amount * flow.sign }
}
