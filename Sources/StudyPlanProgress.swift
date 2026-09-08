import Foundation

/// Decode account-wide completion, including answers accepted before this plan run.
/// LeetCode's study-plan UI explicitly distinguishes SOLVED from PAST_SOLVED.
struct StudyPlanProgress {
    static let accepted: Set<String> = ["SOLVED", "PAST_SOLVED", "AC"]
    static let recognized = accepted.union(["TO_DO", "ATTEMPTED", "TRIED"])

    static func solvedQuestions(groups: [[String: Any]], catalog: Set<String>) throws -> [String] {
        guard !catalog.isEmpty else { throw invalid("本地题单为空") }
        var rows = [[String: Any]]()
        for group in groups {
            guard let questions = group["questions"] as? [[String: Any]] else {
                throw invalid("力扣返回的题目列表不完整")
            }
            rows.append(contentsOf: questions)
        }
        var seen = Set<String>(), solved = Set<String>(), unknown = Set<String>()
        for row in rows {
            guard let slug = row["titleSlug"] as? String, !slug.isEmpty else {
                throw invalid("力扣返回的题目标识缺失")
            }
            guard catalog.contains(slug) else { continue }
            guard seen.insert(slug).inserted else { throw invalid("力扣返回了重复题目") }
            guard let status = row["status"] as? String else {
                throw invalid("力扣返回的题目状态为空")
            }
            if !recognized.contains(status) { unknown.insert(status) }
            if accepted.contains(status) { solved.insert(slug) }
        }
        let missing = catalog.subtracting(seen).count
        if missing > 0 { throw invalid("力扣返回的 Hot 100 缺少 \(missing) 道题") }
        if !unknown.isEmpty {
            // Report only short enum values, never account data or the API response.
            let names = unknown.sorted().map { String($0.prefix(40)) }.joined(separator: "、")
            throw invalid("力扣返回了未识别的状态：\(names)")
        }
        return solved.sorted()
    }

    private static func invalid(_ message: String) -> NSError {
        NSError(domain: "LeetCode-Team.Progress", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message + "；已保留原进度，暂停上传"])
    }
}
