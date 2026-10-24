import Foundation
import Vision
import UIKit

/// 用苹果自带的 Vision 框架在本地做文字识别，全程离线，不上传任何图片。
enum OCR {

    /// OCR 是纯 CPU 活，跑几百毫秒。放在主线程上会把界面卡住，
    /// 所以丢到后台队列，靠 continuation 回主线程。
    static func recognizeText(in image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = orientation(of: image)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String], Error>) in
            // Vision 的回调 + perform 抛错这两条路径都可能碰到 continuation，
            // 重复 resume 会直接把 App 崩掉，所以只放行第一次。
            let flag = OnceFlag()
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { request, error in
                    guard flag.consume() else { return }
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    let observations = request.results as? [VNRecognizedTextObservation] ?? []
                    let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                    continuation.resume(returning: lines)
                }
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["zh-Hans", "en-US"]
                request.usesLanguageCorrection = true
                if #available(iOS 16.0, *) {
                    request.automaticallyDetectsLanguage = false
                }

                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
                do {
                    try handler.perform([request])
                } catch {
                    guard flag.consume() else { return }
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// continuation 只允许 resume 一次，这里保证这件事。
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

    private static func orientation(of image: UIImage) -> CGImagePropertyOrientation {
        switch image.imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    /// 判断这张图的文字像不像「一笔付款」。
    ///
    /// 注意顺序：这一步在 OCR 之后跑。OCR 本身没法预筛（不认字怎么知道是不是付款），
    /// 所以这里的作用是挡住「OCR 认出了字，但显然不是账单」的图
    /// ——比如菜单、路牌、聊天记录，别让它们进解析器凑出个假金额。
    static func looksLikePaymentScreenshot(_ lines: [String]) -> Bool {
        let joined = lines.joined(separator: "")
        let keywords = ["支付", "付款", "收款", "转账", "消费", "交易成功", "已支付", "扣款",
                        "账单", "余额", "微信", "支付宝", "银行", "元", "¥", "￥"]
        return keywords.contains { joined.contains($0) }
    }
}
