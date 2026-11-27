import SwiftUI

struct OfflineRehearsalView: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var seedText = String(OfflineRehearsal.defaultSeed)
    @State private var report: OfflineRehearsal.Report?
    @State private var issue: OfflineRehearsal.Issue?
    @State private var task: Task<Void, Never>?
    @State private var sampleIndex = 0
    @State private var showDistribution = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                StudioHeading(title: "离线试跑", subtitle: "本地预览最多 20 份样例，AI 填空以占位文本展示。", icon: "checklist")
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 10) {
                Text("随机种子")
                TextField("随机种子", text: $seedText)
                    .frame(width: 145)
                    .onSubmit(generate)
                Button(report == nil ? "生成样例" : "重新生成", action: generate)
                    .buttonStyle(.borderedProminent)
                    .disabled(Int(seedText) == nil || task != nil)
                if task != nil {
                    ProgressView().controlSize(.small)
                }
                if let report {
                    Spacer()
                    Text("\(report.samples.count) 份样例 · 种子 \(report.seed)")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .studioPanel(radius: 12)

            if let issue {
                HStack {
                    Label(issue.message, systemImage: "exclamationmark.circle")
                        .foregroundStyle(StudioStyle.danger)
                    if let question = issue.questionNumber {
                        Button("编辑第 \(question) 题") { edit(question) }
                            .buttonStyle(.link)
                    }
                }
            }
            if let report {
                Picker("查看", selection: $showDistribution) {
                    Text("逐份样例").tag(false)
                    Text("选项分布").tag(true)
                }
                .pickerStyle(.segmented)

                if showDistribution {
                    distributionList(report)
                } else {
                    sampleList(report)
                }
            } else {
                Spacer()
            }
        }
        .padding(22)
        .background(StudioStyle.canvas)
        .tint(StudioStyle.accent)
        .frame(minWidth: 590, idealWidth: 690, minHeight: 460, idealHeight: 560)
        .onDisappear { task?.cancel() }
    }

    private func sampleList(_ report: OfflineRehearsal.Report) -> some View {
        let sample = report.samples[sampleIndex]
        return VStack(alignment: .leading, spacing: 6) {
            Picker("样例", selection: $sampleIndex) {
                ForEach(report.samples) { sample in
                    Text(sample.sourceRow.map { "样例 \(sample.id) · 表格第 \($0) 行" } ?? "样例 \(sample.id)")
                        .tag(sample.id - 1)
                }
            }
            List(sample.questions) { question in
                VStack(alignment: .leading, spacing: 4) {
                    questionButton(question.id, title: question.title)
                    Text(question.answer)
                        .foregroundStyle(question.answered ? .primary : .secondary)
                        .textSelection(.enabled)
                    ForEach(question.details, id: \.self) { detail in
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .studioPanel(radius: 14)
        }
    }

    private func distributionList(_ report: OfflineRehearsal.Report) -> some View {
        List(report.distributions) { question in
            VStack(alignment: .leading, spacing: 4) {
                questionButton(question.id, title: question.title)
                Text("\(question.answeredCount)/\(report.samples.count) 份样例作答")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(question.counts.keys.sorted(), id: \.self) { option in
                    let count = question.counts[option, default: 0]
                    HStack {
                        Text(option)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ProgressView(value: Double(count), total: Double(max(1, question.answeredCount)))
                            .frame(width: 86)
                        Text("\(count) 份")
                            .monospacedDigit()
                    }
                    .font(.caption)
                }
            }
            .padding(.vertical, 4)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .studioPanel(radius: 14)
    }

    private func questionButton(_ number: Int, title: String) -> some View {
        Button("第 \(number) 题 · \(title)") { edit(number) }
            .buttonStyle(.link)
    }

    private func edit(_ number: Int) {
        model.editQuestion(number)
        dismiss()
    }

    private func generate() {
        guard let seed = Int(seedText), task == nil else { return }
        report = nil
        issue = nil
        task = Task {
            defer { task = nil }
            do {
                let result = try await model.rehearse(seed: seed)
                try Task.checkCancellation()
                sampleIndex = 0
                report = result
            } catch is CancellationError {
                return
            } catch {
                issue = error as? OfflineRehearsal.Issue
                    ?? OfflineRehearsal.Issue(questionNumber: nil, message: error.localizedDescription)
            }
        }
    }
}
