import SwiftUI
import SafariServices

struct NOAAResourceRow: View {
    let resource: NOAAResource

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: resource.symbolName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.cyan)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(resource.title)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.94))

                Text(resource.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)

                Text(resource.source)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.cyan.opacity(0.82))
            }

            Spacer(minLength: 12)

            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.44))
                .padding(.top, 4)
        }
        .padding(16)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        }
    }
}

struct NOAAResourceBrowser: View {
    let resource: NOAAResource
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SafariView(url: resource.url)
                .ignoresSafeArea()
                .navigationTitle(resource.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
