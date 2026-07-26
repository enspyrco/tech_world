import 'dart:typed_data';

/// Blob storage for worlds that need to persist bytes.
///
/// **No-leak rule**: no backend type may cross this boundary. Implementations
/// translate `firebase_storage.Reference`, `gs://` URLs and provider metadata
/// types into [BlobRef] and plain Dart values.
abstract interface class StorageProvider {
  /// Stores [bytes] at [path] and returns a reference to them.
  Future<BlobRef> upload(
    Uint8List bytes, {
    required String path,
    String? contentType,
  });

  /// Retrieves the bytes [ref] points at.
  Future<Uint8List> download(BlobRef ref);

  /// Returns a URL a renderer can fetch [ref] from directly.
  ///
  /// Whether the URL is time-limited, signed, or permanently public is the
  /// implementation's policy — the engine makes no promise either way, so
  /// consumers must not cache the result indefinitely.
  Future<Uri> publicUrl(BlobRef ref);

  /// Deletes the blob [ref] points at.
  Future<void> delete(BlobRef ref);
}

/// A reference to stored bytes.
class BlobRef {
  /// References [path] within [backend].
  const BlobRef({required this.backend, required this.path});

  /// Which backend holds the bytes.
  final StorageBackendId backend;

  /// Location within [backend]. Opaque — its grammar is the backend's.
  final String path;
}

/// Identifier for a storage backend. Open set, registry-validated.
///
/// Same instance-not-singleton discipline as `WorldTypeRegistry`: a registry
/// is threaded from the engine entry point rather than consulted globally.
///
/// Like `WorldTypeId`, the brand is a parse aid, not a capability — erased at
/// runtime, forgeable by cast, and carrying no registry watermark. Trust-boundary
/// read paths re-`parse` the wire; they don't trust a cast.
extension type const StorageBackendId._(String value) {
  /// Constructs from a wire string, validating against [registry].
  ///
  /// Throws [ArgumentError] if [wire] is not registered.
  factory StorageBackendId.parse(String wire, StorageBackendRegistry registry) {
    if (!registry.isRegistered(wire)) {
      throw ArgumentError.value(wire, 'wire', 'Unknown storage backend');
    }
    return StorageBackendId._(wire);
  }

  /// Firebase Cloud Storage.
  static const firebase = StorageBackendId._('firebase');

  /// S3 or an S3-compatible object store.
  static const s3 = StorageBackendId._('s3');

  /// On-device storage.
  static const local = StorageBackendId._('local');
}

/// Which storage backends this engine instance knows about.
///
/// The three canonical backends self-register so `parse('firebase')` works out
/// of the box; operators with custom backends call [register] at startup.
/// Duplicate registration throws unless [register] is passed
/// `allowOverride: true`.
class StorageBackendRegistry {
  /// Creates a registry pre-populated with the canonical backends.
  StorageBackendRegistry() {
    register(StorageBackendId.firebase.value);
    register(StorageBackendId.s3.value);
    register(StorageBackendId.local.value);
  }

  final Set<String> _registered = {};

  /// Registers [wire] as a known backend and returns its branded id.
  ///
  /// Returns the [StorageBackendId] for the same one-door reason as
  /// [WorldTypeRegistry.register]: a caller that just registered a backend
  /// holds a validated id without threading [wire] back through
  /// [StorageBackendId.parse].
  ///
  /// Throws [StateError] if already registered and [allowOverride] is false.
  StorageBackendId register(String wire, {bool allowOverride = false}) {
    if (!allowOverride && _registered.contains(wire)) {
      throw StateError('StorageBackend "$wire" is already registered. '
          'Pass allowOverride: true to replace.');
    }
    _registered.add(wire);
    return StorageBackendId._(wire);
  }

  /// Whether [wire] names a registered backend.
  bool isRegistered(String wire) => _registered.contains(wire);
}
