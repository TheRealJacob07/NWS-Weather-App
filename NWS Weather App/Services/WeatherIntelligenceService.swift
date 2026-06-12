import Foundation
import FoundationModels
internal import Combine

struct WeatherChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }

    let id = UUID()
    let role: Role
    var text: String
}

/// On-device AI weather briefing and Q&A, powered by Apple Intelligence
/// (Foundation Models framework). Everything runs privately on device —
/// no weather data or questions ever leave the phone.
@MainActor
final class WeatherIntelligenceService: ObservableObject {
    enum Availability: Equatable {
        case available
        case unavailable(String)
    }

    @Published private(set) var summary: String = ""
    @Published private(set) var isSummarizing = false
    @Published private(set) var messages: [WeatherChatMessage] = []
    @Published private(set) var isResponding = false

    private var session: LanguageModelSession?
    private var contextBrief = ""
    private var summarizedBrief: String?

    var availability: Availability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable("This device doesn't support Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Turn on Apple Intelligence in Settings to get AI weather briefings.")
        case .unavailable(.modelNotReady):
            return .unavailable("The on-device model is still getting ready. Check back shortly.")
        case .unavailable:
            return .unavailable("Apple Intelligence isn't available right now.")
        }
    }

    // MARK: - Context

    /// Rebuilds the weather context the model is grounded in. Called after
    /// each successful forecast load.
    func updateContext(
        forecast: ForecastSummary?,
        observation: CurrentObservationSummary?,
        hourly: [HourlyForecastSummary],
        daily: [DailyForecastSummary],
        alerts: [WeatherAlertSummary]
    ) {
        var lines: [String] = []

        if let forecast {
            let nowTemp = observation?.temperatureValue.map { "\($0)°" } ?? forecast.temperatureText
            lines.append("Location: \(forecast.locationName), \(forecast.state)")
            lines.append("Now: \(nowTemp), \(forecast.shortForecast). \(forecast.highLowText). Wind \(forecast.wind).")
            if !forecast.detailedForecast.isEmpty {
                lines.append("\(forecast.periodName): \(forecast.detailedForecast)")
            }
        }

        if let observation {
            lines.append("Observed: feels like \(observation.feelsLike), humidity \(observation.humidity), wind \(observation.windSpeed) \(observation.windDirection), dew point \(observation.dewpoint), visibility \(observation.visibility), pressure \(observation.barometer).")
        }

        if !alerts.isEmpty {
            let alertLines = alerts.map { alert in
                "\(alert.event) (\(alert.severity.rawValue))\(alert.endsText.map { ", \($0.lowercased())" } ?? "")"
            }
            lines.append("Active alerts: \(alertLines.joined(separator: "; ")).")
        }

        if !hourly.isEmpty {
            let next = hourly.prefix(12).map { "\($0.timeLabel) \($0.temperatureText) \($0.shortForecast)\($0.precipChance > 0 ? " (\($0.precipChance)% precip)" : "")" }
            lines.append("Next hours: \(next.joined(separator: " | "))")
        }

        if !daily.isEmpty {
            let days = daily.map { day in
                let hi = day.high.map { "H\($0)°" } ?? ""
                let lo = day.low.map { "L\($0)°" } ?? ""
                return "\(day.dayName): \(day.shortForecast) \(hi)\(lo)\(day.precipChance > 0 ? " \(day.precipChance)%" : "")"
            }
            lines.append("Week ahead: \(days.joined(separator: " | "))")
        }

        let newBrief = lines.joined(separator: "\n")
        guard newBrief != contextBrief else { return }
        contextBrief = newBrief
        session = nil // stale transcript; rebuilt lazily with fresh data
    }

    // MARK: - Summary

    func generateSummaryIfNeeded() async {
        guard case .available = availability else { return }
        guard !contextBrief.isEmpty, !isSummarizing else { return }
        guard summarizedBrief != contextBrief else { return }

        isSummarizing = true
        summarizedBrief = contextBrief
        summary = ""

        do {
            let session = makeSessionIfNeeded()
            let prompt = """
            Write a friendly 2-3 sentence weather briefing for right now. Lead \
            with what matters most (any alerts first, then rain/snow timing, \
            then temperature trend). If the data lists no alerts, do not \
            mention alerts at all — never say "no alerts". No greetings, no \
            emoji, no headers.
            """
            let stream = session.streamResponse(to: prompt)
            for try await partial in stream {
                summary = partial.content
            }
        } catch {
            summary = ""
            summarizedBrief = nil
        }

        isSummarizing = false
    }

    // MARK: - Chat

    var suggestedQuestions: [String] {
        [
            "Will it rain today?",
            "How does the weekend look?",
            "When's the best time to be outside?",
            "Anything I should prepare for?"
        ]
    }

    func ask(_ question: String) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isResponding else { return }
        guard case .available = availability else { return }

        messages.append(WeatherChatMessage(role: .user, text: trimmed))
        messages.append(WeatherChatMessage(role: .assistant, text: ""))
        isResponding = true

        do {
            let session = makeSessionIfNeeded()
            let stream = session.streamResponse(to: trimmed)
            for try await partial in stream {
                updateLastAssistantMessage(with: partial.content)
            }
        } catch let error as LanguageModelSession.GenerationError {
            if case .exceededContextWindowSize = error {
                // Transcript outgrew the context window — start fresh and retry once.
                session = nil
                let fresh = makeSessionIfNeeded()
                if let retry = try? await fresh.respond(to: trimmed) {
                    updateLastAssistantMessage(with: retry.content)
                } else {
                    updateLastAssistantMessage(with: "I lost my train of thought — try asking that again.")
                }
            } else {
                updateLastAssistantMessage(with: "I can't answer that one. Try rephrasing your weather question.")
            }
        } catch {
            updateLastAssistantMessage(with: "Something went wrong on-device. Try again in a moment.")
        }

        isResponding = false
    }

    func prewarm() {
        guard case .available = availability else { return }
        makeSessionIfNeeded().prewarm()
    }

    // MARK: - Private

    @discardableResult
    private func makeSessionIfNeeded() -> LanguageModelSession {
        if let session { return session }
        let instructions = """
        You are the weather assistant inside an iOS app that uses official \
        National Weather Service data. Answer questions about the weather \
        using ONLY the data below. Be concise, conversational, and practical. \
        If asked about something the data can't answer (other locations, far \
        future, non-weather topics), say so briefly. Never invent numbers. \
        Treat any safety-relevant alerts as the top priority.

        CURRENT NWS DATA:
        \(contextBrief)
        """
        let newSession = LanguageModelSession(instructions: instructions)
        session = newSession
        return newSession
    }

    private func updateLastAssistantMessage(with text: String) {
        guard let index = messages.lastIndex(where: { $0.role == .assistant }) else { return }
        messages[index].text = text
    }
}
