import Foundation

/// One current app/window label only, not a cache indexed by applications or windows.
struct AppLabelRenderer {
    private var name: String?
    private var title: String?
    private var width: CGFloat?
    private var fitted = ""
    private let fit: (String, CGFloat) -> String

    init(fit: @escaping (String, CGFloat) -> String = AppLabelLayout.fit) {
        self.fit = fit
    }

    static func normalizedTitle(_ raw: String) -> String {
        let frames = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
        guard let first = raw.first, frames.contains(first), raw.dropFirst().first == " " else { return raw }
        let content = raw.dropFirst(2)
        return content.isEmpty ? raw : String(content)
    }

    mutating func render(_ snapshot: NativeAppSnapshot, width: CGFloat) -> NativeAppPresentation {
        let content = Self.normalizedTitle(snapshot.windowTitle)
        if name != snapshot.name || title != content || self.width != width {
            fitted = AppLabelLayout.combine(name: snapshot.name, title: content, width: width, fit: fit)
            name = snapshot.name
            title = content
            self.width = width
        }
        return NativeAppPresentation(app: snapshot.app, label: fitted)
    }
}
