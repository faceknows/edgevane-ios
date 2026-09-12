import SwiftUI

struct TappableOption<Value: Hashable>: Hashable {
    var value: Value
    var title: String
}

enum TappableChipFlow {
    static let minTapLength: CGFloat = 44
    static let spacing: CGFloat = 4
    static let inset: CGFloat = 4

    static func layout(sizes: [CGSize], limit: CGFloat, spacing: CGFloat = spacing) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0
        let finiteLimit = limit.isFinite ? max(0, limit) : .infinity

        for size in sizes {
            let width = min(size.width, finiteLimit)
            let height = size.height
            if x > 0, x + width > finiteLimit {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, height)
            x += width + spacing
            maxWidth = max(maxWidth, x - spacing)
        }

        return (origins, CGSize(width: maxWidth, height: y + rowHeight))
    }

    static func resolvedWidth(proposal: CGFloat?, arranged: CGFloat) -> CGFloat {
        if let proposed = proposal, proposed.isFinite {
            return proposed
        }
        return arranged
    }
}

struct TappableValue<Value: Hashable>: View {
    var options: [TappableOption<Value>]
    @Binding var selection: Value
    var onSelect: ((Value) -> Void)? = nil

    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                ChipWrapLayout(spacing: TappableChipFlow.spacing) {
                    ForEach(options, id: \.value) { option in
                        chip(for: option)
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TappableChipFlow.spacing) {
                        ForEach(options, id: \.value) { option in
                            chip(for: option)
                        }
                    }
                }
            }
        }
        .padding(TappableChipFlow.inset)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(uiColor: .separator), lineWidth: 1)
        )
    }

    private func chip(for option: TappableOption<Value>) -> some View {
        let selected = option.value == selection
        return Button {
            guard option.value != selection else { return }
            selection = option.value
            onSelect?(option.value)
        } label: {
            Text(option.title)
                .font(.caption.weight(selected ? .semibold : .regular))
                .foregroundColor(selected ? .white : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 10)
                .frame(minWidth: TappableChipFlow.minTapLength, minHeight: TappableChipFlow.minTapLength)
                .contentShape(Rectangle())
                .background(selected ? Color.accentColor : Color.clear)
                .cornerRadius(8)
        }
        .buttonStyle(.borderless)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

@available(iOS 16.0, *)
private struct ChipWrapLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let arranged = arrange(proposal: proposal, subviews: subviews)
        let width = TappableChipFlow.resolvedWidth(proposal: proposal.width, arranged: arranged.size.width)
        return CGSize(width: width, height: arranged.size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arranged = arrange(
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height),
            subviews: subviews
        )
        for index in subviews.indices {
            let origin = arranged.origins[index]
            let size = arranged.sizes[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: ProposedViewSize(size)
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (origins: [CGPoint], sizes: [CGSize], size: CGSize) {
        let limit = proposal.width ?? .infinity
        var sizes: [CGSize] = []
        for subview in subviews {
            let ideal = subview.sizeThatFits(.unspecified)
            let proposedWidth: CGFloat
            if limit.isFinite {
                proposedWidth = min(max(ideal.width, TappableChipFlow.minTapLength), max(0, limit))
            } else {
                proposedWidth = max(ideal.width, TappableChipFlow.minTapLength)
            }
            let fitted = subview.sizeThatFits(ProposedViewSize(width: proposedWidth, height: nil))
            sizes.append(
                CGSize(
                    width: proposedWidth,
                    height: max(fitted.height, TappableChipFlow.minTapLength)
                )
            )
        }
        let packed = TappableChipFlow.layout(sizes: sizes, limit: limit, spacing: spacing)
        return (packed.origins, sizes, packed.size)
    }
}

struct TappableValueField<Value: Hashable>: View {
    var title: String
    @Binding var selection: Value
    var options: [TappableOption<Value>]
    var onSelect: ((Value) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            TappableValue(options: options, selection: $selection, onSelect: onSelect)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
