import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var store: LedgerStore
    @EnvironmentObject private var scanner: LibraryScanner

    @State private var exportURL: URL?
    @State private var showingShare = false
    @State private var showingImporter = false
    @State private var alertMessage: String?
    @State private var notifyEnabled = false
    @State private var showingWipeConfirm = false
    @State private var scanDays = 30

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        Task { await scanner.scanRecent(days: scanDays) }
                    } label: {
                        HStack {
                            Label("现在扫描相册", systemImage: "magicwand")
                            Spacer()
                            if scanner.isScanning {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .disabled(scanner.isScanning)

                    Picker("扫描范围", selection: $scanDays) {
                        Text("最近 7 天").tag(7)
                        Text("最近 30 天").tag(30)
                        Text("最近 90 天").tag(90)
                        Text("最近一年").tag(365)
                    }

                    if scanner.isLimitedAccess {
                        Button {
                            scanner.presentLimitedPicker()
                        } label: {
                            Label("选择「可访问的照片」范围", systemImage: "photo.badge.plus")
                        }
                        Text("现在只允许读取相册里的一部分照片。新截图默认不在里面，点上面这一行把它们加进来，否则会一直显示「没有新截图」。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if let error = scanner.lastError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    } else if !scanner.statusText.isEmpty {
                        Text(scanner.statusText).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("截图识别")
                } footer: {
                    Text("打开 App 会自动扫一遍。识别只在本机进行，照片不会离开手机。")
                }

                Section {
                    Toggle("每月 1 号推送月报", isOn: $notifyEnabled)
                        .onChange(of: notifyEnabled) { enabled in
                            Task { @MainActor in
                                if enabled {
                                    let ok = await ReportNotifier.requestPermission()
                                    if !ok {
                                        notifyEnabled = false
                                        alertMessage = "系统里关掉了通知权限，去「设置 → 通知 → 截图账本」打开"
                                        return
                                    }
                                    let report = MonthlyReport.build(
                                        from: store.transactions(inMonthOf: Date()),
                                        month: Date()
                                    )
                                    await ReportNotifier.scheduleMonthlyRecap { report.notificationText }
                                } else {
                                    ReportNotifier.cancel()
                                }
                            }
                        }
                } header: {
                    Text("月报提醒")
                } footer: {
                    Text("1 号上午 9 点弹一条：上月花了多少、哪类最多、最大一笔是什么。")
                }

                Section {
                    Button {
                        exportURL = store.exportJSON()
                        showingShare = exportURL != nil
                    } label: {
                        Label("导出账本（JSON）", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        exportURL = store.exportCSV()
                        showingShare = exportURL != nil
                    } label: {
                        Label("导出表格（CSV）", systemImage: "tablecells")
                    }

                    Button {
                        showingImporter = true
                    } label: {
                        Label("导入账本", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("换手机 / 备份")
                } footer: {
                    Text("JSON 用于完整备份与恢复，CSV 可以丢进 Excel 或 Numbers 打开。导入按每条账的唯一编号合并，重复导入不会出现重复账目。")
                }

                Section {
                    HStack {
                        Text("账目数量")
                        Spacer()
                        Text("\(store.transactions.count)").foregroundStyle(.secondary)
                    }
                    Button(role: .destructive) {
                        showingWipeConfirm = true
                    } label: {
                        Label("清空全部账目", systemImage: "trash")
                    }
                } header: {
                    Text("数据")
                } footer: {
                    Text("清空后无法恢复，建议先导出一份 JSON。")
                }

                Section {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0").foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("仅供个人使用，未上架 App Store。")
                }
            }
            .navigationTitle("设置")
            .sheet(isPresented: $showingShare) {
                if let exportURL {
                    ShareSheet(items: [exportURL])
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let count = store.importJSON(from: url)
                    alertMessage = count > 0 ? "导入了 \(count) 笔账目" : "没有发现新账目（可能已经导入过）"
                case .failure(let error):
                    alertMessage = "导入失败：\(error.localizedDescription)"
                }
            }
            .alert("提示", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("好", role: .cancel) { alertMessage = nil }
            } message: {
                Text(alertMessage ?? "")
            }
            .confirmationDialog("确定清空全部账目？", isPresented: $showingWipeConfirm) {
                Button("清空", role: .destructive) {
                    store.delete(ids: Set(store.transactions.map(\.id)))
                    scanner.resetProcessedIDs()
                    alertMessage = "已清空。下次打开 App 会重新扫一遍相册。"
                }
                Button("取消", role: .cancel) {}
            }
            .onAppear {
                Task { @MainActor in
                    let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
                    notifyEnabled = requests.contains { $0.identifier == ReportNotifier.identifier }
                }
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
