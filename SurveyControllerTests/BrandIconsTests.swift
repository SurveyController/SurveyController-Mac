// 品牌图标矢量解析的正确性（GitHub 官方 24×24 路径）

import XCTest
import AppKit
@testable import SurveyController

final class BrandIconsTests: XCTestCase {

    func test_github_mark_parses_into_square_24pt_path() throws {
        let path = SVGPathParser.path(from: GitHubIcon.markPath, in: CGSize(width: 24, height: 24))
        let bounding = path.boundingRect
        XCTAssertFalse(bounding.isEmpty, "GitHub 轮廓解析为空")
        // 官方路径 x 方向恰好铺满 0~24，y 方向约 0.3~23.9
        XCTAssertEqual(bounding.width, 24, accuracy: 0.1)
        XCTAssertGreaterThan(bounding.height, 23)
        XCTAssertLessThanOrEqual(bounding.height, 24.01)

        // 纯 CG 离屏渲染成 PNG 供目检（/tmp/github_icon.png）
        let scale: CGFloat = 16
        let width = Int(24 * scale + 32)
        let height = Int(24 * scale + 32)
        var pixelData = [UInt8](repeating: 255, count: width * height * 4)
        let context = CGContext(
            data: &pixelData, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        let translated = path.applying(CGAffineTransform(translationX: 16, y: 16).scaledBy(x: scale, y: scale))
        context.addPath(translated.cgPath)
        context.fillPath()
        if let cgImage = context.makeImage() {
            let rep = NSBitmapImageRep(cgImage: cgImage)
            if let png = rep.representation(using: .png, properties: [:]) {
                try png.write(to: URL(fileURLWithPath: "/tmp/github_icon.png"))
            }
        }
    }

    func test_parser_handles_negative_numbers_without_spaces() {
        // "1.5.5-2 3" 之类紧贴负号/双小数点的写法必须被正确分词
        let path = SVGPathParser.path(from: "M1.5.5-2 3L4-1 5", in: CGSize(width: 10, height: 10))
        XCTAssertFalse(path.isEmpty)
        let bounding = path.boundingRect
        XCTAssertTrue(bounding.width > 0 && bounding.height > 0)
    }

}
