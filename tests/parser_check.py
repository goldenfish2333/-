#!/usr/bin/env python3
"""
ReceiptParser 的等价实现 + 回归测试。

Swift 版在 ScreenshotLedger/Recognition/ReceiptParser.swift，
这里是同一套规则的 Python 镜像，用抽象出来的微信 / 支付宝 / 银行截图 OCR 文本行
验证「金额 / 收支方向 / 商户 / 分类」抽取是否站得住。

改 Swift 规则时，先在这里跑通再同步过去。

用法：python tests/parser_check.py
退出码 0 表示全部通过。
"""

import re
import sys
from dataclasses import dataclass
from datetime import datetime
from typing import List, Optional, Tuple

INCOME_WORDS = ["收款", "收入", "到账", "入账", "已存入", "退款", "退回", "工资", "红包已收"]
EXPENSE_WORDS = ["付款", "支付", "消费", "支出", "转出", "扣款", "已扣除", "缴费", "转账给"]

MERCHANT_HINTS = ["收款方", "商户名称", "商户", "付款给", "转账给", "商品名称", "付款方"]

KNOWN_MERCHANTS = ["美团", "饿了么", "滴滴出行", "滴滴", "星巴克", "瑞幸", "麦当劳", "肯德基",
                   "盒马", "全家", "罗森", "便利蜂", "711", "永辉", "沃尔玛", "天猫超市",
                   "淘宝", "天猫", "京东", "拼多多", "中石化", "中石油", "中国移动",
                   "中国联通", "中国电信", "铁路12306"]

# 顺序即优先级，先命中先返回
CATEGORY_RULES = [
    ("工资", ["工资", "薪资", "薪水", "奖金", "报销", "公积金"]),
    ("居住", ["房租", "租金", "物业", "水费", "电费", "燃气", "取暖", "装修", "房贷"]),
    ("餐饮", ["外卖", "美团", "饿了么", "麦当劳", "肯德基", "星巴克", "瑞幸", "咖啡", "奶茶",
             "餐厅", "饭店", "食堂", "烧烤", "火锅", "面馆", "小面", "拉面", "米线", "米粉",
             "螺蛳粉", "饺子", "包子", "煎饼", "面包", "烘焙", "早餐", "午餐", "晚餐", "夜宵"]),
    ("交通", ["滴滴", "高德", "地铁", "公交", "出行", "打车", "出租车", "高铁", "铁路", "12306",
             "加油", "中石化", "中石油", "停车", "共享单车", "哈啰", "青桔", "航空", "机票"]),
    ("通讯", ["话费", "流量", "宽带", "中国移动", "中国联通", "中国电信", "充值中心"]),
    ("医疗", ["医院", "药房", "药店", "诊所", "体检", "挂号", "门诊"]),
    ("娱乐", ["电影", "影院", "游戏", "腾讯视频", "爱奇艺", "优酷", "bilibili", "B站", "网易云",
             "KTV", "剧本杀", "健身", "演出", "会员"]),
    ("购物", ["淘宝", "天猫", "京东", "拼多多", "唯品会", "抖音商城", "商城", "专柜", "服饰",
             "鞋", "家电", "数码", "苹果", "小米"]),
    ("日用", ["便利店", "全家", "罗森", "711", "7-Eleven", "便利蜂", "超市", "百货", "洗护",
             "日用", "盒马", "永辉"]),
    ("理财", ["基金", "股票", "理财", "保险", "定期", "转入余额宝", "零钱通"]),
    ("转账", ["转账给", "转给", "AA收款", "代付", "发红包", "红包"]),
]

# 版式标签词，会污染分类判断，先抠掉。
# 注意：「转账给 / 付款给」不在这个表里——它们是语义，不是版式标签，
# 抠掉之后「转账给 张伟」就认不出是转账了。
LAYOUT_LABELS = ["收款方", "付款方", "商户名称", "商户", "商品名称",
                 "商品", "订单号", "订单", "转账时间", "支付时间", "付款时间",
                 "交易时间", "创建时间", "账单号", "交易单号", "支付方式", "到账时间"]

