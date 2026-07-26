import 'dart:typed_data';

/// A renderer-neutral snapshot of a room, for display in a room-listing
/// surface such as a foyer.
///
/// Sealed so the "image XOR vector" invariant is enforced by the type system
/// rather than by prose discipline. A renderer walks the variants with an
/// exhaustive `switch` — no nullable-pair ambiguity, no "both populated"
/// failure mode.
///
/// An audience-bounded sealed surface: adding a variant IS a breaking change
/// for consumers' exhaustive switches, and lands as a minor-version bump with
/// a migration note. Leaves are `final` (`sealed` root + `final` leaves) so the
/// hierarchy is closed at both ends — no other package can subclass a variant.
sealed class RoomPreview {
  /// Creates a preview carrying [worldHints].
  const RoomPreview({required this.worldHints});

  /// Non-visual facts about the room, renderable even when the visual isn't.
  final PreviewHints worldHints;
}

/// A raster snapshot — PNG/WebP bytes a renderer can blit directly.
final class RasterPreview extends RoomPreview {
  /// Creates a raster preview from encoded [image] bytes.
  const RasterPreview({required this.image, required super.worldHints});

  /// Encoded image bytes.
  final Uint8List image;
}

/// A vector shape list a renderer draws in whatever style it likes.
///
/// Lets a world describe its shape without committing to pixels, so the
/// renderer can theme, dim, or scale the preview to match its own presentation.
final class VectorPreview extends RoomPreview {
  /// Creates a vector preview from [shapes].
  const VectorPreview({required this.shapes, required super.worldHints});

  /// Shapes to render, in paint order.
  final List<PreviewShape> shapes;
}

/// "I have no visual to show — just use the hints."
///
/// The renderer draws a generic placeholder from [RoomPreview.worldHints] and
/// nothing more.
final class EmptyPreview extends RoomPreview {
  /// Creates a hints-only preview.
  const EmptyPreview({required super.worldHints});
}

/// Non-visual facts about a room's current state.
class PreviewHints {
  /// Creates preview hints.
  const PreviewHints({
    required this.participantCount,
    this.activityLabel,
    this.voiceActive = false,
  });

  /// How many participants are currently in the room.
  final int participantCount;

  /// A short world-authored description, e.g. 'live coding', 'quiet'.
  final String? activityLabel;

  /// Whether anyone is currently speaking.
  final bool voiceActive;
}

/// A shape in a [VectorPreview]. Open extension point.
///
/// Deliberately NOT sealed: sealing would commit the engine to a closed
/// vector-graphics vocabulary, contradicting the rule that the engine has no
/// rendering opinion. Worlds wanting bezier curves, SVG paths, glyph runs or
/// anything else ship their own `implements PreviewShape` types in their own
/// package. The three below are conveniences, not a complete vocabulary.
///
/// ## VectorPreview rendering contract
///
/// Binding on every consumer of [RoomPreview] that switches on
/// [VectorPreview] and walks [VectorPreview.shapes] — the reference room-listing
/// UI, operator-built listings, and debug tooling alike. It does NOT bind
/// `PresenceService.watchPublicPresence` consumers, which see `PublicProjection`
/// (carrying an opaque avatar ref, not shapes).
///
/// 1. **Per-shape skip, not per-preview discard.** Unknown shapes are skipped
///    individually. Known sibling shapes in the same preview MUST still
///    render. A renderer never discards a whole preview over one unrecognised
///    shape.
/// 2. **Telemetry, not error.** An unknown shape emits an
///    `UnknownPreviewShapeEncountered` event (PII policy: non-PII) so
///    operators can detect worlds shipping shapes their renderer can't render.
/// 3. **No exceptions cross the render boundary.** Previews render during
///    listing scroll; one bad shape MUST NOT halt the listing. Renderers wrap each shape
///    in a try/catch and treat any failure as a skip plus a separate
///    `PreviewShapeRenderFailed` event.
///
/// **Enforcement status: prose-grade.** The `realm_test` conformance package
/// and the `RoomPreviewRenderer` mixin that would make this structural are
/// deferred to their own PR. Until they ship, the compensating control is
/// cage-match review of any new [VectorPreview] consumer.
abstract interface class PreviewShape {}

/// A circle, in the world's own preview coordinate space.
class CirclePreviewShape implements PreviewShape {
  /// Creates a circle of [radius] at [center].
  const CirclePreviewShape({required this.center, required this.radius});

  /// Circle centre.
  final ({double x, double y}) center;

  /// Circle radius.
  final double radius;
}

/// A rectangle, in the world's own preview coordinate space.
class RectPreviewShape implements PreviewShape {
  /// Creates a rectangle of [size] with its top-left at [origin].
  const RectPreviewShape({required this.origin, required this.size});

  /// Top-left corner.
  final ({double x, double y}) origin;

  /// Width and height.
  final ({double width, double height}) size;
}

/// A text run, in the world's own preview coordinate space.
///
/// The renderer chooses the font, size and colour — the world supplies only the
/// string and where it sits.
class TextPreviewShape implements PreviewShape {
  /// Creates a text run at [origin].
  const TextPreviewShape({required this.text, required this.origin});

  /// The string to draw.
  final String text;

  /// Where the run starts.
  final ({double x, double y}) origin;
}
