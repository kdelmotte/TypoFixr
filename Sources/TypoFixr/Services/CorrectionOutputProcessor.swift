import Foundation

struct CorrectionOutputProcessor {
    typealias ParsedCompletion = GroqService.ParsedCompletion
    typealias CorrectionResult = GroqService.CorrectionResult
    typealias APIError = GroqService.APIError
    private let noChangesMarker = "__NO_CHANGES__"
    // Security: Maximum allowed output length multiplier
    private let maxOutputLengthMultiplier = 3.0

    // Boundary quote characters for restoration (single quotes excluded — apostrophe overlap)
    private static let leadingQuoteChars: Set<Character> = ["\"", "\u{201C}", "\u{00AB}"]  // ", \u{201C}, \u{00AB}
    private static let trailingQuoteChars: Set<Character> = ["\"", "\u{201D}", "\u{00BB}"]  // ", \u{201D}, \u{00BB}

    // MARK: - Security Validation

    /// Patterns that indicate the AI refused to process the request
    private let refusalPatterns: [String] = [
        "i'm sorry",
        "i am sorry",
        "i cannot",
        "i can't",
        "i am unable",
        "i'm unable",
        "cannot assist",
        "can't assist",
        "cannot help",
        "can't help",
        "not able to",
        "unable to help",
        "unable to assist",
        "i apologize",
        "against my guidelines",
        "violates my guidelines",
        "i'm not able",
        "i am not able",
    ]

    /// Patterns that indicate potentially malicious AI output
    private let suspiciousPatterns: [(pattern: String, description: String)] = [
        // Script injection attempts
        ("<script", "script tag"),
        ("javascript:", "javascript URL"),
        ("on\\w+\\s*=", "event handler"),

        // Shell command patterns
        ("^\\s*\\$\\s+", "shell prompt"),
        ("sudo\\s+", "sudo command"),
        ("rm\\s+-rf", "dangerous rm command"),
        ("(?:;|&&|\\|\\|)\\s*(curl|wget|bash|sh|python|ruby|perl)(?:\\s+|$)", "command injection"),
        ("\\|\\s*(bash|sh|zsh)", "pipe to shell"),

        // AppleScript/macOS specific
        ("osascript", "osascript command"),
        ("do shell script", "AppleScript shell"),

        // URL patterns that might be phishing
        ("(https?://[^\\s]+\\.(ru|cn|tk|ml|ga|cf|gq)(/|$|\\s))", "suspicious domain"),
    ]

    /// Validates AI output for security concerns
    private func validateOutput(_ output: String, originalInput: String) throws {
        let lowerOutput = output.lowercased()
        let lowerInput = originalInput.lowercased()

        // 1. Check for AI refusal - but only if these phrases weren't in the original
        // Also check for apostrophe-less versions since typos often omit apostrophes
        // e.g., "i cant" should match "i can't" to avoid false positives
        for pattern in refusalPatterns {
            if lowerOutput.contains(pattern) {
                // Check both the exact pattern and the version without apostrophes
                let patternWithoutApostrophe = pattern.replacingOccurrences(of: "'", with: "")
                let inputContainsPattern = lowerInput.contains(pattern) || lowerInput.contains(patternWithoutApostrophe) || Self.containsTypoVariant(of: pattern, in: lowerInput)

                if !inputContainsPattern {
                    throw APIError.aiRefused
                }
            }
        }

        // 2. Length validation - output shouldn't be drastically longer than input
        let maxAllowedLength = Int(Double(originalInput.count) * maxOutputLengthMultiplier) + 50
        if output.count > maxAllowedLength {
            throw APIError.outputTooLong
        }

        // 3. Check for suspicious patterns
        for (pattern, description) in suspiciousPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               regex.firstMatch(in: output, options: [], range: NSRange(output.startIndex..., in: output)) != nil {
                throw APIError.suspiciousOutput(description)
            }
        }

