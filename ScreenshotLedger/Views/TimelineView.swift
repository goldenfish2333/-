import SwiftUI
import UIKit

/// 一天的账目。原来这里用 (Date, [Transaction]) 元组，
/// 但 ForEach 的 id 需要 KeyPath，而 Swift 的 KeyPath 不能指向元组元素（\\.0 会编译报错），
/// 所以换成一个小结构体。
private struct DayGroup: Identifiable {
    var id: Date { day }
    let day: Date
    let items: [Transaction]
}

struct TimelineView: View {
    @EnvironmentObject private var store: LedgerStore
    @EnvironmentObject private var scanner: LibraryScanner

    /// 改一笔 / 补一笔共用一个 sheet。
    /// 为什么不用两个 .sheet 修饰符：同一个 View 上挂两个 sheet，iOS 只认最后一个，
    /// 「+」按钮会点了没反应。所以合并成一个 item 驱动的 sheet。
    private enum SheetTarget: Identifiable {
        case edit(Transaction)
        case create

        var id: String {
            switch self {
            case .edit(let item): return item.id.uuidString
            case .create: return "new"
            }
        }
    }

    @State private var sheetTarget: SheetTarget?
    @State private var pendingDelete: Transaction?

    private var grouped: [DayGroup] {
        let calendar = Calendar.current
        let buckets = Dictionary(grouping: store.transactions) { item in
            calendar.startOfDay(for: item.date)
        }
        return buckets
            .map { DayGroup(day: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.transactions.isEmpty {
                    EmptyStateView(
                        title: "还没有账目",
                        message: "去微信或支付宝付一笔钱，截图存进相册，回来打开这个 App 就会自动出现。",
                        actionTitle: "现在扫一遍相册"
                    ) {
                        Task { await scanner.scanRecent(days: 90) }
                    }
                } else {
                    List {
                        ForEach(grouped) { group in
                            Section {
                                ForEach(group.items) { item in
                                    Button {
                                        sheetTarget = .edit(item)
                                    } label: {
                                        TransactionRow(item: item)
                                    }
                                    .buttonStyle(.plain)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            pendingDelete = item
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                                }
                            } header: {
                                DayHeader(day: group.day, items: group.items)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await scanner.scanRecent(days: 90) }
                }
            }
            .navigationTitle("账目")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        Task { await scanner.scanRecent(days: 90) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(scanner.isScanning)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        sheetTarget = .create
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $sheetTarget) { target in
                switch target {
                case .edit(let item):
                    EntryEditor(mode: .edit(item))
                        .environmentObject(store)
                case .create:
                    EntryEditor(mode: .create)
                        .environmentObject(store)
                }
            }
            .confirmationDialog(
                "删除这笔账？",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                presenting: pendingDelete
            ) { item in
                Button("删除", role: .destructive) {
                    store.delete(item)
                    pendingDelete = nil
                }
                Button("取消", role: .cancel) { pendingDelete = nil }
            } message: { item in
                Text("\(item.merchant)  \(MonthlyReport.yuan(item.amount))")
            }
        }
    }
}

private struct DayHeader: View {
    let day: Date
    let items: [Transaction]

    private var total: Double {
        items.filter { $0.flow == .expense }.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        HStack {
            Text(day.formatted(.dateTime.month().day().weekday(.abbreviated)))
            Spacer()
            if total > 0 {
                Text("支出 \(MonthlyReport.yuan(total))")
                    .monospacedDigit()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .textCase(nil)
    }
}

struct TransactionRow: View {
    let item: Transaction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: Categories.symbol(for: item.category))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(item.merchant.isEmpty ? item.category : item.merchant)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.category)
                    Text(item.date.formatted(.dateTime.hour().minute()))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(signedAmountText)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(item.flow == .expense ? Color.primary : Color.green)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var signedAmountText: String {
        let sign = item.flow == .expense ? "-" : "+"
        return sign + String(MonthlyReport.yuan(item.amount).dropFirst())
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
