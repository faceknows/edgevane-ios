import Foundation

enum AppError: Error, Equatable {
    case network
    case cancelled
    case decoding
    case orderHistoryIncomplete
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

    var isNotFound: Bool {
        if case let .http(status, _, _) = self { return status == 404 }
        return false
    }
}

enum UserFacingError {
    static func message(from error: Error) -> String? {
        if error.isCancellation { return nil }
        guard let appError = error as? AppError else {
            return L10n.Errors.generic
        }

        switch appError {
        case .cancelled:
            return nil
        case .network:
            return L10n.Errors.network
        case .decoding:
            return L10n.Errors.generic
        case .orderHistoryIncomplete:
            return L10n.Trading.orderHistoryIncomplete
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

extension Error {
    var isCancellation: Bool {
        if (self as? AppError)?.isCancellation == true {
            return true
        }
        if self is CancellationError {
            return true
        }
        if (self as? URLError)?.code == .cancelled {
            return true
        }
        let nsError = self as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    var isUnauthorized: Bool {
        (self as? AppError)?.isUnauthorized == true
    }

    var isNotFound: Bool {
        (self as? AppError)?.isNotFound == true
    }
}