# 这些行里的数字永远不是交易金额，整行跳过
HARD_SKIP = ["订单号", "交易单号", "流水号", "凭证号", "客服", "热线",
             "参考号", "汇率", "积分", "手续费", "优惠", "立减", "减免"]

# 可疑但可能仍含交易金额的词：有交易动词就放行
SOFT_SKIP = ["余额", "可用额度", "剩余额度", "尾号", "手机号", "账户"]

TRANSACTION_VERBS = ["支出", "消费", "付款", "支付", "收入", "入账",
                     "到账", "退款", "转入", "转出", "扣款", "扣费"]

AMOUNT_RE = re.compile(r"[¥￥]?\s*(\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)")
DATE_LIKE_RE = re.compile(r"\d{4}[-/年]\d{1,2}[-/月]\d{1,2}|\d{1,2}:\d{2}")

# 提取金额前要抹掉的「长得像金额但不是金额」片段
MASK_PATTERNS = [
    re.compile(r"\d{7,}"),                                    # 订单号、账单号、长卡号
    re.compile(r"\d{4}[-/年]\d{1,2}[-/月]\d{1,2}日?"),         # 2026-10-24 / 2026年10月24日
    re.compile(r"\d{1,2}月\d{1,2}日"),                         # 10月22日
    re.compile(r"\d{1,2}:\d{2}(?::\d{2})?"),                   # 19:05 / 12:47:03
    re.compile(r"(?:尾号|卡号|账号|账户|手机号)\s*[:：]?\s*\d+"),
]

DATE_RE = re.compile(
    r"(\d{4}[-/年]\d{1,2}[-/月]\d{1,2}日?(?:\s*\d{1,2}:\d{2}(?::\d{2})?)?)"
    r"|(\d{1,2}月\d{1,2}日?(?:\s*\d{1,2}:\d{2})?)"
)
FULL_DATE_FORMATS = ["%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y-%m-%d",
                     "%Y/%m/%d %H:%M", "%Y/%m/%d", "%Y年%m月%d日 %H:%M", "%Y年%m月%d日"]


@dataclass
class ParseResult:
    amount: Optional[float]
    flow: str
    merchant: str
    category: str
    date: Optional[datetime]
    confidence: float
    is_likely_payment: bool

    def __str__(self):
        amount = f"{self.amount:.2f}" if self.amount is not None else "None"
        date = self.date.strftime("%Y-%m-%d %H:%M") if self.date else "None"
        return (f"金额={amount} 方向={self.flow} 商户={self.merchant} "
                f"分类={self.category} 日期={date} 置信度={self.confidence:.2f}")


def strip_labels(text: str) -> str:
    for label in LAYOUT_LABELS:
        text = text.replace(label, " ")
    return text


def detect_platform(text: str) -> Optional[str]:
    if "微信支付" in text or "转账给" in text or "已支付" in text:
        return "微信"
    if "支付宝" in text or "余额宝" in text or "花呗" in text:
        return "支付宝"
    if any(b in text for b in ("工商银行", "建设银行", "招商银行", "农业银行",
                               "中国银行", "交通银行", "信用卡")):
        return "银行"
    return None


def detect_flow(text: str) -> str:
    income = sum(1 for w in INCOME_WORDS if w in text)
    expense = sum(1 for w in EXPENSE_WORDS if w in text)
    return "收入" if income > expense else "支出"


def mask(line: str) -> str:
    for pattern in MASK_PATTERNS:
        line = pattern.sub(" ", line)
    return line


def should_skip(line: str) -> bool:
    if any(p in line for p in HARD_SKIP):
        return True
    if any(p in line for p in SOFT_SKIP):
        # 有交易动词就放行（银行短信），纯余额行才丢
        return not any(v in line for v in TRANSACTION_VERBS)
    return False


