import 'challenge.dart';

// ---------------------------------------------------------------------------
// Beginner challenges (10 total)
// ---------------------------------------------------------------------------

const helloDart = Challenge(
  id: 'hello_dart',
  title: 'Hello Dart',
  difficulty: Difficulty.beginner,
  description: 'Write a function that returns a greeting string.\n'
      'Given a name, return "Hello, <name>!".',
  starterCode: '''
String greet(String name) {
  // TODO: Return a greeting string
}

void main() {
  print(greet('World'));
}
''',
);

const sumList = Challenge(
  id: 'sum_list',
  title: 'Sum a List',
  difficulty: Difficulty.beginner,
  description: 'Write a function that returns the sum of all integers '
      'in a list.\nReturn 0 for an empty list.',
  starterCode: '''
int sumAll(List<int> numbers) {
  // TODO: Return the sum of all numbers
}

void main() {
  print(sumAll([1, 2, 3, 4, 5])); // 15
  print(sumAll([])); // 0
}
''',
);

const fizzbuzz = Challenge(
  id: 'fizzbuzz',
  title: 'FizzBuzz',
  difficulty: Difficulty.beginner,
  description: 'Write a function that returns a list of strings from 1 to n.\n'
      'For multiples of 3, use "Fizz".\n'
      'For multiples of 5, use "Buzz".\n'
      'For multiples of both, use "FizzBuzz".\n'
      'Otherwise, use the number as a string.',
  starterCode: '''
List<String> fizzBuzz(int n) {
  // TODO: Implement FizzBuzz
}

void main() {
  print(fizzBuzz(15));
}
''',
);

const stringReversal = Challenge(
  id: 'string_reversal',
  title: 'String Reversal',
  difficulty: Difficulty.beginner,
  description: 'Write a function that reverses a string.\n'
      'For example, "hello" becomes "olleh".',
  starterCode: '''
String reverseString(String input) {
  // TODO: Return the reversed string
}

void main() {
  print(reverseString('hello')); // olleh
  print(reverseString('Dart'));  // traD
  print(reverseString(''));      // (empty string)
}
''',
);

const evenNumbers = Challenge(
  id: 'even_numbers',
  title: 'Even Numbers',
  difficulty: Difficulty.beginner,
  description: 'Write a function that takes a list of integers and returns '
      'a new list containing only the even numbers.\n'
      'Preserve the original order. Return an empty list if there are no '
      'even numbers.',
  starterCode: '''
List<int> filterEvens(List<int> numbers) {
  // TODO: Return only the even numbers
}

void main() {
  print(filterEvens([1, 2, 3, 4, 5, 6])); // [2, 4, 6]
  print(filterEvens([1, 3, 5]));           // []
  print(filterEvens([]));                  // []
}
''',
);

const palindromeCheck = Challenge(
  id: 'palindrome_check',
  title: 'Palindrome Check',
  difficulty: Difficulty.beginner,
  description: 'Write a function that checks whether a string is a palindrome.\n'
      'A palindrome reads the same forwards and backwards.\n'
      'The check should be case-insensitive and ignore spaces.',
  starterCode: '''
bool isPalindrome(String input) {
  // TODO: Return true if the input is a palindrome
}

void main() {
  print(isPalindrome('racecar'));     // true
  print(isPalindrome('Race Car'));    // true
  print(isPalindrome('hello'));       // false
  print(isPalindrome('A Santa at NASA')); // true
}
''',
);

const wordCounter = Challenge(
  id: 'word_counter',
  title: 'Word Counter',
  difficulty: Difficulty.beginner,
  description: 'Write a function that counts the number of words in a string.\n'
      'Words are separated by one or more spaces.\n'
      'Return 0 for an empty or whitespace-only string.',
  starterCode: '''
int countWords(String text) {
  // TODO: Return the number of words
}

void main() {
  print(countWords('Hello World'));        // 2
  print(countWords('  Dart is  great  ')); // 3
  print(countWords(''));                   // 0
  print(countWords('   '));                // 0
}
''',
);

const temperatureConverter = Challenge(
  id: 'temperature_converter',
  title: 'Temperature Converter',
  difficulty: Difficulty.beginner,
  description: 'Write a function that converts a temperature from Celsius '
      'to Fahrenheit.\n'
      'Formula: F = C * 9/5 + 32\n'
      'Return the result as a double.',
  starterCode: '''
double celsiusToFahrenheit(double celsius) {
  // TODO: Convert Celsius to Fahrenheit
}

void main() {
  print(celsiusToFahrenheit(0));    // 32.0
  print(celsiusToFahrenheit(100));  // 212.0
  print(celsiusToFahrenheit(-40));  // -40.0
  print(celsiusToFahrenheit(37));   // 98.6
}
''',
);

