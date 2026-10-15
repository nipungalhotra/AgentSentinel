import Foundation
import AppKit

// MARK: - Island Display Mode

public enum IslandDisplayMode: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Physical notch mode on MacBook Pro/Air screens (safeAreaInsets.top > 0)
    case physicalNotch = "Physical Camera Notch"
    /// Universal floating island for external displays, Mac mini/Studio, Windows & Linux
    case floatingIsland = "Universal Floating Island"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .physicalNotch: return "laptopcomputer"
        case .floatingIsland: return "display"
        }
    }
}

// MARK: - Island Screen Geometry

@MainActor
public struct IslandScreenGeometry: Sendable {
    public let mode: IslandDisplayMode
    public let isNotchPresent: Bool
    public let notchWidth: CGFloat
    public let notchHeight: CGFloat
    public let screenFrame: NSRect
    public let topAnchorY: CGFloat
    public let centerX: CGFloat

    public init(screen: NSScreen) {
        let safeAreaTop = screen.safeAreaInsets.top
        let auxLeft = screen.auxiliaryTopLeftArea?.width ?? 0
        let auxRight = screen.auxiliaryTopRightArea?.width ?? 0

        // Detect physical MacBook notch
        if safeAreaTop > 0 && (auxLeft > 0 || auxRight > 0) {
            self.isNotchPresent = true
            self.mode = .physicalNotch
            self.notchHeight = max(safeAreaTop, 32)
            let calculatedWidth = screen.frame.width - auxLeft - auxRight
            self.notchWidth = calculatedWidth > 50 ? calculatedWidth : 180
            self.screenFrame = screen.frame
            self.topAnchorY = screen.frame.maxY
            self.centerX = screen.frame.midX
        } else {
            // Universal Floating Island fallback (Windows, Linux, external Mac displays)
            self.isNotchPresent = false
            self.mode = .floatingIsland
            self.notchWidth = 164
            self.notchHeight = 32
            self.screenFrame = screen.frame
            let menuBarOffset: CGFloat = (NSApplication.shared.mainMenu != nil) ? 26 : 0
            self.topAnchorY = screen.frame.maxY - menuBarOffset - 10
            self.centerX = screen.frame.midX
        }
    }

    /// Calculate the panel frame for the current unfolding animation phase
    public func frame(forContentSize size: CGSize, margin: CGFloat, morphProgress: CGFloat) -> NSRect {
        let targetWidth = size.width + margin * 2
        let targetHeight = size.height + margin * 2

        if mode == .physicalNotch {
            // Unfolds downward directly from the camera notch cutout
            let currentWidth = notchWidth + (targetWidth - notchWidth) * morphProgress
            let currentHeight = notchHeight + (targetHeight - notchHeight) * morphProgress
            let x = centerX - currentWidth / 2
            let y = topAnchorY + margin - currentHeight
            return NSRect(x: x, y: y, width: currentWidth, height: currentHeight)
        } else {
            // Universal Floating Island: Expands symmetrically with top anchor
            let currentWidth = notchWidth + (targetWidth - notchWidth) * morphProgress
            let currentHeight = notchHeight + (targetHeight - notchHeight) * morphProgress
            let x = centerX - currentWidth / 2
            let y = topAnchorY + margin - currentHeight
            return NSRect(x: x, y: y, width: currentWidth, height: currentHeight)
        }
    }
}
