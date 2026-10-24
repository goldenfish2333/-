import Foundation
// ObservableObject / @Published 来自 Combine，Foundation 不带它们。
// 少了这一行会报「cannot find type 'ObservableObject' in scope」。
import Combine

/// 账本存储：JSON 存本地 Documents 目录，导出 / 导入走同一个 Codable 结构。
@MainActor
final class LedgerStore: ObservableObject {

    @Published private(set) var transactions: [Transaction] = []

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("ledger.json")
    }()

    init() {
        load()
    }

    // MARK: - CRUD

    func add(_ items: [Transaction]) {
        guard !items.isEmpty else { return }
        transactions.append(contentsOf: items)
        transactions.sort { $0.date > $1.date }
        save()
    }

    func add(_ item: Transaction) {
        add([item])
    }

    func update(_ item: Transaction) {
        guard let index = transactions.firstIndex(where: { $0.id == item.id }) else { return }
        transactions[index] = item
        transactions.sort { $0.date > $1.date }
        save()
    }

    func delete(ids: Set<UUID>) {
        transactions.removeAll { ids.contains($0.id) }
        save()
    }

    func delete(_ item: Transaction) {
        delete(ids: [item.id])
    }

    // MARK: - 查询

    func transactions(inMonthOf date: Date) -> [Transaction] {
        let calendar = Calendar.current
        return transactions.filter {
            calendar.isDate($0.date, equalTo: date, toGranularity: .month)
        }
    }

    func availableMonths() -> [Date] {
        let calendar = Calendar.current
        let months = Set(transactions.map {
            calendar.date(from: calendar.dateComponents([.year, .month], from: $0.date)) ?? $0.date
        })
        return months.sorted(by: >)
    }

    // MARK: - 持久化

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        transactions = (try? decoder.decode([Transaction].self, from: data)) ?? []
        transactions.sort { $0.date > $1.date }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(transactions) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - 导出 / 导入

    func exportJSON() -> URL? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(transactions) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-\(Self.stamp()).json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    func exportCSV() -> URL? {
        var csv = "日期,收支,金额,分类,商户,备注\n"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        for item in transactions {
            let fields = [
                formatter.string(from: item.date),
                item.flow.label,
                String(format: "%.2f", item.amount),
                item.category,
                item.merchant,
                item.note
            ]
            csv += fields.map(Self.escapeCSV).joined(separator: ",") + "\n"
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-\(Self.stamp()).csv")
        do {
            // 加 BOM，Excel 打开中文不乱码
            var data = Data([0xEF, 0xBB, 0xBF])
            data.append(Data(csv.utf8))
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// 导入时按 id 去重合并，重复导入同一份文件不会产生重复账目。
    @discardableResult
    func importJSON(from url: URL) -> Int {
        let needsRelease = url.startAccessingSecurityScopedResource()
        defer { if needsRelease { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { return 0 }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let incoming = try? decoder.decode([Transaction].self, from: data) else { return 0 }

        let existing = Set(transactions.map(\.id))
        let fresh = incoming.filter { !existing.contains($0.id) }
        add(fresh)
        return fresh.count
    }

    private static func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
