import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: LedgerStore
    @EnvironmentObject private var scanner: LibraryScanner
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            TimelineView()
                .tabItem { Label("账目", systemImage: "list.bullet.rectangle") }

            ReportView()
                .tabItem { Label("月报", systemImage: "chart.pie") }

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .overlay(alignment: .top) { // 扫描时顶部条
            if scanner.isScanning {
                ScanningBanner(text: scanner.statusText, progress: scanner.progress)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: scanner.isScanning)
        .task {
            // 冷启动扫一遍新增截图，用户什么都不用做
            await scanAndRefresh()
        }
        .onChange(of: scenePhase) { phase in
            // 关键路径：付完钱截图，切回 App —— 这时是从后台恢复，.task 不会重跑。
            // 不补这一次，这一笔要等到下次冷启动才出现，等于漏记。
            guard phase == .active else { return }
            Task { await scanAndRefresh() }
        }
    }

    /// 扫描 + 把月报通知的文案换成最新账本的数字。
    @MainActor
    private func scanAndRefresh() async {
        await scanner.scanRecent(days: 30)
        await refreshNotificationBody()
    }

    /// 只刷新通知文案，不主动要权限——权限留给用户在设置里开，
    /// 免得第一次打开 App 就弹一个系统授权框。
    ///
    /// 文案用的是**当前这个月**的账本：通知排在**下月 1 号 9 点**响，
    /// 那时这个月刚过去，数字正好对上。
    @MainActor
    private func refreshNotificationBody() async {
        guard await ReportNotifier.isAuthorized() else { return }
        let thisMonth = Date()
        let report = MonthlyReport.build(
            from: store.transactions(inMonthOf: thisMonth),
            month: thisMonth
        )
        await ReportNotifier.scheduleMonthlyRecap { report.notificationText }
    }
}

private struct ScanningBanner: View {
    let text: String
    let progress: Double

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(text.isEmpty ? "正在扫描相册…" : text)
                    .font(.footnote)
                    .foregroundStyle(.primary)
            }
            ProgressView(value: max(0.02, progress))
                .tint(.accentColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }
}
