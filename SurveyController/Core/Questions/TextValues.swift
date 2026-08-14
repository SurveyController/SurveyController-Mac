// 对标 software/core/questions/text_values.py + utils.py（文本生成器部分）
// v0.1 说明：姓名/手机号生成器为简化实现；身份证号使用少量常用区划码 + 正确校验位算法。

import Foundation

public let multiTextDelimiter = "||"
public let randomNameToken = "__RANDOM_NAME__"
public let randomMobileToken = "__RANDOM_MOBILE__"
public let randomIdCardToken = "__RANDOM_ID_CARD__"
public let randomTextToken = "__RANDOM_TEXT__"
let randomIntTokenPrefix = "__RANDOM_INT__:"

public enum TextValues {

    /// 对标 resolve_text_values_from_config。
    public static func resolveValues(
        answerCandidates: [Any?]?,
        probabilities: [Any?]?,
        blankCount: Int = 1,
        entryType: String = "text",
        blankModes: [Any?]? = nil,
        blankIntRanges: [Any?]? = nil,
        rng: RandomSource = SystemRandomSource()
    ) -> [String] {
        var candidates = (answerCandidates ?? [])
            .map { JSONCoercion.asTrimmedString($0) }
            .filter { !$0.isEmpty }
        if candidates.isEmpty { candidates = [defaultFillText] }

        var weights = (probabilities ?? []).compactMap { item -> Double? in
            if let number = item as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
                return number.doubleValue
            }
            if let text = item as? String { return Double(text) }
            return nil
        }
        if weights.count < candidates.count {
            weights.append(contentsOf: [Double](repeating: 0, count: candidates.count - weights.count))
        } else if weights.count > candidates.count {
            weights = Array(weights.prefix(candidates.count))
        }
        let normalized = (try? AnswerProbabilities.normalize(weights))
            ?? (try? AnswerProbabilities.normalize([Double](repeating: 1.0, count: candidates.count)))
            ?? [1.0]

        let selectedRaw = candidates[rng.weightedIndex(normalized)]
        let resolvedBlankCount = max(1, blankCount)

        var textValues: [String]
        if entryType == "multi_text" {
            textValues = selectedRaw
                .components(separatedBy: multiTextDelimiter)
                .map { resolveDynamicTextToken($0, rng: rng) }
        } else {
            textValues = [resolveDynamicTextToken(selectedRaw, rng: rng)]
        }
        if textValues.isEmpty { textValues = [defaultFillText] }
        if textValues.count < resolvedBlankCount {
            let last = textValues.last ?? defaultFillText
            textValues.append(contentsOf: [String](repeating: last, count: resolvedBlankCount - textValues.count))
        }
        textValues = Array(textValues.prefix(resolvedBlankCount))

