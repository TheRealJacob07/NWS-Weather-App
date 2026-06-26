import SwiftUI
import UIKit

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

            Image(systemName: "chevron.right")
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

/// Native NOAA product viewer: pinch-to-zoom imagery, frame picker, and
/// pull-fresh refresh — no external browser.
struct NOAAResourceBrowser: View {
    let resource: NOAAResource
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFrame: NOAAProductFrame?
    @State private var cacheBuster: Int = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.05, blue: 0.09)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    ZoomableProductImage(url: activeURL)
                        .id(activeURL) // reload + reset zoom when frame changes
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    VStack(spacing: 10) {
                        if resource.frames.count > 1 {
                            HStack(spacing: 8) {
                                ForEach(resource.frames) { frame in
                                    frameChip(frame)
                                }
                                Spacer()
                            }
                        }

                        HStack {
                            Text("Source: \(resource.source) • Pinch to zoom")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.45))
                            Spacer()
                            Button {
                                cacheBuster += 1
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.interactive(), in: .capsule)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle(resource.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var activeURL: URL {
        let base = (selectedFrame ?? resource.frames.first!).url
        guard resource.refreshesFrequently || cacheBuster > 0 else { return base }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "v", value: String(refreshToken))
        ]
        return components.url ?? base
    }

    /// Satellite imagery refreshes every ~5 min, so bucket the token to
    /// 5-minute windows; manual refresh always forces a new token.
    private var refreshToken: Int {
        Int(Date().timeIntervalSince1970 / 300) + cacheBuster
    }

    @ViewBuilder
    private func frameChip(_ frame: NOAAProductFrame) -> some View {
        let isSelected = (selectedFrame ?? resource.frames.first) == frame
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                selectedFrame = frame
            }
        } label: {
            Text(frame.title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? .white : .white.opacity(0.65))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(
            isSelected ? .regular.tint(.cyan.opacity(0.28)).interactive() : .regular.interactive(),
            in: .capsule
        )
    }
}

// MARK: - Zoomable image

/// UIScrollView-backed image viewer with pinch zoom, double-tap zoom, and
/// panning — the natural way to read dense NOAA charts on a phone.
struct ZoomableProductImage: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 6.0
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .clear
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = .white
        spinner.hidesWhenStopped = true
        scrollView.addSubview(spinner)
        context.coordinator.spinner = spinner

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        context.coordinator.scrollView = scrollView

        context.coordinator.load(url: url)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.layout(in: scrollView)
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.load(url: url)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: UIScrollView?
        var imageView: UIImageView?
        var spinner: UIActivityIndicatorView?
        var loadedURL: URL?
        private var loadTask: Task<Void, Never>?

        func load(url: URL) {
            loadedURL = url
            loadTask?.cancel()
            spinner?.startAnimating()
            loadTask = Task { [weak self] in
                let request = URLRequest(url: url)
                let data = try? await NetworkSessions.tiles.data(for: request).0
                guard !Task.isCancelled, let self else { return }
                await MainActor.run {
                    self.spinner?.stopAnimating()
                    guard let data, let image = UIImage(data: data) else { return }
                    self.imageView?.image = image
                    if let scrollView = self.scrollView {
                        scrollView.zoomScale = 1.0
                        self.layout(in: scrollView)
                    }
                }
            }
        }

        func layout(in scrollView: UIScrollView) {
            guard let imageView, scrollView.bounds.width > 0 else { return }
            if scrollView.zoomScale == scrollView.minimumZoomScale {
                imageView.frame = scrollView.bounds
                scrollView.contentSize = scrollView.bounds.size
            }
            if let spinner {
                spinner.center = CGPoint(x: scrollView.bounds.midX, y: scrollView.bounds.midY)
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            // Keep the image centered while zoomed out smaller than bounds.
            guard let imageView else { return }
            let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) * 0.5, 0)
            let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) * 0.5, 0)
            imageView.center = CGPoint(
                x: scrollView.contentSize.width * 0.5 + offsetX,
                y: scrollView.contentSize.height * 0.5 + offsetY
            )
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let size = CGSize(
                    width: scrollView.bounds.width / 3,
                    height: scrollView.bounds.height / 3
                )
                let rect = CGRect(
                    x: point.x - size.width / 2,
                    y: point.y - size.height / 2,
                    width: size.width,
                    height: size.height
                )
                scrollView.zoom(to: rect, animated: true)
            }
        }

        deinit { loadTask?.cancel() }
    }
}
