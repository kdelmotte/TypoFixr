import Foundation
import NaturalLanguage

struct CorrectionChunker {
    typealias SentenceChunks = GroqService.SentenceChunks
    typealias ReassemblyPlan = GroqService.ReassemblyPlan
    typealias ParsedList = GroqService.ParsedList
    private let chunkingThreshold = 300
    private let maxClauseChunkSize = 295
    private let minClauseFragment = 40
    private struct ClauseDelimiter {
        let pattern: String
        let leftSuffix: String
        let gap: String
    }

    private static let clauseDelimiters: [ClauseDelimiter] = [
        ClauseDelimiter(pattern: ", ", leftSuffix: ",", gap: " "),    // comma: attach to left, space becomes gap
        ClauseDelimiter(pattern: "; ", leftSuffix: ";", gap: " "),    // semicolon: same
        ClauseDelimiter(pattern: " - ", leftSuffix: "", gap: " - "),  // dash: full delimiter becomes gap
    ]

    // MARK: - Multi-Line List Detection

    /// Bullet pattern: `- `, `* `, `• `, `– `, `— ` with optional leading whitespace
    private static let bulletPattern = #"^(\s*[-*•–—]\s+)"#
    /// Numbered pattern: `1. `, `2) ` etc. with optional leading whitespace
    private static let numberedPattern = #"^(\s*\d+[.)]\s+)"#

    /// Detect multi-line list text and parse into items with prefixes.
    /// Returns nil if the text is not a list (mixed types, single item, non-list lines).
    static func parseMultiLineList(_ text: String) -> ParsedList? {
        let lines = text.components(separatedBy: "\n")
        guard lines.count >= 2 else { return nil }

        // Classify non-blank lines and track gaps
        var items: [ParsedList.Item] = []
        var gaps: [String] = []
        var leadingGap = ""
        var trailingGap = ""
        var detectedType: String? = nil  // "bullet" or "numbered"
        var pendingBlankLines: [String] = []  // blank lines accumulated between items
        var foundFirstItem = false

        let bulletRegex = try! NSRegularExpression(pattern: bulletPattern)
        let numberedRegex = try! NSRegularExpression(pattern: numberedPattern)

        for line in lines {
            // Blank line — accumulate between items
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if foundFirstItem {
                    pendingBlankLines.append(line)
                } else {
                    leadingGap += (leadingGap.isEmpty ? "" : "\n") + line
                }
                continue
            }

            let range = NSRange(line.startIndex..., in: line)

            // Try bullet match
            if let match = bulletRegex.firstMatch(in: line, range: range),
               let prefixRange = Range(match.range(at: 1), in: line) {
                let lineType = "bullet"
                if detectedType == nil { detectedType = lineType }
                guard detectedType == lineType else { return nil }

                if foundFirstItem {
                    // Gap = \n + blank lines joined by \n + \n (if blank lines exist), else just \n
                    if pendingBlankLines.isEmpty {
                        gaps.append("\n")
                    } else {
                        gaps.append("\n" + pendingBlankLines.joined(separator: "\n") + "\n")
                    }
                } else {
                    if !leadingGap.isEmpty { leadingGap += "\n" }
                    foundFirstItem = true
                }
                pendingBlankLines = []

                let prefix = String(line[prefixRange])
                let body = String(line[prefixRange.upperBound...])
                items.append(ParsedList.Item(prefix: prefix, text: body))
                continue
            }

            // Try numbered match
            if let match = numberedRegex.firstMatch(in: line, range: range),
               let prefixRange = Range(match.range(at: 1), in: line) {
                let lineType = "numbered"
                if detectedType == nil { detectedType = lineType }
                guard detectedType == lineType else { return nil }

                if foundFirstItem {
                    if pendingBlankLines.isEmpty {
                        gaps.append("\n")
                    } else {
                        gaps.append("\n" + pendingBlankLines.joined(separator: "\n") + "\n")
                    }
                } else {
                    if !leadingGap.isEmpty { leadingGap += "\n" }
                    foundFirstItem = true
                }
                pendingBlankLines = []

                let prefix = String(line[prefixRange])
                let body = String(line[prefixRange.upperBound...])
                items.append(ParsedList.Item(prefix: prefix, text: body))
                continue
            }

            // Non-list line found — not a valid list
            return nil
        }

