// 品牌与功能图标：SF Symbols 没有品牌标识，这里自绘矢量
//（GitHub 官方轮廓走内建 SVG path 解析，Windows/安卓用原生图形组合）。

import SwiftUI

// MARK: - 迷你 SVG path 解析器（支持 M/L/H/V/C/S/Q/T/Z 与相对坐标）

enum SVGPathParser {
    static func path(from svgPath: String, in size: CGSize) -> Path {
        var path = Path()
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint? = nil

        // 规范化分隔：逗号→空格；数字后跟负号→插入空格；一个数字内第二个小数点→插入空格
        var normalized = ""
        var dotInCurrentNumber = false
        var previousIsNumberish = false
        for character in svgPath {
            switch character {
            case ",", " ", "\t", "\n", "\r":
                normalized.append(" ")
                dotInCurrentNumber = false
                previousIsNumberish = false
            case "-":
                if previousIsNumberish {
                    normalized.append(" ")
                }
                normalized.append("-")
                dotInCurrentNumber = false
                previousIsNumberish = false
            case ".":
                if dotInCurrentNumber {
                    normalized.append(" ")
                }
                normalized.append(".")
                dotInCurrentNumber = true
                previousIsNumberish = true
            case let c where c.isLetter:
                normalized.append(c)
                dotInCurrentNumber = false
                previousIsNumberish = false
            default:
                normalized.append(character)
                previousIsNumberish = character.isNumber
            }
        }

        let tokens = normalized.split(whereSeparator: { $0.isWhitespace })
        var numbers: [Double] = []
        var command: Character = " "

        func flushNumber() {
            guard !numbers.isEmpty else { return }
            defer { numbers.removeAll() }
            let p0 = current
            switch command {
            case "M", "m":
                let target = absPoint(numbers[0], numbers[1], relative: command == "m")
                path.move(to: target)
                current = target
                start = target
                if numbers.count > 2 {
                    // 多组坐标按 L 处理
                    var index = 2
                    while index + 1 < numbers.count {
                        let t = absPoint(numbers[index], numbers[index + 1], relative: command == "m")
                        path.addLine(to: t)
                        current = t
                        index += 2
                    }
                }
            case "L", "l":
                var index = 0
                while index + 1 < numbers.count {
                    let t = absPoint(numbers[index], numbers[index + 1], relative: command == "l")
                    path.addLine(to: t)
                    current = t
                    index += 2
                }
            case "H", "h":
                for value in numbers {
                    current.x = command == "h" ? current.x + CGFloat(value) : CGFloat(value)
                    path.addLine(to: current)
                }
            case "V", "v":
                for value in numbers {
                    current.y = command == "v" ? current.y + CGFloat(value) : CGFloat(value)
                    path.addLine(to: current)
                }
            case "C", "c":
                var index = 0
                while index + 5 < numbers.count {
                    let c1 = absPoint(numbers[index], numbers[index + 1], relative: command == "c")
                    let c2 = absPoint(numbers[index + 2], numbers[index + 3], relative: command == "c")
                    let to = absPoint(numbers[index + 4], numbers[index + 5], relative: command == "c")
                    path.addCurve(to: to, control1: c1, control2: c2)
                    current = to
                    lastControl = c2
                    index += 6
                }
            case "S", "s":
                var index = 0
                while index + 3 < numbers.count {
                    let reflected = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                    let c2 = absPoint(numbers[index], numbers[index + 1], relative: command == "s")
                    let to = absPoint(numbers[index + 2], numbers[index + 3], relative: command == "s")
                    path.addCurve(to: to, control1: reflected, control2: c2)
                    current = to
                    lastControl = c2
                    index += 4
                }
            case "Q", "q":
                var index = 0
                while index + 3 < numbers.count {
                    let c = absPoint(numbers[index], numbers[index + 1], relative: command == "q")
                    let to = absPoint(numbers[index + 2], numbers[index + 3], relative: command == "q")
                    path.addQuadCurve(to: to, control: c)
                    current = to
                    lastControl = c
                    index += 4
                }
            default:
                break
            }
        }

        func absPoint(_ x: Double, _ y: Double, relative: Bool) -> CGPoint {
            let px = CGFloat(x)
            let py = CGFloat(y)
            return relative ? CGPoint(x: current.x + px, y: current.y + py) : CGPoint(x: px, y: py)
        }

        for token in tokens {
            guard let first = token.first, first.isLetter else {
                // 纯数字段（可能带前导负号）
                if let value = Double(token) { numbers.append(value) }
                continue
            }
            // 字母 = 新命令，先冲刷上一段
            flushNumber()
            command = first.isLowercase ? Character(first.lowercased()) : Character(first.uppercased())
            let remainder = String(token.dropFirst())
            if let value = Double(remainder) { numbers.append(value) }
        }
        flushNumber()
        if command == "Z" || command == "z" {
            path.closeSubpath()
            current = start
        }

        // 归一化到目标尺寸
        let bounding = path.boundingRect
        guard !bounding.isEmpty, bounding.width > 0, bounding.height > 0 else { return path }
        let scale = min(size.width / bounding.width, size.height / bounding.height)
        var transform = CGAffineTransform(translationX: -bounding.minX, y: -bounding.minY)
        transform = transform.scaledBy(x: scale, y: scale)
        return path.applying(transform)
    }
}

