import Foundation

public struct HardcoverSearchResult: Sendable, Identifiable {
    public let id: Int
    public let title: String
    public let authorNames: [String]
    public let releaseYear: Int?
}

public struct HardcoverEditionInfo: Sendable, Identifiable {
    public let id: Int
    public let format: String
    public let isbn13: String?
    public let pages: Int?
    public let releaseDate: String?
    public let language: String?
    public let narrators: [String]
    public let otherContributors: [(name: String, role: String)]
}

public struct HardcoverBookDetails: Sendable {
    public let title: String?
    public let subtitle: String?
    public let description: String?
    public let releaseDate: String?
    public let rating: Double?
    public let language: String?
    public let authors: [String]
    public let narrators: [String]
    public let creators: [(name: String, role: String)]
    public let series: [(name: String, position: Double?, featured: Bool)]
    public let tags: [String]
    public let editions: [HardcoverEditionInfo]

    public init(
        title: String?, subtitle: String?, description: String?,
        releaseDate: String?, rating: Double?, language: String? = nil,
        authors: [String], narrators: [String],
        creators: [(name: String, role: String)],
        series: [(name: String, position: Double?, featured: Bool)],
        tags: [String], editions: [HardcoverEditionInfo]
    ) {
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.releaseDate = releaseDate
        self.rating = rating
        self.language = language
        self.authors = authors
        self.narrators = narrators
        self.creators = creators
        self.series = series
        self.tags = tags
        self.editions = editions
    }
}

