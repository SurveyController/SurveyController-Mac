// 联动占比滑块组（对标桌面端 ratio_slider.py + 安卓端 RatioSliders.kt 的增强版）：
// 拖动任一项，其余「未锁定」项按原比例自动补足，总和恒为 100%；
// 顶部分布预览条 + 均分按钮 + 每项锁定 + 百分比点击精确输入；5% 步进吸附。
// 滑杆为自绘样式（无系统滑杆的细轨道线）。

import SwiftUI

// MARK: - 分布预览条

struct DistributionBar: View {
    let values: [Int]

    static let palette: [Color] = [
        Color(red: 0.00, green: 0.40, blue: 0.75),
        Color(red: 0.18, green: 0.62, blue: 0.36),
        Color(red: 0.91, green: 0.51, blue: 0.23),
        Color(red: 0.61, green: 0.35, blue: 0.71),
        Color(red: 0.91, green: 0.30, blue: 0.24),
        Color(red: 0.09, green: 0.63, blue: 0.52),
        Color(red: 0.95, green: 0.77, blue: 0.06),
        Color(red: 0.20, green: 0.29, blue: 0.37),
    ]

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    if value > 0 {
                        Rectangle()
                            .fill(Self.palette[index % Self.palette.count])
                            .frame(width: proxy.size.width * CGFloat(value) / 100.0)
                    }
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 8)
    }
}

// MARK: - 自绘滑杆（无轨道细线，填充式）

struct FluidSlider: View {
    let value: Double // 0...1
    let tint: Color
    var enabled: Bool = true
    let onDrag: (Double) -> Void

    @State private var isDragging = false
    @State private var hover = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let thumbRadius: CGFloat = 7
            let trackHeight: CGFloat = 6
            let clamped = min(1, max(0, value))
            let fillWidth = (width - thumbRadius * 2) * clamped + thumbRadius
            let thumbX = fillWidth

            ZStack(alignment: .leading) {
                // 轨道
                Capsule()
                    .fill(Color.primary.opacity(enabled ? 0.10 : 0.06))
                    .frame(height: trackHeight)
                    .frame(maxHeight: .infinity)
                // 填充
                Capsule()
                    .fill(enabled ? tint : tint.opacity(0.4))
                    .frame(width: max(0, fillWidth), height: trackHeight)
                    .frame(maxHeight: .infinity)
                // 滑块
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(isDragging ? 0.30 : 0.20), radius: isDragging ? 3 : 1.5, y: 1)
                    .frame(width: thumbRadius * 2, height: thumbRadius * 2)
                    .overlay(
                        Circle().strokeBorder(enabled ? tint.opacity(0.5) : Color.primary.opacity(0.15), lineWidth: 1)
                    )
                    .frame(maxHeight: .infinity)
                    .offset(x: thumbX - thumbRadius)
                    .scaleEffect(isDragging ? 1.12 : hover ? 1.06 : 1.0)
                    .animation(.spring(response: 0.2), value: isDragging)
                    .animation(.spring(response: 0.2), value: hover)
            }
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard enabled else { return }
                        isDragging = true
                        let fraction = (gesture.location.x - thumbRadius) / (width - thumbRadius * 2)
                        onDrag(min(1, max(0, Double(fraction))))
                    }
                    .onEnded { _ in isDragging = false }
            )
        }
        .frame(height: 22)
    }
}

// MARK: - 联动滑块组

struct RatioSliders: View {
    let labels: [String]
    let values: [Int]              // 展示值（总和恒 100，由外部用 normalizeTo100 归一后传入）
    let locked: Set<Int>
    let onChange: ([Int]) -> Void
    let onToggleLock: ((Int) -> Void)?

    @State private var editingIndex: Int? = nil
    @State private var editText: String = ""

