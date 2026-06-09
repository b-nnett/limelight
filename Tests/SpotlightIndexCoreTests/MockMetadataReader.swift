import Foundation
@testable import SpotlightIndexCore

struct MockMetadataReader: SpotlightMetadataReading {
    let path: String?
    let values: [String: Any]

    func value(for attribute: String) -> Any? {
        values[attribute]
    }
}
