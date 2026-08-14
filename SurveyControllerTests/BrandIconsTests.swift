// 品牌图标矢量解析的正确性（GitHub 官方 24×24 路径）

import XCTest
@testable import SurveyController

final class BrandIconsTests: XCTestCase {

    func test_github_mark_parses_into_square_24pt_path() {
        let path = SVGPathParser.path(from: GitHubIcon.markPath, in: CGSize(width: 24, height: 24))
        let bounding = path.boundingRect
        XCTAssertFalse(bounding.isEmpty, "GitHub 轮廓解析为空")
        // 官方轮廓非满幅，等比缩放后两条边都应接近画布且不超出
        XCTAssertLessThanOrEqual(bounding.width, 24.5)
        XCTAssertLessThanOrEqual(bounding.height, 24.5)
        XCTAssertGreaterThan(bounding.width, 20)
        XCTAssertGreaterThan(bounding.height, 20)
        // 路径元素应显著非空（曲线填充）
        XCTAssertGreaterThan(bounding.width * bounding.height, 100)
    }

    func test_parser_handles_negative_numbers_without_spaces() {
        // "1.5.5-2 3" 之类紧贴负号/双小数点的写法必须被正确分词
        let path = SVGPathParser.path(from: "M1.5.5-2 3L4-1 5", in: CGSize(width: 10, height: 10))
        XCTAssertFalse(path.isEmpty)
        let bounding = path.boundingRect
        XCTAssertTrue(bounding.width > 0 && bounding.height > 0)
    }
}
