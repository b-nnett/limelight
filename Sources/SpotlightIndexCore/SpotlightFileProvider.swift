import CoreServices
import Foundation

struct SpotlightFileProvider: SearchProvider {
    let source: SearchSource = .files

    func search(_ context: ProviderSearchContext) throws -> [SearchResultRecord] {
        let request = SearchRequest(query: context.query, types: context.types, sources: [SearchSource.files.rawValue], onlyIn: context.onlyIn, limit: context.limit)
        let built = try SpotlightQueryBuilder.build(from: request)
        guard let query = MDQueryCreate(kCFAllocatorDefault, built.expression as CFString, nil, nil) else {
            throw SpotlightSearchError.queryCreationFailed
        }

        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else {
            throw SpotlightSearchError.queryExecutionFailed
        }

        let resultCount = MDQueryGetResultCount(query)
        var results: [SearchResultRecord] = []
        var seenPaths: Set<String> = []
        results.reserveCapacity(built.limit)

        for index in 0..<resultCount {
            guard let result = MDQueryGetResultAtIndex(query, index) else {
                continue
            }

            let item = unsafeBitCast(result, to: MDItem.self)
            let record = SpotlightRecordNormalizer.normalize(MDItemMetadataReader(item: item))
            if !record.path.isEmpty && record.isWithinAnyScope(built.scopes) && !record.isNoisyDefaultResult(whenScopesAre: built.scopes) {
                seenPaths.insert(URL(fileURLWithPath: record.path).standardizedFileURL.path)
                results.append(record.searchResult(query: context.query))
                if results.count == built.limit {
                    break
                }
            }
        }

        if results.count < built.limit && !built.scopes.isEmpty {
            results.append(contentsOf: directScopedFallback(
                query: context.query,
                scopes: built.scopes,
                limit: built.limit - results.count,
                seenPaths: seenPaths
            ))
        }

        return results
    }

    private func directScopedFallback(query: String, scopes: [String], limit: Int, seenPaths: Set<String>) -> [SearchResultRecord] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, limit > 0 else {
            return []
        }

        var records: [SearchResultRecord] = []
        var seenPaths = seenPaths
        var inspected = 0
        for scope in scopes {
            guard let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: scope),
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                inspected += 1
                if inspected > 5_000 {
                    return records
                }

                let path = url.standardizedFileURL.path
                guard seenPaths.insert(path).inserted else {
                    continue
                }

                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                      values.isRegularFile == true else {
                    continue
                }

                let filename = url.lastPathComponent
                let reason: String
                if SearchUtilities.contains(filename, needle) {
                    reason = "filename"
                } else if fileContents(at: url, maxBytes: 1_000_000).map({ SearchUtilities.contains($0, needle) }) == true {
                    reason = "content"
                } else {
                    continue
                }

                records.append(SearchResultRecord(
                    id: SearchUtilities.stableID([SearchSource.files.rawValue, path]),
                    source: SearchSource.files.rawValue,
                    entityType: "file",
                    title: filename,
                    subtitle: "Filesystem fallback",
                    path: path,
                    modifiedAt: values.contentModificationDate,
                    sizeBytes: values.fileSize.map(Int64.init),
                    metadata: [
                        "matchReason": .string(reason),
                        "fallback": .string("filesystem-scope")
                    ]
                ))
                if records.count == limit {
                    return records
                }
            }
        }
        return records
    }

    private func fileContents(at url: URL, maxBytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer {
            try? handle.close()
        }
        let data = handle.readData(ofLength: maxBytes)
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .ascii)
    }
}

extension SpotlightRecord {
    func searchResult(query: String = "") -> SearchResultRecord {
        var metadata = metadata
        let matchReason = fileMatchReason(query: query)
        if !matchReason.isEmpty {
            metadata["matchReason"] = .string(matchReason)
        }
        return SearchResultRecord(
            id: id,
            source: SearchSource.files.rawValue,
            entityType: "file",
            title: displayName ?? URL(fileURLWithPath: path).lastPathComponent,
            subtitle: kind,
            path: path,
            contentType: contentType,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            authors: authors,
            sizeBytes: sizeBytes,
            metadata: metadata
        )
    }

    func isWithinAnyScope(_ scopes: [String]) -> Bool {
        guard !scopes.isEmpty else {
            return true
        }

        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        return scopes.contains { scope in
            let standardizedScope = URL(fileURLWithPath: scope).standardizedFileURL.path
            return standardizedPath == standardizedScope || standardizedPath.hasPrefix("\(standardizedScope)/")
        }
    }

    func isNoisyDefaultResult(whenScopesAre scopes: [String]) -> Bool {
        guard scopes.isEmpty else {
            return false
        }
        let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents.map { $0.lowercased() }
        let noisyComponents: Set<String> = [
            "node_modules",
            ".git",
            ".build",
            "build",
            "deriveddata",
            "caches",
            "logs",
            "__pycache__"
        ]
        return components.contains { noisyComponents.contains($0) }
    }

    private func fileMatchReason(query: String) -> String {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            return "metadata"
        }

        let filename = URL(fileURLWithPath: path).lastPathComponent
        if SearchUtilities.contains(filename, needle) || SearchUtilities.contains(displayName, needle) {
            return "filename"
        }

        if fileContents(maxBytes: 1_000_000).map({ SearchUtilities.contains($0, needle) }) == true {
            return "content"
        }

        return "metadata"
    }

    private func fileContents(maxBytes: Int) -> String? {
        let url = URL(fileURLWithPath: path)
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer {
            try? handle.close()
        }
        let data = handle.readData(ofLength: maxBytes)
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .ascii)
    }
}
