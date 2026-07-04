import AppKit
import SwiftUI

/// AppKit bridge for SwiftUI scroll views that must not inherit macOS' chunky
/// legacy scrollers when System Settings is set to always show scroll bars.
enum ScrollChrome {
    static func hideNativeScrollers(from view: NSView, attempts: Int = 4) {
        configureNearestScrollView(from: view)

        guard attempts > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            hideNativeScrollers(from: view, attempts: attempts - 1)
        }
    }

    private static func configureNearestScrollView(from view: NSView) {
        var current: NSView? = view
        while let candidate = current {
            if let scrollView = candidate as? NSScrollView {
                configure(scrollView)
                return
            }
            current = candidate.superview
        }
    }

    static func configure(_ scrollView: NSScrollView) {
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScroller = nil
        scrollView.horizontalScrollElasticity = .none

        scrollView.hasVerticalScroller = false
        scrollView.verticalScroller = nil
        scrollView.verticalScrollElasticity = .automatic

        let zeroInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.contentInsets = zeroInsets
        scrollView.scrollerInsets = zeroInsets
    }
}
