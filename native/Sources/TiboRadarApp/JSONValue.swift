import Foundation

enum JSONValue: Codable, Equatable, Sendable {
  case object([String: JSONValue])
  case array([JSONValue])
  case string(String)
  case number(Double)
  case bool(Bool)
  case null

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: JSONValue].self) {
      self = .object(value)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Unsupported JSON value"
      )
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .object(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .bool(let value): try container.encode(value)
    case .null: try container.encodeNil()
    }
  }

  var objectValue: [String: JSONValue]? {
    guard case .object(let value) = self else { return nil }
    return value
  }

  var arrayValue: [JSONValue]? {
    guard case .array(let value) = self else { return nil }
    return value
  }

  var stringValue: String? {
    guard case .string(let value) = self else { return nil }
    return value
  }

  var numberValue: Double? {
    guard case .number(let value) = self else { return nil }
    return value
  }

  var intValue: Int? {
    numberValue.map { Int($0) }
  }

  var boolValue: Bool? {
    guard case .bool(let value) = self else { return nil }
    return value
  }
}

extension Dictionary where Key == String, Value == JSONValue {
  func string(_ key: String) -> String? { self[key]?.stringValue }
  func number(_ key: String) -> Double? { self[key]?.numberValue }
  func int(_ key: String) -> Int? { self[key]?.intValue }
  func bool(_ key: String) -> Bool? { self[key]?.boolValue }
  func object(_ key: String) -> [String: JSONValue]? { self[key]?.objectValue }
  func array(_ key: String) -> [JSONValue]? { self[key]?.arrayValue }
}
