// SwiftSoup 的 attr/text/className 均为 throwing API；
// 解析器大量读取属性，统一封装为非抛出版本（对标 BeautifulSoup 的宽松读取）。

import Foundation
import SwiftSoup

extension Element {
    /// 非抛出的属性读取（对标 BeautifulSoup tag.get(name)，异常时返回 ""）。
    public func attrText(_ name: String) -> String {
        (try? attr(name)) ?? ""
    }

    /// 非抛出的文本读取（对标 tag.get_text()）。
    public func textValue() -> String {
        (try? text()) ?? ""
    }

    /// 非抛出的 class 读取。
    public func classValue() -> String {
        (try? className()) ?? ""
    }
}

extension Element {
    public func selectFirst(_ cssQuery: String) -> Element? {
        (try? select(cssQuery).first()) ?? nil
    }

    public func selectAll(_ cssQuery: String) -> [Element] {
        ((try? select(cssQuery).array()) ?? nil) ?? []
    }
}