        let modes = (blankModes ?? []).map { JSONCoercion.asTrimmedString($0).lowercased() }
        let ranges = blankIntRanges ?? []
        for blankIndex in 0..<resolvedBlankCount {
            let mode = blankIndex < modes.count ? modes[blankIndex] : ""
            switch mode {
            case textRandomName:
                textValues[blankIndex] = generateRandomChineseName(rng: rng)
            case textRandomMobile:
                textValues[blankIndex] = generateRandomMobile(rng: rng)
            case textRandomIdCard:
                textValues[blankIndex] = generateRandomIdCard(rng: rng)
            case textRandomInteger:
                let range = blankIndex < ranges.count ? ranges[blankIndex] : nil
                if let parsed = tryParseRandomIntRange(range) {
                    textValues[blankIndex] = String(rng.nextInt(lower: parsed.min, upper: parsed.max))
                }
            default:
                break
            }
        }
        return textValues
    }

    /// 对标 resolve_dynamic_text_token。
    public static func resolveDynamicTextToken(_ token: Any?, rng: RandomSource = SystemRandomSource()) -> String {
        guard let token, !(token is NSNull) else { return defaultFillText }
        let text = JSONCoercion.asTrimmedString(token)

        if text.hasPrefix(randomIntTokenPrefix) {
            let payload = String(text.dropFirst(randomIntTokenPrefix.count))
            let parts = payload.components(separatedBy: ":")
            if parts.count == 2, let parsed = tryParseRandomIntRange(parts) {
                return String(rng.nextInt(lower: parsed.min, upper: parsed.max))
            }
        }
        switch text {
        case randomNameToken: return generateRandomChineseName(rng: rng)
        case randomMobileToken: return generateRandomMobile(rng: rng)
        case randomIdCardToken: return generateRandomIdCard(rng: rng)
        case randomTextToken: return generateRandomGenericText(rng: rng)
        default: return text.isEmpty ? defaultFillText : text
        }
    }

    // MARK: - 生成器

    static let surnamePool = [
        "张", "王", "李", "赵", "陈", "杨", "刘", "黄", "周", "吴", "徐", "孙", "马", "朱", "胡", "林",
        "郭", "何", "高", "罗", "郑", "梁", "谢", "宋", "唐", "韩", "曹", "许", "邓", "冯",
    ]
    static let maleGivenPool = Array("伟俊涛强磊刚凯鹏鑫宇浩瑞博杰宁豪轩皓子思远家文博宇航志明")
    static let femaleGivenPool = Array("婷雅静怡欣萱琳玲芳颖慧敏雪晶莉倩蕾佳媛茜悦岚蓉瑶诗梦菲琪韵彤璐")
    static let neutralGivenPool = Array("嘉明华建安晨泽文超洋")

    /// 对标 generate_random_chinese_name（简化：姓 + 1~2 字名）。
    public static func generateRandomChineseName(rng: RandomSource = SystemRandomSource()) -> String {
        let surname = rng.choice(surnamePool) ?? "张"
        let pools = [maleGivenPool, femaleGivenPool, neutralGivenPool]
        let pool = rng.choice(pools) ?? neutralGivenPool
        let givenCount = rng.nextInt(lower: 1, upper: 2)
        var given = ""
        for _ in 0..<givenCount {
            given.append(rng.choice(pool) ?? "明")
        }
        return surname + given
    }

    /// 对标 generate_random_mobile：1[3-9] + 9 位数字。
    public static func generateRandomMobile(rng: RandomSource = SystemRandomSource()) -> String {
        var digits = "1"
        digits.append(Character(String(rng.nextInt(lower: 3, upper: 9))))
        for _ in 0..<9 {
            digits.append(String(rng.nextInt(lower: 0, upper: 9)))
        }
        return digits
    }

    static let idCardAreaCodes = ["110101", "310101", "440103", "330102", "510104", "420102", "320102", "500103"]
    static let idCardChecksumWeights = [7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2]
    static let idCardChecksumChars = Array("10X98765432")

    /// 对标 generate_random_id_card（区划码为常用子集，校验位算法 1:1）。
    public static func generateRandomIdCard(rng: RandomSource = SystemRandomSource()) -> String {
        let areaCode = rng.choice(idCardAreaCodes) ?? "110101"
        let year = rng.nextInt(lower: 1965, upper: 2004)
        let month = rng.nextInt(lower: 1, upper: 12)
        let day = rng.nextInt(lower: 1, upper: 28)
        let birth = String(format: "%04d%02d%02d", year, month, day)
        var sequence = String(format: "%02d", rng.nextInt(lower: 0, upper: 99))
        sequence.append(String(rng.nextInt(lower: 0, upper: 9)))

        let firstSeventeen = areaCode + birth + sequence
        var total = 0
        for (index, char) in firstSeventeen.enumerated() {
            if let digit = char.wholeNumberValue, index < idCardChecksumWeights.count {
                total += digit * idCardChecksumWeights[index]
            }
        }
        let checksum = idCardChecksumChars[total % 11]
        return firstSeventeen + String(checksum)
    }

    static let genericSamples = [
        "已填写", "同上", "无", "OK", "收到", "确认", "正常", "通过", "测试数据", "自动填写",
    ]

    /// 对标 generate_random_generic_text。
    public static func generateRandomGenericText(rng: RandomSource = SystemRandomSource()) -> String {
        let base = rng.choice(genericSamples) ?? "无"
        let suffix = rng.nextInt(lower: 10, upper: 999)
        return "\(base)\(suffix)"
    }
}