    init(
        labels: [String],
        values: [Int],
        locked: Set<Int> = [],
        onToggleLock: ((Int) -> Void)? = nil,
        onChange: @escaping ([Int]) -> Void
    ) {
        self.labels = labels
        self.values = values
        self.locked = locked
        self.onToggleLock = onToggleLock
        self.onChange = onChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                DistributionBar(values: values)
                Button {
                    onChange(RatioSliderMath.evenSplit(labels.count))
                } label: {
                    Label("均分", systemImage: "arrow.2.squarepath")
                        .font(.caption)
                }
                .controlSize(.small)
            }

            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                sliderRow(index: index, label: label)
            }
        }
        .sheet(item: Binding(
            get: { editingIndex.map { EditTarget(index: $0) } },
            set: { editingIndex = $0?.index }
        )) { target in
            editSheet(target)
        }
    }

    private func sliderRow(index: Int, label: String) -> some View {
        let isLocked = locked.contains(index)
        let tint = DistributionBar.palette[index % DistributionBar.palette.count]

        return HStack(spacing: 10) {
            Text(label.isEmpty ? "选项\(index + 1)" : label)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 150, alignment: .leading)
                .foregroundStyle(isLocked ? Color.secondary : Color.primary)

            if let onToggleLock {
                Button {
                    onToggleLock(index)
                } label: {
                    Image(systemName: isLocked ? "lock.fill" : "lock.open")
                        .font(.system(size: 11))
                        .foregroundStyle(isLocked ? tint : Color.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help(isLocked ? "已锁定（拖动其他项时保持不变）" : "未锁定")
            }

            FluidSlider(
                value: Double(values[index]) / 100.0,
                tint: tint,
                enabled: !isLocked
            ) { fraction in
                let target = RatioSliderMath.roundToStep(fraction * 100)
                onChange(RatioSliderMath.redistribute(values, changed: index, newValueRaw: target, locked: locked))
            }

            Text("\(values[index])%")
                .monospacedDigit()
                .font(.callout.weight(.medium))
                .foregroundStyle(isLocked ? Color.secondary : tint)
                .frame(width: 46, alignment: .trailing)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isLocked else { return }
                    editText = String(values[index])
                    editingIndex = index
                }
                .help("点击精确输入")
        }
    }

    private struct EditTarget: Identifiable {
        let index: Int
        var id: Int { index }
    }

    private func editSheet(_ target: EditTarget) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("设置「\(labels.indices.contains(target.index) ? labels[target.index] : "选项\(target.index + 1)")」占比")
                .font(.headline)
            HStack {
                TextField("0 - 100", text: $editText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                Text("%").foregroundStyle(.secondary)
                Spacer()
                Button("取消") { editingIndex = nil }
                Button("确定") {
                    if let v = Int(editText.filter(\.isNumber)) {
                        onChange(RatioSliderMath.redistribute(
                            values, changed: target.index, newValueRaw: v, locked: locked
                        ))
                    }
                    editingIndex = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

// MARK: - 多选「命中概率」独立滑杆（0-100 各自独立，不归一化）

struct HitRateSliders: View {
    let labels: [String]
    let values: [Int]
    let onChange: ([Int]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 深浅预览条：每项独立概率
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor.opacity(0.15 + 0.85 * Double(min(100, max(0, value))) / 100))
                    }
                }
            }
            .frame(height: 8)

            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                HStack(spacing: 10) {
                    Text(label.isEmpty ? "选项\(index + 1)" : label)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: 150, alignment: .leading)
                    FluidSlider(
                        value: Double(values[index]) / 100.0,
                        tint: .accentColor
                    ) { fraction in
                        var next = values
                        next[index] = RatioSliderMath.roundToStep(fraction * 100)
                        onChange(next)
                    }
                    Text("\(values[index])%")
                        .monospacedDigit()
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 46, alignment: .trailing)
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        RatioSliders(
            labels: ["微信端", "手机浏览器", "电脑网页端"],
            values: [33, 33, 34],
            locked: [1]
        ) { _ in }
        HitRateSliders(
            labels: ["选项A", "选项B", "选项C", "选项D"],
            values: [80, 40, 20, 0]
        ) { _ in }
    }
    .padding(24)
    .frame(width: 460)
}