public actor HardcoverActor {
    public static let shared = HardcoverActor()

    private let endpoint = "https://api.hardcover.app/v1/graphql"
    private var token: String?
    private let urlSession: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        urlSession = URLSession(configuration: config)
    }

    public func setToken(_ token: String?) {
        self.token = token
    }

    public var hasToken: Bool { token != nil }

    public func searchBooks(query: String) async throws -> [HardcoverSearchResult] {
        guard let token else { throw HardcoverError.noToken }

        let graphQL: [String: Any] = [
            "query": """
                query SearchBooks($q: String!) {
                    search(query: $q, query_type: "Book", per_page: 10) {
                        results
                    }
                }
                """,
            "variables": ["q": query],
        ]

        let body = try JSONSerialization.data(withJSONObject: graphQL)
        let responseData = try await postGraphQL(body: body, token: token)

        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
            let data = json["data"] as? [String: Any],
            let search = data["search"] as? [String: Any]
        else {
            throw HardcoverError.invalidResponse
        }

        let hits: [[String: Any]]
        if let resultsRaw = search["results"] {
            let resultsObj: [String: Any]
            if let resultsString = resultsRaw as? String,
                let parsed = try? JSONSerialization.jsonObject(
                    with: Data(resultsString.utf8)) as? [String: Any]
            {
                resultsObj = parsed
            } else if let dict = resultsRaw as? [String: Any] {
                resultsObj = dict
            } else {
                throw HardcoverError.graphQLError(
                    "Unexpected results format: \(type(of: resultsRaw))")
            }
            hits = resultsObj["hits"] as? [[String: Any]] ?? []
        } else {
            hits = []
        }

        return hits.compactMap { hit in
            guard let doc = hit["document"] as? [String: Any],
                let title = doc["title"] as? String
            else { return nil }

            let id: Int
            if let intId = doc["id"] as? Int {
                id = intId
            } else if let strId = doc["id"] as? String, let parsed = Int(strId) {
                id = parsed
            } else {
                return nil
            }

            let authorNames = doc["author_names"] as? [String] ?? []
            let releaseYear = doc["release_year"] as? Int

            return HardcoverSearchResult(
                id: id,
                title: title,
                authorNames: authorNames,
                releaseYear: releaseYear
            )
        }
    }

    public func fetchBookDetails(id: Int) async throws -> HardcoverBookDetails {
        guard let token else { throw HardcoverError.noToken }

        let graphQL: [String: Any] = [
            "query": """
                query GetBook($id: Int!) {
                    books(where: {id: {_eq: $id}}) {
                        title
                        subtitle
                        description
                        release_date
                        rating
                        contributions {
                            contribution
                            author { name }
                        }
                        book_series {
                            position
                            featured
                            series { name }
                        }
                        taggings {
                            tag { tag }
                        }
                        default_audio_edition {
                            contributions {
                                contribution
                                author { name }
                            }
                        }
                        editions {
                            id
                            edition_format
                            isbn_13
                            pages
                            release_date
                            language { language }
                            contributions {
                                contribution
                                author { name }
                            }
                        }
                    }
                }
                """,
            "variables": ["id": id],
        ]

        let body = try JSONSerialization.data(withJSONObject: graphQL)
        let responseData = try await postGraphQL(body: body, token: token)

        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
            let data = json["data"] as? [String: Any],
            let books = data["books"] as? [[String: Any]],
            let book = books.first
        else { throw HardcoverError.bookNotFound }

        let title = book["title"] as? String
        let subtitle = book["subtitle"] as? String
        let description = book["description"] as? String
        let releaseDate: String? = {
            guard let raw = book["release_date"] as? String else { return nil }
            let df = ISO8601DateFormatter()
            df.formatOptions = [.withFullDate]
            if let date = df.date(from: raw) {
                let full = ISO8601DateFormatter()
                full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return full.string(from: date)
            }
            return raw
        }()
        let rating = book["rating"] as? Double

        let contributions = book["contributions"] as? [[String: Any]] ?? []
        var authors: [String] = []
        var creators: [(name: String, role: String)] = []

        for contrib in contributions {
            guard let author = contrib["author"] as? [String: Any],
                let name = author["name"] as? String
            else { continue }
            let role = contrib["contribution"] as? String ?? ""
            if role.lowercased() == "author" || role.isEmpty {
                authors.append(name)
            } else {
                creators.append((name: name, role: role))
            }
        }

        var narrators: [String] = []
        if let audioEdition = book["default_audio_edition"] as? [String: Any],
            let audioContribs = audioEdition["contributions"] as? [[String: Any]]
        {
            for contrib in audioContribs {
                guard let author = contrib["author"] as? [String: Any],
                    let name = author["name"] as? String
                else { continue }
                let role = contrib["contribution"] as? String ?? ""
                if role.lowercased() == "narrator" {
                    narrators.append(name)
                }
            }
        }

        let bookSeries = book["book_series"] as? [[String: Any]] ?? []
        let series: [(name: String, position: Double?, featured: Bool)] = bookSeries.compactMap {
            bs in
            guard let seriesObj = bs["series"] as? [String: Any],
                let name = seriesObj["name"] as? String
            else { return nil }
            let position = bs["position"] as? Double
            let featured = bs["featured"] as? Bool ?? false
            return (name: name, position: position, featured: featured)
        }

        let taggings = book["taggings"] as? [[String: Any]] ?? []
        let tags: [String] = taggings.compactMap { tagging in
            guard let tag = tagging["tag"] as? [String: Any],
                let name = tag["tag"] as? String
            else { return nil }
            return name
        }

        let editionsRaw = book["editions"] as? [[String: Any]] ?? []
        let editions: [HardcoverEditionInfo] = editionsRaw.compactMap { ed in
            guard let format = ed["edition_format"] as? String,
                let edId = ed["id"] as? Int
            else { return nil }
            let lang = (ed["language"] as? [String: Any])?["language"] as? String
            let edContribs = ed["contributions"] as? [[String: Any]] ?? []
            var edNarrators: [String] = []
            var edOther: [(name: String, role: String)] = []
            for c in edContribs {
                guard let a = c["author"] as? [String: Any],
                    let name = a["name"] as? String
                else { continue }
                let role = c["contribution"] as? String ?? ""
                if role.lowercased() == "narrator" {
                    edNarrators.append(name)
                } else if !role.isEmpty && role.lowercased() != "author" {
                    edOther.append((name: name, role: role))
                }
            }
            return HardcoverEditionInfo(
                id: edId,
                format: format,
                isbn13: ed["isbn_13"] as? String,
                pages: ed["pages"] as? Int,
                releaseDate: ed["release_date"] as? String,
                language: lang,
                narrators: edNarrators,
                otherContributors: edOther
            )
        }

        return HardcoverBookDetails(
            title: title,
            subtitle: subtitle,
            description: description,
            releaseDate: releaseDate,
            rating: rating,
            authors: authors,
            narrators: narrators,
            creators: creators,
            series: series,
            tags: tags,
            editions: editions
        )
    }

    private func postGraphQL(body: Data, token: String) async throws -> Data {
        guard let url = URL(string: endpoint) else { throw HardcoverError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let auth = token.hasPrefix("Bearer ") ? token : "Bearer \(token)"
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HardcoverError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300: break
        case 401: throw HardcoverError.unauthorized
        case 429: throw HardcoverError.rateLimited
        default: throw HardcoverError.unexpectedStatus(httpResponse.statusCode)
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let errors = json["errors"] as? [[String: Any]], let first = errors.first {
                let message = first["message"] as? String ?? "Unknown GraphQL error"
                throw HardcoverError.graphQLError(message)
            }
            if let error = json["error"] as? String {
                throw HardcoverError.graphQLError(error)
            }
        }

        return data
    }
}

public enum HardcoverError: Error, LocalizedError {
    case noToken
    case invalidURL
    case invalidResponse
    case unauthorized
    case rateLimited
    case bookNotFound
    case unexpectedStatus(Int)
    case graphQLError(String)

    public var errorDescription: String? {
        switch self {
        case .noToken: return "No Hardcover API token configured"
        case .invalidURL: return "Invalid API URL"
        case .invalidResponse: return "Invalid response from server"
        case .unauthorized: return "Invalid or expired Hardcover token"
        case .rateLimited: return "Rate limited - try again in a minute"
        case .bookNotFound: return "Book not found on Hardcover"
        case .unexpectedStatus(let code): return "Unexpected HTTP status: \(code)"
        case .graphQLError(let msg): return "Hardcover: \(msg)"
        }
    }
}
