import Foundation

struct TeamError: LocalizedError {
    let message: String
    var status: Int? = nil
    var errorDescription: String? { message }
}

struct AccountRenameConfirmation: LocalizedError {
    let previous: String
    let current: String
    var errorDescription: String? { "力扣主页标识已变化，请确认是否为同一账号改名。" }
}

/// Repository transport is authenticated exclusively through the dedicated GitHub App.
final class GitHubTeam {
    typealias Transport = ([String], Data?) throws -> Data
    let run: Transport
    init(run: @escaping Transport = GitHubTeam.execute) { self.run = run }
    static func execute(_ arguments: [String], _ input: Data?) throws -> Data {
        try GitHubAppSession.shared.execute(arguments,input)
    }
    func api(_ endpoint: String, body: [String: Any]? = nil) throws -> Any {
        var args = ["api", "--hostname", "github.com", endpoint]
        var input: Data?
        if let body = body { args += ["--method", "PUT", "--input", "-"]; input = try JSONSerialization.data(withJSONObject: body) }
        return try JSONSerialization.jsonObject(with: run(args, input))
    }
    static func repoName(_ value: String) throws -> String {
        var value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("https://github.com/") { value = String(value.dropFirst(19)) }
        if value.hasSuffix("/") { value.removeLast() }
        guard value.range(of: "^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9_.-]{1,100}$", options: .regularExpression) != nil,
              !value.hasSuffix("/.."), !value.hasSuffix("/.") else { throw TeamError(message: "请输入 owner/repo 或 GitHub 仓库网址。") }
        guard value.components(separatedBy:"/").last == "leetcode-team-sync" else {throw TeamError(message:"只允许连接 房主/leetcode-team-sync。") }
        return value
    }
    func identity() throws -> String {
        guard let user = try api("user") as? [String: Any], let login = user["login"] as? String,
              login.range(of: "^[A-Za-z0-9][A-Za-z0-9-]{0,38}$", options: .regularExpression) != nil else {
            throw TeamError(message: "请先完成 GitHub 登录，再检查连接。")
        }
        return login
    }
    func validate(_ repo: String, marker: Bool = true) throws {
        _ = try Self.repoName(repo)
        guard let data = try api("repos/\(repo)") as? [String: Any], data["private"] as? Bool == true,
              let permissions = data["permissions"] as? [String: Any], permissions["push"] as? Bool == true else {
            throw TeamError(message: "需要私有仓库的写权限。请让房主邀请你，并先在 GitHub 接受邀请。")
        }
        if marker {
            let file = try read(repo, ".leetcode-team.json")
            guard file.object["schemaVersion"] as? Int == 1, file.object["studyPlan"] as? String == "top-100-liked" else {
                throw TeamError(message: "这个仓库不是 LeetCode-Team 的 Hot 100 小队仓库。")
            }
        }
    }
    func read(_ repo: String, _ path: String) throws -> (object: [String: Any], sha: String) {
        guard let file = try api("repos/\(repo)/contents/\(path)") as? [String: Any],
              let content = file["content"] as? String, let sha = file["sha"] as? String,
              let data = Data(base64Encoded: content, options: .ignoreUnknownCharacters), data.count < 100_000,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TeamError(message: "仓库中的进度文件格式不正确，已停止同步。")
        }
        return (object, sha)
    }
    func write(_ repo: String, _ path: String, object: [String: Any], sha: String? = nil) throws {
        let content = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).base64EncodedString()
        var body: [String: Any] = ["message": "Update LeetCode-Team progress", "content": content]
        if let sha = sha { body["sha"] = sha }
        _ = try api("repos/\(repo)/contents/\(path)", body: body)
    }
    func create(_ name: String, login: String) throws -> String {
        let repo = try Self.repoName(login + "/" + name)
        try validate(repo,marker:false)
        do {try validate(repo)} catch let error as TeamError where error.status == 404 {
            try write(repo,".leetcode-team.json",object:["schemaVersion":1,"studyPlan":"top-100-liked"])
        }
        return repo
    }
    func snapshot(_ repo: String, login: String, catalog: Set<String>, progress: [String: Any]? = nil, confirmedPreviousUsername: String? = nil) throws -> [String: Any] {
        for attempt in 0..<3 {
            do {return try snapshotAttempt(repo,login:login,catalog:catalog,progress:progress,confirmedPreviousUsername:confirmedPreviousUsername)}
            catch let error as TeamError where error.status == 409 {
                if attempt == 2 {throw TeamError(message:"仓库仍在被其他客户端更新，已保留原记录；请关闭重复打开的旧版客户端后同步。",status:409)}
            }
        }
        throw TeamError(message:"同步重试已结束")
    }
    private func snapshotAttempt(_ repo:String, login:String, catalog:Set<String>, progress:[String:Any]?, confirmedPreviousUsername:String?) throws -> [String:Any] {
        try validate(repo)
        let entries: [[String: Any]]
        do {
            guard let listing = try api("repos/\(repo)/contents/members") as? [[String: Any]], listing.count <= 100 else {
                throw TeamError(message: "成员目录不可用，或超过 100 个文件。")
            }
            entries = listing
        } catch let error as TeamError where error.status == 404 {
            // A newly initialized team has no member directory until its first upload.
            entries = []
        }
        var members = [[String: Any]](), mine: (object: [String: Any], sha: String)?
        for entry in entries {
            guard let name = entry["name"] as? String,
                  name.range(of: "^[A-Za-z0-9][A-Za-z0-9-]{0,38}\\.json$", options: .regularExpression) != nil else { continue }
            let file = try read(repo, "members/" + name)
            let memberLogin = String(name.dropLast(5))
            guard file.object["schemaVersion"] as? Int == 1,
                  file.object["github"] as? String == memberLogin,
                  file.object["studyPlan"] as? String == "top-100-liked",
                  let solved = file.object["solved"] as? [String], Set(solved).isSubset(of: catalog),
                  let username = file.object["username"] as? String, username.count <= 100,
                  let updated = file.object["updated"] as? Double, updated.isFinite else {
                throw TeamError(message: "成员进度格式不正确，已保留上次记录。")
            }
            if memberLogin == login { mine = file }
            var member = file.object; member["id"] = memberLogin; member["nickname"] = memberLogin
            members.append(member)
        }
        if let progress = progress, let username = progress["username"] as? String, !username.isEmpty,
           let solved = progress["solved"] as? [String], Set(solved).isSubset(of: catalog) {
            if let previous = mine?.object["username"] as? String, previous != username, confirmedPreviousUsername != previous {
                throw AccountRenameConfirmation(previous: previous, current: username)
            }
            // Hot 100 is cumulative: an older local snapshot must never erase remote completions.
            let solved = Array(Set(solved).union(mine?.object["solved"] as? [String] ?? [])).sorted()
            if mine == nil || mine?.object["username"] as? String != username || Set(mine?.object["solved"] as? [String] ?? []) != Set(solved) {
                let object: [String: Any] = ["schemaVersion": 1, "studyPlan": "top-100-liked", "github": login, "username": username, "solved": solved.sorted(), "updated": Date().timeIntervalSince1970]
                try write(repo, "members/\(login).json", object: object, sha: mine?.sha)
                var member = object; member["id"] = login; member["nickname"] = login
                members.removeAll { $0["id"] as? String == login }; members.append(member)
            }
        }
        return ["team": ["name": repo.components(separatedBy: "/").last!, "code": repo], "members": members.sorted { ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "") }, "me": login]
    }
}
