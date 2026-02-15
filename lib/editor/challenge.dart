enum Difficulty { beginner, intermediate, advanced }

class Challenge {
  const Challenge({
    required this.id,
    required this.title,
    required this.description,
    required this.starterCode,
    this.difficulty = Difficulty.beginner,
  });

  final String id;
  final String title;
  final String description;
  final String starterCode;
  final Difficulty difficulty;
}
