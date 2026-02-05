import 'challenge.dart';

const helloDart = Challenge(
  id: 'hello_dart',
  title: 'Hello Dart',
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

const allChallenges = [helloDart, sumList, fizzbuzz];
