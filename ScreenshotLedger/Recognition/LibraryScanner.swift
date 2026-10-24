import Foundation
import Photos
import UIKit
// 同 LedgerStore：ObservableObject / @Published 在 Combine 里
import Combine

/// 相册扫描器：把「新增的截图」交给 OCR 解析，已经处理过的资源 ID 记在本地，
/// 下次打开 App 只处理增量，不会重复记账。
@MainActor
final class LibraryScanner: ObservableObject {

    @Published var isScanning = false
    @Published var progress: Double = 0
    @Published var statusText = ""
    @Published var lastBatch: [Transaction] = []
    @Published var lastError: String?

    private let processedKey = "processedAssetIDs"
    /// 上一次成功扫完相册的时间。用来决定这次要往回翻多少天——
    /// 如果只固定扫 30 天，你出差两个月没打开这个 App，中间那些截图就永远被跳过了。
    private let lastScanKey = "lastScanAt"
    private let store: LedgerStore

    init(store: LedgerStore) {
        self.store = store
    }

    private var processedIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: processedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: processedKey) }
    }

    func requestAccess() async -> Bool {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if current == .authorized || current == .limited { return true }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status == .authorized || status == .limited)
            }
        }
    }

    /// 用户如果选了「仅允许访问部分照片」，新截图默认不在名单里，
    /// 扫描会一直显示「没有新截图」——必须主动把选择器叫出来。
    @MainActor
    var isLimitedAccess: Bool {
        PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited
    }

    @MainActor
    func presentLimitedPicker() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: root)
    }

    /// 清空账本时要一并忘掉「哪些截图已经处理过」，
    /// 否则删完账再扫一遍，一张都不会回来（都被当成处理过的了）。
    /// 连「上次扫描时间」一起清掉，让下次扫描把范围放到最大。
    func resetProcessedIDs() {
        UserDefaults.standard.removeObject(forKey: processedKey)
        UserDefaults.standard.removeObject(forKey: lastScanKey)
        lastBatch = []
        statusText = ""
        lastError = nil
    }

    /// 扫描最近 `days` 天内、还没处理过的截图。
    func scanRecent(days: Int = 30) async {
        guard !isScanning else { return }
        isScanning = true
        lastError = nil
        lastBatch = []
        progress = 0
        defer { isScanning = false }

        guard await requestAccess() else {
            lastError = "没有相册权限，去「设置 → 截图账本 → 照片」里打开"
            return
        }

        // 实际往回翻的天数取「设置里的范围」和「距上次扫描的天数 + 1」的较大值。
        // 理由：如果两个月没打开过这个 App，只扫 30 天会把中间一个月的截图整段跳过，
        // 那些账就永远补不回来了。上限一年，免得第一次装就翻遍整个相册。
        let effectiveDays = max(1, min(365, max(days, daysSinceLastScan() + 1)))

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(
            format: "mediaType == %d AND creationDate >= %@",
            PHAssetMediaType.image.rawValue,
            Date().addingTimeInterval(-Double(effectiveDays) * 86_400) as NSDate
        )

        let assets = PHAsset.fetchAssets(with: options)
        var targets: [PHAsset] = []
        var newIDs = processedIDs
        // 账本里已经存在的截图 ID 也算「处理过」。
        // 场景：换手机 → 导入 JSON 账本 → 重新扫相册。
        // 这时 UserDefaults 里那份 processedIDs 是空的（新装的 App），
        // 只靠它去重会把导入进来的账目再记一遍，账本里每一笔都变成两条。
        let alreadyInLedger = Set(store.transactions.compactMap(\.assetID))
        assets.enumerateObjects { asset, _, _ in
            guard Self.isScreenshotLike(asset) else { return }
            if alreadyInLedger.contains(asset.localIdentifier) {
                newIDs.insert(asset.localIdentifier)
                return
            }
            guard !newIDs.contains(asset.localIdentifier) else { return }
            targets.append(asset)
        }

        guard !targets.isEmpty else {
            statusText = "没有新截图"
            processedIDs = newIDs
            UserDefaults.standard.set(Date(), forKey: lastScanKey)
            return
        }

        var found: [Transaction] = []

        for (index, asset) in targets.enumerated() {
            statusText = "正在识别第 \(index + 1)/\(targets.count) 张"
            progress = Double(index) / Double(targets.count)
            defer { newIDs.insert(asset.localIdentifier) }

            guard let image = await loadImage(for: asset) else { continue }
            guard let lines = try? await OCR.recognizeText(in: image), !lines.isEmpty else { continue }
            guard OCR.looksLikePaymentScreenshot(lines) else { continue }

            let parsed = ReceiptParser.parse(lines: lines)
            guard parsed.isLikelyPayment, let amount = parsed.amount, amount > 0 else { continue }

            found.append(Transaction(
                amount: amount,
                flow: parsed.flow,
                merchant: parsed.merchant,
                category: parsed.category,
                date: parsed.date ?? asset.creationDate ?? Date(),
                note: "",
                assetID: asset.localIdentifier,
                rawText: lines.joined(separator: "\n")
            ))
        }

        processedIDs = newIDs
        store.add(found)
        lastBatch = found
        progress = 1
        statusText = found.isEmpty ? "扫了 \(targets.count) 张，没发现新的付款截图" : "识别到 \(found.count) 笔"
        UserDefaults.standard.set(Date(), forKey: lastScanKey)
    }

    /// 距上次成功扫描过了多少天。第一次装（没有记录）返回 30。
    private func daysSinceLastScan() -> Int {
        guard let last = UserDefaults.standard.object(forKey: lastScanKey) as? Date else { return 30 }
        let seconds = Date().timeIntervalSince(last)
        guard seconds > 0 else { return 30 }
        return Int(seconds / 86_400)
    }

    /// 系统截图在相册里的标记（.photoScreenshot）；但微信里「保存图片」下来的截图
    /// 会丢掉这个标记，所以再补一条「宽高比像手机屏幕」的判断，
    /// 免得用户转发一圈再存回来就识别不到了。
    private nonisolated static func isScreenshotLike(_ asset: PHAsset) -> Bool {
        if asset.mediaSubtypes.contains(.photoScreenshot) { return true }
        let width = Double(asset.pixelWidth)
        let height = Double(asset.pixelHeight)
        guard width > 0, height > 0 else { return false }
        let ratio = max(width, height) / min(width, height)
        return ratio >= 1.7 && ratio <= 2.35
    }

    /// PHImageManager 在高质量模式下可能回调多次，只认第一次，
    /// 否则 continuation 会被重复 resume 直接崩掉。
    private final class OnceFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var used = false
        func consume() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if used { return false }
            used = true
            return true
        }
    }

    private func loadImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .downscale
            options.isNetworkAccessAllowed = true
            let flag = OnceFlag()
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 1600, height: 1600),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                guard flag.consume() else { return }
                continuation.resume(returning: image)
            }
        }
    }
}
