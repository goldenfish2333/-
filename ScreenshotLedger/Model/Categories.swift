import Foundation

enum Categories {
    static let all = [
        "餐饮", "交通", "购物", "日用", "居住", "医疗",
        "娱乐", "通讯", "转账", "工资", "理财", "其他"
    ]

    /// 关键词 -> 分类。顺序即优先级，先命中先返回。
    /// 注意：这里的词要「够具体」，别放「转账」「收款」这种版式标签词，
    /// 否则截图里的「转账时间」「收款方」会把分类带偏。
    private static let rules: [(String, [String])] = [
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
        ("转账", ["转账给", "转给", "AA收款", "代付", "发红包", "红包"])
    ]

    static func classify(merchant: String, text: String) -> String {
        let haystack = (merchant + " " + text).lowercased()
        for (category, keywords) in rules {
            for keyword in keywords where haystack.contains(keyword.lowercased()) {
                return category
            }
        }
        return "其他"
    }

    static let symbols: [String: String] = [
        "餐饮": "fork.knife", "交通": "car.fill", "购物": "bag.fill", "日用": "cart.fill",
        "居住": "house.fill", "医疗": "cross.case.fill", "娱乐": "gamecontroller.fill",
        "通讯": "antenna.radiowaves.left.and.right", "转账": "arrow.left.arrow.right",
        "工资": "banknote.fill", "理财": "chart.pie.fill", "其他": "ellipsis.circle.fill"
    ]

    static func symbol(for category: String) -> String {
        symbols[category] ?? "ellipsis.circle.fill"
    }
}
