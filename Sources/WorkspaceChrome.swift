import Cocoa

/// A titlebar surface which continues the sidebar background without a separator.
/// Controls remain native AppKit buttons, including macOS traffic lights.
final class WorkspaceChrome: NSView {
    var sidebar = false
    override var mouseDownCanMoveWindow: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
        let color: NSColor
        if sidebar {
            color = dark ? NSColor(srgbRed:37/255,green:37/255,blue:39/255,alpha:1) : NSColor(srgbRed:245/255,green:245/255,blue:247/255,alpha:1)
        } else { color = dark ? NSColor(srgbRed:30/255,green:30/255,blue:32/255,alpha:1) : .white }
        color.setFill(); dirtyRect.fill()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance();needsDisplay=true }
    override func mouseDown(with event:NSEvent) {
        if event.clickCount == 2 { window?.performZoom(nil) }
        else {window?.performDrag(with:event)}
    }
}