        guard items.count >= 2 else { return nil }

        // Any trailing blank lines after the last item become trailingGap
        if !pendingBlankLines.isEmpty {
            trailingGap = "\n" + pendingBlankLines.joined(separator: "\n")
        }

        return ParsedList(
            items: items,
            gaps: gaps,
            leadingGap: leadingGap,
            trailingGap: trailingGap
        )
    }

    /// Reassemble corrected texts with original list prefixes and gaps.
    static func reassembleList(list: ParsedList, correctedTexts: [String]) -> String {
        var result = list.leadingGap
        for (i, item) in list.items.enumerated() {
            result += item.prefix + correctedTexts[i]
            if i < list.gaps.count {
                result += list.gaps[i]
            }
        }
        result += list.trailingGap
        return result
    }

    // MARK: - Sentence Chunking

    func splitIntoSentenceChunks(_ text: String) -> SentenceChunks {
        // 1. NLTokenizer to get raw sentence ranges
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var rawRanges: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            rawRanges.append(range)
            return true
        }

        guard !rawRanges.isEmpty else {
            return SentenceChunks(sentences: [], gaps: [], leadingGap: text, trailingGap: "")
        }

        // 2. URL-healing merge: detect URLs that span chunk boundaries
        var mergedRanges = rawRanges
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let nsText = text as NSString
            let urlMatches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

            for match in urlMatches {
                guard let urlRange = Range(match.range, in: text) else { continue }

                // Find which chunks the URL spans
                var firstIdx: Int?
                var lastIdx: Int?
                for (i, chunkRange) in mergedRanges.enumerated() {
                    if chunkRange.overlaps(urlRange) {
                        if firstIdx == nil { firstIdx = i }
                        lastIdx = i
                    }
                }

                // Merge chunks that split this URL
                if let first = firstIdx, let last = lastIdx, first < last {
                    let merged = mergedRanges[first].lowerBound..<mergedRanges[last].upperBound
                    mergedRanges.replaceSubrange(first...last, with: [merged])
                }
            }
        }

        // 3. Whitespace-only filter: skip chunks that are only whitespace
        //    and extract gaps between chunks
        var sentences: [String] = []
        var gaps: [String] = []
        var sentenceRanges: [Range<String.Index>] = []

        for range in mergedRanges {
            let chunk = String(text[range])
            if chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Fold into gap — will be captured between sentenceRanges
                continue
            }
            sentenceRanges.append(range)
        }

        guard !sentenceRanges.isEmpty else {
            return SentenceChunks(sentences: [], gaps: [], leadingGap: text, trailingGap: "")
        }

        // 4. Right-trim each sentence and compute gaps
        //    Gap[i] = text between end of sentence[i] and start of sentence[i+1]
        let leadingGap = String(text[text.startIndex..<sentenceRanges[0].lowerBound])

        for (i, range) in sentenceRanges.enumerated() {
            let raw = String(text[range])

            // Right-trim: strip trailing whitespace, fold it into gap
            var trimmed = raw
            var trailingWS = ""
            while trimmed.hasSuffix(" ") || trimmed.hasSuffix("\t") || trimmed.hasSuffix("\n") || trimmed.hasSuffix("\r") {
                trailingWS = String(trimmed.last!) + trailingWS
                trimmed = String(trimmed.dropLast())
            }

            sentences.append(trimmed)

            // Gap between this sentence and next
            if i < sentenceRanges.count - 1 {
                let gapStart = range.upperBound
                let gapEnd = sentenceRanges[i + 1].lowerBound
                let interGap = gapStart < gapEnd ? String(text[gapStart..<gapEnd]) : ""
                gaps.append(trailingWS + interGap)
            } else {
                // Last sentence: trailing gap = trimmed WS + text after last range
                let afterLast = range.upperBound < text.endIndex ? String(text[range.upperBound..<text.endIndex]) : ""
                // trailingGap stored separately below
                gaps.append("") // placeholder, not used
                let trailingGapFinal = trailingWS + afterLast
                // We'll set trailingGap after the loop
                sentences[sentences.count - 1] = trimmed
                // Store trailing gap in a temporary — handled after loop
                gaps[gaps.count - 1] = trailingGapFinal
            }
        }

        // Extract trailing gap from the last entry in gaps
        let trailingGap = gaps.removeLast()

        // 5. Aggressive sentence merging: merge adjacent sentences when combined <= maxClauseChunkSize
        var mergedSentences: [String] = []
        var mergedGaps: [String] = []
        var i = 0

        while i < sentences.count {
            var current = sentences[i]

            while i + 1 < sentences.count
                && (current.count + gaps[i].count + sentences[i + 1].count) <= maxClauseChunkSize {
                current = current + gaps[i] + sentences[i + 1]
                i += 1
            }

            mergedSentences.append(current)
            if i < gaps.count {
                mergedGaps.append(gaps[i])
            }
            i += 1
        }

        // mergedGaps should have exactly mergedSentences.count - 1 entries
        if mergedGaps.count >= mergedSentences.count {
            mergedGaps = Array(mergedGaps.prefix(mergedSentences.count - 1))
        }

        // 6. Clause-level splitting: break chunks > maxClauseChunkSize at clause boundaries
        let (finalSentences, finalGaps) = splitOversizedChunks(sentences: mergedSentences, gaps: mergedGaps)

        return SentenceChunks(
            sentences: finalSentences,
            gaps: finalGaps,
            leadingGap: leadingGap,
            trailingGap: trailingGap
        )
    }

    /// Split a single oversized chunk at clause boundaries (`, `, `; `, ` - `).
    /// Returns sub-chunks and gaps that reassemble to the original text.
    private func splitChunkAtClauseBoundaries(_ text: String) -> (sentences: [String], gaps: [String]) {
        guard text.count > maxClauseChunkSize else {
            return (sentences: [text], gaps: [])
        }

        let midpoint = text.count / 2

        // Find all clause delimiter positions and pick the one closest to midpoint
        var bestSplit: (position: Int, leftSuffix: String, gap: String)?
        var bestDistance = Int.max

        for delim in Self.clauseDelimiters {
            var searchStart = text.startIndex
            while let range = text.range(of: delim.pattern, range: searchStart..<text.endIndex) {
                let charPos = text.distance(from: text.startIndex, to: range.lowerBound)

                // Enforce minimum fragment size on left side
                let leftLen = charPos + delim.leftSuffix.count
                if leftLen >= minClauseFragment {
                    let distance = abs(charPos - midpoint)
                    if distance < bestDistance {
                        bestDistance = distance
                        bestSplit = (position: charPos, leftSuffix: delim.leftSuffix, gap: delim.gap)
                    }
                }

                searchStart = range.upperBound
            }
        }

        guard let split = bestSplit else {
            // No suitable delimiter found — keep as-is (falls back to medium reasoning)
            return (sentences: [text], gaps: [])
        }

        // Split: left gets text before delimiter + punctuation, right gets text after delimiter
        let delimStartIndex = text.index(text.startIndex, offsetBy: split.position)

        // Find the actual delimiter pattern to know its full length
        var delimLength = 0
        for delim in Self.clauseDelimiters {
            if text[delimStartIndex...].hasPrefix(delim.pattern) {
                delimLength = delim.pattern.count
                break
            }
        }

        let left = String(text[..<delimStartIndex]) + split.leftSuffix
        let delimEndIndex = text.index(delimStartIndex, offsetBy: delimLength)
        let right = String(text[delimEndIndex...])

        // Recursively split both halves if still oversized
        let (leftSentences, leftGaps) = splitChunkAtClauseBoundaries(left)
        let (rightSentences, rightGaps) = splitChunkAtClauseBoundaries(right)

        // Combine: leftSentences + [gap] + rightSentences
        var combinedSentences = leftSentences
        var combinedGaps = leftGaps
        combinedGaps.append(split.gap)
        combinedSentences.append(contentsOf: rightSentences)
        combinedGaps.append(contentsOf: rightGaps)

        return (sentences: combinedSentences, gaps: combinedGaps)
    }

    /// Apply clause-level splitting to all oversized chunks, preserving inter-sentence gaps.
    private func splitOversizedChunks(sentences: [String], gaps: [String]) -> (sentences: [String], gaps: [String]) {
        var finalSentences: [String] = []
        var finalGaps: [String] = []

        for (i, chunk) in sentences.enumerated() {
            let (subSentences, subGaps) = splitChunkAtClauseBoundaries(chunk)

            // Append a gap before this chunk's sub-sentences (inter-sentence gap from previous)
            if !finalSentences.isEmpty && i - 1 < gaps.count {
                finalGaps.append(gaps[i - 1])
            }

            finalSentences.append(contentsOf: subSentences)
            finalGaps.append(contentsOf: subGaps)
        }

        // finalGaps should have exactly finalSentences.count - 1 entries
        if finalGaps.count >= finalSentences.count {
            finalGaps = Array(finalGaps.prefix(finalSentences.count - 1))
        }

        return (sentences: finalSentences, gaps: finalGaps)
    }

    // MARK: - Paragraph Splitting

    /// Split text at `\n\n` (2+ consecutive newlines) into paragraphs.
    /// Returns nil if no paragraph breaks found or only one non-empty paragraph.
    static func splitIntoParagraphs(_ text: String) -> SentenceChunks? {
        // Split at 2+ consecutive newlines
        guard let regex = try? NSRegularExpression(pattern: "\\n{2,}") else { return nil }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, range: fullRange)

        guard !matches.isEmpty else { return nil }

        // Build paragraph ranges and delimiter ranges
        var paragraphs: [String] = []
        var delimiters: [String] = []
        var pos = 0

        for match in matches {
            let paraEnd = match.range.location
            let para = nsText.substring(with: NSRange(location: pos, length: paraEnd - pos))
            paragraphs.append(para)
            delimiters.append(nsText.substring(with: match.range))
            pos = match.range.location + match.range.length
        }
        // Last paragraph after final delimiter
        paragraphs.append(nsText.substring(from: pos))

        // Determine leading/trailing gaps from empty paragraphs
        var leadingGap = ""
        var trailingGap = ""

        // Fold leading empty paragraphs into leadingGap
        while !paragraphs.isEmpty
            && paragraphs[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            leadingGap += paragraphs.removeFirst()
            if !delimiters.isEmpty {
                leadingGap += delimiters.removeFirst()
            }
        }

        // Fold trailing empty paragraphs into trailingGap
        while !paragraphs.isEmpty
            && paragraphs[paragraphs.count - 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let last = paragraphs.removeLast()
            if !delimiters.isEmpty {
                trailingGap = delimiters.removeLast() + last + trailingGap
            } else {
                trailingGap = last + trailingGap
            }
        }

        // Need at least 2 non-empty paragraphs
        guard paragraphs.count >= 2 else { return nil }

        // delimiters now correspond to gaps between remaining paragraphs
        return SentenceChunks(
            sentences: paragraphs,
            gaps: delimiters,
            leadingGap: leadingGap,
            trailingGap: trailingGap
        )
    }

    /// Reassemble corrected chunks with original whitespace gaps
    static func reassemble(chunks: SentenceChunks, corrected: [String]) -> String {
        var result = chunks.leadingGap
        for (i, text) in corrected.enumerated() {
            result += text
            if i < chunks.gaps.count {
                result += chunks.gaps[i]
            }
        }
        result += chunks.trailingGap
        return result
    }

    // MARK: - Flatten / Reassemble

    /// Eagerly splits text into all leaf-level chunks (no API calls).
    /// Returns the flat array of leaf texts and a plan for bottom-up reassembly.
    func flattenIntoLeafChunks(_ text: String) -> ([String], ReassemblyPlan) {
        // 1. Try list detection (top-level)
        if let list = Self.parseMultiLineList(text), list.items.count > 1 {
            let leaves = list.items.map { $0.text }
            return (leaves, .list(list))
        }

        // 2. Try paragraph splitting (>= chunkingThreshold with \n\n)
        if text.count >= chunkingThreshold, text.contains("\n\n"),
           let paragraphs = Self.splitIntoParagraphs(text) {

            // Paragraph-level merging: combine small adjacent paragraphs
            let merged = mergeParagraphs(paragraphs)


            var allLeaves: [String] = []
            var subPlans: [ReassemblyPlan.SubPlan] = []

            for para in merged.sentences {
                let startIdx = allLeaves.count

                // Skip empty/whitespace-only paragraphs
                guard !para.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    allLeaves.append(para)
                    subPlans.append(ReassemblyPlan.SubPlan(
                        chunkRange: startIdx..<(startIdx + 1),
                        kind: .single
                    ))
                    continue
                }

                // Try list within paragraph
                if let list = Self.parseMultiLineList(para), list.items.count > 1 {
                    let leaves = list.items.map { $0.text }
                    allLeaves.append(contentsOf: leaves)
                    subPlans.append(ReassemblyPlan.SubPlan(
                        chunkRange: startIdx..<allLeaves.count,
                        kind: .list(list)
                    ))
                    continue
                }

                // Try sentence chunking within paragraph
                if para.count >= chunkingThreshold {
                    let chunks = splitIntoSentenceChunks(para)
                    if chunks.sentences.count > 1 {
                        allLeaves.append(contentsOf: chunks.sentences)
                        subPlans.append(ReassemblyPlan.SubPlan(
                            chunkRange: startIdx..<allLeaves.count,
                            kind: .sentences(chunks)
                        ))
                        continue
                    }
                }

                // Single paragraph
                allLeaves.append(para)
                subPlans.append(ReassemblyPlan.SubPlan(
                    chunkRange: startIdx..<allLeaves.count,
                    kind: .single
                ))
            }

            return (allLeaves, .paragraphs(paragraphChunks: merged, subPlans: subPlans))
        }

        // 3. Try sentence chunking
        if text.count >= chunkingThreshold {
            let chunks = splitIntoSentenceChunks(text)
            if chunks.sentences.count > 1 {
                return (chunks.sentences, .sentences(chunks))
            }
        }

        // 4. Single text fallback
        return ([text], .single)
    }

    /// Merge small adjacent paragraphs when combined size <= maxClauseChunkSize.
    private func mergeParagraphs(_ paragraphs: SentenceChunks) -> SentenceChunks {
        guard paragraphs.sentences.count > 1 else { return paragraphs }

        var merged: [String] = []
        var mergedGaps: [String] = []
        var i = 0

        while i < paragraphs.sentences.count {
            var current = paragraphs.sentences[i]

            while i + 1 < paragraphs.sentences.count {
                let gap = paragraphs.gaps[i]
                let next = paragraphs.sentences[i + 1]
                if (current.count + gap.count + next.count) <= maxClauseChunkSize {
                    current = current + gap + next
                    i += 1
                } else {
                    break
                }
            }

            merged.append(current)
            if i < paragraphs.gaps.count {
                mergedGaps.append(paragraphs.gaps[i])
            }
            i += 1
        }

        // mergedGaps should have exactly merged.count - 1 entries
        if mergedGaps.count >= merged.count {
            mergedGaps = Array(mergedGaps.prefix(merged.count - 1))
        }

        return SentenceChunks(
            sentences: merged,
            gaps: mergedGaps,
            leadingGap: paragraphs.leadingGap,
            trailingGap: paragraphs.trailingGap
        )
    }

    /// Reconstruct the full corrected text from leaf results using the reassembly plan.
    static func reassembleFromLeafResults(_ results: [String], plan: ReassemblyPlan) -> String {
        switch plan {
        case .single:
            return results[0]

        case .sentences(let chunks):
            return reassemble(chunks: chunks, corrected: results)

        case .list(let list):
            return reassembleList(list: list, correctedTexts: results)

        case .paragraphs(let paragraphChunks, let subPlans):
            // Reassemble each sub-plan from its slice of results
            var paragraphResults: [String] = []
            for sub in subPlans {
                let slice = Array(results[sub.chunkRange])
                switch sub.kind {
                case .single:
                    paragraphResults.append(slice[0])
                case .sentences(let chunks):
                    paragraphResults.append(reassemble(chunks: chunks, corrected: slice))
                case .list(let list):
                    paragraphResults.append(reassembleList(list: list, correctedTexts: slice))
                }
            }
            return reassemble(chunks: paragraphChunks, corrected: paragraphResults)
        }
    }

}