const findMaximum = Challenge(
  id: 'find_maximum',
  title: 'Find Maximum',
  difficulty: Difficulty.beginner,
  description: 'Write a function that finds the largest number in a list '
      'of integers.\n'
      'Do not use the built-in reduce or fold methods.\n'
      'You may assume the list is non-empty.',
  starterCode: '''
int findMax(List<int> numbers) {
  // TODO: Return the largest number without using reduce/fold
}

void main() {
  print(findMax([3, 1, 4, 1, 5, 9, 2, 6])); // 9
  print(findMax([-5, -1, -8]));               // -1
  print(findMax([42]));                       // 42
}
''',
);

const removeDuplicates = Challenge(
  id: 'remove_duplicates',
  title: 'Remove Duplicates',
  difficulty: Difficulty.beginner,
  description: 'Write a function that removes duplicate items from a list, '
      'keeping only the first occurrence of each element.\n'
      'Preserve the original order of elements.',
  starterCode: '''
List<int> removeDuplicates(List<int> items) {
  // TODO: Return a new list with duplicates removed
}

void main() {
  print(removeDuplicates([1, 2, 3, 2, 1, 4])); // [1, 2, 3, 4]
  print(removeDuplicates([5, 5, 5]));           // [5]
  print(removeDuplicates([]));                  // []
}
''',
);

// ---------------------------------------------------------------------------
// Intermediate challenges (7 total)
// ---------------------------------------------------------------------------

const binarySearch = Challenge(
  id: 'binary_search',
  title: 'Binary Search',
  difficulty: Difficulty.intermediate,
  description: 'Implement binary search on a sorted list of integers.\n'
      'Return the index of the target value, or -1 if not found.\n'
      'Do not use indexOf or any built-in search methods.',
  starterCode: '''
int binarySearch(List<int> sortedList, int target) {
  // TODO: Implement binary search
  // Return the index of target, or -1 if not found
}

void main() {
  final list = [1, 3, 5, 7, 9, 11, 13, 15];
  print(binarySearch(list, 7));  // 3
  print(binarySearch(list, 1));  // 0
  print(binarySearch(list, 15)); // 7
  print(binarySearch(list, 6));  // -1
}
''',
);

const fibonacciSequence = Challenge(
  id: 'fibonacci_sequence',
  title: 'Fibonacci Sequence',
  difficulty: Difficulty.intermediate,
  description: 'Write a function that generates the first n numbers of the '
      'Fibonacci sequence.\n'
      'The sequence starts with 0, 1 and each subsequent number is the sum '
      'of the two preceding ones.\n'
      'Return an empty list if n is 0.',
  starterCode: '''
List<int> fibonacci(int n) {
  // TODO: Return the first n Fibonacci numbers
}

void main() {
  print(fibonacci(8));  // [0, 1, 1, 2, 3, 5, 8, 13]
  print(fibonacci(1));  // [0]
  print(fibonacci(0));  // []
}
''',
);

const caesarCipher = Challenge(
  id: 'caesar_cipher',
  title: 'Caesar Cipher',
  difficulty: Difficulty.intermediate,
  description: 'Implement a Caesar cipher that shifts each letter by a '
      'given amount.\n'
      'Only shift alphabetic characters (a-z, A-Z). Preserve case.\n'
      'Non-alphabetic characters remain unchanged.\n'
      'Handle shifts larger than 26 and negative shifts.',
  starterCode: '''
String caesarCipher(String text, int shift) {
  // TODO: Shift each letter by the given amount
}

void main() {
  print(caesarCipher('Hello, World!', 3));  // Khoor, Zruog!
  print(caesarCipher('Khoor, Zruog!', -3)); // Hello, World!
  print(caesarCipher('abc XYZ', 1));        // bcd YZA
}
''',
);

const anagramChecker = Challenge(
  id: 'anagram_checker',
  title: 'Anagram Checker',
  difficulty: Difficulty.intermediate,
  description: 'Write a function that checks whether two strings are anagrams '
      'of each other.\n'
      'Two strings are anagrams if they contain the same characters with the '
      'same frequencies.\n'
      'The comparison should be case-insensitive and ignore spaces.',
  starterCode: '''
bool areAnagrams(String a, String b) {
  // TODO: Return true if a and b are anagrams
}

void main() {
  print(areAnagrams('listen', 'silent'));       // true
  print(areAnagrams('Astronomer', 'Moon starer')); // true
  print(areAnagrams('hello', 'world'));         // false
  print(areAnagrams('aab', 'abb'));             // false
}
''',
);

