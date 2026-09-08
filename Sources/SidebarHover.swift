import Cocoa
import WebKit

final class SidebarHoverButton: NSButton {
    var hoverChanged: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area=hoverArea {removeTrackingArea(area)}
        let area=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self,userInfo:nil)
        addTrackingArea(area);hoverArea=area
    }
    override func mouseEntered(with event:NSEvent) {hoverChanged?(true)}
    override func mouseExited(with event:NSEvent) {hoverChanged?(false)}
}

final class SidebarWebView: WKWebView {
    var hoverChanged: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area=hoverArea {removeTrackingArea(area)}
        let area=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self,userInfo:nil)
        addTrackingArea(area);hoverArea=area
    }
    override func mouseEntered(with event:NSEvent) {hoverChanged?(true)}
    override func mouseExited(with event:NSEvent) {hoverChanged?(false)}
}

/// Animation completions must not hide a sidebar pinned during an earlier fade.
struct SidebarPresentation {
    var hidden: Bool
    private(set) var previewing=false
    private(set) var revision=0
    var reservesSpace: Bool {!hidden}
    mutating func preview() {
        guard hidden else {return}
        previewing=true;revision+=1
    }
    mutating func dismiss() {
        previewing=false;revision+=1
    }
    mutating func toggle() {
        hidden.toggle();previewing=false;revision+=1
    }
    func canFinishDismiss(_ oldRevision:Int)->Bool {
        oldRevision==revision && hidden && !previewing
    }
}
