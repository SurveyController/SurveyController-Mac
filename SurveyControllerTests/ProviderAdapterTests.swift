import XCTest
@testable import SurveyController

final class ProviderAdapterTests: XCTestCase {
    func test_tencent_maps_jump_and_display_dependencies() {
        let raw: [ProviderJSON] = [
            ["id": "q-first", "type": "radio", "page_id": "p-a", "title": "选择", "options": [
                ["id": "o-1", "text": "显示", "display": ["q-second"]],
                ["id": "o-2", "text": "结束", "goto": "finish"],
            ]],
            ["id": "q-second", "type": "text", "page_id": "p-a", "title": "填写", "refer": ["q-first"]],
        ]
        let questions = TencentProvider.standardize(raw)
        XCTAssertEqual(questions.map(\.providerQuestionId), ["q-first", "q-second"])
        XCTAssertTrue(questions[0].hasJump)
        XCTAssertEqual(questions[0].logicParseStatus, "complete")
        XCTAssertEqual(questions[1].displayConditions.first?["condition_question_num"] as? Int, 1)
        XCTAssertEqual(questions[1].displayConditions.first?["condition_option_indices"] as? [Int], [0])
    }

    func test_tencent_encodes_checked_options_and_selected_fill() throws {
        let question: ProviderJSON = [
            "id": "q-a", "type": "radio", "options": [
                ["id": "o-a", "text": "A"],
                ["id": "o-b", "text": "B {fillblank-b}"],
            ],
        ]
        let result = try XCTUnwrap(TencentProvider.encode(
            question, action: AnswerAction(selectedIndices: [1], optionFillTexts: [(1, "补充")])
        ).first)
        XCTAssertEqual(result.objects("options").map { $0.int("checked") }, [0, 1])
        XCTAssertEqual(result.objects("blanks").first?.text("id"), "fillblank-b")
        XCTAssertEqual(result.objects("blanks").first?.text("text"), "补充")
    }

    func test_credamo_handles_worksheet_shape_and_matrix_encoding() throws {
        let item: ProviderJSON = [
            "qstId": 11, "qstNo": "Q3", "questionType": 4, "qstTitle": "矩阵",
            "choices": [["choiceId": 21, "display": "行"]],
            "answers": [["answerId": 31, "display": "列"]],
        ]
        let raw = CredamoProvider.rawQuestions(["blocks": [["elements": [["question": item]]]]])
        let question = try XCTUnwrap(CredamoProvider.standardize(raw).first)
        XCTAssertEqual(question.num, 3)
        XCTAssertEqual(question.optionTexts, ["列"])
        XCTAssertEqual(question.rowTexts, ["行"])

        let answer = try CredamoProvider.encode(item, action: AnswerAction(matrixIndices: [0]))
        let row = try XCTUnwrap(answer.objects("answerQstChoiceList").first)
        XCTAssertEqual(row.int("choiceId"), 21)
        XCTAssertEqual(row.objects("choiceAnswerList").first?.int("answerId"), 31)
    }

    func test_credamo_datetime_window_keeps_end_within_window() {
        let start = CredamoProvider.startTime(window: (1000, 5000), fallback: 10, duration: 2000)
        XCTAssertGreaterThanOrEqual(start, 1000)
        XCTAssertLessThanOrEqual(start + 2000, 5000)
        XCTAssertEqual(CredamoProvider.startTime(window: (0, 0), fallback: 10, duration: 2000), 10)
    }
}
