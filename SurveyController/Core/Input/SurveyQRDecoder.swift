import CoreImage
import Foundation

enum SurveyQRDecoder {
    enum ReadError: LocalizedError {
        case invalidImage
        case noSurveyLink

        var errorDescription: String? {
            switch self {
            case .invalidImage: "无法打开二维码图片"
            case .noSurveyLink: "图片中未找到受支持的问卷链接"
            }
        }
    }

    static func surveyURL(from file: URL) throws -> String {
        guard let image = CIImage(contentsOf: file, options: [.applyOrientationProperty: true]) else {
            throw ReadError.invalidImage
        }
        return try surveyURL(in: image)
    }

    static func surveyURL(in image: CIImage) throws -> String {
        guard let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) else {
            throw ReadError.noSurveyLink
        }
        let images = [image, image.applyingFilter("CIColorInvert")]
        for candidate in images {
            for case let feature as CIQRCodeFeature in detector.features(in: candidate) {
                guard let text = feature.messageString else { continue }
                let url = ProviderType.normalizeSurveyParseUrl(text)
                if ProviderType.isSupportedSurveyUrl(url) {
                    return url
                }
            }
        }
        throw ReadError.noSurveyLink
    }
}
