import Foundation

enum PanelSizing {
    static func maximumContentHeight(screenHeight: CGFloat, availableHeight: CGFloat, chromeHeight: CGFloat) -> CGFloat {
        max(1, floor(min(screenHeight / 2, availableHeight) - max(0, chromeHeight)))
    }

    static func viewportHeight(contentHeight: CGFloat, maximumHeight: CGFloat) -> CGFloat {
        min(max(1, contentHeight), max(1, maximumHeight))
    }

    static func needsScrolling(contentHeight: CGFloat, maximumHeight: CGFloat) -> Bool {
        contentHeight > max(1, maximumHeight) + 0.5
    }
}
