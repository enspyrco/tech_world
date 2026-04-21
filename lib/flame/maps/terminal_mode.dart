/// The type of interaction terminals provide in a map.
///
/// Each map has a single terminal mode that applies to all its terminals.
/// This determines what UI opens when a player interacts with a terminal.
enum TerminalMode {
  /// Coding challenges — opens the code editor panel.
  code,

  /// Prompt spell challenges (future) — opens the prompt editor panel.
  prompt,
}
