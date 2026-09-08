import Foundation
@main struct GitHubTests {
    static func main() throws {
        var files: [String: [String: Any]] = [".leetcode-team.json": ["schemaVersion":1,"studyPlan":"top-100-liked"]]
        var writes = [String](), privateRepo = true, conflict = false, missingDirectory = false, push = true
        func data(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
        let github = GitHubTeam { args, input in
            let endpoint=args[3]
            if endpoint == "repos/host/leetcode-team-sync" { return try data(["private":privateRepo,"permissions":["push":push]] as [String:Any]) }
            let path=String(endpoint.dropFirst("repos/host/leetcode-team-sync/contents/".count))
            if let input=input {
                if conflict { throw TeamError(message:"conflict") }
                let request=try JSONSerialization.jsonObject(with:input) as! [String:Any]
                if files[path] != nil {precondition(request["sha"] as? String == "sha")}
                let content=Data(base64Encoded:request["content"] as! String)!
                files[path]=try JSONSerialization.jsonObject(with:content) as? [String:Any];writes.append(path);if path.hasPrefix("members/") {missingDirectory=false}
                return try data(["content":[String:String]()])
            }
            if path == "members" && missingDirectory {throw TeamError(message:"Not Found",status:404)}
            if path == "members" { return try data(files.keys.filter{$0.hasPrefix("members/")}.map{["name":String($0.dropFirst(8))]}) }
            guard let file=files[path] else {throw TeamError(message:"missing",status:404)}
            return try data(["content":try data(file).base64EncodedString(),"sha":"sha"])
        }
        func rejected(_ operation: () throws -> Void) { do {try operation();fatalError("Expected rejection")} catch {} }
        let normalized = try GitHubTeam.repoName("https://github.com/host/leetcode-team-sync"); precondition(normalized == "host/leetcode-team-sync")
        rejected {_ = try GitHubTeam.repoName("host/../other")}
        rejected {_ = try GitHubTeam.repoName("host/another-repo")}
        privateRepo=false
        rejected {_ = try github.snapshot("host/leetcode-team-sync",login:"alice",catalog:["two-sum"],progress:["username":"lc","solved":["two-sum"]])}
        precondition(writes.isEmpty);privateRepo=true
        push=false;rejected {try github.validate("host/leetcode-team-sync")};push=true
        missingDirectory=true
        let progress:[String:Any] = ["username":"lc","solved":["two-sum"]]
        _ = try github.snapshot("host/leetcode-team-sync",login:"alice",catalog:["two-sum"],progress:progress)
        precondition(writes == ["members/alice.json"])
        _ = try github.snapshot("host/leetcode-team-sync",login:"alice",catalog:["two-sum"],progress:progress)
        precondition(writes.count == 1,"Unchanged progress must not create a commit")
        rejected {_ = try github.snapshot("host/leetcode-team-sync",login:"alice",catalog:["two-sum"],progress:["username":"other","solved":[String]()])}
        let renameProgress:[String:Any] = ["username":"renamed","solved":["two-sum"]]
        rejected {_ = try github.snapshot("host/leetcode-team-sync",login:"alice",catalog:["two-sum"],progress:renameProgress,confirmedPreviousUsername:"wrong-old-name")}
        _ = try github.snapshot("host/leetcode-team-sync",login:"alice",catalog:["two-sum"],progress:renameProgress,confirmedPreviousUsername:"lc")
        precondition(files["members/alice.json"]?["username"] as? String == "renamed")
        precondition(writes.count == 2, "Rename must write even when progress is unchanged")
        _ = try github.snapshot("host/leetcode-team-sync",login:"alice",catalog:["two-sum"],progress:renameProgress)
        precondition(writes.count == 2)
        rejected {_ = try github.snapshot("host/leetcode-team-sync",login:"alice",catalog:["two-sum"],progress:progress,confirmedPreviousUsername:"lc")}
        files["members/alice.json"]?["username"]="lc";writes.removeLast()
        conflict=true
        rejected {_ = try github.snapshot("host/leetcode-team-sync",login:"alice",catalog:["two-sum"],progress:["username":"lc","solved":[String]()])}
        precondition(writes.count == 1);conflict=false
        files["members/bob.json"]=["schemaVersion":1,"studyPlan":"top-100-liked","github":"alice","username":"b","solved":[String](),"updated":0]
        rejected {_ = try github.snapshot("host/leetcode-team-sync",login:"alice",catalog:["two-sum"])}
        files=[:];writes=[];missingDirectory=true
        _ = try github.create("leetcode-team-sync",login:"host")
        precondition(writes == [".leetcode-team.json"])
        _ = try github.snapshot("host/leetcode-team-sync",login:"alice",catalog:["two-sum"],progress:progress)
        precondition(writes == [".leetcode-team.json","members/alice.json"])
        let saved=files;let written=writes.count
        _ = try github.create("leetcode-team-sync",login:"host")
        precondition(writes.count == written && files.count == saved.count)
        files.removeValue(forKey:".leetcode-team.json")
        _ = try github.create("leetcode-team-sync",login:"host")
        precondition(writes.count == written+1)
        files[".leetcode-team.json"]=["schemaVersion":9,"studyPlan":"different"]
        rejected {_ = try github.create("leetcode-team-sync",login:"host")}
        precondition(writes.count == written+1)
        print("GitHub checks passed: creation retry and incompatible marker protection, create, missing member directory, write permission, private repository, paths, per-user file, no-op, account switch, conflict and malformed member.")
    }
}
