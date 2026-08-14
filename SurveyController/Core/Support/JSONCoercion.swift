// 对标 Python 对动态 dict 的宽松类型转换习惯（int()/bool()/str()）。
// 配置文件与平台返回的 JSON 形状不固定，统一走这里的宽容转换。

import Foundation

public enum JSONCoercion {
    /// Python int(value)：数字取整，字符串解析，失败返回 default。
    public static func asInt(_ value: Any?, default defaultValue: Int = 0) -> Int {
        if let number = value as? NSNumber {
            // Bool 是 NSNumber 的特例，按 Python bool→int 语义处理
            if number === kCFBooleanTrue || CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? 1 : 0
            }
            return number.intValue
        }
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let text = value as? String { return Int(text.trimmingCharacters(in: .whitespaces)) ?? defaultValue }
        return defaultValue
    }

    /// Python float(value)。
    public static func asDouble(_ value: Any?, default defaultValue: Double = 0.0) -> Double {
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? 1.0 : 0.0
            }
            return number.doubleValue
        }
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let text = value as? String { return Double(text.trimmingCharacters(in: .whitespaces)) ?? defaultValue }
        return defaultValue
    }

    /// codec._as_bool：None→default；bool 原样；数字取真值；
    /// 字符串 1/true/yes/on → true，0/false/no/off/空 → false，其余 default。
    public static func asBool(_ value: Any?, default defaultValue: Bool = false) -> Bool {
        guard let value = value else { return defaultValue }
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
            return number.doubleValue != 0
        }
        if let int = value as? Int { return int != 0 }
        if let double = value as? Double { return double != 0 }
        if let text = value as? String {
            switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes", "on": return true
            case "0", "false", "no", "off", "": return false
            default: return defaultValue
            }
        }
        return defaultValue
    }

    /// Python str(value or "")。
    public static func asString(_ value: Any?) -> String {
        guard let value = value else { return "" }
        if let text = value as? String { return text }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "True" : "False" }
            let double = number.doubleValue
            if double.truncatingRemainder(dividingBy: 1) == 0 && abs(double) < 1e15 {
                return String(Int(double))
            }
            return number.stringValue
        }
        return String(describing: value)
    }

    /// Python str(value or "").strip()。
    public static func asTrimmedString(_ value: Any?) -> String {
        asString(value).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 列表元素宽松转 Int（失败跳过）。
    public static func asIntList(_ value: Any?) -> [Int] {
        guard let list = value as? [Any] else { return [] }
        return list.compactMap { item -> Int? in
            if let number = item as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
                return number.intValue
            }
            if let text = item as? String { return Int(text.trimmingCharacters(in: .whitespaces)) }
            if let int = item as? Int { return int }
            return nil
        }
    }

    /// 列表元素转字符串。
    public static func asStringList(_ value: Any?) -> [String] {
        guard let list = value as? [Any] else { return [] }
        return list.map { item -> String in
            if item is NSNull { return "" }
            return asString(item)
        }
    }

    /// 列表元素转字典（非字典元素跳过）。
    public static func asDictList(_ value: Any?) -> [[String: Any]] {
        guard let list = value as? [Any] else { return [] }
        return list.compactMap { $0 as? [String: Any] }
    }

    /// 浮点数值列表（用于概率数组：Int/Double/数字字符串都接受）。
    public static func asDoubleList(_ value: Any?) -> [Double]? {
        guard let list = value as? [Any] else { return nil }
        var result: [Double] = []
        for item in list {
            if let number = item as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
                result.append(number.doubleValue)
            } else if let text = item as? String, let double = Double(text) {
                result.append(double)
            } else {
                return nil
            }
        }
        return result
    }

    /// 数值是否为正（对标 _prob_config_is_unset 里的 float(item) > 0 判断）。
    public static func isPositiveNumber(_ value: Any?) -> Bool {
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return number.doubleValue > 0
        }
        if let text = itemText(value) { return (Double(text) ?? 0) > 0 }
        if let nested = value as? [Any] { return nested.contains { isPositiveNumber($0) } }
        return false
    }

    static func itemText(_ value: Any?) -> String? {
        guard let value = value, !(value is NSNull) else { return nil }
        if let text = value as? String { return text.trimmingCharacters(in: .whitespaces) }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return number.stringValue
        }
        return nil
    }
}
