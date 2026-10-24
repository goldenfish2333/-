import SwiftUI
import UIKit

struct ReportView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var month: Date = Date()

    private var items: [Transaction] { store.transactions(inMonthOf: month) }
    private var report: MonthlyReport { MonthlyReport.build(from: items, month: month) }
    private var months: [Date] { store.availableMonths() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    MonthSwitcher(month: $month, months: months)

                    HeadlineCard(report: report)
                    SummaryRow(report: report)

                    if report.categories.isEmpty {
                        Text("这个月还没有支出")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else {
                        CategorySection(report: report)
                        LargestCard(item: report.largest)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("月报")
        }
    }
}

private struct MonthSwitcher: View {
    @Binding var month: Date
    /// 有账目的月份，按时间倒序（第 0 个是最新的）
    let months: [Date]

    private var calendar: Calendar { Calendar.current }

    /// 可选月份：所有有账的月份 + 本月，去重后倒序
    private var available: [Date] {
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        var all = months
        if !all.contains(where: { calendar.isDate($0, equalTo: thisMonth, toGranularity: .month) }) {
            all.append(thisMonth)
        }
        return all.sorted(by: >)
    }

    private var index: Int {
        available.firstIndex { calendar.isDate($0, equalTo: month, toGranularity: .month) } ?? 0
    }

    private var canGoOlder: Bool { index < available.count - 1 }
    private var canGoNewer: Bool { index > 0 }

    var body: some View {
        HStack {
            // 左箭头 = 上个月（更早）
            Button {
                step(to: index + 1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 32, height: 32)
            }
            .disabled(!canGoOlder)

            Spacer()

            Text(month.formatted(.dateTime.year().month()))
                .font(.subheadline.weight(.semibold))
                .contentTransition(.numericText())

            Spacer()

            // 右箭头 = 下个月（更新），最多到本月
            Button {
                step(to: index - 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 32, height: 32)
            }
            .disabled(!canGoNewer)
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }

    private func step(to newIndex: Int) {
        guard available.indices.contains(newIndex) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { month = available[newIndex] }
    }
}

private struct HeadlineCard: View {
    let report: MonthlyReport

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("本月花费")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(MonthlyReport.yuan(report.expenseTotal))
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            Text(report.headline)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if report.count > 0 {
                Text("共 \(report.count) 笔 · 日均 \(MonthlyReport.yuan(report.averagePerDay))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct SummaryRow: View {
    let report: MonthlyReport

    var body: some View {
        HStack(spacing: 10) {
            MiniCard(title: "收入", value: MonthlyReport.yuan(report.incomeTotal), tint: .green)
            MiniCard(
                title: "结余",
                value: MonthlyReport.yuan(report.balance),
                tint: report.balance < 0 ? .red : .blue
            )
        }
    }
}

private struct MiniCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct CategorySection: View {
    let report: MonthlyReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("钱花在哪")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                ForEach(report.categories) { stat in
                    VStack(spacing: 5) {
                        HStack(spacing: 8) {
                            Image(systemName: Categories.symbol(for: stat.name))
                                .font(.caption)
                                .foregroundStyle(.tint)
                                .frame(width: 18)
                            Text(stat.name).font(.subheadline)
                            Text("\(stat.count) 笔")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(MonthlyReport.yuan(stat.total))
                                .font(.subheadline.weight(.medium))
                                .monospacedDigit()
                            Text("\(Int((stat.share * 100).rounded()))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 34, alignment: .trailing)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(.tertiarySystemFill))
                                Capsule()
                                    .fill(Color.accentColor.opacity(0.85))
                                    .frame(width: max(4, geo.size.width * stat.share))
                            }
                        }
                        .frame(height: 5)
                    }
                }
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct LargestCard: View {
    let item: Transaction?

    var body: some View {
        Group {
            if let item {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.up.right.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("最大一笔支出").font(.caption).foregroundStyle(.secondary)
                        Text("\(item.merchant) · \(item.category)")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text(item.date.formatted(.dateTime.month().day().hour().minute()))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(MonthlyReport.yuan(item.amount))
                        .font(.headline.weight(.semibold))
                        .monospacedDigit()
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
}
