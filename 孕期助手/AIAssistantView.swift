import SwiftUI
import UIKit

enum AIRequestErrorKind: String {
    case network
    case timeout
    case dns
    case unauthorized
    case server
    case client
    case unknown
}

enum AIRequestStage: Equatable {
    case connecting
    case retrying(current: Int, total: Int)
    case compensating
    case finished
}

struct AIRequestError: LocalizedError {
    let kind: AIRequestErrorKind
    let userMessage: String
    let rawMessage: String
    let httpStatus: Int?

    var errorDescription: String? {
        userMessage
    }

    static func map(_ error: Error) -> AIRequestError {
        if let mapped = error as? AIRequestError {
            return mapped
        }
        if let urlError = error as? URLError {
            return map(urlError)
        }
        return AIRequestError(
            kind: .unknown,
            userMessage: "有点小波动，我们稍后再试一次。",
            rawMessage: error.localizedDescription,
            httpStatus: nil
        )
    }

    static func map(_ urlError: URLError) -> AIRequestError {
        switch urlError.code {
        case .timedOut:
            return AIRequestError(
                kind: .timeout,
                userMessage: "AI 回复有点慢，我们稍后再试一次。",
                rawMessage: urlError.localizedDescription,
                httpStatus: nil
            )
        case .cannotFindHost, .dnsLookupFailed:
            return AIRequestError(
                kind: .dns,
                userMessage: "暂时找不到服务地址，请稍后再试。",
                rawMessage: urlError.localizedDescription,
                httpStatus: nil
            )
        case .notConnectedToInternet:
            return AIRequestError(
                kind: .network,
                userMessage: "当前网络不可用，请先检查 Wi-Fi 或蜂窝网络。",
                rawMessage: urlError.localizedDescription,
                httpStatus: nil
            )
        case .networkConnectionLost, .cannotConnectToHost:
            return AIRequestError(
                kind: .network,
                userMessage: "暂时连不上 AI 服务，稍后再试；若连续失败，建议切换网络。",
                rawMessage: urlError.localizedDescription,
                httpStatus: nil
            )
        default:
            return AIRequestError(
                kind: .network,
                userMessage: "网络连接有点不稳定，稍后再试一次。",
                rawMessage: urlError.localizedDescription,
                httpStatus: nil
            )
        }
    }

    static func mapHTTP(status: Int, rawMessage: String) -> AIRequestError {
        let normalizedRaw = rawMessage.lowercased()
        if normalizedRaw.contains("invalid api key") || normalizedRaw.contains("authorized_error") {
            return AIRequestError(
                kind: .unauthorized,
                userMessage: "服务鉴权失败，请检查后端 Token 或 Minimax Key。",
                rawMessage: rawMessage,
                httpStatus: status
            )
        }
        switch status {
        case 401:
            return AIRequestError(
                kind: .unauthorized,
                userMessage: "服务鉴权失败，请检查后端 Token 或 Minimax Key。",
                rawMessage: rawMessage,
                httpStatus: status
            )
        case 502, 503, 504:
            return AIRequestError(
                kind: .server,
                userMessage: "AI 服务有点忙，我们稍后再试。",
                rawMessage: rawMessage,
                httpStatus: status
            )
        case 400, 403, 404:
            return AIRequestError(
                kind: .client,
                userMessage: "配置看起来有异常，请检查服务地址和参数后再试。",
                rawMessage: rawMessage,
                httpStatus: status
            )
        default:
            if (500...599).contains(status) {
                return AIRequestError(
                    kind: .server,
                    userMessage: "AI 服务暂时异常，稍后再试一次。",
                    rawMessage: rawMessage,
                    httpStatus: status
                )
            }
            return AIRequestError(
                kind: .unknown,
                userMessage: "有点小波动，我们稍后再试一次。",
                rawMessage: rawMessage,
                httpStatus: status
            )
        }
    }
}

struct ChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    var id = UUID()
    var role: Role
    var text: String
    var time: Date

    init(role: Role, text: String, time: Date) {
        self.role = role
        self.text = text
        self.time = time
    }

    init?(stored: StoredAIMessage) {
        if stored.role == "user" {
            self.role = .user
        } else if stored.role == "assistant" {
            self.role = .assistant
        } else {
            return nil
        }
        self.id = UUID(uuidString: stored.id) ?? UUID()
        if self.role == .assistant {
            self.text = assistantDisplayText(from: stored.content)
        } else {
            self.text = stored.content
        }
        self.time = stored.time
    }
}

private func assistantDisplayText(from raw: String) -> String {
    guard let action = AIParse.parse(raw) else {
        return "我收到了，但这句我没完全听懂，换个说法我再帮你。"
    }
    if action.needClarify {
        return action.clarifyQuestion.isEmpty ? "还需要一点信息～" : action.clarifyQuestion
    }
    if action.intent == "unknown" {
        return action.assistantReply.isEmpty ? "我在呢～" : action.assistantReply
    }
    switch action.intent {
    case "create_medication":
        let name = action.slots["item_name"] ?? "用药"
        return "已识别：新增用药（\(name)）"
    case "create_check_record":
        return "已识别：新增检查报告"
    case "create_appointment":
        return "已识别：新增预约"
    case "create_reminder":
        let name = action.slots["item_name"] ?? "提醒"
        return "已识别：创建提醒（\(name)）"
    case "query_schedule":
        let date = action.slots["date_semantic"] ?? "今天"
        return "已识别：查询\(date)用药安排"
    case "update_profile":
        return "已识别：记录身高体重"
    case "update_reminder_time":
        return "已识别：更新提醒时间"
    default:
        return "已识别指令：\(action.intent)"
    }
}

