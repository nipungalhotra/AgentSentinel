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
        } else {
            self.isNotchPresent = false
            self.mode = .floatingIsland
            self.notchWidth = 164
            self.notchHeight = 32
        }

        // Camera/Notch bottom anchor calculation
        // On notched MacBooks: directly below safeAreaTop notch cutout
        // On external/non-notched displays: directly below the menu bar
        let cameraBottomY = (safeAreaTop > 0)
            ? (screen.frame.maxY - safeAreaTop)
            : screen.visibleFrame.maxY

        self.screenFrame = screen.frame
        self.topAnchorY = cameraBottomY - (safeAreaTop > 0 ? 4 : 8)
        self.centerX = screen.frame.midX
    }

    /// Calculate the panel frame centered directly below the camera
    public func frame(forContentSize size: CGSize, margin: CGFloat = 0, morphProgress: CGFloat = 1.0) -> NSRect {
        let finalWidth = size.width
        let finalHeight = size.height

        let currentWidth = (mode == .physicalNotch)
            ? (notchWidth + (finalWidth - notchWidth) * morphProgress)
            : finalWidth
        let currentHeight = (mode == .physicalNotch)
            ? (notchHeight + (finalHeight - notchHeight) * morphProgress)
            : finalHeight

        let x = centerX - (currentWidth / 2)
        let y = topAnchorY - currentHeight

        return NSRect(x: x, y: y, width: currentWidth, height: currentHeight)
    }
}
