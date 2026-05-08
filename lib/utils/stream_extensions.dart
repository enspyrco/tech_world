/// Stream extensions for Kleisli composition in the Maybe-Stream monad.
///
/// The `.whereMap<T>(f)` extension replaces the repeated pattern:
///
///     stream.map((x) { ... return nullable; }).where((x) => x != null).cast<T>()
///
/// which is `flatMap` in the composition of `Maybe` and `Stream` monads.
/// Each mapping function `S -> T?` is a Kleisli arrow: `S -> Maybe<T>`.
/// `.whereMap` lifts it into `Stream<S> -> Stream<T>`.
extension StreamWhereMap<S> on Stream<S> {
  /// Apply [f] to each element and emit only non-null results.
  ///
  /// Equivalent to `.map(f).where((x) => x != null).cast<T>()` but
  /// expressed as a single combinator. Named `whereMap` because it
  /// maps and filters in one step — the Kleisli bind of the Maybe monad
  /// over a Stream.
  Stream<T> whereMap<T>(T? Function(S) f) =>
      map(f).where((x) => x != null).cast<T>();
}