struct AIBackendChatService {
    private struct AIRequestPolicy {
        var requestTimeout: TimeInterval
        var resourceTimeout: TimeInterval
        var maxAttempts: Int
        var backoffs: [TimeInterval]
        var maxWait: TimeInterval
    }

    struct APIMessage: Codable {
        var role: String
        var content: String
    }

    struct ChatRequestBody: Codable {
        var context: String
        var history: [APIMessage]
        var userInput: String
        var model: String?
    }

    struct HomeSummaryRequestBody: Codable {
        var snapshot: String
        var model: String?
    }

    struct DailyGuideRequestBody: Codable {
        var date: String
        var gestational_text: String
        var profile_context: String
        var model: String?
    }

    struct DailyGuideResponse: Codable {
        var date_key: String?
        var week_guide: String
        var baby_change: String
        var mom_change: String
        var source: String?
    }

    struct PanelGroupRequestBody: Codable {
        var ocr_texts: [String]
        var now: String
        var model: String?
    }

    struct GroupedPanelRecord: Codable {
        var check_type: String?
        var check_date: String
        var hcg: Double
        var progesterone: Double
        var estradiol: Double
        var note: String?
        var source_indexes: [Int]?
    }

    struct PanelGroupResponse: Codable {
        var records: [GroupedPanelRecord]
        var failed_indexes: [Int]
    }

    struct IngredientAnalyzeRequestBody: Codable {
        var ocr_texts: [String]
        var profile_context: String
        var model: String?
    }

    struct IngredientEvidenceItem: Codable {
        var name: String
        var reason: String
    }

    struct IngredientAnalyzeResponse: Codable {
        var overall: String
        var usable: [IngredientEvidenceItem]
        var caution: [IngredientEvidenceItem]
        var avoid: [IngredientEvidenceItem]
        var summary: String
        var alternatives: [String]
        var disclaimer: String
    }

    struct GenericTextResponse: Codable {
        var content: String?
        var reply: String?
        var text: String?
        var result: String?
        var output: String?
        var answer: String?
    }

    struct OpenAICompatibleResponse: Codable {
        struct Choice: Codable {
            struct Message: Codable {
                var content: String
            }
            var message: Message
        }
        var choices: [Choice]
    }

    private let primaryPolicy = AIRequestPolicy(
        requestTimeout: 45,
        resourceTimeout: 55,
        maxAttempts: 2,
        backoffs: [1.8],
        maxWait: 70
    )
    private let compensationPolicy = AIRequestPolicy(
        requestTimeout: 30,
        resourceTimeout: 36,
        maxAttempts: 1,
        backoffs: [],
        maxWait: 35
    )
    private let endToEndBudget: TimeInterval = 75
    private let warmupTimeout: TimeInterval = 60

    func send(config: AIConfig, context: String, history: [StoredAIMessage], userInput: String) async throws -> String {
        try await sendWithRecovery(
            config: config,
            context: context,
            history: history,
            userInput: userInput,
            onStage: nil
        )
    }

    func sendWithRecovery(
        config: AIConfig,
        context: String,
        history: [StoredAIMessage],
        userInput: String,
        onStage: (@MainActor (AIRequestStage) -> Void)? = nil
    ) async throws -> String {
        let historyMessages: [APIMessage] = history.suffix(40).compactMap { item in
            guard item.role == "user" || item.role == "assistant" else { return nil }
            return APIMessage(role: item.role, content: item.content)
        }

        let body = ChatRequestBody(
            context: context,
            history: historyMessages,
            userInput: userInput,
            model: config.model
        )

        let baseCandidates = parseBaseURLs(config.baseURL)
        guard !baseCandidates.isEmpty else {
            throw AIRequestError(
                kind: .client,
                userMessage: "还没配置 AI 后端地址，请先补充配置。",
                rawMessage: config.baseURL,
                httpStatus: nil
            )
        }
        let requestID = shortRequestID()
        let startedAt = Date()
        defer {
            Task { @MainActor in
                onStage?(.finished)
            }
        }

        var lastError: AIRequestError?

        for (index, baseURL) in baseCandidates.enumerated() {
            let endpoint = buildChatEndpoint(baseURL)
            await onStage?(.connecting)
            await quickWarmupBeforeSendIfNeeded(baseURL: baseURL, requestID: requestID)

            do {
                return try await withOverallTimeout(
                    seconds: endToEndBudget,
                    userMessage: "暂时连不上 AI 服务器，请稍后重试。"
                ) {
                    do {
                        return try await requestTextWithPolicy(
                            config: config,
                            endpoint: endpoint,
                            body: body,
                            policy: primaryPolicy,
                            phase: "primary",
                            requestID: requestID,
                            onStage: onStage
                        )
                    } catch let primaryError as AIRequestError {
                        guard shouldCompensate(after: primaryError) else {
                            throw primaryError
                        }

                        await onStage?(.compensating)
                        return try await requestTextWithPolicy(
                            config: config,
                            endpoint: endpoint,
                            body: body,
                            policy: compensationPolicy,
                            phase: "compensation",
                            requestID: requestID,
                            onStage: nil
                        )
                    }
                }
            } catch {
                let mapped = AIRequestError.map(error)
                lastError = mapped
                debugLog(
                    requestID: requestID,
                    phase: "final",
                    attempt: 0,
                    kind: mapped.kind.rawValue,
                    status: mapped.httpStatus,
                    elapsedMs: elapsedMilliseconds(since: startedAt),
                    message: "failed endpoint=\(endpoint)"
                )

                let canFallback = index < baseCandidates.count - 1 && shouldFallbackToNextEndpoint(for: mapped)
                if canFallback {
                    continue
                }
                throw mapped
            }
        }

        throw lastError ?? AIRequestError(
            kind: .unknown,
            userMessage: "有点小波动，我们稍后再试一次。",
            rawMessage: "No endpoint candidates available.",
            httpStatus: nil
        )
    }

