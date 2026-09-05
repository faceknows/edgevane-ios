import Foundation

final class LogoutCleanup {
    private var handlers: [() -> Void] = []

    func register(_ handler: @escaping () -> Void) {
        handlers.append(handler)
    }

    func run() {
        handlers.forEach { $0() }
    }
}
