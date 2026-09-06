import Foundation

enum RoleLimitValue: Equatable {
    case number(Double)
    case bool(Bool)

    var number: Double? {
        if case let .number(value) = self { return value }
        return nil
    }

    var bool: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }

    var displayText: String {
        switch self {
        case let .number(value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(value)
        case let .bool(value):
            return value ? L10n.Common.enabled : L10n.Common.disabled
        }
    }
}

extension RoleLimitValue: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Double.self), value.isFinite {
            self = .number(value)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Role limit must be a finite number or boolean"
        )
    }
}

struct RoleConfiguration: Equatable {
    var values: [String: RoleLimitValue]

    var maxOrderValue: Double {
        guard let value = values["MAX_ORDER_VALUE"]?.number, value.isFinite, value > 0 else {
            return 50
        }
        return value
    }

    var enabledFeatureKeys: [String] {
        values
            .compactMap { key, value in
                value.bool == true ? key : nil
            }
            .sorted()
    }

    var sortedEntries: [(key: String, value: RoleLimitValue)] {
        values.keys.sorted().compactMap { key in
            guard let value = values[key] else { return nil }
            return (key, value)
        }
    }

    static func decodeFlexible(from data: Data) throws -> RoleConfiguration {
        let decoder = HTTPClient.makeDecoder()
        if let envelope = try? decoder.decode(JSONEnvelope<RoleConfigurationDTO>.self, from: data) {
            return RoleConfiguration(values: envelope.data.configuration)
        }
        if let dto = try? decoder.decode(RoleConfigurationDTO.self, from: data) {
            return RoleConfiguration(values: dto.configuration)
        }
        throw AppError.decoding
    }
}

private struct RoleConfigurationDTO: Decodable {
    var configuration: [String: RoleLimitValue]
}
