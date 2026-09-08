import Foundation

/// Device authorization uses only the public Client ID. No CLI token, secret or private key.
final class GitHubAppSession: NSObject, URLSessionTaskDelegate {
    static let shared = GitHubAppSession()
    private var token = ""
    private var expires = Date.distantPast
    private lazy var session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func logout() { token="";expires = .distantPast }
    private func request(_ url:URL, method:String="GET", body:Data?=nil, authenticated:Bool=false) throws -> Data {
        var request=URLRequest(url:url);request.httpMethod=method;request.httpBody=body;request.timeoutInterval=25
        request.setValue("application/json",forHTTPHeaderField:"Accept")
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.setValue("LeetCode-Team",forHTTPHeaderField:"User-Agent")
        if authenticated {
            guard !token.isEmpty,Date()<expires else {throw TeamError(message:"请登录 LeetCode-Team 的专用 GitHub App。会话过期后需重新授权。",status:401)}
            request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")
        }
        let signal=DispatchSemaphore(value:0)
        var result:Result<Data,Error> = .failure(TeamError(message:"GitHub 请求超时"))
        let task=session.dataTask(with:request) { data,response,error in
            defer {signal.signal()}
            if error != nil {result = .failure(TeamError(message:"无法连接 GitHub，请检查网络后重试。"));return}
            let status=(response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status),let data=data else {
                let messages=[401:"GitHub 会话已失效，请重新登录。",403:"权限不足或请求额度已用完，请检查仓库安装权限。",404:"找不到仓库或文件，请确认房主账号、App 安装及协作者邀请。",409:"提交冲突，原记录未被覆盖，请重新同步。",422:"GitHub 拒绝提交，请检查分支规则或文件冲突。"]
                result = .failure(TeamError(message:messages[status] ?? "GitHub 请求失败（HTTP \(status)）",status:status));return
            }
            result = .success(data)
        }
        task.resume();signal.wait()
        return try result.get()
    }
    func login(clientID:String, code:@escaping(String)->Void) throws {
        guard clientID.range(of:"^Iv[0-9A-Za-z_.-]{5,100}$",options:.regularExpression) != nil else {throw TeamError(message:"尚未配置专用 GitHub App 的 Client ID，请先完成项目设置。")}
        logout()
        func post(_ path:String,_ body:[String:String]) throws -> [String:Any] {
            let data=try request(URL(string:"https://github.com/"+path)!,method:"POST",body:JSONSerialization.data(withJSONObject:body))
            guard let object=try JSONSerialization.jsonObject(with:data) as? [String:Any] else {throw TeamError(message:"GitHub 授权响应无效")}
            return object
        }
        let device=try post("login/device/code",["client_id":clientID])
        guard let deviceCode=device["device_code"] as? String,let userCode=device["user_code"] as? String else {throw TeamError(message:"无法开始授权，请检查 Client ID 并启用 GitHub App 的 Device flow。")}
        let deadline=Date().addingTimeInterval(min(900,device["expires_in"] as? Double ?? 900))
        var interval=max(5,device["interval"] as? Double ?? 5)
        code(userCode)
        while Date()<deadline {
            Thread.sleep(forTimeInterval:interval)
            let response=try post("login/oauth/access_token",["client_id":clientID,"device_code":deviceCode,"grant_type":"urn:ietf:params:oauth:grant-type:device_code"])
            if let access=response["access_token"] as? String {
                guard access.hasPrefix("ghu_"),(response["scope"] as? String ?? "").isEmpty else {throw TeamError(message:"拒绝使用通用 OAuth 凭证；需要专用 GitHub App。")}
                token=access;expires=Date().addingTimeInterval(min(28800,response["expires_in"] as? Double ?? 28800))
                return
            }
            switch response["error"] as? String {
            case "authorization_pending":continue
            case "slow_down":interval=max(interval+5,response["interval"] as? Double ?? 0)
            case "access_denied":throw TeamError(message:"你已取消 GitHub 授权。")
            case "expired_token":throw TeamError(message:"授权码已过期，请重新登录。")
            default:throw TeamError(message:"GitHub 授权未完成，请检查 App 配置后重试。")
            }
        }
        throw TeamError(message:"授权码已过期，请重新登录。")
    }
    func verifyInstallationBoundary(repository: String) throws {
        func get(_ path:String) throws -> [String:Any] {
            let data=try request(URL(string:"https://api.github.com/"+path)!,authenticated:true)
            guard let object=try JSONSerialization.jsonObject(with:data) as? [String:Any] else {throw TeamError(message:"无法验证 GitHub App 安装范围")}
            return object
        }
        let response=try get("user/installations?per_page=100")
        guard let installations=response["installations"] as? [[String:Any]],
              response["total_count"] as? Int == installations.count,
              let installation=installations.first(where:{ (($0["account"] as? [String:Any])?["login"] as? String)?.lowercased() == repository.components(separatedBy:"/").first?.lowercased() }),
              installation["repository_selection"] as? String == "selected",
              let id=installation["id"] as? Int,
              let permissions=installation["permissions"] as? [String:String],
              permissions["contents"] == "write",permissions["metadata"] == "read",
              Set(permissions.keys).isSubset(of:["contents","metadata"]) else {
            throw TeamError(message:"安装范围不符合最小权限：请只选择一个小队安装，仅开仓库 Contents 读写与 Metadata 读取，不添加组织权限。")
        }
        let repositories=try get("user/installations/\(id)/repositories?per_page=100")
        guard repositories["total_count"] as? Int == 1,
              let items=repositories["repositories"] as? [[String:Any]],let repo=items.first,
              (repo["full_name"] as? String)?.lowercased() == repository.lowercased(),repo["private"] as? Bool == true else {
            throw TeamError(message:"请把 App 安装范围限制为一个私有仓库：房主/leetcode-team-sync。")
        }
    }
    func execute(_ args:[String],_ input:Data?) throws -> Data {
        guard args.count>=4,args[0]=="api" else {throw TeamError(message:"请由房主在 GitHub 网页创建私有仓库 leetcode-team-sync。")}
        let endpoint=args[3]
        guard endpoint=="user" || endpoint.range(of:"^repos/[A-Za-z0-9-]+/leetcode-team-sync(?:/contents/[A-Za-z0-9_./-]+)?$",options:.regularExpression) != nil,
              !endpoint.contains("..") else {throw TeamError(message:"请求已被限制：仅允许同步房主的 leetcode-team-sync 仓库。")}
        if endpoint.hasPrefix("repos/") && endpoint.components(separatedBy:"/").count == 3 {
            let parts=endpoint.components(separatedBy:"/")
            try verifyInstallationBoundary(repository:parts[1]+"/"+parts[2])
        }
        return try request(URL(string:"https://api.github.com/"+endpoint)!,method:input == nil ? "GET":"PUT",body:input,authenticated:true)
    }
}