    func sendHomeSummary(config: AIConfig, snapshot: String) async throws -> String {
        let body = HomeSummaryRequestBody(snapshot: snapshot, model: config.model)
        let requestID = shortRequestID()
        let candidates = parseBaseURLs(config.baseURL)
        guard !candidates.isEmpty else {
            throw AIRequestError(
                kind: .client,
                userMessage: "还没配置 AI 后端地址，请先补充配置。",
                rawMessage: config.baseURL,
                httpStatus: nil
            )
        }

        var lastError: AIRequestError?
        for (index, baseURL) in candidates.enumerated() {
            do {
                let raw = try await requestTextWithPolicy(
                    config: config,
                    endpoint: buildHomeSummaryEndpoint(baseURL),
                    body: body,
                    policy: primaryPolicy,
                    phase: "summary",
                    requestID: requestID,
                    onStage: nil
                )
                let normalized = normalizePlainText(raw)
                if normalized.isEmpty {
                    throw AIRequestError(
                        kind: .server,
                        userMessage: "这次没拿到首页总结，我们稍后再试。",
                        rawMessage: "home summary empty",
                        httpStatus: nil
                    )
                }
                return normalized
            } catch {
                let mapped = AIRequestError.map(error)
                lastError = mapped
                let canFallback = index < candidates.count - 1 && shouldFallbackToNextEndpoint(for: mapped)
                if canFallback {
                    continue
                }
                throw mapped
            }
        }

        throw lastError ?? AIRequestError(
            kind: .unknown,
            userMessage: "有点小波动，我们稍后再试一次。",
            rawMessage: "No summary endpoint candidates available.",
            httpStatus: nil
        )
    }

    func sendDailyGuide(
        config: AIConfig,
        date: String,
        gestationalText: String,
        profileContext: String
    ) async throws -> DailyGuideResponse {
        let body = DailyGuideRequestBody(
            date: date,
            gestational_text: gestationalText,
            profile_context: profileContext,
            model: config.model
        )
        let candidates = parseBaseURLs(config.baseURL)
        guard !candidates.isEmpty else {
            throw AIRequestError(
                kind: .client,
                userMessage: "还没配置 AI 后端地址，请先补充配置。",
                rawMessage: config.baseURL,
                httpStatus: nil
            )
        }

        var lastError: AIRequestError?
        let requestID = shortRequestID()
        for (index, baseURL) in candidates.enumerated() {
            do {
                let raw = try await requestTextWithPolicy(
                    config: config,
                    endpoint: buildDailyGuideEndpoint(baseURL),
                    body: body,
                    policy: primaryPolicy,
                    phase: "daily-guide",
                    requestID: requestID,
                    onStage: nil
                )
                return try decodeDailyGuideResponse(raw, fallbackDate: date)
            } catch {
                let mapped = AIRequestError.map(error)
                lastError = mapped
                let canFallback = index < candidates.count - 1 && shouldFallbackToNextEndpoint(for: mapped)
                if canFallback {
                    continue
                }
                throw mapped
            }
        }

        throw lastError ?? AIRequestError(
            kind: .unknown,
            userMessage: "当天内容拉取失败，请稍后再试。",
            rawMessage: "No daily-guide endpoint candidates available.",
            httpStatus: nil
        )
    }

    func groupPregnancyPanelReports(
        config: AIConfig,
        ocrTexts: [String],
        nowISO8601: String
    ) async throws -> PanelGroupResponse {
        let body = PanelGroupRequestBody(
            ocr_texts: ocrTexts,
            now: nowISO8601,
            model: config.model
        )
        let candidates = parseBaseURLs(config.baseURL)
        guard !candidates.isEmpty else {
            throw AIRequestError(
                kind: .client,
                userMessage: "还没配置 AI 后端地址，请先补充配置。",
                rawMessage: config.baseURL,
                httpStatus: nil
            )
        }

        var lastError: AIRequestError?
        let requestID = shortRequestID()
        for (index, baseURL) in candidates.enumerated() {
            do {
                let raw = try await requestTextWithPolicy(
                    config: config,
                    endpoint: buildReportGroupEndpoint(baseURL),
                    body: body,
                    policy: primaryPolicy,
                    phase: "panel-group",
                    requestID: requestID,
                    onStage: nil
                )
                return try decodePanelGroupResponse(raw)
            } catch {
                let mapped = AIRequestError.map(error)
                lastError = mapped
                let canFallback = index < candidates.count - 1 && shouldFallbackToNextEndpoint(for: mapped)
                if canFallback {
                    continue
                }
                throw mapped
            }
        }

        throw lastError ?? AIRequestError(
            kind: .unknown,
            userMessage: "报告分组暂时失败，请再试一次。",
            rawMessage: "No panel-group endpoint candidates available.",
            httpStatus: nil
        )
    }

