import Foundation

@main struct SidebarTests {
    static func main() {
        var state=SidebarPresentation(hidden:true)
        precondition(!state.reservesSpace)
        state.preview();precondition(state.previewing && !state.reservesSpace)
        state.dismiss();let old=state.revision
        precondition(state.canFinishDismiss(old))
        state.preview();precondition(!state.canFinishDismiss(old))
        state.dismiss();let fading=state.revision
        state.toggle();precondition(!state.hidden && state.reservesSpace && !state.previewing)
        precondition(!state.canFinishDismiss(fading),"Old completion must not hide pinned sidebar")
        state.preview();precondition(!state.previewing,"Hovering pinned sidebar is a no-op")
        state.toggle();precondition(state.hidden && !state.previewing && !state.reservesSpace)
        print("Sidebar preview, dismiss, pin, rapid re-entry and stale-animation checks passed.")
    }
}
