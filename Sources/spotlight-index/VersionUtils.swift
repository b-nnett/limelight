import Foundation

enum VersionUtils {
    static func normalized(_ version: String) -> String {
        version.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) == .orderedDescending
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = parts(lhs)
        let right = parts(rhs)
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func parts(_ version: String) -> [Int] {
        normalized(version)
            .split(separator: ".")
            .map { Int($0.filter(\.isNumber)) ?? 0 }
    }
}
