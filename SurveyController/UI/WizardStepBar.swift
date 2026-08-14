// 对标官方 5.0 向导步骤条：1-6 步圆圈 + 下方标签 + 连接线。

import SwiftUI

struct WizardStepBar: View {
    let steps: [AppModel.WizardStep]
    @Binding var current: AppModel.WizardStep
    let maxReached: AppModel.WizardStep
    let onSelect: (AppModel.WizardStep) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                if index > 0 {
                    connector(after: steps[index - 1], before: step)
                }
                stepItem(step)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func stepItem(_ step: AppModel.WizardStep) -> some View {
        let isCurrent = step == current
        let isDone = step.rawValue < current.rawValue
        let isReachable = step.rawValue <= maxReached.rawValue

        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(isCurrent ? Color.accentColor : (isDone ? Color.accentColor.opacity(0.55) : Color(nsColor: .quaternaryLabelColor)))
                    .frame(width: 28, height: 28)
                Text("\(step.rawValue)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isCurrent || isDone ? .white : Color.secondary)
            }
            Text(step.title)
                .font(.caption)
                .foregroundStyle(isCurrent ? .primary : .secondary)
        }
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            if isReachable {
                onSelect(step)
            }
        }
        .help(isReachable ? "跳转到「\(step.title)」" : "需先完成前面的步骤")
    }

    private func connector(after: AppModel.WizardStep, before: AppModel.WizardStep) -> some View {
        let active = before.rawValue <= current.rawValue
        return Rectangle()
            .fill(active ? Color.accentColor.opacity(0.55) : Color(nsColor: .quaternaryLabelColor))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
            .padding(.top, 13)
            .padding(.horizontal, -6)
    }
}
