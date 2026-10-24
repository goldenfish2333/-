import SwiftUI

@main
struct ScreenshotLedgerApp: App {
    @StateObject private var store: LedgerStore
    @StateObject private var scanner: LibraryScanner

    init() {
        // 先建 store，再把它注入 scanner，保证两者操作的是同一份账本
        let store = LedgerStore()
        _store = StateObject(wrappedValue: store)
        _scanner = StateObject(wrappedValue: LibraryScanner(store: store))
    }

    var body: some Scene {
        WindowGroup {
            // 扫描时机交给 RootView 处理：
            // onChange(of:) 是 View 的修饰符，挂在 Scene 上编译不过（iOS 16）。
            RootView()
                .environmentObject(store)
                .environmentObject(scanner)
        }
    }
}
