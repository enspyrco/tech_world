enum Difficulty { beginner, intermediate, advanced }

/// The closed set of code-editor coding challenges.
///
/// `CodeChallengeId` is the **domain type** for code challenges across the
/// editor flow, ChatService help requests, and ProgressService completions
/// originating from the code editor. Strings only appear at boundaries —
/// Firestore on-disk format, chat metadata payloads — and parse via
/// [CodeChallengeId.parse].
///
/// This is a sibling type to `PromptChallengeId` (in `lib/prompt/`). Both
/// share `ProgressService` as the persistence layer, where they convert
/// to [String] via [wireName] at the call site. The two namespaces are
/// disjoint by construction (every `CodeChallengeId.wireName` differs
/// from every `PromptChallengeId.wireName`) so the shared Firestore array
/// is unambiguous.
///
/// Wire format: each value owns its [wireName] (e.g.
/// `CodeChallengeId.helloDart.wireName == 'hello_dart'`). Existing
/// Firestore data parses unchanged.
enum CodeChallengeId {
  helloDart('hello_dart'),
  sumList('sum_list'),
  fizzbuzz('fizzbuzz'),
  stringReversal('string_reversal'),
  evenNumbers('even_numbers'),
  palindromeCheck('palindrome_check'),
  wordCounter('word_counter'),
  temperatureConverter('temperature_converter'),
  findMaximum('find_maximum'),
  removeDuplicates('remove_duplicates'),
  binarySearch('binary_search'),
  fibonacciSequence('fibonacci_sequence'),
  caesarCipher('caesar_cipher'),
  anagramChecker('anagram_checker'),
  flattenList('flatten_list'),
  matrixSum('matrix_sum'),
  bracketMatching('bracket_matching'),
  mergeSort('merge_sort'),
  stackImplementation('stack_implementation'),
  romanNumerals('roman_numerals'),
  runLengthEncoding('run_length_encoding'),
  longestCommonSubsequence('longest_common_subsequence'),
  asyncDataPipeline('async_data_pipeline');

  const CodeChallengeId(this.wireName);

  /// On-disk / wire identifier. Stable across refactors of the Dart
  /// identifier — this is what Firestore stores.
  final String wireName;

  /// Parse a wire-format string into a [CodeChallengeId], or `null` if
  /// unknown. Use at boundaries (Firestore reads, chat metadata) and
  /// decide what to do with `null` at the call site.
  static CodeChallengeId? parse(String wire) {
    for (final c in CodeChallengeId.values) {
      if (c.wireName == wire) return c;
    }
    return null;
  }
}

class Challenge {
  const Challenge({
    required this.id,
    required this.title,
    required this.description,
    required this.starterCode,
    this.difficulty = Difficulty.beginner,
  });

  /// Strongly-typed identifier — see [CodeChallengeId].
  final CodeChallengeId id;
  final String title;
  final String description;
  final String starterCode;
  final Difficulty difficulty;
}
