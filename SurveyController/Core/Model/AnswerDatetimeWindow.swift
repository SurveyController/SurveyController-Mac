// 对标 software/core/config/answer_datetime_window.py
// 见数平台的作答时间窗口（"YYYY-MM-DD HH:MM:SS" 对）。

import Foundation

public let answerDatetimeWindowFormat = "yyyy-MM-dd HH:mm:ss"
public let emptyAnswerDatetimeWindow = ("", "")

private let windowFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = answerDatetimeWindowFormat
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    return formatter
}()

/// 对标 parse_answer_datetime_string。
public func parseAnswerDatetimeString(_ value: Any?) -> Date? {
    let text = JSONCoercion.asTrimmedString(value)
    guard !text.isEmpty else { return nil }
    return windowFormatter.date(from: text)
}

/// 对标 format_answer_datetime_string。
public func formatAnswerDatetimeString(_ value: Date?) -> String {
    guard let value else { return "" }
    return windowFormatter.string(from: value)
}

/// 对标 normalize_answer_datetime_window。
public func normalizeAnswerDatetimeWindow(_ value: Any?) -> (start: String, end: String) {
    guard let list = value as? [Any] else { return (emptyAnswerDatetimeWindow.0, emptyAnswerDatetimeWindow.1) }
    let startRaw = list.count >= 1 ? list[0] : nil
    let endRaw = list.count >= 2 ? list[1] : nil
    let start = formatAnswerDatetimeString(parseAnswerDatetimeString(startRaw))
    let end = formatAnswerDatetimeString(parseAnswerDatetimeString(endRaw))
    return (start, end)
}

/// 对标 answer_datetime_window_to_epoch_ms。
public func answerDatetimeWindowToEpochMs(_ value: Any?) -> (startMs: Int, endMs: Int) {
    let (startText, endText) = normalizeAnswerDatetimeWindow(value)
    guard let start = parseAnswerDatetimeString(startText), let end = parseAnswerDatetimeString(endText) else {
        return (0, 0)
    }
    return (Int(start.timeIntervalSince1970 * 1000), Int(end.timeIntervalSince1970 * 1000))
}

/// 对标 has_configured_answer_datetime_window。
public func hasConfiguredAnswerDatetimeWindow(_ value: Any?) -> Bool {
    let (start, end) = normalizeAnswerDatetimeWindow(value)
    return !start.isEmpty && !end.isEmpty
}
