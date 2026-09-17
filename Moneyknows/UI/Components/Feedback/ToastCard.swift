import SwiftUI

enum ToastSwipe {
    static let distance: CGFloat = 72

    static func shouldDismiss(translation: CGSize, predicted: CGSize = .zero) -> Bool {
        exceeds(translation) || exceeds(predicted)
    }

    static func flyOffOffset(translation: CGSize, travel: CGFloat = 480) -> CGSize {
        let horizontal = abs(translation.width)
        let upward = max(0, -translation.height)
        if horizontal >= upward, translation.width != 0 {
            let direction: CGFloat = translation.width > 0 ? 1 : -1
            return CGSize(width: direction * travel, height: translation.height)
        }
        return CGSize(width: translation.width, height: -travel)
    }

    private static func exceeds(_ size: CGSize) -> Bool {
        abs(size.width) >= distance || size.height <= -distance
    }
}

struct ToastCard<Content: View>: View {
    var id: AnyHashable
    var onDismiss: () -> Void
    var onTap: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        ToastCardBody(onDismiss: onDismiss, onTap: onTap, content: content)
            .id(id)
    }
}

private struct ToastCardBody<Content: View>: View {
    var onDismiss: () -> Void
    var onTap: (() -> Void)?
    @ViewBuilder var content: () -> Content

    @State private var offset = CGSize.zero
    @State private var isDismissing = false
    @State private var didDrag = false
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        Button(action: handleTap) {
            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ToastPalette.fill)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(ToastPalette.accent)
                        .frame(width: 4)
                }
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.fieldCorner, style: .continuous))
                .shadow(color: ToastPalette.accent.opacity(0.28), radius: 10, y: 3)
                .contentShape(RoundedRectangle(cornerRadius: AppTheme.fieldCorner, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDismissing)
        .offset(offset)
        .opacity(opacity)
        .simultaneousGesture(drag)
        .onDisappear {
            dismissTask?.cancel()
            dismissTask = nil
        }
    }

    private var opacity: Double {
        let distance = max(abs(offset.width), abs(offset.height))
        return Double(max(0.35, 1 - distance / 280))
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                guard !isDismissing else { return }
                if hypot(value.translation.width, value.translation.height) >= 12 {
                    didDrag = true
                }
                offset = CGSize(width: value.translation.width, height: min(24, value.translation.height))
            }
            .onEnded { value in
                guard !isDismissing else { return }
                if ToastSwipe.shouldDismiss(translation: value.translation, predicted: value.predictedEndTranslation) {
                    dismiss(with: value.translation)
                } else {
                    withAnimation(.spring()) {
                        offset = .zero
                    }
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        if !isDismissing {
                            didDrag = false
                        }
                    }
                }
            }
    }

    private func handleTap() {
        guard !isDismissing, !didDrag else { return }
        if let onTap {
            onTap()
        } else {
            onDismiss()
        }
    }

    private func dismiss(with translation: CGSize) {
        isDismissing = true
        withAnimation(.easeIn(duration: 0.18)) {
            offset = ToastSwipe.flyOffOffset(translation: translation)
        }
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }
}
