import XCTest
@testable import TypoFixr

final class SentenceChunkingTests: XCTestCase {
    private let service = GroqService.shared

    // MARK: - Basic Splitting

    func testMultiSentenceTextProducesMultipleChunks() {
        // Combined adjacent sentences exceed maxClauseChunkSize (280) so they won't all merge
        let text = "The quick brown fox jumped gracefully over the extremely lazy dog sleeping in the sunny yard. " +
            "She sells hundreds of beautiful seashells by the sparkling seashore every single bright morning. " +
            "Peter Piper carefully picked a large peck of perfectly pickled peppers from the garden this afternoon."
        let chunks = service.splitIntoSentenceChunks(text)
        XCTAssertGreaterThan(chunks.sentences.count, 1, "Multi-sentence text should produce multiple chunks")
    }

    func testSingleSentenceProducesOneChunk() {
        let text = "This is a single sentence without any period at the end"
        let chunks = service.splitIntoSentenceChunks(text)
        XCTAssertEqual(chunks.sentences.count, 1)
    }

    func testEmptyTextProducesNoChunks() {
        let chunks = service.splitIntoSentenceChunks("")
        XCTAssertTrue(chunks.sentences.isEmpty)
    }

    // MARK: - Reassembly Invariant

    func testReassemblyPreservesSpacesBetweenSentences() {
        let text = "Hello world. How are you? I am fine."
        let chunks = service.splitIntoSentenceChunks(text)
        let reassembled = GroqService.reassemble(chunks: chunks, corrected: chunks.sentences)
        XCTAssertEqual(reassembled, text)
    }

    func testReassemblyPreservesNewlines() {
        let text = "First line.\nSecond line.\nThird line."
        let chunks = service.splitIntoSentenceChunks(text)
        let reassembled = GroqService.reassemble(chunks: chunks, corrected: chunks.sentences)
        XCTAssertEqual(reassembled, text)
    }

    func testReassemblyPreservesParagraphBreaks() {
        let text = "First paragraph.\n\nSecond paragraph.\n\nThird paragraph."
        let chunks = service.splitIntoSentenceChunks(text)
        let reassembled = GroqService.reassemble(chunks: chunks, corrected: chunks.sentences)
        XCTAssertEqual(reassembled, text)
    }

    func testReassemblyPreservesLeadingWhitespace() {
        let text = "  Leading spaces. Then another sentence."
        let chunks = service.splitIntoSentenceChunks(text)
        let reassembled = GroqService.reassemble(chunks: chunks, corrected: chunks.sentences)
        XCTAssertEqual(reassembled, text)
    }

    func testReassemblyPreservesTrailingWhitespace() {
        let text = "A sentence. Another one.  "
        let chunks = service.splitIntoSentenceChunks(text)
        let reassembled = GroqService.reassemble(chunks: chunks, corrected: chunks.sentences)
        XCTAssertEqual(reassembled, text)
    }

    func testReassemblyPreservesMixedFormatting() {
        let text = "- First item.\n- Second item.\n\nA paragraph here. With two sentences.\n\n- Third item."
        let chunks = service.splitIntoSentenceChunks(text)
        let reassembled = GroqService.reassemble(chunks: chunks, corrected: chunks.sentences)
        XCTAssertEqual(reassembled, text)
    }

    // MARK: - URL Healing

    func testURLWithQuestionMarkStaysInOneChunk() {
        let text = "Check this: https://docs.google.com/doc/edit?usp=sharing for details. Then do something else."
        let chunks = service.splitIntoSentenceChunks(text)

        // The URL should not be split across chunks
        for sentence in chunks.sentences {
            if sentence.contains("https://") {
                XCTAssertTrue(sentence.contains("usp=sharing"), "URL should not be split at the ? character")
            }
        }
    }

    // MARK: - Whitespace-Only Chunks

    func testWhitespaceOnlyChunksAreFiltered() {
        let text = "First.\n\nSecond."
        let chunks = service.splitIntoSentenceChunks(text)

        for sentence in chunks.sentences {
            XCTAssertFalse(
                sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Whitespace-only chunks should be filtered out"
            )
        }
    }

    // MARK: - Small Sentence Merging

    func testSmallSentencesAreMerged() {
        // Each sentence is tiny; combined easily <= maxClauseChunkSize (280)
        let text = "Hi. Yes. No. Ok. Sure. Fine."
        let chunks = service.splitIntoSentenceChunks(text)
        // 6 tiny sentences should be merged into fewer chunks
        XCTAssertLessThan(chunks.sentences.count, 6, "Small adjacent sentences should be merged")
    }

    func testMergedChunksDontExceedThreshold() {
        // Build text with many small sentences
        let text = (0..<20).map { "Sentence number \($0)." }.joined(separator: " ")
        let chunks = service.splitIntoSentenceChunks(text)

        for sentence in chunks.sentences {
            XCTAssertLessThan(sentence.count, 300, "Merged chunks should not exceed chunking threshold")
        }
    }