// MARK: - GitHub 官方轮廓（24×24 标准路径）

struct GitHubIcon: View {
    var size: CGFloat = 20

    static let markPath = "M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12"

    var body: some View {
        SVGPathParser.path(from: Self.markPath, in: CGSize(width: size, height: size))
            .fill(.primary)
            .frame(width: size, height: size)
    }
}

// MARK: - Windows 徽标（四格窗）

struct WindowsIcon: View {
    var size: CGFloat = 20

    var body: some View {
        let gap = size * 0.09
        let cell = (size - gap) / 2
        let color = Color(red: 0.0, green: 0.47, blue: 0.84)
        VStack(spacing: gap) {
            HStack(spacing: gap) {
                RoundedRectangle(cornerRadius: size * 0.04).fill(color).frame(width: cell, height: cell)
                RoundedRectangle(cornerRadius: size * 0.04).fill(color).frame(width: cell, height: cell)
            }
            HStack(spacing: gap) {
                RoundedRectangle(cornerRadius: size * 0.04).fill(color).frame(width: cell, height: cell)
                RoundedRectangle(cornerRadius: size * 0.04).fill(color).frame(width: cell, height: cell)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 安卓机器人

struct AndroidIcon: View {
    var size: CGFloat = 20
    private let green = Color(red: 0.24, green: 0.73, blue: 0.28)

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            // 头部（半圆 + 天线）
            Path { p in
                p.addArc(center: CGPoint(x: w / 2, y: h * 0.52),
                         radius: w * 0.30,
                         startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                p.closeSubpath()
            }
            .fill(green)
            // 身体
            RoundedRectangle(cornerRadius: w * 0.10)
                .fill(green)
                .frame(width: w * 0.60, height: h * 0.34)
                .position(x: w / 2, y: h * 0.70)
            // 天线
            Path { p in
                p.move(to: CGPoint(x: w * 0.32, y: h * 0.30))
                p.addLine(to: CGPoint(x: w * 0.24, y: h * 0.16))
            }
            .stroke(green, lineWidth: w * 0.05)
            Path { p in
                p.move(to: CGPoint(x: w * 0.68, y: h * 0.30))
                p.addLine(to: CGPoint(x: w * 0.76, y: h * 0.16))
            }
            .stroke(green, lineWidth: w * 0.05)
            // 眼睛
            Circle().fill(.white)
                .frame(width: w * 0.07)
                .position(x: w * 0.39, y: h * 0.42)
            Circle().fill(.white)
                .frame(width: w * 0.07)
                .position(x: w * 0.61, y: h * 0.42)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 反馈图标（自绘：气泡 + 感叹号）

struct FeedbackIcon: View {
    var size: CGFloat = 20

    var body: some View {
        ZStack {
            BubbleShape()
                .fill(Color.accentColor.opacity(0.9))
            VStack(spacing: size * 0.05) {
                Capsule().fill(.white).frame(width: size * 0.08, height: size * 0.28)
                Circle().fill(.white).frame(width: size * 0.09, height: size * 0.09)
            }
        }
        .frame(width: size, height: size)
    }

    private struct BubbleShape: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            let radius = rect.height * 0.28
            let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.78)
            p.addPath(Path(roundedRect: body, cornerRadius: radius))
            // 尾巴
            p.move(to: CGPoint(x: rect.width * 0.28, y: rect.height * 0.74))
            p.addLine(to: CGPoint(x: rect.width * 0.18, y: rect.height * 0.98))
            p.addLine(to: CGPoint(x: rect.width * 0.45, y: rect.height * 0.78))
            p.closeSubpath()
            return p
        }
    }
}

// MARK: - 文档图标（自绘：打开的书）

struct DocsIcon: View {
    var size: CGFloat = 20

    var body: some View {
        ZStack {
            BookShape()
                .stroke(Color.accentColor, lineWidth: size * 0.07)
                .background(BookShape().fill(Color.accentColor.opacity(0.12)))
            Path { p in
                p.move(to: CGPoint(x: size * 0.5, y: size * 0.22))
                p.addLine(to: CGPoint(x: size * 0.5, y: size * 0.86))
            }
            .stroke(Color.accentColor, lineWidth: size * 0.07)
        }
        .frame(width: size, height: size)
    }

    private struct BookShape: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            let left = CGRect(x: rect.minX, y: rect.minY, width: rect.width / 2, height: rect.height)
            let right = CGRect(x: rect.midX, y: rect.minY, width: rect.width / 2, height: rect.height)
            p.addPath(Path(roundedRect: left, cornerRadius: rect.width * 0.12))
            p.addPath(Path(roundedRect: right, cornerRadius: rect.width * 0.12))
            return p
        }
    }
}

// MARK: - 链接卡片行（关于页/社区页共用）

struct LinkRow<Icon: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var icon: Icon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                icon
                    .frame(width: 36, height: 36)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.background)
                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        )
    }
}

#Preview("Icons") {
    HStack(spacing: 22) {
        GitHubIcon(size: 28)
        WindowsIcon(size: 28)
        AndroidIcon(size: 28)
        FeedbackIcon(size: 28)
        DocsIcon(size: 28)
    }
    .padding(30)
}
