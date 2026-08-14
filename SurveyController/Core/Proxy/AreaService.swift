// 对标 software/network/proxy/areas/service.py + policy/source.py 的地区逻辑子集：
// 省市码映射（assets/area_codes_2022.json）、省级判断、地区池选择。

import Foundation

public struct AreaProvince: Identifiable, Hashable, Sendable {
    public let name: String
    public let code: String
    public let cities: [AreaCity]
    public var id: String { code }
}

public struct AreaCity: Identifiable, Hashable, Sendable {
    public let name: String
    public let code: String
    public var id: String { code }
}

public enum AreaService: @unchecked Sendable {

    /// 对标 _AREA_CODE_PATTERN：6 位数字。
    public static func normalizeAreaCode(_ raw: Any?) -> String {
        let text = JSONCoercion.asTrimmedString(raw)
        return text.count == 6 && text.allSatisfy(\.isNumber) ? text : ""
    }

    /// 对标 _is_province_level_area_code：6 位且以 0000 结尾。
    public static func isProvinceLevel(_ areaCode: String?) -> Bool {
        let code = normalizeAreaCode(areaCode)
        return !code.isEmpty && code.hasSuffix("0000")
    }

    /// 对标 _resolve_default_pool_by_area：指定地区时默认源使用优质池。
    public static func resolveDefaultPool(areaCode: String?) -> String? {
        let normalized = normalizeAreaCode(areaCode)
        return normalized.isEmpty ? nil : proxyPoolQuality
    }

    // MARK: - 数据加载

    private final class CacheBox: @unchecked Sendable {
        var provinces: [AreaProvince]? = nil
    }
    private static let cache = CacheBox()

    /// 全部省份与城市（资源缺失时返回空）。
    public static func provinces() -> [AreaProvince] {
        let cached = cache.provinces
        if let cached { return cached }
        guard let url = Bundle.main.url(forResource: "area_codes_2022", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = (try? JSONSerialization.jsonObject(with: data)) as? [[Any]] else {
            return []
        }
        var result: [AreaProvince] = []
        for entry in raw {
            guard entry.count >= 3,
                  let name = entry[0] as? String,
                  let code = entry[1] as? String else { continue }
            var cities: [AreaCity] = []
            if let cityList = entry[2] as? [[Any]] {
                for city in cityList where city.count >= 2 {
                    if let cityName = city[0] as? String, let cityCode = city[1] as? String {
                        cities.append(AreaCity(name: cityName, code: cityCode))
                    }
                }
            }
            result.append(AreaProvince(name: name, code: code, cities: cities))
        }
        cache.provinces = result
        return result
    }

    /// 按名称或码查找省份。
    public static func findProvince(byName name: String) -> AreaProvince? {
        provinces().first { $0.name == name }
    }

    /// 区域码 → 展示名（"广东 广州"，省级只显示省名）。
    public static func describe(areaCode: String?) -> String {
        let code = normalizeAreaCode(areaCode)
        guard !code.isEmpty else { return "不限制" }
        for province in provinces() {
            if province.code == code { return province.name }
            if let city = province.cities.first(where: { $0.code == code }) {
                return "\(province.name) \(city.name)"
            }
        }
        return "不限制"
    }

    /// 全省的所有市码（含省码本身），用于"全省"选项的取值说明。
    public static func cityCodes(of province: AreaProvince) -> [String] {
        [province.code] + province.cities.map { $0.code }
    }
}