    // MARK: - Right-Trimming

    func testSentencesAreRightTrimmed() {
        let text = "Hello world.  How are you?"
        let chunks = service.splitIntoSentenceChunks(text)

        for sentence in chunks.sentences {
            let trimmed = sentence.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
            XCTAssertEqual(sentence, trimmed, "Sentences should be right-trimmed")
        }
    }

    // MARK: - Routing Logic

    func testShortTextUsesLowReasoningPolicy() {
        let shortText = "teh quik brwn fox"
        let policy = service.requestPolicy(for: shortText)
        XCTAssertEqual(policy.reasoningEffort, "low")
    }

    func testLongSingleSentenceFallsBackToMediumPolicy() {
        let longSentence = String(repeating: "word ", count: 80) // ~400 chars, no period
        let policy = service.requestPolicy(for: longSentence)
        XCTAssertEqual(policy.reasoningEffort, "medium")

        // Should produce 1 chunk (no sentence breaks)
        let chunks = service.splitIntoSentenceChunks(longSentence)
        XCTAssertEqual(chunks.sentences.count, 1, "Single long sentence should produce 1 chunk")
    }

    func testLongMultiSentenceTextProducesMultipleChunks() {
        // Build text >300 chars with clear sentence boundaries
        let text = "The quick brown fox jumps over the lazy dog. " +
            "She sells seashells by the seashore every morning. " +
            "Peter Piper picked a peck of pickled peppers today. " +
            "The rain in Spain falls mainly on the plain below. " +
            "How much wood would a woodchuck chuck if possible. " +
            "Jack and Jill went up the hill to fetch a pail. " +
            "Humpty Dumpty sat on a wall and had a great fall."
        XCTAssertGreaterThan(text.count, 300)

        let chunks = service.splitIntoSentenceChunks(text)
        XCTAssertGreaterThan(chunks.sentences.count, 1, "Long multi-sentence text should be chunked")

        // Reassembly should be exact
        let reassembled = GroqService.reassemble(chunks: chunks, corrected: chunks.sentences)
        XCTAssertEqual(reassembled, text)
    }

    // MARK: - Abbreviations

    func testAbbreviationsDontCauseFalseSplits() {
        let text = "Dr. Smith went to Washington D.C. for the conference."
        let chunks = service.splitIntoSentenceChunks(text)
        // NLTokenizer should handle abbreviations — this is a single sentence
        XCTAssertEqual(chunks.sentences.count, 1, "Abbreviations should not cause false sentence splits")
    }

    // MARK: - List Items

    func testListItemsProduceSeparateChunks() {
        let text = "- First item.\n- Second item.\n- Third item."
        let chunks = service.splitIntoSentenceChunks(text)
        XCTAssertGreaterThanOrEqual(chunks.sentences.count, 1)

        // Reassembly should be exact
        let reassembled = GroqService.reassemble(chunks: chunks, corrected: chunks.sentences)
        XCTAssertEqual(reassembled, text)
    }

    // MARK: - Emoji

    func testEmojiHandledCorrectly() {
        let text = "Had a great day! 🎉 The weather was perfect. ☀️"
        let chunks = service.splitIntoSentenceChunks(text)
        let reassembled = GroqService.reassemble(chunks: chunks, corrected: chunks.sentences)
        XCTAssertEqual(reassembled, text)
    }

    // MARK: - Clause-Level Splitting

    func testOversizedChunkSplitAtComma() {
        // A single long "sentence" >280 chars with commas — should be split at clause boundaries
        let text = "I went to the store yesterday to buy some groceries because we were running low on everything, " +
            "and then I stopped by the pharmacy to pick up my prescription that had been waiting for a few days, " +
            "and after that I drove home through the heavy traffic which took forever to clear up on the highway."
        XCTAssertGreaterThan(text.count, 280)

        let chunks = service.splitIntoSentenceChunks(text)

        // Should be split into multiple sub-chunks
        XCTAssertGreaterThan(chunks.sentences.count, 1, "Oversized chunk should be split at clause boundaries")

        // All sub-chunks should be <= 280 chars
        for sentence in chunks.sentences {
            XCTAssertLessThanOrEqual(sentence.count, 280, "All sub-chunks should be <= 280 chars: '\(sentence)' (\(sentence.count))")
        }

        // Reassembly must be exact
        let reassembled = GroqService.reassemble(chunks: chunks, corrected: chunks.sentences)
        XCTAssertEqual(reassembled, text)
    }

