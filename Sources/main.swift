import Cocoa
import WebKit

let resource = Bundle.main.resourceURL!
let homeURL = URL(string: "https://leetcode.cn/studyplan/top-100-liked/")!

final class App: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    var window: NSWindow!
    var refreshAccountAfterNavigation = false
    var panel: SidebarWebView!
    var panelWidth: NSLayoutConstraint!
    var panelLeading: NSLayoutConstraint!
    var sidebarMotion: Timer?
    var motionGeneration = 0
    var chromeWidth: NSLayoutConstraint!
    var titleLeading: NSLayoutConstraint!
    var sidebar=SidebarPresentation(hidden:UserDefaults.standard.bool(forKey:"sidebarHidden"))
    var sidebarHidden: Bool {sidebar.hidden}
    var browserLeading: NSLayoutConstraint!
    var hoverDismissTimer: Timer?
    var browser: WKWebView!
    var timer: Timer?
    var questions = [[String: Any]]()
    var state: [String: Any] = ["status":"在右侧登录力扣，开始一起刷题", "username":"", "solved":[String](), "busy":false]
    let github = GitHubTeam()
    // Public app identity is supplied by the maintainer at build time, never by end users.
    let githubAppConfig = (try? JSONSerialization.jsonObject(with: Data(contentsOf: resource.appendingPathComponent("github-app.json")))) as? [String:String] ?? [:]
    var githubClientID: String {githubAppConfig["clientID"] ?? ""}
    var githubAppSlug: String {githubAppConfig["slug"] ?? ""}
    var githubConfigured: Bool {
        githubClientID.range(of:"^Iv[0-9A-Za-z_.-]{5,100}$",options:.regularExpression) != nil && githubAppSlug.range(of:"^[a-z0-9-]{1,100}$",options:.regularExpression) != nil
    }
    let githubQueue = DispatchQueue(label:"app.leetsquad.github")
    var githubLogin = ""
    var repository = UserDefaults.standard.string(forKey:"githubRepository") ?? ""
    var syncing = false
    var teamBusy = false
    var ready = false
    var lastSync: Date?
    var team: [String:Any]?

    func applicationDidFinishLaunching(_ notification: Notification) {
        questions = (try? JSONSerialization.jsonObject(with: Data(contentsOf: resource.appendingPathComponent("hot100.json")))) as? [[String:Any]] ?? []
        let menu = NSMenu(); let item = NSMenuItem(); menu.addItem(item)
        let appMenu = NSMenu(); appMenu.addItem(withTitle:"关于 LeetCode-Team", action:#selector(about), keyEquivalent:"")
        appMenu.addItem(.separator()); appMenu.addItem(withTitle:"退出 LeetCode-Team",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q"); item.submenu = appMenu
        let edit = NSMenuItem(); menu.addItem(edit); let editMenu = NSMenu(title:"编辑"); edit.submenu = editMenu
        for (title,action,key) in [("撤销","undo:","z"),("剪切","cut:","x"),("复制","copy:","c"),("粘贴","paste:","v"),("全选","selectAll:","a")] { editMenu.addItem(withTitle:title,action:Selector(action),keyEquivalent:key) }
        let viewItem=NSMenuItem(); menu.addItem(viewItem)
        let viewMenu=NSMenu(title:"显示");viewItem.submenu=viewMenu
        let toggleItem=viewMenu.addItem(withTitle:"显示/隐藏侧边栏",action:#selector(toggleSidebar),keyEquivalent:"s")
        toggleItem.keyEquivalentModifierMask=[.command,.control];toggleItem.target=self
        NSApp.mainMenu = menu
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:1440,height:920),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.delegate=self
        window.isReleasedWhenClosed = false
        window.title = "LeetCode-Team"; window.minSize = NSSize(width:900,height:620); window.center()
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false
        NSApp.applicationIconImage = NSImage(contentsOf:resource.appendingPathComponent("AppIcon.png"))
        let root = NSView(); window.contentView = root
        let localConfig = WKWebViewConfiguration(); localConfig.userContentController.add(self,name:"app")
        panel = SidebarWebView(frame:.zero,configuration:localConfig); panel.navigationDelegate = self; panel.uiDelegate = self
        let config = WKWebViewConfiguration(); config.websiteDataStore = .default()
        browser = WKWebView(frame:.zero,configuration:config); browser.navigationDelegate = self; browser.uiDelegate = self
        browser.allowsBackForwardNavigationGestures = true
        for view in [panel!,browser!] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        root.addSubview(panel,positioned:.above,relativeTo:browser)
        panel.hoverChanged = { [weak self] entered in
            if entered {self?.hoverDismissTimer?.invalidate()}
            else {self?.schedulePreviewDismiss()}
        }
        browserLeading=browser.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:sidebarHidden ? 0 : 340)
        panelWidth=panel.widthAnchor.constraint(equalToConstant:340)
        panelLeading=panel.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:sidebarHidden ? -340 : 0)
        root.wantsLayer=true;root.layer?.masksToBounds=true
        panel.isHidden=sidebarHidden
        NSLayoutConstraint.activate([panelLeading,panel.topAnchor.constraint(equalTo:root.topAnchor,constant:56),panel.bottomAnchor.constraint(equalTo:root.bottomAnchor),panelWidth,browserLeading,browser.topAnchor.constraint(equalTo:root.topAnchor,constant:56),browser.trailingAnchor.constraint(equalTo:root.trailingAnchor),browser.bottomAnchor.constraint(equalTo:root.bottomAnchor)])
        installChrome(in:root)
        panel.loadFileURL(resource.appendingPathComponent("sidebar.html"),allowingReadAccessTo:resource)
        browser.load(URLRequest(url:homeURL))
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        timer = Timer.scheduledTimer(withTimeInterval:60,repeats:true) { [weak self] _ in self?.sync() }
    }
    /// Animate constraints at a fixed sidebar width so text does not reflow during motion.
    /// A new transition starts from the visible position, including rapid reversals.
    func animateSidebar(visible: Bool, reservesSpace: Bool) {
        sidebarMotion?.invalidate();motionGeneration += 1
        let generation=motionGeneration
        let root=window.contentView!
        let startX=panelLeading.constant,startBrowser=browserLeading.constant
        let startChrome=chromeWidth.constant,startTitle=titleLeading.constant
        let startAlpha=panel.isHidden ? 0 : panel.alphaValue
        let endX:CGFloat=visible ? 0 : -340
        let endBrowser:CGFloat=reservesSpace ? 340 : 0
        let endTitle:CGFloat=reservesSpace ? 20 : 220
        panel.isHidden=false
        let duration=NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.0 : 0.24
        let start=ProcessInfo.processInfo.systemUptime
        func update(_ fraction:Double) {
            let t=CGFloat(1-pow(1-fraction,3))
            self.panelLeading.constant=startX+(endX-startX)*t
            self.browserLeading.constant=startBrowser+(endBrowser-startBrowser)*t
            self.chromeWidth.constant=startChrome+(endBrowser-startChrome)*t
            self.titleLeading.constant=startTitle+(endTitle-startTitle)*t
            self.panel.alphaValue=startAlpha+((visible ? 1 : 0)-startAlpha)*t
            root.layoutSubtreeIfNeeded()
        }
        if duration == 0 {update(1);panel.isHidden = !visible;return}
        let timer=Timer(timeInterval:1.0/60,repeats:true) { [weak self] timer in
            guard let self=self,self.motionGeneration==generation else {timer.invalidate();return}
            let fraction=min(1,(ProcessInfo.processInfo.systemUptime-start)/duration)
            update(fraction)
            if fraction >= 1 {timer.invalidate();self.sidebarMotion=nil;self.panel.isHidden = !visible}
        }
        sidebarMotion=timer;RunLoop.main.add(timer,forMode:.common)
    }
    @objc func toggleSidebar() {
        hoverDismissTimer?.invalidate()
        sidebar.toggle()
        UserDefaults.standard.set(sidebarHidden,forKey:"sidebarHidden")
        animateSidebar(visible:!sidebarHidden,reservesSpace:!sidebarHidden)
        if sidebarHidden {window.makeFirstResponder(browser)}
    }
    func showSidebarPreview() {
        guard sidebarHidden,!sidebar.previewing else {return}
        hoverDismissTimer?.invalidate()
        sidebar.preview()
        animateSidebar(visible:true,reservesSpace:false)
    }
    func schedulePreviewDismiss() {
        hoverDismissTimer?.invalidate()
        guard sidebarHidden,sidebar.previewing else {return}
        hoverDismissTimer=Timer.scheduledTimer(withTimeInterval:0.18,repeats:true) { [weak self] timer in
            guard let self=self else {timer.invalidate();return}
            guard self.sidebarHidden,self.sidebar.previewing else {timer.invalidate();return}
            if let root=self.window.contentView,self.window.isKeyWindow {
                let point=root.convert(self.window.mouseLocationOutsideOfEventStream,from:nil)
                // Include the short path between the top button and preview panel.
                let region=NSRect(x:0,y:0,width:340,height:root.bounds.height)
                if region.contains(point) {return}
            }
            timer.invalidate();self.dismissSidebarPreview()
        }
    }
    func dismissSidebarPreview() {
        guard sidebarHidden,sidebar.previewing else {return}
        sidebar.dismiss()
        animateSidebar(visible:false,reservesSpace:false)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { window.makeKeyAndOrderFront(nil) }
        return true
    }

    func windowDidResignKey(_ notification:Notification) {dismissSidebarPreview()}
    @objc func toolbarBack() {browser.goBack()}
    @objc func toolbarReload() {browser.reload()}
    @objc func toolbarSync() {sync()}
    func installChrome(in root:NSView) {
        let bar=WorkspaceChrome();bar.translatesAutoresizingMaskIntoConstraints=false;root.addSubview(bar)
        let left=WorkspaceChrome();left.sidebar=true;left.translatesAutoresizingMaskIntoConstraints=false;bar.addSubview(left)
        chromeWidth=left.widthAnchor.constraint(equalToConstant:sidebarHidden ? 0 : 340)
        NSLayoutConstraint.activate([bar.leadingAnchor.constraint(equalTo:root.leadingAnchor),bar.trailingAnchor.constraint(equalTo:root.trailingAnchor),bar.topAnchor.constraint(equalTo:root.topAnchor),bar.heightAnchor.constraint(equalToConstant:56),left.leadingAnchor.constraint(equalTo:bar.leadingAnchor),left.topAnchor.constraint(equalTo:bar.topAnchor),left.bottomAnchor.constraint(equalTo:bar.bottomAnchor),chromeWidth])
        let controls:[(NSWindow.ButtonType,Selector,String)]=[(.closeButton,#selector(NSWindow.close),"关闭窗口"),(.miniaturizeButton,#selector(NSWindow.miniaturize(_:)),"最小化"),(.zoomButton,#selector(NSWindow.toggleFullScreen(_:)),"全屏")]
        for (i,spec) in controls.enumerated() {
            if let button=window.standardWindowButton(spec.0) {
                button.removeFromSuperview();button.isHidden=false
                button.target=window;button.action=spec.1;button.toolTip=spec.2
                button.translatesAutoresizingMaskIntoConstraints=false;bar.addSubview(button)
                NSLayoutConstraint.activate([button.leadingAnchor.constraint(equalTo:bar.leadingAnchor,constant:20+CGFloat(i)*20),button.centerYAnchor.constraint(equalTo:bar.centerYAnchor),button.widthAnchor.constraint(equalToConstant:14),button.heightAnchor.constraint(equalToConstant:14)])
            }
        }
        let actions:[(String,String,Selector)]=[("sidebar.left","显示/隐藏侧边栏 (⌃⌘S)",#selector(toggleSidebar)),("chevron.left","后退",#selector(toolbarBack)),("arrow.clockwise","重新加载",#selector(toolbarReload))]
        for (i,spec) in actions.enumerated() {
            let button=SidebarHoverButton(image:NSImage(systemSymbolName:spec.0,accessibilityDescription:spec.1)!,target:self,action:spec.2)
            if i == 0 {
                button.hoverChanged = { [weak self] entered in
                    if entered {self?.showSidebarPreview()}
                    else {self?.schedulePreviewDismiss()}
                }
            }
            button.isBordered=false;button.contentTintColor = .secondaryLabelColor;button.toolTip=spec.1;button.translatesAutoresizingMaskIntoConstraints=false;bar.addSubview(button)
            NSLayoutConstraint.activate([button.leadingAnchor.constraint(equalTo:bar.leadingAnchor,constant:108+CGFloat(i)*34),button.centerYAnchor.constraint(equalTo:bar.centerYAnchor),button.widthAnchor.constraint(equalToConstant:26),button.heightAnchor.constraint(equalToConstant:28)])
        }
        let title=NSTextField(labelWithString:"Hot 100");title.font = .systemFont(ofSize:15,weight:.medium);title.translatesAutoresizingMaskIntoConstraints=false;bar.addSubview(title)
        titleLeading=title.leadingAnchor.constraint(equalTo:browser.leadingAnchor,constant:sidebarHidden ? 220 : 20)
        let sync=NSButton(image:NSImage(systemSymbolName:"arrow.triangle.2.circlepath",accessibilityDescription:"同步进度")!,target:self,action:#selector(toolbarSync));sync.isBordered=false;sync.contentTintColor = .secondaryLabelColor;sync.toolTip="同步进度";sync.translatesAutoresizingMaskIntoConstraints=false;bar.addSubview(sync)
        NSLayoutConstraint.activate([titleLeading,title.centerYAnchor.constraint(equalTo:bar.centerYAnchor),sync.trailingAnchor.constraint(equalTo:bar.trailingAnchor,constant:-20),sync.centerYAnchor.constraint(equalTo:bar.centerYAnchor),sync.widthAnchor.constraint(equalToConstant:28),sync.heightAnchor.constraint(equalToConstant:28)])
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { true }
    func applicationWillTerminate(_ notification:Notification) { timer?.invalidate(); hoverDismissTimer?.invalidate(); sidebarMotion?.invalidate() }
    @objc func about() { let a=NSAlert(); a.messageText="LeetCode-Team"; a.informativeText="Hot 100 小队刷题 · 独立第三方客户端\n题目、编辑器与判题由力扣提供。\n小队进度是成员客户端上报的账号累计通过状态。"; a.runModal() }
    func emit() {
        guard ready else { return }
        state["questions"] = questions; state["githubConfigured"] = githubConfigured;state["githubLogin"] = githubLogin; state["repository"] = repository; state["teamBusy"] = teamBusy; state["teamData"] = team ?? [:]
        if let data=try? JSONSerialization.data(withJSONObject:state), let json=String(data:data,encoding:.utf8) { panel.evaluateJavaScript("window.render(\(json))",completionHandler:nil) }
    }
    func status(_ message:String) { state["status"]=message; emit() }
    func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage) {
        guard message.webView === panel, message.frameInfo.isMainFrame,
              message.frameInfo.request.url?.standardizedFileURL == resource.appendingPathComponent("sidebar.html").standardizedFileURL,
              let body=message.body as? [String:Any],let action=body["action"] as? String else { return }
        if sidebar.previewing && action != "ready" && action != "toggleSidebar" {toggleSidebar()}
        switch action {
        case "ready": ready=true; emit()
        case "login":
            refreshAccountAfterNavigation = true
            lastSync = nil
            navigate(URL(string:"https://leetcode.cn/accounts/login/")!)
        case "plan": navigate(homeURL)
        case "toggleSidebar": toggleSidebar()
        case "back": browser.goBack()
        case "reload": browser.reload()
        case "problem":
            if let slug=body["slug"] as? String, questions.contains(where:{$0["slug"] as? String == slug}) {
                state["selected"]=slug; emit(); navigate(URL(string:"https://leetcode.cn/problems/\(slug)/?envType=study-plan-v2&envId=top-100-liked")!)
            }
        case "sync": sync()
        case "refresh": refreshTeam()
        case "githubInstall":
            guard githubConfigured else {status("此版本尚未启用 GitHub 登录，等待开发者完成配置。力扣刷题可正常使用。");return}
            NSWorkspace.shared.open(URL(string:"https://github.com/apps/"+githubAppSlug+"/installations/new")!)
        case "createRepo":NSWorkspace.shared.open(URL(string:"https://github.com/new?name=leetcode-team-sync&visibility=private")!)
        case "githubLogin":
            guard githubConfigured else {status("此版本尚未启用 GitHub 登录，等待开发者完成配置。力扣刷题可正常使用。");return}
            let client=githubClientID
            githubTask {
                try GitHubAppSession.shared.login(clientID:client) { code in DispatchQueue.main.async {
                    self.state["deviceCode"]=code;self.emit();NSWorkspace.shared.open(URL(string:"https://github.com/login/device")!)
                }}
                return try self.github.identity()
            } completion: { login in
                self.state.removeValue(forKey:"deviceCode");self.githubLogin=login;self.team=nil;self.status("已连接专用 GitHub App · @"+login);self.refreshTeam()
            }
        case "githubCheck":
            githubTask { try self.github.identity() } completion: { login in
                if self.githubLogin != login { self.team=nil };self.githubLogin=login;self.status("已连接 GitHub · @"+login);self.refreshTeam()
            }
        case "create", "join":
            guard !githubLogin.isEmpty else {status("请先连接 GitHub");return}
            let value=body["value"] as? String ?? ""
            let login=githubLogin
            githubTask {
                guard try self.github.identity() == login else {throw TeamError(message:"GitHub 账号已切换，请重新检查连接。")}
                let repo = try action == "create" ? self.github.create("leetcode-team-sync",login:login) : GitHubTeam.repoName(value)
                try self.github.validate(repo)
                return repo
            } completion: { repo in
                self.repository=repo;UserDefaults.standard.set(repo,forKey:"githubRepository")
                self.status("已连接小队仓库");self.refreshTeam()
            }
        case "repo":
            if let repo=try? GitHubTeam.repoName(repository),let url=URL(string:"https://github.com/"+repo) {NSWorkspace.shared.open(url)}
        case "invite", "removeMember":
            guard repository.components(separatedBy:"/").first?.lowercased() == githubLogin.lowercased(), !githubLogin.isEmpty else {status("只有房主可以邀请或移除成员。");return}
            if action == "removeMember" {
                guard let member=body["member"] as? String, member != githubLogin,
                      member.range(of:"^[A-Za-z0-9][A-Za-z0-9-]{0,38}$",options:.regularExpression) != nil else {return}
                status("请在 GitHub 管理页移除 @"+member+"；完成后其仓库访问权限将撤销，历史进度仍保留。")
            } else {status("请在 GitHub 添加指定账号；每份邀请只能由该账号接受。")}
            if let repo=try? GitHubTeam.repoName(repository),let url=URL(string:"https://github.com/"+repo+"/settings/access") {NSWorkspace.shared.open(url)}
        case "copy":
            guard !repository.isEmpty else {return}
            NSPasteboard.general.clearContents();NSPasteboard.general.setString("https://github.com/"+repository,forType:.string);status("仓库链接已复制；队友需先接受 GitHub 邀请")
        case "leave":
            guard !teamBusy else {return}
            repository="";team=nil;UserDefaults.standard.removeObject(forKey:"githubRepository");status("已断开仓库，已提交的共享记录保留在 GitHub")
        default:break
        }
    }
    func navigate(_ url:URL) { browser.load(URLRequest(url:url)) }
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) {
        if webView === browser { status("页面已加载 · 登录后点击同步进度"); if refreshAccountAfterNavigation || lastSync == nil || Date().timeIntervalSince(lastSync!)>20 { sync() } }
    }
    func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error) {
        if (error as NSError).code != NSURLErrorCancelled { status("页面未能加载：\(error.localizedDescription)。可点击重载重试。") }
    }
    func webView(_ webView:WKWebView,decidePolicyFor navigationAction:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void) {
        guard let url=navigationAction.request.url else {decisionHandler(.cancel);return}
        if webView === panel { decisionHandler(url.isFileURL && url.standardizedFileURL.path.hasPrefix(resource.standardizedFileURL.path+"/") ? .allow:.cancel); return }
        if ["https","http","about"].contains(url.scheme ?? "") { decisionHandler(.allow) } else { decisionHandler(.cancel) }
    }
    func webView(_ webView:WKWebView,createWebViewWith configuration:WKWebViewConfiguration,for navigationAction:WKNavigationAction,windowFeatures:WKWindowFeatures)->WKWebView? {
        // Preserve in-app login flows and their opener relationship, including OAuth popups.
        let popup=WKWebView(frame:NSRect(x:0,y:0,width:680,height:760),configuration:configuration)
        popup.navigationDelegate=self; popup.uiDelegate=self
        let w=NSWindow(contentRect:popup.frame,styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        w.isReleasedWhenClosed=false; w.title="力扣登录 / 链接"; w.contentView=popup; w.center(); w.makeKeyAndOrderFront(nil)
        popups.append(w); return popup
    }
    var popups=[NSWindow]()
    func webViewDidClose(_ webView:WKWebView) { if let i=popups.firstIndex(where:{$0.contentView === webView}) {popups[i].close();popups.remove(at:i);sync()} }
    func webView(_ webView:WKWebView,runJavaScriptAlertPanelWithMessage message:String,initiatedByFrame frame:WKFrameInfo,completionHandler:@escaping()->Void) { let a=NSAlert();a.messageText=message;a.runModal();completionHandler() }
    func webView(_ webView:WKWebView,runJavaScriptConfirmPanelWithMessage message:String,initiatedByFrame frame:WKFrameInfo,completionHandler:@escaping(Bool)->Void) {let a=NSAlert();a.messageText=message;a.addButton(withTitle:"确定");a.addButton(withTitle:"取消");completionHandler(a.runModal() == .alertFirstButtonReturn)}
    func sync() {
        guard !syncing else{return}
        guard browser.url?.host == "leetcode.cn",!browser.isLoading else { refreshTeam(); return }
        syncing=true; state["busy"]=true;status("正在读取力扣通过状态…")
        let script = """
        if (location.origin !== 'https://leetcode.cn') throw Error('请返回力扣页面');
        const controller = new AbortController(); const timeout = setTimeout(()=>controller.abort(),20000);
        try {
          const csrf = document.cookie.split('; ').find(x=>x.startsWith('csrftoken='));
          const response = await fetch('/graphql/', {method:'POST',credentials:'same-origin',cache:'no-store',signal:controller.signal,
            headers:{'Content-Type':'application/json',...(csrf?{'X-CSRFToken':decodeURIComponent(csrf.slice(10))}:{})},
            body:JSON.stringify({query:'query { userStatus { isSignedIn username userSlug realName } studyPlanV2Detail(planSlug: "top-100-liked") { planSubGroups { questions { titleSlug status } } } }'})});
          if (!response.ok) throw Error('力扣返回 HTTP '+response.status);
          const result = await response.json(); if(result.errors) throw Error('力扣接口已变化或暂不可用');
          return result.data;
        } finally { clearTimeout(timeout); }
        """
        browser.callAsyncJavaScript(script,arguments:[:],in:nil,in:.defaultClient) { [weak self] result in
            guard let self=self else{return};self.syncing=false;self.state["busy"]=false;self.lastSync=Date()
            switch result {
            case .failure(let e):self.status("同步失败，保留上次进度：\(e.localizedDescription)");self.refreshTeam(silent:true)
            case .success(let value):
                guard let data=value as? [String:Any],let user=data["userStatus"] as? [String:Any],user["isSignedIn"] as? Bool == true else {
                    self.state["displayName"]="";self.state["username"]="";self.state["solved"]=[String]();self.status("尚未登录力扣 · 请在右侧完成登录");self.refreshTeam(silent:true);return
                }
                let displayName = (user["realName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                self.state["displayName"] = displayName
                self.refreshAccountAfterNavigation = false
                self.emit()
                guard let plan=data["studyPlanV2Detail"] as? [String:Any],let groups=plan["planSubGroups"] as? [[String:Any]] else {self.status("力扣未返回题单状态，保留上次进度");return}
                let username=(user["userSlug"] as? String) ?? (user["username"] as? String) ?? ""
                let known=Set(self.questions.compactMap{$0["slug"] as? String})
                let solved: [String]
                do {
                    solved = try StudyPlanProgress.solvedQuestions(groups: groups, catalog: known)
                } catch {
                    self.status(error.localizedDescription)
                    return
                }
                self.state["username"]=username;self.state["solved"]=solved
                let f=DateFormatter();f.dateFormat="HH:mm";self.state["syncedAt"]=f.string(from:Date())
                self.status("已同步 · \(solved.count)/100 题通过")
                self.refreshTeam()
            }
        }
    }
    func githubTask<T>(_ work:@escaping () throws -> T, completion:@escaping (T)->Void) {
        guard !teamBusy else {return};teamBusy=true;state["teamStatus"]="正在连接 GitHub…";emit()
        githubQueue.async {
            let result=Result {try work()}
            DispatchQueue.main.async {
                self.teamBusy=false;self.state.removeValue(forKey:"deviceCode")
                switch result {
                case .success(let value):self.state["teamStatus"]="";completion(value)
                case .failure(let error):
                    self.state["teamStatus"]=error.localizedDescription;self.status(error.localizedDescription)
                    if let rename=error as? AccountRenameConfirmation {
                        let repo=self.repository, login=self.githubLogin
                        let alert=NSAlert();alert.messageText="这是同一个力扣账号改名了吗？"
                        alert.informativeText="已共享标识："+rename.previous+"\n当前标识："+rename.current+"\n\n旧记录没有不可变账号 ID，无法自动区分改名和换号。确认后仅更新你自己的成员记录及当前通过进度，历史版本仍保留在 GitHub。若切换了账号，请取消。"
                        alert.addButton(withTitle:"是同一账号，更新记录");alert.addButton(withTitle:"取消")
                        if alert.runModal() == .alertFirstButtonReturn,
                           self.repository == repo, self.githubLogin == login,
                           self.state["username"] as? String == rename.current {
                            self.refreshTeam(confirmedPreviousUsername:rename.previous)
                        }
                    }
                }
                self.emit()
            }
        }
    }
    func refreshTeam(silent:Bool=false, confirmedPreviousUsername:String?=nil) {
        guard !githubLogin.isEmpty,!repository.isEmpty,!teamBusy else {return}
        let repo=repository,login=githubLogin,catalog=Set(questions.compactMap{$0["slug"] as? String})
        // Only upload a successfully validated, currently signed-in LeetCode snapshot.
        let progress: [String:Any]? = (!silent && !(state["username"] as? String ?? "").isEmpty) ? ["username":state["username"]!,"solved":state["solved"]!] : nil
        githubTask {
            guard try self.github.identity() == login else {throw TeamError(message:"GitHub 账号已切换，请重新检查连接。")}
            return try self.github.snapshot(repo,login:login,catalog:catalog,progress:progress,confirmedPreviousUsername:confirmedPreviousUsername)
        } completion: { data in
            guard self.repository==repo,self.githubLogin==login else {return}
            self.team=data;self.state["teamStatus"]="已同步 GitHub";self.emit()
        }
    }
}
let app=NSApplication.shared
let delegate=App();app.delegate=delegate;app.setActivationPolicy(.regular);app.run()
