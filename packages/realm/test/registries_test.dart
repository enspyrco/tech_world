import 'package:realm/realm.dart';
import 'package:test/test.dart';

/// A world that does nothing, for registry tests that only care about identity.
class _StubWorld implements World {
  _StubWorld(this.descriptor);

  @override
  final RoomDescriptor descriptor;

  @override
  RoomId get roomId => descriptor.id;

  @override
  Future<void> onEnter() async {}

  @override
  void onPeerJoin(RealmUser peer) {}

  @override
  void onPeerLeave(UserId peerId) {}

  @override
  Future<void> onLeave(LeaveReason reason) async {}

  @override
  Future<RoomPreview?> previewSnapshot() async => null;
}

void main() {
  group('WorldTypeRegistry', () {
    test('a wire string is not a WorldTypeId until a registry vouches for it',
        () {
      final registry = WorldTypeRegistry();

      // This is the whole point of the branded type: a typo in a room document
      // cannot become a live worldType, because there is no path from String
      // to WorldTypeId that skips the registry.
      expect(
        () => WorldTypeId.parse('tech_wrold', registry),
        throwsA(isA<WorldTypeNotRegistered>()),
      );

      registry.register('tech_world', _StubWorld.new);
      expect(WorldTypeId.parse('tech_world', registry).value, 'tech_world');
    });

    test('registries are instances, so two are genuinely independent', () {
      // Not incidental — it is why parallel tests do not contaminate each
      // other, why hot reload leaves no stale registrations, and why two
      // operators can host disjoint sets of world types in one process.
      final a = WorldTypeRegistry()..register('foyer', _StubWorld.new);
      final b = WorldTypeRegistry();

      expect(a.isRegistered('foyer'), isTrue);
      expect(b.isRegistered('foyer'), isFalse);
      expect(
        () => WorldTypeId.parse('foyer', b),
        throwsA(isA<WorldTypeNotRegistered>()),
      );
    });

    test('duplicate registration throws unless override is explicit', () {
      final registry = WorldTypeRegistry()..register('repo_body', _StubWorld.new);

      expect(
        () => registry.register('repo_body', _StubWorld.new),
        throwsStateError,
      );

      // The override path exists for test setups that deliberately swap an
      // implementation. Requiring the flag keeps an accidental double-register
      // in production code loud instead of last-write-wins.
      registry.register('repo_body', _StubWorld.new, allowOverride: true);
      expect(registry.isRegistered('repo_body'), isTrue);
    });

    test('instantiate dispatches through the registry, not a switch', () {
      final registry = WorldTypeRegistry()..register('tech_world', _StubWorld.new);
      final descriptor = RoomDescriptor(
        id: const RoomId('room-1'),
        displayName: 'Wizards Tower',
        worldType: WorldTypeId.parse('tech_world', registry),
        foyerVisibility: FoyerVisibility.public,
      );

      final world = registry.instantiate(descriptor);
      expect(world, isA<_StubWorld>());
      expect(world.roomId, const RoomId('room-1'));
    });
  });

  group('StorageBackendRegistry', () {
    test('canonical backends work without any operator setup', () {
      final registry = StorageBackendRegistry();

      for (final wire in ['firebase', 's3', 'local']) {
        expect(registry.isRegistered(wire), isTrue, reason: wire);
        expect(StorageBackendId.parse(wire, registry).value, wire);
      }
    });

    test('an unknown backend is refused', () {
      expect(
        () => StorageBackendId.parse('dropbox', StorageBackendRegistry()),
        throwsArgumentError,
      );
    });

    test('an operator can add a backend the engine never heard of', () {
      final registry = StorageBackendRegistry()..register('minio');
      expect(StorageBackendId.parse('minio', registry).value, 'minio');
    });

    test('re-registering a canonical backend throws without override', () {
      expect(
        () => StorageBackendRegistry().register('firebase'),
        throwsStateError,
      );
    });
  });
}