def amount_candidates(lines: List[str]) -> List[Tuple[float, float]]:
    result: List[Tuple[float, float]] = []
    for index, raw_line in enumerate(lines):
        line = raw_line.strip()
        if not line or len(line) > 60:
            continue
        if should_skip(line):
            continue

        cleaned = mask(line)
        matches = list(AMOUNT_RE.finditer(cleaned))
        if not matches:
            continue

        base = 1.0
        if "¥" in line or "￥" in line:
            base += 1.2
        if any(k in line for k in ("金额", "合计", "总计", "实付", "应付")):
            base += 1.5
        if "元" in line:
            base += 0.6
        base += max(0.0, 0.4 - index * 0.05)
        if DATE_LIKE_RE.search(line):
            base -= 1.2

        for match in matches:
            raw = match.group(1).replace(",", "")
            try:
                value = float(raw)
            except ValueError:
                continue
            if value <= 0 or value >= 10_000_000:
                continue
            weight = base
            # 整数落在年份区间且不含小数点，多半是年份
            if 1900 <= value <= 2100 and "." not in raw:
                weight -= 3.0
            result.append((value, weight))
    return result


def pick_amount(lines: List[str]) -> Optional[float]:
    candidates = amount_candidates(lines)
    if not candidates:
        return None
    scores: dict = {}
    for value, weight in candidates:
        scores[value] = scores.get(value, 0) + weight
    ranked = sorted(scores.items(), key=lambda kv: (kv[1], kv[0]), reverse=True)
    return ranked[0][0]


def detect_merchant(lines: List[str]) -> str:
    for line in lines:
        for hint in MERCHANT_HINTS:
            if hint in line:
                cleaned = line.replace(hint, "").strip(" ：:　")
                if 2 <= len(cleaned) <= 24:
                    return cleaned

    joined = " ".join(lines)
    for name in KNOWN_MERCHANTS:
        if name in joined:
            return name

    banned = ["支付", "付款", "收款", "微信", "支付宝", "银行", "成功", "账单", "余额",
              "详情", "账单详情", "交易", "已", "元"]
    for line in lines[:6]:
        trimmed = line.strip()
        if not (2 <= len(trimmed) <= 16):
            continue
        if re.search(r"\d", trimmed):
            continue
        if any(b in trimmed for b in banned):
            continue
        return trimmed
    return "未知商户"


def detect_date(text: str) -> Optional[datetime]:
    match = DATE_RE.search(text)
    if not match:
        return None
    matched = match.group(0)
    variants = [matched, matched.replace("日", "")]

    for variant in variants:
        for fmt in FULL_DATE_FORMATS:
            try:
                return datetime.strptime(variant, fmt)
            except ValueError:
                continue

    # 只有月（日）没有年份的写法：手工补今年，避免 Python 的默认年份歧义
    short = re.search(r"(\d{1,2})月(\d{1,2})日?(?:\s*(\d{1,2}):(\d{2}))?", matched)
    if short:
        year = datetime.now().year
        return datetime(year, int(short.group(1)), int(short.group(2)),
                        int(short.group(3) or 0), int(short.group(4) or 0))

    short = re.search(r"(\d{1,2})-(\d{1,2})(?:\s*(\d{1,2}):(\d{2}))?", matched)
    if short:
        year = datetime.now().year
        return datetime(year, int(short.group(1)), int(short.group(2)),
                        int(short.group(3) or 0), int(short.group(4) or 0))
    return None


def classify(merchant: str, text: str) -> str:
    haystack = (merchant + " " + text).lower()
    for category, keywords in CATEGORY_RULES:
        if any(kw.lower() in haystack for kw in keywords):
            return category
    return "其他"