const flattenList = Challenge(
  id: 'flatten_list',
  title: 'Flatten List',
  difficulty: Difficulty.intermediate,
  description: 'Write a function that flattens a nested list of integers '
      'into a single flat list.\n'
      'The input can contain integers and lists of integers (which may '
      'themselves be nested).\n'
      'Use the dynamic type for the input elements.',
  starterCode: '''
List<int> flatten(List<dynamic> nested) {
  // TODO: Flatten the nested list into a single list of ints
}

void main() {
  print(flatten([1, [2, 3], [4, [5, 6]]])); // [1, 2, 3, 4, 5, 6]
  print(flatten([[1], [2], [3]]));           // [1, 2, 3]
  print(flatten([1, 2, 3]));                 // [1, 2, 3]
  print(flatten([]));                        // []
}
''',
);

const matrixSum = Challenge(
  id: 'matrix_sum',
  title: 'Matrix Sum',
  difficulty: Difficulty.intermediate,
  description: 'Write a function that computes the sum of all elements in '
      'a 2D list (matrix) of integers.\n'
      'The matrix may have rows of different lengths.\n'
      'Return 0 for an empty matrix.',
  starterCode: '''
int matrixSum(List<List<int>> matrix) {
  // TODO: Return the sum of all elements in the matrix
}

void main() {
  print(matrixSum([
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9],
  ])); // 45

  print(matrixSum([
    [10],
    [20, 30],
  ])); // 60

  print(matrixSum([])); // 0
}
''',
);

const bracketMatching = Challenge(
  id: 'bracket_matching',
  title: 'Bracket Matching',
  difficulty: Difficulty.intermediate,
  description: 'Write a function that checks whether a string of brackets '
      'is balanced.\n'
      'Support three types of brackets: (), [], {}.\n'
      'Non-bracket characters should be ignored.\n'
      'An empty string is considered balanced.',
  starterCode: '''
bool isBalanced(String input) {
  // TODO: Return true if all brackets are properly matched
}

void main() {
  print(isBalanced('({[]})')); // true
  print(isBalanced('([)]'));   // false
  print(isBalanced('{[()]}'));  // true
  print(isBalanced('hello'));  // true
  print(isBalanced('(('));     // false
  print(isBalanced(''));       // true
}
''',
);

// ---------------------------------------------------------------------------
// Advanced challenges (6 total)
// ---------------------------------------------------------------------------

const mergeSort = Challenge(
  id: 'merge_sort',
  title: 'Merge Sort',
  difficulty: Difficulty.advanced,
  description: 'Implement the merge sort algorithm.\n'
      'Merge sort works by dividing the list in half, recursively sorting '
      'each half, then merging the two sorted halves together.\n'
      'Return a new sorted list (do not modify the original).',
  starterCode: '''
List<int> mergeSort(List<int> list) {
  // TODO: Implement merge sort
}

List<int> merge(List<int> left, List<int> right) {
  // TODO: Merge two sorted lists into one sorted list
}

void main() {
  print(mergeSort([38, 27, 43, 3, 9, 82, 10])); // [3, 9, 10, 27, 38, 43, 82]
  print(mergeSort([5, 1, 4, 2, 8]));             // [1, 2, 4, 5, 8]
  print(mergeSort([]));                           // []
  print(mergeSort([1]));                          // [1]
}
''',
);

const stackImplementation = Challenge(
  id: 'stack_implementation',
  title: 'Stack Implementation',
  difficulty: Difficulty.advanced,
  description: 'Implement a generic Stack data structure with the following '
      'methods:\n'
      '- push(item): Add an item to the top\n'
      '- pop(): Remove and return the top item (throw if empty)\n'
      '- peek(): Return the top item without removing it (throw if empty)\n'
      '- isEmpty: Check if the stack is empty\n'
      '- size: Return the number of items',
  starterCode: '''
class Stack<T> {
  // TODO: Add internal storage

  void push(T item) {
    // TODO: Add item to the top of the stack
  }

  T pop() {
    // TODO: Remove and return the top item
    // Throw StateError if empty
    throw UnimplementedError();
  }

  T peek() {
    // TODO: Return the top item without removing it
    // Throw StateError if empty
    throw UnimplementedError();
  }

  bool get isEmpty => throw UnimplementedError();

  int get size => throw UnimplementedError();
}

void main() {
  final stack = Stack<int>();
  stack.push(1);
  stack.push(2);
  stack.push(3);
  print(stack.peek()); // 3
  print(stack.pop());  // 3
  print(stack.pop());  // 2
  print(stack.size);   // 1
  print(stack.isEmpty); // false
  print(stack.pop());  // 1
  print(stack.isEmpty); // true
}
''',
);

