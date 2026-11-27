import CoreImage
import XCTest
@testable import SurveyController

final class SurveyInputTests: XCTestCase {
    func test_reads_selected_workbook_sheet_with_sparse_rows() throws {
        let raw = "UEsDBBQAAAAIALpje12yq2YWeQAAAJQAAAAPAAAAeGwvd29ya2Jvb2sueG1sNY47DsMgEAWvgjhA1kmRAgFVbpATYLIEZMOiXZzP7eMirp5GM8Wzb+JlJlrUp65NDDudx+gGQGLGGuREHdvuEnENY0d+AqVUIt4obhXbgMs0XYFxDaNQk1y6aG8lIw75r2qhotP3jV/41YpNeTjNZw3ewhHC8cT/AFBLAwQUAAAACAC6Y3td5qb88D0AAABVAAAAGgAAAHhsL19yZWxzL3dvcmtib29rLnhtbC5yZWxzswlKzUksyczPK87ILCi2s0HmKnim2CoVGSophCQWpaeW2CqV5xdlF2ekppYU64MpI72K3BwlfTsbfVRTAFBLAwQUAAAACAC6Y3tdO5HDhSoAAAA/AAAAFAAAAHhsL3NoYXJlZFN0cmluZ3MueG1ssykuLrGzKc60symxM9R72dD5cuFOG32gkD5IDCL+dMr6Jzsa0OX0QToBUEsDBBQAAAAIALpje10wCKd1cAAAAKQAAAAYAAAAeGwvd29ya3NoZWV0cy9zaGVldDIueG1ssynPL8ouzkhNLbGzAVMuiSWJdjZF+eUKRbZKhkp2NskghpOhkkKJrVIxkF9mZ2CjX2Zno58MxEB1cMXGcMXGYMWZeTmZeanBJUVA8cxiO5sSu6dT1j/Z0fCyofPlwp02+kAb9UHiCIP0kVygj3AYAFBLAQIUAxQAAAAIALpje12yq2YWeQAAAJQAAAAPAAAAAAAAAAAAAACAAQAAAAB4bC93b3JrYm9vay54bWxQSwECFAMUAAAACAC6Y3td5qb88D0AAABVAAAAGgAAAAAAAAAAAAAAgAGmAAAAeGwvX3JlbHMvd29ya2Jvb2sueG1sLnJlbHNQSwECFAMUAAAACAC6Y3tdO5HDhSoAAAA/AAAAFAAAAAAAAAAAAAAAgAEbAQAAeGwvc2hhcmVkU3RyaW5ncy54bWxQSwECFAMUAAAACAC6Y3tdMAindXAAAACkAAAAGAAAAAAAAAAAAAAAgAF3AQAAeGwvd29ya3NoZWV0cy9zaGVldDIueG1sUEsFBgAAAAAEAAQADQEAAB0CAAAAAA=="
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("xlsx")
        defer { try? FileManager.default.removeItem(at: file) }
        try XCTUnwrap(Data(base64Encoded: raw)).write(to: file)

        let rows = try XlsxReader.read(file)
        XCTAssertEqual(rows, [[1: "1.选项"], [:], [1: "唯一选项"]])
    }

    func test_reverse_fill_matches_numbered_columns_and_drops_invalid_rows() {
        let question = SurveyQuestionMeta(num: 1, title: "多选题", typeCode: "4", options: 2, optionTexts: ["A", "B"])
        let spec = ReverseFillSpec.build(
            rows: [
                [0: "1.多选题（选项2）", 1: "1.多选题（选项1）"],
                [0: "1", 1: "0"],
                [0: "2", 1: "0"],
            ],
            questions: [question],
            entries: [QuestionEntry(questionType: "multiple", questionNum: 1)],
            format: reverseFillFormatAuto,
            startRow: 2
        )
        XCTAssertEqual(spec.totalRows, 2)
        XCTAssertEqual(spec.invalidRows, [3])
        XCTAssertEqual(spec.samples.first?.answers[1]?.selectedIndices, [1])
    }

    func test_decodes_and_normalizes_a_questionnaire_qr() throws {
        let filter = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
        filter.setValue(Data("https://WWW.WJX.CN/vm/demo.aspx".utf8), forKey: "inputMessage")
        let image = try XCTUnwrap(filter.outputImage).transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        XCTAssertEqual(try SurveyQRDecoder.surveyURL(in: image), "https://www.wjx.cn/vm/demo.aspx")
    }

    func test_rejects_qr_from_an_unknown_provider() throws {
        let filter = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
        filter.setValue(Data("https://example.test/not-a-survey".utf8), forKey: "inputMessage")
        let image = try XCTUnwrap(filter.outputImage).transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        XCTAssertThrowsError(try SurveyQRDecoder.surveyURL(in: image))
    }
}
