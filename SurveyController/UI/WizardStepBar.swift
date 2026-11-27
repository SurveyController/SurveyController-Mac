import SwiftUI

struct WizardStepBar: View {
    let current: AppModel.WizardStep
    let maxReached: AppModel.WizardStep
    let running: Bool
    let onSelect: (AppModel.WizardStep) -> Void

    var body: some View {
        HStack(spacing: 5) {
            ForEach(AppModel.WizardStep.allCases) { step in
                let selected = step == current
                let complete = step.rawValue < current.rawValue
                Button {
                    onSelect(step)
                } label: {
                    HStack(spacing: 7) {
                        Group {
                            if complete {
                                Image(systemName: "checkmark")
                            } else {
                                Text(String(step.rawValue)).monospacedDigit()
                            }
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 23, height: 23)
                        .background(selected ? StudioStyle.badge : StudioStyle.raised, in: Circle())
                        Text(step.title)
                            .font(.subheadline.weight(selected ? .semibold : .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selected ? StudioStyle.accent : complete ? StudioStyle.success : StudioStyle.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .padding(.horizontal, 4)
                    .background(selected ? StudioStyle.stepSelection : .clear, in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(running || step.rawValue > maxReached.rawValue)
                .accessibilityLabel(step.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(5)
        .background(StudioStyle.toolbar, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(StudioStyle.border).allowsHitTesting(false)
        }
    }
}