const romanNumerals = Challenge(
  id: 'roman_numerals',
  title: 'Roman Numerals',
  difficulty: Difficulty.advanced,
  description: 'Write a function that converts a positive integer to its '
      'Roman numeral representation.\n'
      'Use standard Roman numerals:\n'
      'I=1, V=5, X=10, L=50, C=100, D=500, M=1000\n'
      'Use subtractive notation (e.g., IV=4, IX=9, XL=40, XC=90, CD=400, '
      'CM=900).\n'
      'Input range: 1 to 3999.',
  starterCode: '''
String toRoman(int number) {
  // TODO: Convert the integer to a Roman numeral string
}

void main() {
  print(toRoman(1));    // I
  print(toRoman(4));    // IV
  print(toRoman(9));    // IX
  print(toRoman(58));   // LVIII
  print(toRoman(1994)); // MCMXCIV
  print(toRoman(3999)); // MMMCMXCIX
}
''',
);

const runLengthEncoding = Challenge(
  id: 'run_length_encoding',
  title: 'Run Length Encoding',
  difficulty: Difficulty.advanced,
  description: 'Implement run-length encoding (RLE) compression and '
      'decompression.\n'
      'Encoding: consecutive identical characters are replaced with the '
      'character followed by its count.\n'
      'Single characters should still include the count (e.g., "a" becomes '
      '"a1").\n'
      'Write both encode and decode functions.',
  starterCode: '''
String encode(String input) {
  // TODO: Compress the string using run-length encoding
  // Example: "aaabbc" -> "a3b2c1"
}

String decode(String encoded) {
  // TODO: Decompress a run-length encoded string
  // Example: "a3b2c1" -> "aaabbc"
}

void main() {
  print(encode('aaabbbcccd'));    // a3b3c3d1
  print(encode('aabbc'));        // a2b2c1
  print(encode(''));             // (empty string)

  print(decode('a3b3c3d1'));     // aaabbbcccd
  print(decode('a1b1c1'));       // abc
  print(decode(''));             // (empty string)
}
''',
);

const longestCommonSubsequence = Challenge(
  id: 'longest_common_subsequence',
  title: 'Longest Common Subsequence',
  difficulty: Difficulty.advanced,
  description: 'Write a function that finds the longest common subsequence '
      '(LCS) of two strings.\n'
      'A subsequence is a sequence of characters that appears in the same '
      'relative order but not necessarily contiguously.\n'
      'Return the LCS string. If there are multiple LCS of the same length, '
      'return any one of them.\n'
      'Hint: Use dynamic programming with a 2D table.',
  starterCode: '''
String longestCommonSubsequence(String a, String b) {
  // TODO: Find the longest common subsequence of a and b
}

void main() {
  print(longestCommonSubsequence('ABCBDAB', 'BDCAB')); // BCAB (or BDAB)
  print(longestCommonSubsequence('AGGTAB', 'GXTXAYB')); // GTAB
  print(longestCommonSubsequence('abc', 'def'));          // (empty string)
  print(longestCommonSubsequence('abc', 'abc'));          // abc
}
''',
);

const asyncDataPipeline = Challenge(
  id: 'async_data_pipeline',
  title: 'Async Data Pipeline',
  difficulty: Difficulty.advanced,
  description: 'Build an asynchronous data pipeline that chains Future '
      'operations.\n'
      'Implement three async functions:\n'
      '- fetchData(): Simulates fetching raw data (returns a list of ints '
      'after a delay)\n'
      '- transformData(data): Doubles each value and filters out values > 10\n'
      '- formatResults(data): Converts each int to a string like "Value: n"\n\n'
      'Then write a pipeline() function that chains them together using '
      'async/await.',
  starterCode: '''
Future<List<int>> fetchData() async {
  // TODO: Simulate a network delay of 100ms
  // then return [1, 3, 5, 7, 9]
  throw UnimplementedError();
}

Future<List<int>> transformData(List<int> data) async {
  // TODO: Double each value, then keep only values <= 10
  throw UnimplementedError();
}

Future<List<String>> formatResults(List<int> data) async {
  // TODO: Convert each int to "Value: n"
  throw UnimplementedError();
}

Future<List<String>> pipeline() async {
  // TODO: Chain fetchData -> transformData -> formatResults
  throw UnimplementedError();
}

void main() async {
  final results = await pipeline();
  print(results); // [Value: 2, Value: 6, Value: 10]
}
''',
);

// ---------------------------------------------------------------------------
// All challenges, ordered by difficulty then by original order.
// ---------------------------------------------------------------------------

const allChallenges = [
  // Beginner
  helloDart,
  sumList,
  fizzbuzz,
  stringReversal,
  evenNumbers,
  palindromeCheck,
  wordCounter,
  temperatureConverter,
  findMaximum,
  removeDuplicates,
  // Intermediate
  binarySearch,
  fibonacciSequence,
  caesarCipher,
  anagramChecker,
  flattenList,
  matrixSum,
  bracketMatching,
  // Advanced
  mergeSort,
  stackImplementation,
  romanNumerals,
  runLengthEncoding,
  longestCommonSubsequence,
  asyncDataPipeline,
];
