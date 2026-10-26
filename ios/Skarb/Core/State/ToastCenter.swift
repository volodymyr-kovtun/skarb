import Foundation
import Observation

/// The one-line message that slides in over the tab bar — "Synced", "Rule saved · 12 re-filed".
@Observable
final class ToastCenter {
    struct Toast: Equatable, Identifiable {
        var id = UUID()
        var message: String
        var isError = false
        /// Set when the action behind this toast can be taken back, e.g. "Undo".
        var undoLabel: String?

        // The work behind the label lives in `undoAction`; identity is all the view needs.
        static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }

        /// Long enough to read a count and reach for Undo, short enough not to linger.
        var lifetime: Duration { undoLabel != nil ? .seconds(9) : (isError ? .seconds(5) : .seconds(2.5)) }
    }

    private(set) var current: Toast?
    /// How far above the bottom edge the toast floats. The floating tab bar needs room by default;
    /// the bulk-edit bar, which replaces the tab bar while it is up, needs more.
    var clearance: CGFloat = ToastCenter.tabBarClearance

    static let tabBarClearance: CGFloat = 96
    static let bulkBarClearance: CGFloat = 150

    /// What the current toast's undo button runs. Cleared with the toast.
    @ObservationIgnored private var undoAction: (() async -> Void)?

    func show(_ message: String, isError: Bool = false) {
        undoAction = nil
        current = Toast(message: message, isError: isError)
    }

    /// A toast with a way back — used where one tap rewrote a pile of transactions.
    func show(_ message: String, undoLabel: String = "Undo", undo: @escaping () async -> Void) {
        undoAction = undo
        current = Toast(message: message, undoLabel: undoLabel)
    }

    /// An error, unless it was the app abandoning a request it no longer wanted.
    func show(_ error: Error) {
        guard !error.isCancellation else { return }
        show(error.localizedDescription, isError: true)
    }

    func runUndo() async {
        let action = undoAction
        dismiss()
        await action?()
    }

    func dismiss() {
        undoAction = nil
        current = nil
    }
}
