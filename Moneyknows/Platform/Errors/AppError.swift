import Foundation

enum AppError: Error, Equatable {
    case network
    case cancelled
    case decoding
    case http(status: Int, message: String?, errorCode: String?)
    case versionUnsupported(message: String, storeURL: URL?)

    var isCancellation: Bool {
        if case .cancelled = self { return true }
        return false
    }

    var isUnauthorized: Bool {
        if case let .http(status, _, _) = self { return status == 401 }
        return false
    }
}

enum UserFacingError {
    static func message(from error: Error) -> String? {
        guard let appError = error as? AppError else {
            if (error as NSError).code == NSURLErrorCancelled {
                return nil
            }
            return L10n.Errors.generic
        }

        switch appError {
        case .cancelled:
            return nil
        case .network:
            return L10n.Errors.network
        case .decoding:
            return L10n.Errors.generic
        case let .http(status, message, _):
            if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return message
            }
            return "\(L10n.Errors.generic) (\(status))"
        case let .versionUnsupported(message, _):
            return message
        }
    }
}