    func analyzeIngredients(
        config: AIConfig,
        ocrTexts: [String],
        profileContext: String
    ) async throws -> IngredientAnalyzeResponse {
        let body = IngredientAnalyzeRequestBody(
            ocr_texts: ocrTexts,
            profile_context: profileContext,
            model: config.model
        )
        let candidates = parseBaseURLs(config.baseURL)
        guard !candidates.isEmpty else {
            throw AIRequestError(
                kind: .client,
                userMessage: "还没配置 AI 后端地址，请先补充配置。",
                rawMessage: config.baseURL,
                httpStatus: nil
            )
        }

        var lastError: AIRequestError?
        let requestID = shortRequestID()
        for (index, baseURL) in candidates.enumerated() {
            do {
                let raw = try await requestTextWithPolicy(
                    config: config,
                    endpoint: buildIngredientAnalyzeEndpoint(baseURL),
                    body: body,
                    policy: primaryPolicy,
                    phase: "ingredient",
                    requestID: requestID,
                    onStage: nil
                )
                return try decodeIngredientAnalyzeResponse(raw)
            } catch {
                let mapped = AIRequestError.map(error)
                lastError = mapped
                let canFallback = index < candidates.count - 1 && shouldFallbackToNextEndpoint(for: mapped)
                if canFallback {
                    continue
                }
                throw mapped
            }
        }

        throw lastError ?? AIRequestError(
            kind: .unknown,
            userMessage: "成分识别暂时失败，请再试一次。",
            rawMessage: "No ingredient endpoint candidates available.",
            httpStatus: nil
        )
    }

    func warmup(config: AIConfig) async {
        guard let baseURL = parseBaseURLs(config.baseURL).first,
              let url = buildWarmupURL(from: baseURL) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = warmupTimeout

        do {
            let (_, response) = try await makeWarmupSession().data(for: request)
            if let http = response as? HTTPURLResponse {
                debugLog(
                    requestID: shortRequestID(),
                    phase: "warmup",
                    attempt: 0,
                    kind: "-",
                    status: http.statusCode,
                    elapsedMs: 0,
                    message: "status=\(http.statusCode) url=\(url.absoluteString)"
                )
            } else {
                debugLog(
                    requestID: shortRequestID(),
                    phase: "warmup",
                    attempt: 0,
                    kind: "-",
                    status: nil,
                    elapsedMs: 0,
                    message: "non-http response url=\(url.absoluteString)"
                )
            }
        } catch {
            debugLog(
                requestID: shortRequestID(),
                phase: "warmup",
                attempt: 0,
                kind: AIRequestError.map(error).kind.rawValue,
                status: nil,
                elapsedMs: 0,
                message: "failed \(error.localizedDescription) url=\(url.absoluteString)"
            )
        }
    }

