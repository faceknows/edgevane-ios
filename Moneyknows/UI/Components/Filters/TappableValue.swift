import SwiftUI

struct TappableOption<Value: Hashable>: Hashable {
    var value: Value
    var title: String
}

struct TappableValue<Value: Hashable>: View {
    var options: [TappableOption<Value>]
    @Binding var selection: Value
    var onSelect: ((Value) -> Void)? = nil

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    guard option.value != selection else { return }
                    selection = option.value
                    onSelect?(option.value)
                } label: {
                    Text(option.title)
                        .font(.caption.weight(selected ? .semibold : .regular))
                        .foregroundColor(selected ? .white : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(selected ? Color.accentColor : Color.clear)
                        .cornerRadius(8)
                }
                .buttonStyle(.borderless)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(4)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(uiColor: .separator), lineWidth: 1)
        )
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