        // 4. Check for non-printable control characters (except common whitespace)
        let allowedControlChars = CharacterSet(charactersIn: "\n\r\t\u{200B}\u{200C}\u{200D}\u{FEFF}\u{00AD}")
        let controlChars = CharacterSet.controlCharacters.subtracting(allowedControlChars)
        if output.unicodeScalars.contains(where: { controlChars.contains($0) }) {
            throw APIError.suspiciousOutput("hidden control characters")
        }

    }

    /// A spelling correction inside an apology is not an AI refusal.
    private static func containsTypoVariant(of phrase: String, in input: String) -> Bool {
        func words(_ text: String) -> [String] {
            text.replacingOccurrences(of: "'", with: "")
                .replacingOccurrences(of: "’", with: "")
                .split(whereSeparator: { !$0.isLetter }).map(String.init)
        }
        let expected = words(phrase)
        let actual = words(input)
        guard !expected.isEmpty, actual.count >= expected.count else { return false }
        return (0...(actual.count - expected.count)).contains { start in
            zip(expected, actual[start..<(start + expected.count)]).allSatisfy { a, b in
                if a == b { return true }
                guard a.count >= 3, b.count >= 3 else { return false }
                let lhs = Array(a), rhs = Array(b)
                var row = Array(0...rhs.count)
                for (i, char) in lhs.enumerated() {
                    var next = [i + 1]
                    for (j, other) in rhs.enumerated() {
                        next.append(min(next[j] + 1, row[j + 1] + 1, row[j] + (char == other ? 0 : 1)))
                    }
                    row = next
                }
                return row.last! <= 1
            }
        }
    }

    /// Sanitizes output by removing potentially dangerous content and unwanted tags
    /// Preserves formatting: indentation, line breaks, bullets, numbered lists
    private func sanitizeOutput(_ output: String, originalInput: String) -> String {
        var text = output
        let original = originalInput.lowercased()
        // Remove reasoning only when the source did not contain this markup.
        if !original.contains("<think>"),
           let start = text.range(of: "<think>", options: .caseInsensitive) {
            guard let end = text.range(of: "</think>", options: .caseInsensitive,
                                       range: start.upperBound..<text.endIndex) else {
                return ""
            }
            text.removeSubrange(start.lowerBound..<end.upperBound)
        }
        // Strip a complete model-added wrapper, never arbitrary angle brackets or
        // partial tags. Existing HTML, email brackets, emoji and language joiners survive.
        for tag in ["user_text", "i", "b", "em", "strong"] {
            let opening = "<\(tag)>"
            let closing = "</\(tag)>"
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !original.contains(opening),
               trimmed.lowercased().hasPrefix(opening),
               trimmed.lowercased().hasSuffix(closing) {
                text = String(trimmed.dropFirst(opening.count).dropLast(closing.count))
            }
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines) != noChangesMarker {
            text = Self.normalizeLeadingListArtifacts(originalInput: originalInput, output: text)
        }
        while text.last?.isWhitespace == true { text.removeLast() }
        return text
    }

    // MARK: - List Artifact Normalization

    /// Normalizes model-added leading list artifacts while preserving the original list marker.
    /// For multi-line text where both original and output have the same line count,
    /// applies per-line normalization. Otherwise falls back to single-line (first line) behavior.
    static func normalizeLeadingListArtifacts(originalInput: String, output: String) -> String {
        guard !originalInput.isEmpty, !output.isEmpty else { return output }

        let originalLines = originalInput.components(separatedBy: "\n")
        let outputLines = output.components(separatedBy: "\n")

        // Multi-line: apply per-line when line counts match
        if originalLines.count > 1 && originalLines.count == outputLines.count {
            let normalized = zip(originalLines, outputLines).map { orig, out in
                normalizeLeadingListArtifactsSingleLine(originalInput: orig, output: out)
            }
            return normalized.joined(separator: "\n")
        }

        // Single-line or mismatched line counts: existing behavior
        return normalizeLeadingListArtifactsSingleLine(originalInput: originalInput, output: output)
    }

    /// Single-line normalization: fixes duplicate dashes, checklist artifacts, etc.
    private static func normalizeLeadingListArtifactsSingleLine(originalInput: String, output: String) -> String {
        guard !originalInput.isEmpty, !output.isEmpty else { return output }

        let listPrefixChars = CharacterSet(charactersIn: "-*•–— \t")
        let listMarkerChars = CharacterSet(charactersIn: "-*•–—")

        let originalPrefix = String(originalInput.prefix(while: { $0.unicodeScalars.allSatisfy { listPrefixChars.contains($0) } }))
        let outputPrefix = String(output.prefix(while: { $0.unicodeScalars.allSatisfy { listPrefixChars.contains($0) } }))

        var normalizedOutput = output
        if outputPrefix != originalPrefix {
            // Keep the original prefix exactly, but preserve the corrected body.
            let withoutPrefix = String(normalizedOutput.dropFirst(outputPrefix.count))
            normalizedOutput = originalPrefix + withoutPrefix
        }

        let originalBody = String(originalInput.dropFirst(originalPrefix.count))
        var outputBody = String(normalizedOutput.dropFirst(originalPrefix.count))

        let checkboxPattern = #"^\[(?: |x|X)\]\s+"#
        let dashedCheckboxPattern = #"^[-*•–—]\s*\[(?: |x|X)\]\s+"#
        let listMarkerPattern = #"^[-*•–—]\s+"#

        // If the original line is not a checklist item, drop model-added checklist tokens.
        // This handles Notes where selected list text often excludes the visual list marker.
        let originalIsChecklist = matchesRegex(originalBody, pattern: checkboxPattern)
            || matchesRegex(originalBody, pattern: dashedCheckboxPattern)
        if !originalIsChecklist {
            outputBody = replacingFirstRegexMatch(in: outputBody, pattern: dashedCheckboxPattern, with: "")
            outputBody = replacingFirstRegexMatch(in: outputBody, pattern: checkboxPattern, with: "")
        }

        // Only run duplicate list-marker cleanup if the original text actually had a list marker.
        let originalHasListMarker = originalPrefix.unicodeScalars.contains { listMarkerChars.contains($0) }

        // Remove one extra leading list marker if the model duplicated it.
        if originalHasListMarker && !matchesRegex(originalBody, pattern: listMarkerPattern) {
            outputBody = replacingFirstRegexMatch(in: outputBody, pattern: listMarkerPattern, with: "")
        }

        return originalPrefix + outputBody
    }

    private static func matchesRegex(_ text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        return regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func replacingFirstRegexMatch(in text: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let fullRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: fullRange) else {
            return text
        }
        return regex.stringByReplacingMatches(in: text, options: [], range: match.range, withTemplate: replacement)
    }

    // MARK: - Boundary Quote Restoration

    /// Restores leading/trailing quotes that the model strips when they appear at text boundaries.
    /// The model sometimes interprets boundary quotes as XML-adjacent delimiters and drops them.
    static func restoreBoundaryQuotes(original: String, corrected: String) -> String {
        guard !original.isEmpty, !corrected.isEmpty else { return corrected }
        var result = corrected

        if let firstOrig = original.first, leadingQuoteChars.contains(firstOrig),
           let firstCorr = result.first, !leadingQuoteChars.contains(firstCorr) {
            result = String(firstOrig) + result
        }

        if let lastOrig = original.last, trailingQuoteChars.contains(lastOrig),
           let lastCorr = result.last, !trailingQuoteChars.contains(lastCorr) {
            result = result + String(lastOrig)
        }

        return result
    }

    func resolveCorrection(parsed: ParsedCompletion, originalInput: String) throws -> CorrectionResult {
        let isLengthCapped = parsed.finishReason?.lowercased() == "length"
        if isLengthCapped {
            throw APIError.apiError("Correction exceeded output budget (finish_reason: length). Try selecting a smaller amount of text.")
        }
        guard parsed.finishReason?.lowercased() == "stop" else {
            throw APIError.invalidResponse
        }

        guard let content = parsed.content, !content.isEmpty else {
            let reason = (parsed.finishReason ?? "unknown").lowercased()
            throw APIError.apiError("Received empty response from API (finish_reason: \(reason)). Try selecting a smaller amount of text.")
        }

        // Check for __NO_CHANGES__ on raw content BEFORE sanitization
        // (normalizeLeadingListArtifacts can prepend list prefixes that corrupt the marker)
        let rawTrimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawTrimmed == noChangesMarker {
            return CorrectionResult(correctedText: originalInput, inputTokens: parsed.inputTokens, outputTokens: parsed.outputTokens)
        }

        let sanitizedText = sanitizeOutput(content, originalInput: originalInput)
        guard !sanitizedText.isEmpty else {
            let reason = (parsed.finishReason ?? "unknown").lowercased()
            throw APIError.apiError("Received empty response from API (finish_reason: \(reason)). Try selecting a smaller amount of text.")
        }

        let trimmedSanitizedText = sanitizedText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Explicit no-changes marker
        if trimmedSanitizedText == noChangesMarker {
            return CorrectionResult(correctedText: originalInput, inputTokens: parsed.inputTokens, outputTokens: parsed.outputTokens)
        }

        // Restore boundary quotes that the model strips at text boundaries
        let restoredText = Self.restoreBoundaryQuotes(original: originalInput, corrected: sanitizedText)

        // Security validation
        try validateOutput(restoredText, originalInput: originalInput)

        // Unchanged text without marker — model saw no corrections needed
        let trimmedRestoredText = restoredText.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalNormalized = originalInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedRestoredText == originalNormalized {
            return CorrectionResult(correctedText: originalInput, inputTokens: parsed.inputTokens, outputTokens: parsed.outputTokens)
        }

        return CorrectionResult(correctedText: restoredText, inputTokens: parsed.inputTokens, outputTokens: parsed.outputTokens)
    }

}