    private func requestTextWithPolicy<Body: Encodable>(
        config: AIConfig,
        endpoint: String,
        body: Body,
        policy: AIRequestPolicy,
        phase: String,
        requestID: String,
        onStage: (@MainActor (AIRequestStage) -> Void)?
    ) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw AIRequestError(
                kind: .client,
                userMessage: "AI 后端地址格式不正确，请检查后再试。",
                rawMessage: endpoint,
                httpStatus: nil
            )
        }

        let bodyData: Data
        do {
            bodyData = try JSONEncoder().encode(body)
        } catch {
            throw AIRequestError(
                kind: .client,
                userMessage: "请求参数处理失败，请稍后再试。",
                rawMessage: error.localizedDescription,
                httpStatus: nil
            )
        }

        return try await withOverallTimeout(
            seconds: policy.maxWait,
            userMessage: "AI 服务响应超时，请稍后重试。"
        ) {
            let session = makeSession(policy: policy)

            for attempt in 1...policy.maxAttempts {
                let attemptStartedAt = Date()
                do {
                    let output = try await requestTextOnce(
                        session: session,
                        url: url,
                        config: config,
                        bodyData: bodyData,
                        requestTimeout: policy.requestTimeout
                    )
                    debugLog(
                        requestID: requestID,
                        phase: phase,
                        attempt: attempt,
                        kind: "-",
                        status: nil,
                        elapsedMs: elapsedMilliseconds(since: attemptStartedAt),
                        message: "success endpoint=\(endpoint)"
                    )
                    return output
                } catch let requestError as AIRequestError {
                    debugLog(
                        requestID: requestID,
                        phase: phase,
                        attempt: attempt,
                        kind: requestError.kind.rawValue,
                        status: requestError.httpStatus,
                        elapsedMs: elapsedMilliseconds(since: attemptStartedAt),
                        message: "failed endpoint=\(endpoint)"
                    )

                    if shouldRetry(error: requestError, attempt: attempt, maxAttempts: policy.maxAttempts) {
                        await onStage?(.retrying(current: attempt + 1, total: policy.maxAttempts))
                        try await backoffBeforeRetry(attempt: attempt, backoffs: policy.backoffs)
                        continue
                    }
                    throw requestError
                } catch {
                    let wrapped = AIRequestError.map(error)
                    debugLog(
                        requestID: requestID,
                        phase: phase,
                        attempt: attempt,
                        kind: wrapped.kind.rawValue,
                        status: wrapped.httpStatus,
                        elapsedMs: elapsedMilliseconds(since: attemptStartedAt),
                        message: "failed wrapped endpoint=\(endpoint)"
                    )
                    if shouldRetry(error: wrapped, attempt: attempt, maxAttempts: policy.maxAttempts) {
                        await onStage?(.retrying(current: attempt + 1, total: policy.maxAttempts))
                        try await backoffBeforeRetry(attempt: attempt, backoffs: policy.backoffs)
                        continue
                    }
                    throw wrapped
                }
            }

            throw AIRequestError(
                kind: .unknown,
                userMessage: "有点小波动，我们稍后再试一次。",
                rawMessage: "Reached unexpected retry end.",
                httpStatus: nil
            )
        }
    }

    private func withOverallTimeout<T>(
        seconds: TimeInterval,
        userMessage: String,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                let ns = UInt64(max(0, seconds) * 1_000_000_000)
                try await Task.sleep(nanoseconds: ns)
                throw AIRequestError(
                    kind: .timeout,
                    userMessage: userMessage,
                    rawMessage: "Request exceeded maxTotalWait=\(seconds)s",
                    httpStatus: nil
                )
            }

            let value = try await group.next()!
            group.cancelAll()
            return value
        }
    }

    private func requestTextOnce(
        session: URLSession,
        url: URL,
        config: AIConfig,
        bodyData: Data,
        requestTimeout: TimeInterval
    ) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = bodyData

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AIRequestError(
                    kind: .unknown,
                    userMessage: "服务返回异常，请稍后再试。",
                    rawMessage: "Non-HTTP response",
                    httpStatus: nil
                )
            }

            guard (200...299).contains(http.statusCode) else {
                let text = String(data: data, encoding: .utf8) ?? "请求失败"
                throw AIRequestError.mapHTTP(status: http.statusCode, rawMessage: text)
            }

            guard let output = decodeTextPayload(from: data), !output.isEmpty else {
                throw AIRequestError(
                    kind: .server,
                    userMessage: "AI 这次没有返回内容，请稍后再试。",
                    rawMessage: "Empty decoded payload",
                    httpStatus: http.statusCode
                )
            }
            return output
        } catch let urlError as URLError {
            throw AIRequestError.map(urlError)
        }
    }

    private func makeSession(policy: AIRequestPolicy) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = policy.requestTimeout
        configuration.timeoutIntervalForResource = policy.resourceTimeout
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }

    private func makeWarmupSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = warmupTimeout
        configuration.timeoutIntervalForResource = warmupTimeout + 5
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }

    private func makeQuickWarmupSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }

    private func quickWarmupBeforeSendIfNeeded(baseURL: String, requestID: String) async {
        guard let url = buildWarmupURL(from: baseURL) else { return }
        guard isLikelyRenderHost(url) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8

        do {
            let (_, response) = try await makeQuickWarmupSession().data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode
            debugLog(
                requestID: requestID,
                phase: "quick-warmup",
                attempt: 0,
                kind: "-",
                status: status,
                elapsedMs: 0,
                message: "ok url=\(url.absoluteString)"
            )
        } catch {
            debugLog(
                requestID: requestID,
                phase: "quick-warmup",
                attempt: 0,
                kind: AIRequestError.map(error).kind.rawValue,
                status: nil,
                elapsedMs: 0,
                message: "ignored failure \(error.localizedDescription)"
            )
        }
    }

    private func shouldRetry(error: AIRequestError, attempt: Int, maxAttempts: Int) -> Bool {
        guard attempt < maxAttempts else { return false }
        switch error.kind {
        case .timeout, .network, .dns:
            return true
        case .server:
            return error.httpStatus == 502 || error.httpStatus == 503 || error.httpStatus == 504
        case .unauthorized, .client, .unknown:
            return false
        }
    }

    private func shouldCompensate(after error: AIRequestError) -> Bool {
        switch error.kind {
        case .timeout, .network, .dns:
            return true
        case .server:
            return error.httpStatus == 502 || error.httpStatus == 503 || error.httpStatus == 504
        case .unauthorized, .client, .unknown:
            return false
        }
    }

    private func shouldFallbackToNextEndpoint(for error: AIRequestError) -> Bool {
        switch error.kind {
        case .network, .timeout, .dns:
            return true
        case .server:
            return error.httpStatus == nil || error.httpStatus == 502 || error.httpStatus == 503 || error.httpStatus == 504
        case .unauthorized, .client, .unknown:
            return false
        }
    }

    private func isLikelyRenderHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.contains("onrender.com")
    }

    private func parseBaseURLs(_ raw: String) -> [String] {
        let parts = raw
            .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var unique: [String] = []
        for item in parts where !unique.contains(item) {
            unique.append(item)
        }
        return unique
    }

    private func backoffBeforeRetry(attempt: Int, backoffs: [TimeInterval]) async throws {
        guard !backoffs.isEmpty else { return }
        let index = max(0, min(attempt - 1, backoffs.count - 1))
        let seconds = backoffs[index]
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func elapsedMilliseconds(since date: Date) -> Int {
        Int(Date().timeIntervalSince(date) * 1000)
    }

    private func shortRequestID() -> String {
        String(UUID().uuidString.prefix(8))
    }

    private func debugLog(
        requestID: String,
        phase: String,
        attempt: Int,
        kind: String,
        status: Int?,
        elapsedMs: Int,
        message: String
    ) {
        #if DEBUG
        print(
            "[AIBackendChatService] requestID=\(requestID) phase=\(phase) attempt=\(attempt) " +
            "kind=\(kind) status=\(status.map(String.init) ?? "-") elapsedMs=\(elapsedMs) message=\(message)"
        )
        #endif
    }

    private func decodeTextPayload(from data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(GenericTextResponse.self, from: data),
           let text = firstNonEmpty([
               decoded.content,
               decoded.reply,
               decoded.text,
               decoded.result,
               decoded.output,
               decoded.answer
           ]) {
            return text
        }

        if let openAI = try? JSONDecoder().decode(OpenAICompatibleResponse.self, from: data),
           let text = openAI.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }

        if
            let object = try? JSONSerialization.jsonObject(with: data, options: []),
            let map = object as? [String: Any]
        {
            if let nested = map["data"] as? [String: Any] {
                let candidates = [
                    nested["content"] as? String,
                    nested["reply"] as? String,
                    nested["text"] as? String,
                    nested["result"] as? String,
                    nested["output"] as? String
                ]
                if let text = firstNonEmpty(candidates) {
                    return text
                }
            }

            if let rawDataText = map["data"] as? String,
               !rawDataText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return rawDataText
            }

            if
                map["intent"] != nil || map["slots"] != nil || map["assistant_reply"] != nil,
                let jsonData = try? JSONSerialization.data(withJSONObject: map, options: []),
                let jsonString = String(data: jsonData, encoding: .utf8)
            {
                return jsonString
            }
        }

        let plainText = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (plainText?.isEmpty == false) ? plainText : nil
    }

    private func firstNonEmpty(_ values: [String?]) -> String? {
        for value in values {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private func normalizePlainText(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "```text", with: "")
            text = text.replacingOccurrences(of: "```", with: "")
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 有些推理模型会输出 <think>...</think>，这里只保留最终回答。
        if let closeRange = text.range(of: "</think>", options: [.caseInsensitive]) {
            let tail = text[closeRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty {
                text = String(tail)
            }
        }

        if let regex = try? NSRegularExpression(pattern: "(?is)<think\\b[^>]*>.*?</think>") {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }

        if let openRange = text.range(of: "<think", options: [.caseInsensitive]) {
            text = String(text[..<openRange.lowerBound])
        }

        if text.hasPrefix("\""), text.hasSuffix("\""), text.count >= 2 {
            text = String(text.dropFirst().dropLast())
        }

        text = text.replacingOccurrences(of: "\n", with: " ")
        if let spaceRegex = try? NSRegularExpression(pattern: "\\s+") {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = spaceRegex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: " ")
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 兜底：超长时仅保留末尾 1-2 句，避免把提示词/过程展示给用户。
        if text.count > 120 {
            let separators = CharacterSet(charactersIn: "。！？!?")
            let parts = text
                .components(separatedBy: separators)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !parts.isEmpty {
                let picked = parts.suffix(2).joined(separator: "。")
                text = picked.hasSuffix("。") ? picked : picked + "。"
            }
        }

        return text
    }

    private func buildChatEndpoint(_ input: String) -> String {
        buildEndpoint(input, path: "/api/ai/chat", suffixes: ["/api/ai/chat", "/ai/chat", "/chat"])
    }

    private func buildHomeSummaryEndpoint(_ input: String) -> String {
        buildEndpoint(
            input,
            path: "/api/ai/home-summary",
            suffixes: ["/api/ai/home-summary", "/ai/home-summary", "/home-summary", "/summary"]
        )
    }

    private func buildDailyGuideEndpoint(_ input: String) -> String {
        buildEndpoint(
            input,
            path: "/api/ai/guide/daily",
            suffixes: ["/api/ai/guide/daily", "/ai/guide/daily", "/guide/daily"]
        )
    }

    private func buildReportGroupEndpoint(_ input: String) -> String {
        buildEndpoint(
            input,
            path: "/api/ai/report/pregnancy-panel/group",
            suffixes: [
                "/api/ai/report/pregnancy-panel/group",
                "/ai/report/pregnancy-panel/group",
                "/report/pregnancy-panel/group"
            ]
        )
    }

    private func buildIngredientAnalyzeEndpoint(_ input: String) -> String {
        buildEndpoint(
            input,
            path: "/api/ai/ingredient/analyze",
            suffixes: ["/api/ai/ingredient/analyze", "/ai/ingredient/analyze", "/ingredient/analyze"]
        )
    }

    private func decodeDailyGuideResponse(_ raw: String, fallbackDate: String) throws -> DailyGuideResponse {
        if let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(DailyGuideResponse.self, from: data) {
            return DailyGuideResponse(
                date_key: decoded.date_key ?? fallbackDate,
                week_guide: decoded.week_guide,
                baby_change: decoded.baby_change,
                mom_change: decoded.mom_change,
                source: decoded.source ?? "ai"
            )
        }

        if let data = raw.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data, options: []),
           let map = object as? [String: Any] {
            let weekGuide = (map["week_guide"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let babyChange = (map["baby_change"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let momChange = (map["mom_change"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return DailyGuideResponse(
                date_key: (map["date_key"] as? String) ?? fallbackDate,
                week_guide: weekGuide,
                baby_change: babyChange,
                mom_change: momChange,
                source: (map["source"] as? String) ?? "ai"
            )
        }

        throw AIRequestError(
            kind: .server,
            userMessage: "内容解析失败，请稍后再试。",
            rawMessage: raw,
            httpStatus: nil
        )
    }

    private func decodePanelGroupResponse(_ raw: String) throws -> PanelGroupResponse {
        if let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(PanelGroupResponse.self, from: data) {
            return decoded
        }
        throw AIRequestError(
            kind: .server,
            userMessage: "报告识别结果解析失败，请再试一次。",
            rawMessage: raw,
            httpStatus: nil
        )
    }

    private func decodeIngredientAnalyzeResponse(_ raw: String) throws -> IngredientAnalyzeResponse {
        if let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(IngredientAnalyzeResponse.self, from: data) {
            return decoded
        }

        throw AIRequestError(
            kind: .server,
            userMessage: "成分识别结果解析失败，请再试一次。",
            rawMessage: raw,
            httpStatus: nil
        )
    }

    private func buildEndpoint(_ input: String, path: String, suffixes: [String]) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if suffixes.contains(where: { lower.hasSuffix($0) }) {
            return trimmed
        }
        if trimmed.hasSuffix("/") {
            return trimmed + String(path.dropFirst())
        }
        return trimmed + path
    }

    private func buildWarmupURL(from baseURL: String) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard var components = URLComponents(string: trimmed),
              components.scheme != nil,
              components.host != nil else {
            return nil
        }
        components.path = "/"
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

struct AIAssistantView: View {
    @EnvironmentObject private var store: PregnancyStore

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var sending = false
    @State private var errorText = ""
    @State private var stageText = ""
    @State private var lastFailedInput: String?
    @State private var canRetryLastFailed = false
    @State private var didTriggerBackendWarmup = false

    @State private var longTermMemory = ""

    private let chatService = AIBackendChatService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section("助手设置") {
                        Text("当前通过后端统一接入 AI（支持 Kimi/Gemini）；发布版可在 Info.plist 配置 AI_BACKEND_URL，调试可用 AI_BACKEND_URL / AI_BACKEND_TOKEN / AI_BACKEND_MODEL 覆盖。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        TextField("长期记忆（例如禁忌/偏好）", text: $longTermMemory, axis: .vertical)
                            .lineLimit(2...5)
                        Button("保存长期记忆") {
                            store.saveAILongTermMemory(longTermMemory.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                        Button("清空对话历史") {
                            store.clearAIConversation()
                            messages = []
                        }
                    }

                    Section("提醒设置") {
                        ReminderSettingsView()
                            .environmentObject(store)
                    }

                    Section("对话") {
                        if messages.isEmpty {
                            Text("示例：\n1. 今天几点吃什么药？\n2. 我可以吃海鲜吗？\n3. 明天回诊要准备什么？")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(messages) { message in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(message.role == .user ? "我" : "AI")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(message.text)
                                        .textSelection(.enabled)
                                        .contextMenu {
                                            Button("复制") {
                                                copyToPasteboard(message.text)
                                            }
                                        }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }

                if !errorText.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                        if canRetryLastFailed, lastFailedInput != nil {
                            Button("重试上次发送") {
                                Task { await retryLastFailedMessage() }
                            }
                            .font(.footnote.weight(.semibold))
                            .disabled(sending)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 6)
                }

                if sending, !stageText.isEmpty {
                    Text(stageText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.bottom, 6)
                }

                HStack(spacing: 8) {
                    TextField("输入问题，例如：今天用药安排", text: $inputText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)

                    Button(sending ? "发送中..." : "发送") {
                        Task { await sendMessage() }
                    }
                    .disabled(sending || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }
            .navigationTitle("智能助手")
            .onAppear {
                longTermMemory = store.aiLongTermMemory()
                messages = store.aiConversation().compactMap { ChatMessage(stored: $0) }
                triggerBackendWarmupIfNeeded()
            }
        }
    }

    private func copyToPasteboard(_ text: String) {
        UIPasteboard.general.string = text
    }

    private func sendMessage() async {
        errorText = ""
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""
        sending = true
        stageText = stageText(for: .connecting)
        defer {
            sending = false
            stageText = ""
        }
        let userMessage = ChatMessage(role: .user, text: text, time: Date())
        messages.append(userMessage)

        do {
            let answer = try await requestAssistantAnswer(for: text) { stage in
                stageText = stageText(for: stage)
            }
            let displayText = assistantDisplayText(from: answer)
            messages.append(ChatMessage(role: .assistant, text: displayText, time: Date()))

            store.appendAIMessage(role: "user", content: text)
            store.appendAIMessage(role: "assistant", content: answer)
            canRetryLastFailed = false
            lastFailedInput = nil
        } catch {
            let mapped = AIRequestError.map(error)
            errorText = mapped.userMessage
            canRetryLastFailed = true
            lastFailedInput = text
        }
    }

    private func retryLastFailedMessage() async {
        guard let text = lastFailedInput, !text.isEmpty else { return }
        guard !sending else { return }

        sending = true
        stageText = stageText(for: .connecting)
        defer {
            sending = false
            stageText = ""
        }
        errorText = ""

        do {
            let answer = try await requestAssistantAnswer(for: text) { stage in
                stageText = stageText(for: stage)
            }
            let displayText = assistantDisplayText(from: answer)
            messages.append(ChatMessage(role: .assistant, text: displayText, time: Date()))

            store.appendAIMessage(role: "user", content: text)
            store.appendAIMessage(role: "assistant", content: answer)
            canRetryLastFailed = false
            lastFailedInput = nil
        } catch {
            let mapped = AIRequestError.map(error)
            errorText = mapped.userMessage
            canRetryLastFailed = true
        }
    }

    private func requestAssistantAnswer(
        for input: String,
        onStage: (@MainActor (AIRequestStage) -> Void)? = nil
    ) async throws -> String {
        let config = store.currentAIConfig()
        if config.baseURL.isEmpty {
            throw AIRequestError(
                kind: .client,
                userMessage: "AI 服务还没配置，请先设置 AI_BACKEND_URL。",
                rawMessage: "Missing AI_BACKEND_URL",
                httpStatus: nil
            )
        }

        return try await chatService.sendWithRecovery(
            config: config,
            context: store.aiContextSummary(),
            history: store.aiConversation(),
            userInput: input,
            onStage: onStage
        )
    }

    private func stageText(for stage: AIRequestStage) -> String {
        switch stage {
        case .connecting:
            return "正在连接 AI 服务…"
        case let .retrying(current, total):
            return "网络波动，正在第 \(current)/\(total) 次重试…"
        case .compensating:
            return "正在执行补偿重试…"
        case .finished:
            return ""
        }
    }

    private func triggerBackendWarmupIfNeeded() {
        guard !didTriggerBackendWarmup else { return }
        let config = store.currentAIConfig()
        guard !config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        didTriggerBackendWarmup = true
        Task {
            await chatService.warmup(config: config)
        }
    }
}

struct ReminderSettingsView: View {
    @EnvironmentObject private var store: PregnancyStore

    @State private var wakeUpTime = Date()
    @State private var breakfastTime = Date()
    @State private var lunchTime = Date()
    @State private var dinnerTime = Date()
    @State private var sleepTime = Date()
    @State private var enableSystemReminders = false
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingField(title: "起床时间", selection: $wakeUpTime)
            settingField(title: "早餐时间", selection: $breakfastTime)
            settingField(title: "午餐时间", selection: $lunchTime)
            settingField(title: "晚餐时间", selection: $dinnerTime)
            settingField(title: "睡觉时间", selection: $sleepTime)

            Toggle("同步到 iOS 提醒事项", isOn: $enableSystemReminders)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
        }
        .padding(12)
        .background(AppTheme.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            let config = store.currentReminderConfig()
            wakeUpTime = dateFromHHmm(config.wakeUpTime)
            breakfastTime = dateFromHHmm(config.breakfastTime)
            lunchTime = dateFromHHmm(config.lunchTime)
            dinnerTime = dateFromHHmm(config.dinnerTime)
            sleepTime = dateFromHHmm(config.sleepTime)
            enableSystemReminders = config.enableSystemReminders
            didLoad = true
        }
        .onChange(of: wakeUpTime) { _ in persistReminderConfigIfReady() }
        .onChange(of: breakfastTime) { _ in persistReminderConfigIfReady() }
        .onChange(of: lunchTime) { _ in persistReminderConfigIfReady() }
        .onChange(of: dinnerTime) { _ in persistReminderConfigIfReady() }
        .onChange(of: sleepTime) { _ in persistReminderConfigIfReady() }
        .onChange(of: enableSystemReminders) { _ in persistReminderConfigIfReady() }
    }

    private func settingField(title: String, selection: Binding<Date>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: 78, alignment: .leading)
            DatePicker(
                "",
                selection: selection,
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .frame(minHeight: 40)
            .background(AppTheme.card)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .tint(AppTheme.actionPrimary)
        }
    }

    private func persistReminderConfigIfReady() {
        guard didLoad else { return }
        let newConfig = ReminderConfig(
            wakeUpTime: hhmmFromDate(wakeUpTime),
            breakfastTime: hhmmFromDate(breakfastTime),
            lunchTime: hhmmFromDate(lunchTime),
            dinnerTime: hhmmFromDate(dinnerTime),
            sleepTime: hhmmFromDate(sleepTime),
            minutesBefore: 0,
            enableSystemReminders: enableSystemReminders
        )
        store.saveReminderConfig(newConfig)
    }

    private func dateFromHHmm(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        let normalized = store.normalizeTimeText(text) ?? text
        guard let parsed = formatter.date(from: normalized) else {
            return Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
        }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: parsed)
        return Calendar.current.date(bySettingHour: comps.hour ?? 8, minute: comps.minute ?? 0, second: 0, of: Date()) ?? Date()
    }

    private func hhmmFromDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
