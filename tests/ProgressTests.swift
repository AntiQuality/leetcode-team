import Foundation

@main struct ProgressTests {
    static func main() throws {
        let catalog: Set<String> = ["two-sum", "group-anagrams", "longest-consecutive-sequence"]
        func groups(_ states: [Any]) -> [[String: Any]] {
            [["questions": zip(catalog.sorted(), states).map { ["titleSlug": $0.0, "status": $0.1] as [String: Any] }]]
        }
        func rejected(_ data: [[String: Any]], _ fragment: String) {
            do {
                _ = try StudyPlanProgress.solvedQuestions(groups: data, catalog: catalog)
                fatalError("Expected rejection: \(fragment)")
            } catch {
                precondition(error.localizedDescription.contains(fragment), error.localizedDescription)
            }
        }
        let sorted = catalog.sorted()
        let actual = try StudyPlanProgress.solvedQuestions(groups: groups(["PAST_SOLVED", "SOLVED", "TO_DO"]), catalog: catalog)
        precondition(actual == Array(sorted.prefix(2)), "Both historical and current completions must count")
        let none = try StudyPlanProgress.solvedQuestions(groups: groups(["TO_DO", "ATTEMPTED", "TRIED"]), catalog: catalog)
        precondition(none.isEmpty)
        let all = try StudyPlanProgress.solvedQuestions(groups: groups(["PAST_SOLVED", "PAST_SOLVED", "PAST_SOLVED"]), catalog: catalog)
        precondition(all.count == 3)
        rejected(groups(["SOLVED", "NEW_STATE", "TO_DO"]), "NEW_STATE")
        rejected(groups(["SOLVED", "TO_DO"]), "缺少 1 道题")
        rejected(groups(["SOLVED", NSNull(), "TO_DO"]), "状态为空")
        rejected([["questions": "malformed"]], "列表不完整")
        rejected([["questions": [["titleSlug": "two-sum", "status": "SOLVED"], ["titleSlug": "two-sum", "status": "TO_DO"]]]], "重复题目")
        // Full Hot 100 regression: only the first day's three answers have past-solved status.
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let fullCatalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
        let fullRows = fullCatalog.enumerated().map { ["titleSlug": $0.element["slug"]!, "status": $0.offset < 3 ? "PAST_SOLVED" : "TO_DO"] }
        let result = try StudyPlanProgress.solvedQuestions(groups: [["questions": fullRows]], catalog: Set(fullCatalog.compactMap{$0["slug"] as? String}))
        precondition(result.count == 3)
        print("9 progress regression checks passed (including full Hot 100 day-one fixture).")
    }
}