    func testOversizedChunkSplitAtSemicolon() {
        let text = "The project deadline was moved up by two weeks which caused a lot of stress for everyone involved; " +
            "the team had to work overtime every single day just to keep up with the accelerated schedule and deliverables; " +
            "management eventually realized the timeline was unrealistic and agreed to push it back a few extra days."
        XCTAssertGreaterThan(text.count, 280)

        let chunks = service.splitIntoSentenceChunks(text)
        XCTAssertGreaterThan(chunks.sentences.count, 1, "Oversized chunk should split at semicolons")

        let reassembled = GroqService.reassemble(chunks: chunks, corrected: chunks.sentences)
        XCTAssertEqual(reassembled, text)
    }

    func testOversizedChunkWithNoDelimitersStaysAsOne() {
        // Long text with no commas/semicolons/dashes — can't be split, stays as one chunk
        let text = String(repeating: "word ", count: 70) // ~350 chars, no delimiters
        XCTAssertGreaterThan(text.count, 280)

        let chunks = service.splitIntoSentenceChunks(text)
        XCTAssertEqual(chunks.sentences.count, 1, "Chunk with no clause delimiters should stay as one")
    }

    func testCommaAttachesToLeftChunkAfterSplit() {
        // Verify that when splitting at ", ", the comma stays on the left chunk
        let text = "This is the first clause of this really long sentence that keeps going and going on and on endlessly, " +
            "and this is the second clause that also keeps going on and on and on and on forever and ever without stopping, " +
            "plus a third clause to make it extra long and ensure it definitely gets split at clause boundaries by the algorithm."
        XCTAssertGreaterThan(text.count, 280)

        let chunks = service.splitIntoSentenceChunks(text)
        XCTAssertGreaterThan(chunks.sentences.count, 1)

        // At least one left chunk should end with a comma (comma attached to left)
        let hasCommaEnding = chunks.sentences.dropLast().contains { $0.hasSuffix(",") }
        XCTAssertTrue(hasCommaEnding, "Comma should attach to left chunk after split")
    }

    func testAggressiveMergingReducesChunkCount() {
        // Two sentences: 120 chars + 100 chars = 220 combined (well under 280)
        // Old logic (both must be < 80) would NOT merge. New logic merges them.
        let s1 = "The weather forecast predicted heavy rain throughout the entire week starting from Monday until late Friday evening."
        let s2 = "Despite the warnings many people still went outdoors to enjoy the unusually warm temperatures."
        XCTAssertGreaterThan(s1.count, 80)
        XCTAssertGreaterThan(s2.count, 80)
        XCTAssertLessThanOrEqual(s1.count + 1 + s2.count, 280) // +1 for space gap

        let text = s1 + " " + s2
        let chunks = service.splitIntoSentenceChunks(text)
        XCTAssertEqual(chunks.sentences.count, 1, "Adjacent sentences fitting within 280 chars should merge")
    }

    func testAllChunksUseLowReasoningPolicyAfterSplitting() {
        // Long run-on sentence with commas — after clause splitting, each chunk should be <300 → low reasoning
        let text = "I went to the store yesterday to buy some groceries because we were running low on everything, " +
            "and then I stopped by the pharmacy to pick up my prescription that had been waiting for a few days, " +
            "and after that I drove home through the heavy traffic which took forever to clear up on the highway."

        let chunks = service.splitIntoSentenceChunks(text)

        for sentence in chunks.sentences {
            let policy = service.requestPolicy(for: sentence)
            XCTAssertEqual(policy.reasoningEffort, "low",
                "Chunk of \(sentence.count) chars should use low reasoning: '\(sentence.prefix(50))...'")
        }
    }

    func testReassemblyWithMixedSentencesAndClauseSplitChunks() {
        // Mix of short sentences and one long run-on
        let text = "Short one. Another short. " +
            "This is a very long run-on sentence that goes on and on with many commas, " +
            "and it just keeps going without stopping for breath or a period anywhere in sight, " +
            "and then it finally ends with some more words about the weather and how nice it is outside today. " +
            "Final short sentence."

        let chunks = service.splitIntoSentenceChunks(text)
        let reassembled = GroqService.reassemble(chunks: chunks, corrected: chunks.sentences)
        XCTAssertEqual(reassembled, text, "Reassembly must be exact with mixed sentence sizes")
    }

    func testClauseSplitDoesNotCreateTinyFragments() {
        // Sentence with a comma very early — should NOT split there (< 40 chars on left)
        // "Hi, " is only 3 chars on the left side — too small
        let text = "Hi, this is a really long sentence that just keeps going on and on and on and on and on " +
            "with absolutely no other commas or semicolons or dashes anywhere in the remaining text whatsoever at all " +
            "and it continues further past the two hundred and eighty character threshold without any breaks."
        XCTAssertGreaterThan(text.count, 280)

        let chunks = service.splitIntoSentenceChunks(text)

        // If it splits, left fragment should be >= 40 chars
        for sentence in chunks.sentences {
            if chunks.sentences.count > 1 {
                XCTAssertGreaterThanOrEqual(sentence.count, 3,
                    "Clause split should not create trivially small fragments")
            }
        }
    }
}
