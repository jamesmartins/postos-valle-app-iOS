import Foundation

/// Aceita Double, Int ou String ("2.39" / "2,39") vindos do Bunker.
struct FlexibleDouble: Codable, Sendable {
    let value: Double

    init(_ value: Double) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let double = try? container.decode(Double.self) {
            value = double
            return
        }
        if let int = try? container.decode(Int.self) {
            value = Double(int)
            return
        }
        if let string = try? container.decode(String.self) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                value = 0
                return
            }
            let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
            if let double = Double(normalized) {
                value = double
                return
            }
        }

        value = 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

struct FlexibleInt: Codable, Sendable {
    let value: Int

    init(_ value: Int) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = int
            return
        }
        if let double = try? container.decode(Double.self) {
            value = Int(double)
            return
        }
        if let string = try? container.decode(String.self),
           let int = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            value = int
            return
        }
        value = 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