def parse(lines: List[str]) -> ParseResult:
    joined = "\n".join(lines)
    amount = pick_amount(lines)
    flow = detect_flow(joined)
    merchant = detect_merchant(lines)
    date = detect_date(joined)
    category = classify(merchant, strip_labels(joined))

    confidence = 0.0
    if amount is not None:
        confidence += 0.55
    if merchant != "未知商户":
        confidence += 0.2
    if date:
        confidence += 0.15
    if detect_platform(joined):
        confidence += 0.1
    confidence = min(confidence, 1.0)

    return ParseResult(amount, flow, merchant, category, date, confidence,
                       amount is not None and confidence >= 0.55)


# ---------------------------------------------------------------- 测试样本
# 抽象自常见版式的 OCR 文本行（不是真实截图原文）。

SAMPLES = [
    ("微信支付-付款成功", [
        "12:47",
        "微信支付",
        "-25.00",
        "付款成功",
        "收款方  幸福小面",
        "支付方式  零钱",
        "转账时间  2026-10-24 12:47:03",
        "账单号  10000509312026102412345678",
    ], 25.00, "支出", "餐饮"),

    ("支付宝-商家收款", [
        "支付宝",
        "19.90",
        "已支付",
        "便利蜂便利店",
        "花呗",
        "2026-10-23 08:15",
    ], 19.90, "支出", "日用"),

    ("银行动账短信", [
        "工商银行",
        "您尾号 1234 的账户于 10月22日 19:05 支出(消费) 348.00 元",
        "余额 2,318.66 元",
        "如有疑问请致电客服热线 95588",
    ], 348.00, "支出", "其他"),

    ("工资入账", [
        "招商银行",
        "8月10日 09:00",
        "工资入账 18,500.00 元",
        "余额 25,110.20 元",
    ], 18500.00, "收入", "工资"),

    ("滴滴行程", [
        "滴滴出行",
        "支付成功",
        "¥ 32.80",
        "快车 · 行程结束",
        "2026/10/21 22:31",
    ], 32.80, "支出", "交通"),

    ("退款到账", [
        "支付宝",
        "退款到账",
        "¥ 68.00",
        "天猫超市",
        "2026年10月20日 10:02",
    ], 68.00, "收入", "购物"),

    ("带大额余额的消费", [
        "微信支付",
        "-156.40",
        "付款成功",
        "收款方  深夜食堂",
        "时间  2026-10-19 20:41",
        "零钱余额  8,432.15",
    ], 156.40, "支出", "餐饮"),

    ("有优惠的订单", [
        "美团外卖",
        "¥ 42.50",
        "已支付",
        "优惠 -8.00",
        "实付 34.50",
        "2026-10-18 12:20",
    ], 34.50, "支出", "餐饮"),

    ("转账给朋友", [
        "微信支付",
        "-200.00",
        "转账给  张伟",
        "2026-10-17 19:30",
        "零钱",
    ], 200.00, "支出", "转账"),
]


def run_tests() -> int:
    failures = 0
    for name, lines, expect_amount, expect_flow, expect_category in SAMPLES:
        result = parse(lines)
        ok_amount = result.amount is not None and abs(result.amount - expect_amount) < 0.005
        ok_flow = result.flow == expect_flow
        ok_category = result.category == expect_category
        ok = ok_amount and ok_flow and ok_category
        if not ok:
            failures += 1
        print(f"[{'PASS' if ok else 'FAIL'}] {name}")
        print(f"        {result}")
        if not ok_amount:
            print(f"        期望金额 {expect_amount:.2f}，实际 {result.amount}")
        if not ok_flow:
            print(f"        期望方向 {expect_flow}，实际 {result.flow}")
        if not ok_category:
            print(f"        期望分类 {expect_category}，实际 {result.category}")
    print()
    print(f"共 {len(SAMPLES)} 例，失败 {failures} 例")
    return failures


if __name__ == "__main__":
    sys.exit(1 if run_tests() else 0)
