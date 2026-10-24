import Foundation

/// 把 OCR 出来的一堆文字行，解析成一条账目。
///
/// 微信 / 支付宝 / 各大银行的通知截图版式各不相同，无法做到 100% 精确，
/// 所以策略是「先排除绝不能当金额的行，再按权重打分挑主金额，最后抓商户和时间」。
/// 解析结果全部可编辑——用户改一次的成本，远低于漏掉一笔。
struct ReceiptParser {

    struct Result {
        var amount: Double?
        var flow: MoneyFlow
        var merchant: String
        var category: String
        var date: Date?
        var confidence: Double
        var isLikelyPayment: Bool
    }

    // MARK: - 公共入口

    static func parse(lines: [String]) -> Result {
        let joined = lines.joined(separator: "\n")
        let amount = pickAmount(from: lines)
        let flow = detectFlow(in: joined)
        let merchant = detectMerchant(in: lines)
        let date = detectDate(in: joined)
        let category = Categories.classify(merchant: merchant, text: stripLabels(joined))

        var confidence = 0.0
        if amount != nil { confidence += 0.55 }
        if merchant != "未知商户" { confidence += 0.2 }
        if date != nil { confidence += 0.15 }
        if detectPlatform(in: joined) != nil { confidence += 0.1 }

        return Result(
            amount: amount.map { abs($0) },
            flow: flow,
            merchant: merchant,
            category: category,
            date: date,
            confidence: min(confidence, 1.0),
            isLikelyPayment: amount != nil && confidence >= 0.55
        )
    }

    /// 把版式标签词抠掉，否则分类关键词会被标签本身误伤
    /// ——比如「转账时间」里的「转账」会把一笔午饭判成转账。
    /// 注意「转账给 / 付款给」不算版式标签：它们是语义，抠掉就认不出转账了。
    static func stripLabels(_ text: String) -> String {
        var result = text
        let layoutLabels = ["收款方", "付款方", "商户名称", "商户", "商品名称",
                            "商品", "订单号", "订单", "转账时间", "支付时间", "付款时间",
                            "交易时间", "创建时间", "账单号", "交易单号", "支付方式", "到账时间"]
        for label in layoutLabels {
            result = result.replacingOccurrences(of: label, with: " ")
        }
        return result
    }

    // MARK: - 平台

    enum Platform: String {
        case wechat = "微信"
        case alipay = "支付宝"
        case bank = "银行"
    }

    static func detectPlatform(in text: String) -> Platform? {
        if text.contains("微信支付") || text.contains("转账给") || text.contains("已支付") { return .wechat }
        if text.contains("支付宝") || text.contains("余额宝") || text.contains("花呗") { return .alipay }
        for bank in ["工商银行", "建设银行", "招商银行", "农业银行", "中国银行", "交通银行", "信用卡"]
        where text.contains(bank) { return .bank }
        return nil
    }

    // MARK: - 收支方向

    private static let incomeWords = ["收款", "收入", "到账", "入账", "已存入", "退款", "退回", "工资", "红包已收"]
    private static let expenseWords = ["付款", "支付", "消费", "支出", "转出", "扣款", "已扣除", "缴费", "转账给"]

    static func detectFlow(in text: String) -> MoneyFlow {
        var income = 0
        var expense = 0
        for word in incomeWords where text.contains(word) { income += 1 }
        for word in expenseWords where text.contains(word) { expense += 1 }
        return income > expense ? .income : .expense
    }

    // MARK: - 金额

    private static let amountRegex = try! NSRegularExpression(
        pattern: #"[¥￥]?\s*(\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)"#
    )
    private static let dateLikeRegex = try! NSRegularExpression(
        pattern: #"\d{4}[-/年]\d{1,2}[-/月]\d{1,2}|\d{1,2}:\d{2}"#
    )

    private struct Candidate {
        var value: Double
        var weight: Double
    }

    /// 这些行里的数字永远不是「这笔交易的金额」，整行跳过。
    private static let hardSkip = ["订单号", "交易单号", "流水号", "凭证号", "客服", "热线",
                                   "参考号", "汇率", "积分", "手续费", "优惠", "立减", "减免"]

    /// 这些词出现时金额可疑，但如果同一行里还有明确的交易动词，就仍然算数
    /// ——银行短信就是这种：「尾号 1234 的账户于 10月22日 支出(消费) 348.00 元」。
    private static let softSkip = ["余额", "可用额度", "剩余额度", "尾号", "手机号", "账户"]

    private static let transactionVerbs = ["支出", "消费", "付款", "支付", "收入", "入账",
                                           "到账", "退款", "转入", "转出", "扣款", "扣费"]

