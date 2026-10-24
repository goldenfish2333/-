import SwiftUI

struct EntryEditor: View {
    enum Mode {
        case create
        case edit(Transaction)

        var isEdit: Bool {
            if case .edit = self { return true }
            return false
        }
    }

    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var amountText = ""
    @State private var flow: MoneyFlow = .expense
    @State private var merchant = ""
    @State private var category = "其他"
    @State private var date = Date()
    @State private var note = ""
    @State private var showingRawText = false

    private var editingItem: Transaction? {
        if case .edit(let item) = mode { return item }
        return nil
    }

    private var parsedAmount: Double? {
        Double(amountText.replacingOccurrences(of: ",", with: ""))
    }

    private var canSave: Bool {
        guard let value = parsedAmount, value > 0 else { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("¥")
                            .font(.title2.weight(.light))
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    Picker("类型", selection: $flow) {
                        ForEach(MoneyFlow.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("明细") {
                    TextField("商户 / 用途", text: $merchant)

                    Picker("分类", selection: $category) {
                        ForEach(Categories.all, id: \.self) { name in
                            Label(name, systemImage: Categories.symbol(for: name)).tag(name)
                        }
                    }

                    DatePicker("时间", selection: $date, displayedComponents: [.date, .hourAndMinute])

                    TextField("备注（可选）", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }

                if let item = editingItem, let raw = item.rawText, !raw.isEmpty {
                    Section {
                        DisclosureGroup("识别原文", isExpanded: $showingRawText) {
                            Text(raw)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    } footer: {
                        Text("如果金额认错了，直接在上面改，改完保存即可。原文留着方便你核对。")
                    }
                }

                if editingItem == nil {
                    Section {
                        Text("手工补记：现金、别人代付、或者截图没截上的那笔。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(mode.isEdit ? "改这笔账" : "补记一笔")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: loadInitial)
            .onChange(of: merchant) { newValue in
                // 手工改商户名时顺手猜一个分类，用户懒得选就自动填上
                guard editingItem == nil || category == "其他" else { return }
                let guess = Categories.classify(merchant: newValue, text: newValue)
                if guess != "其他" { category = guess }
            }
        }
    }

    private func loadInitial() {
        guard let item = editingItem else {
            amountText = ""
            return
        }
        amountText = String(format: "%.2f", item.amount)
        flow = item.flow
        merchant = item.merchant == "未知商户" ? "" : item.merchant
        category = item.category
        date = item.date
        note = item.note
    }

    private func save() {
        guard let value = parsedAmount, value > 0 else { return }
        let resolvedCategory = category == "其他"
            ? Categories.classify(merchant: merchant, text: merchant)
            : category

        if var item = editingItem {
            item.amount = value
            item.flow = flow
            item.merchant = merchant.isEmpty ? "未知商户" : merchant
            item.category = resolvedCategory
            item.date = date
            item.note = note
            store.update(item)
        } else {
            store.add(Transaction(
                amount: value,
                flow: flow,
                merchant: merchant.isEmpty ? "未知商户" : merchant,
                category: resolvedCategory,
                date: date,
                note: note
            ))
        }
        dismiss()
    }
}
