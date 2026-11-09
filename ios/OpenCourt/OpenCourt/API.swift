import Foundation

struct User: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let email: String
}

struct Facility: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let address: String
}

struct Court: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let facilityId: Int
    let facilityName: String
    let courtNumber: String
    let courtType: String
}

struct CourtSession: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let userId: Int
    let userName: String
    let courtId: Int
    let courtNumber: String
    let facilityId: Int
    let facilityName: String
    let courtType: String
    let startedAt: Date
    let endedAt: Date?

    var isActive: Bool { endedAt == nil }

    var timeLabel: String {
        let start = startedAt.formatted(date: .abbreviated, time: .shortened)
        guard let endedAt else {
            return "\(start) · in progress"
        }
        if Calendar.current.isDate(startedAt, inSameDayAs: endedAt) {
            let end = endedAt.formatted(date: .omitted, time: .shortened)
            return "\(start) – \(end)"
        }
        let end = endedAt.formatted(date: .abbreviated, time: .shortened)
        return "\(start) – \(end)"
    }
}

struct OccupancyCourt: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let courtNumber: String
    let courtType: String
    let inUse: Bool
    let sessionId: Int?
    let playerUserId: Int?
    let playerName: String?
    let playerNames: String?
    let playerUserIds: [Int]
    let startedAt: Date?
}

struct OccupancyFacility: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let address: String
    let courtsInUse: Int
    let courtCount: Int
    let inUsePercent: Int
    let courts: [OccupancyCourt]
}

struct Occupancy: Codable, Sendable {
    let courtsInUse: Int
    let courtCount: Int
    let inUsePercent: Int
    let facilities: [OccupancyFacility]
}

struct SessionStart: Encodable, Sendable {
    let courtId: Int
    let playerIds: [Int]
}

struct UserDraft: Encodable, Sendable {
    let name: String
    let email: String
}

struct TagPlayer: Encodable, Sendable {
    let userId: Int
}

struct CourtUsageRow: Codable, Identifiable, Hashable, Sendable {
    let courtId: Int
    let facilityName: String
    let courtNumber: String
    let courtType: String
    let sessionCount: Int

    var id: Int { courtId }
}

struct LeaderboardEntry: Codable, Identifiable, Hashable, Sendable {
    let rank: Int
    let userId: Int
    let name: String
    let games: Int

    var id: Int { userId }
}

struct CourtUsageReport: Codable, Sendable {
    let totalSessions: Int
    let finishedSessions: Int
    let uniqueUsers: Int
    let averageDurationMinutes: Double?
    let byCourt: [CourtUsageRow]
    let sessions: [CourtSession]
}

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum API {
    static let baseURL = "http://127.0.0.1:8000"

    static func users() async throws -> [User] {
        try await get("/users")
    }

    static func facilities() async throws -> [Facility] {
        try await get("/facilities")
    }

    static func courts(facilityId: Int?) async throws -> [Court] {
        var items: [URLQueryItem] = []
        if let facilityId {
            items.append(URLQueryItem(name: "facility_id", value: String(facilityId)))
        }
        return try await get("/courts", query: items)
    }

    static func courtTypes() async throws -> [String] {
        try await get("/court-types")
    }

    static func occupancy() async throws -> Occupancy {
        try await get("/occupancy")
    }

    static func createUser(name: String, email: String) async throws -> User {
        try await send("POST", path: "/users", body: UserDraft(name: name, email: email))
    }

    static func startSession(courtId: Int, userId: Int, playerIds: [Int] = []) async throws -> CourtSession {
        try await send(
            "POST",
            path: "/sessions",
            body: SessionStart(courtId: courtId, playerIds: playerIds),
            userId: userId
        )
    }

    static func endSession(id: Int, userId: Int) async throws -> CourtSession {
        let data = try await request("POST", path: "/sessions/\(id)/end", query: [], body: nil, userId: userId)
        return try decode(CourtSession.self, from: data)
    }

    static func deleteSession(id: Int, userId: Int) async throws {
        _ = try await request("DELETE", path: "/sessions/\(id)", query: [], body: nil, userId: userId)
    }

    static func tagPlayer(sessionId: Int, playerId: Int, userId: Int) async throws -> CourtSession {
        try await send(
            "POST",
            path: "/sessions/\(sessionId)/players",
            body: TagPlayer(userId: playerId),
            userId: userId
        )
    }

    static func leaderboard() async throws -> [LeaderboardEntry] {
        try await get("/leaderboard")
    }

    static func courtUsage(
        start: Date,
        end: Date,
        facilityId: Int?,
        courtId: Int?
    ) async throws -> CourtUsageReport {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var items = [
            URLQueryItem(name: "start", value: formatter.string(from: start)),
            URLQueryItem(name: "end", value: formatter.string(from: end)),
        ]
        if let facilityId {
            items.append(URLQueryItem(name: "facility_id", value: String(facilityId)))
        }
        if let courtId {
            items.append(URLQueryItem(name: "court_id", value: String(courtId)))
        }
        return try await get("/reports/court-usage", query: items)
    }

    private static func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        let data = try await request("GET", path: path, query: query, body: nil)
        return try decode(T.self, from: data)
    }

    private static func send<Body: Encodable, T: Decodable>(
        _ method: String,
        path: String,
        body: Body,
        userId: Int? = nil
    ) async throws -> T {
        let data = try await request(
            method,
            path: path,
            query: [],
            body: try makeEncoder().encode(body),
            userId: userId
        )
        return try decode(T.self, from: data)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try makeDecoder().decode(type, from: data)
        } catch {
            throw APIError(message: "The API returned data the app could not read.")
        }
    }

    private static func request(
        _ method: String,
        path: String,
        query: [URLQueryItem],
        body: Data?,
        userId: Int? = nil
    ) async throws -> Data {
        guard var components = URLComponents(string: baseURL + path) else {
            throw APIError(message: "Invalid API URL.")
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw APIError(message: "Invalid API URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        if let userId {
            request.setValue(String(userId), forHTTPHeaderField: "X-User-Id")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError(message: "Could not reach the API at \(baseURL). Start the backend and try again.")
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError(message: "The API did not respond.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(message: message(for: http.statusCode, data: data))
        }
        return data
    }

    private static func message(for status: Int, data: Data) -> String {
        if status == 422 {
            return "End time must be after the start time."
        }
        if let body = try? JSONDecoder().decode(ErrorBody.self, from: data), !body.detail.isEmpty {
            return body.detail
        }
        return "Request failed (\(status))."
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = parseDate(value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized date \(value)"
            )
        }
        return decoder
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }

    private static func parseDate(_ value: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: value) {
            return date
        }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: value)
    }
}

private struct ErrorBody: Decodable {
    let detail: String
}