    /// 提取金额前先抹掉这些「长得像金额但不是金额」的片段：
    /// 订单号/卡号/手机号这类长数字、日期时间、尾号与账号。
    private static let maskPatterns: [NSRegularExpression] = {
        let patterns = [
            #"\d{7,}"#,                                            // 订单号、账单号、长卡号
            #"\d{4}[-/年]\d{1,2}[-/月]\d{1,2}日?"#,                 // 2026-10-24 / 2026年10月24日
            #"\d{1,2}月\d{1,2}日"#,                                 // 10月22日
            #"\d{1,2}:\d{2}(?::\d{2})?"#,                           // 19:05 / 12:47:03
            #"(?:尾号|卡号|账号|账户|手机号)\s*[:：]?\s*\d+"#         // 尾号 1234
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    private static func masked(_ line: String) -> String {
        var result = line
        for regex in maskPatterns {
            let ns = result as NSString
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(location: 0, length: ns.length), withTemplate: " "
            )
        }
        return result
    }

    private static func shouldSkip(_ line: String) -> Bool {
        if hardSkip.contains(where: line.contains) { return true }
        if softSkip.contains(where: line.contains) {
            // 有交易动词就放行（银行短信），纯余额行才丢
            return !transactionVerbs.contains(where: line.contains)
        }
        return false
    }

    private static func candidates(from lines: [String]) -> [Candidate] {
        var result: [Candidate] = []
        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, line.count <= 60 else { continue }
            if shouldSkip(line) { continue }

            let cleaned = masked(line)
            let ns = cleaned as NSString
            let matches = amountRegex.matches(in: cleaned, range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { continue }

            var base = 1.0
            if line.contains("¥") || line.contains("￥") { base += 1.2 }
            if ["金额", "合计", "总计", "实付", "应付"].contains(where: line.contains) { base += 1.5 }
            if line.contains("元") { base += 0.6 }
            // 越靠上的大字金额越可能是主金额
            base += max(0, 0.4 - Double(index) * 0.05)
            let fullRange = NSRange(location: 0, length: (line as NSString).length)
            if dateLikeRegex.firstMatch(in: line, range: fullRange) != nil { base -= 1.2 }

            for match in matches {
                guard match.numberOfRanges > 1 else { continue }
                let raw = ns.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: "")
                guard let value = Double(raw), value > 0, value < 10_000_000 else { continue }
                var weight = base
                // 整数值落在年份区间且不含小数点，多半是年份不是金额
                if value >= 1900, value <= 2100, !raw.contains(".") { weight -= 3.0 }
                result.append(Candidate(value: value, weight: weight))
            }
        }
        return result
    }

    private static func pickAmount(from lines: [String]) -> Double? {
        let items = candidates(from: lines)
        guard !items.isEmpty else { return nil }

        // 同一金额出现多次时权重累加：微信截图里金额常在标题和详情各出现一次
        var scoreByValue: [Double: Double] = [:]
        for item in items {
            scoreByValue[item.value, default: 0] += item.weight
        }

        // 先按总权重降序，权重相同再取金额大的（大字金额才是主金额）
        let ranked = scoreByValue.sorted { lhs, rhs in
            if abs(lhs.value - rhs.value) > 0.001 { return lhs.value > rhs.value }
            return lhs.key > rhs.key
        }
        return ranked.first?.key
    }

    // MARK: - 商户

    private static let merchantHints = ["收款方", "商户名称", "商户", "付款给", "转账给", "商品名称", "付款方"]

    private static let knownMerchants = ["美团", "饿了么", "滴滴", "滴滴出行", "星巴克", "瑞幸", "麦当劳",
                                         "肯德基", "盒马", "全家", "罗森", "便利蜂", "711", "永辉",
                                         "沃尔玛", "淘宝", "天猫", "京东", "拼多多", "中石化", "中石油",
                                         "中国移动", "中国联通", "中国电信", "铁路12306", "天猫超市"]

    private static func detectMerchant(in lines: [String]) -> String {
        // 1. 带明确标签的行
        for line in lines {
            for hint in merchantHints where line.contains(hint) {
                let cleaned = line
                    .replacingOccurrences(of: hint, with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ：:　"))
                if cleaned.count >= 2 && cleaned.count <= 24 { return cleaned }
            }
        }
        // 2. 已知商户关键词直接命中
        let joined = lines.joined(separator: " ")
        for name in knownMerchants where joined.contains(name) { return name }
        // 3. 退化为前几行里第一条「短、不带数字、不像状态词」的文本
        let banned = ["支付", "付款", "收款", "微信", "支付宝", "银行", "成功", "账单", "余额",
                      "详情", "账单详情", "交易", "已", "元"]
        for line in lines.prefix(6) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 2, trimmed.count <= 16 else { continue }
            if trimmed.rangeOfCharacter(from: .decimalDigits) != nil { continue }
            if banned.contains(where: trimmed.contains) { continue }
            return trimmed
        }
        return "未知商户"
    }

    // MARK: - 日期

    private static let datePattern = #"(\d{4}[-/年]\d{1,2}[-/月]\d{1,2}日?(?:\s*\d{1,2}:\d{2}(?::\d{2})?)?)|(\d{1,2}月\d{1,2}日?(?:\s*\d{1,2}:\d{2})?)"#

    private static let fullDateFormats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd",
                                          "yyyy/MM/dd HH:mm", "yyyy/MM/dd",
                                          "yyyy年M月d日 HH:mm", "yyyy年M月d日"]
    private static let shortDateFormats = ["M月d日 HH:mm", "M月d日", "MM-dd HH:mm", "MM-dd"]

    private static func detectDate(in text: String) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: datePattern),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)),
              let range = Range(match.range, in: text) else { return nil }

        let matched = String(text[range])
        let variants = [matched, matched.replacingOccurrences(of: "日", with: "")]
        let calendar = Calendar.current

        for variant in variants {
            for format in fullDateFormats {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "zh_CN")
                formatter.dateFormat = format
                if let date = formatter.date(from: variant) { return date }
            }
            for format in shortDateFormats {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "zh_CN")
                formatter.dateFormat = format
                guard let date = formatter.date(from: variant) else { continue }
                // 只有月日的写法会补一个默认年，改成今年，避免跨年时落到 2000 年
                var components = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
                components.year = calendar.component(.year, from: Date())
                if let fixed = calendar.date(from: components) { return fixed }
            }
        }
        return nil
    }
}
