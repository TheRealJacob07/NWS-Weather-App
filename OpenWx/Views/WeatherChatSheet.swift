import SwiftUI

/// On-device AI weather chat. Grounded in the latest NWS data for the
/// active location; everything stays on the device.
struct WeatherChatSheet: View {
    @ObservedObject var intelligence: WeatherIntelligenceService
    let locationName: String

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.06, blue: 0.10)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 12) {
                                if intelligence.messages.isEmpty {
                                    emptyState
                                }

                                ForEach(intelligence.messages) { message in
                                    messageBubble(message)
                                        .id(message.id)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                        }
                        .onChange(of: intelligence.messages.last?.text) { _, _ in
                            if let last = intelligence.messages.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }

                    inputBar
                }
            }
            .navigationTitle("Weather AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 5) {
                        Image(systemName: "lock.shield")
                            .font(.caption2.weight(.semibold))
                        Text("On-device")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.white.opacity(0.45))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { intelligence.prewarm() }
    }

    // MARK: - Pieces

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(colors: [.cyan, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Text("Ask me about the weather in \(locationName).")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
                Text("I'm grounded in the latest National Weather Service forecast and run entirely on your device.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(intelligence.suggestedQuestions, id: \.self) { question in
                    Button {
                        Task { await intelligence.ask(question) }
                    } label: {
                        Text(question)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.cyan)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
            }
        }
    }

    @ViewBuilder
    private func messageBubble(_ message: WeatherChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }

            Group {
                if message.text.isEmpty && message.role == .assistant {
                    HStack(spacing: 6) {
                        ProgressView().tint(.cyan).scaleEffect(0.7)
                        Text("Thinking…")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                } else {
                    Text(message.text)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(message.role == .user ? 1.0 : 0.88))
                        .lineSpacing(3)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(
                message.role == .user
                    ? .regular.tint(.cyan.opacity(0.22))
                    : .regular.tint(.white.opacity(0.05)),
                in: .rect(cornerRadius: 18)
            )

            if message.role == .assistant { Spacer(minLength: 48) }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about the weather…", text: $draft, axis: .vertical)
                .font(.subheadline)
                .foregroundStyle(.white)
                .tint(.cyan)
                .lineLimit(1...4)
                .focused($inputFocused)
                .onSubmit(send)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(
                canSend ? .regular.tint(.cyan.opacity(0.35)).interactive() : .regular,
                in: .circle
            )
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !intelligence.isResponding
    }

    private func send() {
        guard canSend else { return }
        let question = draft
        draft = ""
        Task { await intelligence.ask(question) }
    }
}
