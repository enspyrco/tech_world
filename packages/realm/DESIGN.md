# Realm — Design Note

A multiplayer worldbuilding engine. Hosts named *rooms*, each of which instantiates a *world*. Provides the shared substrate (identity, presence, voice, room transport, blob storage) so a world can be just its own vocabulary — its listeners, its renderable substrate, its events. BYO backend: Firebase, self-hosted, or anything that satisfies the interfaces.

This document is the architectural pin. It must be cage-matched before any extraction code lands.

## Status

- Author: Claude + Nick (Imagineers)
- Date: 2026-05-21
- Will become: `packages/realm/README.md` once the engine is extracted and the package publishes.
- Decision posture: provisional. Names, interface shapes, and scoping are open until the cage-match closes.

## Why

Two pulls converged this week:

1. **The substrate-has-a-body doc** described Tech World as the Imagineer-altitude rendering of engineering-as-place. Building a second world (a github repo rendered as a body, an org rendered as a city of bodies) would be the natural next step.
2. **The instinct that the right second move isn't "build another app" — it's "let the same client host both worlds, in different rooms."** Rooms already exist in Tech World (Firestore doc IDs, LiveKit channels, per-room presence). They are currently uniform: every room is a Tech World instance. They don't have to be.

The first lens-shift this produces: **a room is a world instance**. The engine's job is to host rooms; a world's job is to declare what one room *is*. Today Tech World is the only world type. Adding "github repo body" as a second world type, instantiated in some rooms, is what proves the engine is real.

The second lens-shift, downstream of the first: **if rooms can host different worlds, the engine is open-source-shaped already**. Anyone running their own LiveKit + auth + storage can host the engine, host their own worlds, and have a multiplayer space that isn't Tech World. The engine is the gift; worlds are the gardens grown in it.

## License and business model

This section is architectural, not marketing. The license shapes what the engine *has to be* — open enough to attract self-hosters and federation partners, with value-capture paths that don't contradict either. Stating goals first, then deriving the answer:

- **People play the game** — adoption needs to be frictionless. Free at the door.
- **Federation across operators** — others must be able to stand up their own Realm instances. Closed source kills this.
- **A business model that sustains growth** — revenue capture, but not at the cost of the first two.

The intersection of these three is the "commercial open source" playbook (GitLab, Sentry, Plausible, Mattermost, Grafana, Discourse). The license is open enough to drive adoption and federation; the business model captures value at the *operational* layer (hosting, enterprise features, marketplace), not the *code* layer.

### License: AGPL v3

Realm engine, reference worlds (Tech World, repo-body, foyer), and reference provider implementations all ship under AGPL v3.

Rationale:
- **AGPL's network-use clause deters competitive cloud clones.** Anyone hosting modified Realm-as-a-service must release their changes. Handles the "Amazon problem" that drove MongoDB to SSPL — without resorting to source-available licenses that fracture community trust.
- **AGPL is dual-license-friendly.** Copyright stays with enspyrco *for first-party code*. Enterprises whose lawyers reject AGPL can pay for a commercial license — revenue path preserved. **External contributions require a Contributor License Agreement (CLA)** assigning copyright (or granting a sufficiently broad license) to enspyrco for the dual-license model to remain viable. Without CLA assignment, third-party contributions would be AGPL-only forever and couldn't be included in any commercial edition. The CLA is a governance commitment, not a legal nicety: contribution pipeline (PR template + automated CLA-bot gate) must be in place before accepting any external PR that materially adds code. DCO sign-off alone is insufficient — DCO grants license to upstream, but doesn't enable relicensing.
- **AGPL is OSI-approved.** Genuine open source, not source-available. Avoids the HashiCorp/Elastic-style community backlash from later license-pivot moves.
- **AGPL is more aggressive about openness than MIT/Apache** — fits the federation goal, where shared-protocol interoperability matters more than maximum adoption.

### Open-core split

Free, AGPL-licensed:
- Realm engine (`packages/realm/`)
- Reference World implementations: `TechWorld`, `RepoBodyWorld`, `FoyerWorld`
- Reference provider implementations: Firebase-backed, GitHub OAuth, etc.
- Federation protocols and reference federation server
- All client SDKs

Commercial / proprietary (enspyrco-hosted or paid license):
- Enterprise SSO (SAML, OIDC)
- Audit logging
- Compliance tooling (SOC2 evidence collection, HIPAA-ready provider implementations)
- Priority support, SLA
- Admin dashboard for organization-scale deployments
- Hosted multi-tenant control plane
- Marketplace integration

Principle: **core experience is free; operational and enterprise concerns are paid.** Same shape as GitLab CE/EE, Sentry, Mattermost.

The hardest discipline this requires: **the free tier must be the real thing, not a crippled demo.** If "free" players can't have a complete Tech World experience because key features are paywalled, the adoption goal fails and the funnel above never fills. Premium features should add to the experience for power users, not gate the baseline.

### Revenue paths

For Tech World (the game, consumer-facing):
- **Free tier**: join enspyrco-hosted rooms, default avatars, baseline challenges, public worlds.
- **Premium player** (~$5-10/mo): custom avatars, persistent progress across sessions, premium worlds, higher AI bot quotas.
- **Creator tier** (~$20-50/mo): host your own rooms on enspyrco infrastructure, custom worlds, monetize your worlds (rev-share back to you).
- **Education tier** (~$100-500/mo per org): private rooms, classroom features, teacher dashboards.

For Realm (the platform, operator-facing):
- **Managed Realm hosting**: per-user or per-instance pricing, like managed Postgres. We run your Realm install, you bring your worlds.
- **Enterprise support and custom development**: SLA, dedicated engineer, custom integrations.
- **Realm Marketplace** (year 2+): worlds, avatars, custom assets sold through us, ~15-30% rev share. This is the long-term big one — economic flywheel for world creators.

### Three tensions named honestly

1. **AGPL deters some enterprise adoption** (corporate lawyers often reject AGPL). This is a feature, not a bug — it's what *forces* the dual-license commercial conversation that becomes revenue. Acceptable trade-off because adoption skews toward smaller orgs and individuals initially, which matches the consumer-Tech-World adoption motion anyway.

2. **Hosted-by-enspyrco competes with self-hosters.** Standard resolution: hosted is for operators who don't want to run infrastructure; self-host is for those who do. Don't make self-hosting deliberately painful to push people to hosted — that destroys community trust and contradicts the federation goal.

3. **Federation can dilute monetization.** Users can play Tech World on `freerealm.example.com` without paying us. The answer: enspyrco-hosted is the canonical implementation with the premium worlds, official events, polish, popular community, and trust. Federation drives reach; hub effect drives revenue. Similar to how `mastodon.social` is the largest Mastodon instance despite the protocol being open.

### Pre-revenue funding

Operate from:
- **Screen Australia Games Production Fund grant** (in flight, `docs/grant-application/`)
- **Bootstrap** — Nick's existing runway
- **GitHub Sponsors / Open Collective** (small but signals legitimacy)
- **Pre-sales of enterprise tier** (deliver as we build) — when product-market fit becomes visible

Deferred:
- **VC funding.** Venture-backed open source has different dynamics (growth-or-die, equity dilution, exit pressure). Not categorically wrong, but not taken by accident. Defer until product traction creates leverage on terms.

### Trademark and patent posture

- Use **™** on "Realm" at publish — common-law trademark, free, immediate. Confers some protection in our specific market.
- Defer **®** registration until the brand is worth defending. Pre-revenue ® filing is mostly vanity, and the existing Realm DB (MongoDB, deprecating) and Realm Engine VTT (dormant) collisions make opposition possible. Re-evaluate at ~year 2.
- **No patents.** Realm's novelty is design-level (substrate-has-a-body, foyer model, federation primitives) — post-Alice v. CLS Bank these are largely unpatentable. FOSS and patents are uncomfortable bedfellows (AGPL includes patent grant clauses). The protections that actually matter for Realm are copyright (automatic), license choice (AGPL), first-mover community gravity, and brand association.

### Cage-match hooks for this section

Reviewers should specifically probe:
- Is AGPL the right license, or should it be source-available (BSL) for stronger anti-clone protection? What's the community-trust trade-off cost?
- Is the open-core split principled, or are any "commercial" features actually core experience hiding behind enterprise branding?
- Does the revenue model assume hosting will be cheap? Have we costed LiveKit + Firebase + storage for projected user counts at each tier?
- Does federation actually drive paid conversion, or does it cannibalize it? Is there a worked example from a comparable open-source-with-federation project?
- Is "no VC" durable, or will work pace force the conversation in 6-12 months? What does a VC-acceptable version of this plan look like, in case we need to pivot?
- Will the free tier actually be the real thing, or will scope-pressure quietly paywall key features and break the adoption funnel?

## Core concept: Realm and World

**Realm** is the engine. **World** is the abstract class that per-room implementations extend.

Two distinct things, two distinct names. The engine hosts Worlds; each room declares which World subclass it instantiates. Reads naturally in English: *"Realm hosts Worlds. Each room is one World."*

Concrete worlds:
- `class TechWorld extends World`
- `class RepoBodyWorld extends World`
- `class FoyerWorld extends World`

There is a naming collision to navigate: Flame already has a `World` class that the current `TechWorld` extends. The resolution is import-prefix in the few files that need both: `import 'package:flame/components.dart' as flame;` — then `flame.World` for Flame's class, plain `World` for the Realm abstraction. Most files only need one or the other.

A `World`:
- Owns the room's renderable substrate (tilemap, computed body, anything else)
- Registers its listeners (door, runestone, repo-as-body, whatever)
- Declares its data channels (LiveKit topics for this world type)
- Reads its per-world config from `RoomConfigStore`
- Implements its lifecycle: `onEnter`, `onLeave(LeaveReason)`, `onPeerJoin`, `onPeerLeave`, optional `previewSnapshot()` for the foyer
- Stays inside the engine's contract — never reaches around it to call backend SDKs directly.

The engine (Realm) knows nothing of spellbooks, doors, repos, or bodies. It knows: rooms exist, users join them, presence happens, voice flows, data channels carry typed messages, blob assets exist somewhere, other rooms are visible from the foyer. Worlds bring meaning.

## Engine contract

The five engine-level interfaces. Every one must obey the **no-leak rule**: no backend-specific type may cross the interface boundary. The engine defines its own `RealmUser`, `RoomDescriptor`, `BlobRef`, `PeerPresence`, etc. Implementations translate to/from their backend.

### 1. `AuthProvider`

Sign-in operations take a sealed `AuthMethod` rather than provider-specific methods. Adding a new provider means adding a subtype to `AuthMethod`, not adding a method to every `AuthProvider` implementation. (Closed-set-as-method-names is the same anti-pattern as closed-set-as-Strings; this design rejects both.)

```dart
abstract interface class AuthProvider {
  Stream<RealmUser?> userChanges();
  RealmUser? get currentUser;
  Future<RealmUser> signIn(AuthMethod method);
  Future<void> signOut();
  Future<RealmCredential> getCredential({bool forceRefresh = false});
}

sealed class AuthMethod {
  const AuthMethod();
}
class GoogleAuth extends AuthMethod {
  const GoogleAuth();
}
class AppleAuth extends AuthMethod {
  const AppleAuth();
}
class GitHubAuth extends AuthMethod {
  const GitHubAuth({this.scopes = const []});
  final List<String> scopes;
}
class EmailPassword extends AuthMethod {
  const EmailPassword({required this.email, required this.password});
  final String email;
  final String password;
}
class MagicLink extends AuthMethod {
  const MagicLink({required this.email});
  final String email;
}
class Passkey extends AuthMethod {
  const Passkey();
}
class Anonymous extends AuthMethod {
  const Anonymous();
}

class RealmUser {
  final UserId id;                    // branded type, stable, opaque to engine
  final String? displayName;          // PII — engine treats as such
  final String? email;                // PII — engine treats as such
  final String? username;             // PII — common across most providers
  final Uri? avatarUrl;
  final bool emailVerified;
  final Set<AuthProviderId> providerIds;
  final Map<String, Object?> extraClaims;  // ⚠️ Provider-specific data.
  // extraClaims is the escape hatch — accessing it couples the consumer to
  // the provider's shape. Use typed fields above where possible.
  // Allowed only inside `packages/realm_<provider>/` plugins; flagged
  // elsewhere by the no-leak lint.
}

/// Engine-defined credential token. Translation from provider-native tokens
/// (Firebase ID token, GitHub access token, etc.) happens server-side at
/// the `LiveKitTokenEndpoint`. Engine never sees provider-native tokens.
class RealmCredential {
  const RealmCredential({required this.token, required this.expiresAt});
  final String token;
  final DateTime expiresAt;
}
```

Must NOT leak: `firebase_auth.User`, `IdTokenResult`, GitHub access tokens, provider SDK exceptions. The engine defines `RealmAuthException` (with subtypes `RealmAuthCancelled`, `RealmAuthNetworkError`, `RealmAuthRateLimited`, `RealmAuthCredentialInvalid`); implementations catch provider exceptions and translate.

Ships in Realm:
- `realm_firebase`: `FirebaseAuthProvider` (handles Google, Apple, email/password via Firebase Auth)
- `realm_github_oauth`: `GitHubAuthProvider` (needed for repo-body; translates GitHub OAuth access tokens to `RealmCredential`)

Provider plugins are responsible for the translation from native tokens to `RealmCredential`. This is the "GitHub OAuth ≠ OIDC ID token" issue resolved: each provider plugin emits a Realm-defined credential token; the `LiveKitTokenEndpoint` only verifies Realm credentials, not raw native ones.

### 2. `RoomConfigStore`

```dart
abstract interface class RoomConfigStore {
  Future<List<RoomDescriptor>> listRooms({
    UserId? ownedBy,
    FoyerVisibility? minVisibility,  // null = no filter
  });
  Future<RoomDescriptor?> getRoom(RoomId roomId);
  Stream<RoomDescriptor> watchRoom(RoomId roomId);
  Future<RoomDescriptor> createRoom(NewRoomSpec spec);
  Future<void> updateRoomConfig(RoomId roomId, Map<String, Object?> patch);
}

class RoomDescriptor {
  final RoomId id;
  final String displayName;
  final WorldTypeId worldType;             // branded — registered worlds only
  final Map<String, Object?> worldConfig;  // opaque to engine; each World owns parseConfig()
  final RealmUser? owner;
  final List<UserId> editorIds;
  final FoyerVisibility foyerVisibility;
  final List<RoomRef>? connectedTo;        // reserved for v2 federation; null in v1
}

/// Branded type for room IDs. Globally unique (UUID-shaped, not <org>:<slug>)
/// so cross-instance federation can collide-resist later.
extension type const RoomId(String value) {}

/// Branded type for user IDs. Opaque to the engine; meaning lives in
/// the AuthProvider that minted it.
extension type const UserId(String value) {}

/// Branded type for world-type identifiers. Open set (external Worlds can
/// register their own type) but validated at construction via the
/// WorldTypeRegistry — a typo can't become a live worldType.
extension type const WorldTypeId._(String value) {
  factory WorldTypeId.parse(String wire) {
    if (!WorldTypeRegistry.isRegistered(wire)) {
      throw ArgumentError('Unknown worldType: $wire');
    }
    return WorldTypeId._(wire);
  }
}

/// Each World registers its type id + factory at app startup. The engine
/// looks up Worlds via the registry, not via a hardcoded switch.
class WorldTypeRegistry {
  static final Map<String, World Function(RoomDescriptor)> _registered = {};
  static void register(String wire, World Function(RoomDescriptor) factory) {
    _registered[wire] = factory;
  }
  static bool isRegistered(String wire) => _registered.containsKey(wire);
  static World instantiate(RoomDescriptor desc) =>
      _registered[desc.worldType.value]!(desc);
}

enum FoyerVisibility {
  public('public'),
  unlisted('unlisted'),
  private('private');

  const FoyerVisibility(this.wire);
  final String wire;
  static FoyerVisibility parse(String wire) =>
      values.firstWhere((v) => v.wire == wire,
                       orElse: () => FoyerVisibility.private);  // fail-closed
}
```

Must NOT leak: `DocumentSnapshot`, `QuerySnapshot`, `Timestamp`, Firestore `Reference`.

Ships in Realm:
- `realm_firebase`: `FirestoreRoomConfigStore`
- (LiveKit-metadata-only variant possible later as a self-host-friendly option that needs no separate database.)

### 3. `StorageProvider`

```dart
abstract interface class StorageProvider {
  Future<BlobRef> upload(Uint8List bytes, {required String path, String? contentType});
  Future<Uint8List> download(BlobRef ref);
  Future<Uri> publicUrl(BlobRef ref);
  Future<void> delete(BlobRef ref);
}

class BlobRef {
  final StorageBackendId backend;  // branded — registered backends only
  final String path;                // opaque within backend
}

/// Branded type for storage backends. Open set (operators can register
/// their own backend) but validated. Same pattern as WorldTypeId.
extension type const StorageBackendId._(String value) {
  factory StorageBackendId.parse(String wire) {
    if (!StorageBackendRegistry.isRegistered(wire)) {
      throw ArgumentError('Unknown storage backend: $wire');
    }
    return StorageBackendId._(wire);
  }
  static const firebase = StorageBackendId._('firebase');
  static const s3 = StorageBackendId._('s3');
  static const local = StorageBackendId._('local');
}
```

Must NOT leak: `firebase_storage.Reference`, `gs://` URLs as the canonical form, provider-specific metadata types.

Ships in Realm:
- `realm_firebase`: `FirebaseStorageProvider`

### 4. `LiveKitTokenEndpoint`

This is a **deployment-shape contract**, surfaced to the engine as a thin Dart config value. The engine holds a config (URL + auth strategy); the real implementation is whatever HTTP service stands at that URL. Reference implementations live in `examples/livekit-token-server/` (Node, Go, Rust variants); the production endpoint we ship is a Firebase Cloud Function.

```dart
class LiveKitTokenEndpoint {
  const LiveKitTokenEndpoint({required this.url, required this.authStrategy});
  final Uri url;
  final TokenEndpointAuthStrategy authStrategy;
}

sealed class TokenEndpointAuthStrategy {
  const TokenEndpointAuthStrategy();
}
/// Engine sends `Authorization: Bearer <RealmCredential.token>` with each request.
class BearerCredential extends TokenEndpointAuthStrategy {
  const BearerCredential();
}
/// Engine signs the request body with a shared HMAC secret.
class SignedRequest extends TokenEndpointAuthStrategy {
  const SignedRequest({required this.secret});
  final String secret;
}
```

The engine sends the current user's `RealmCredential` to this endpoint; the endpoint validates the credential (using whatever provider verification logic it needs server-side), then returns a LiveKit access token. Token contents (room grants, embedded agent dispatch, metadata) are the endpoint's concern.

Why this isn't strictly a Dart interface: the engine never *calls a method* on this endpoint via a Dart interface — it sends an HTTP request. But the URL + auth strategy must be Dart-configurable, so they live as a value type in the engine package.

### 5. `PresenceService`

The "watch a room's participants without joining it" primitive. Powers the foyer's cross-room presence display (avatars of who's in each visible room) and, eventually, federation's cross-instance presence layer.

**Critical PII boundary**: presence data includes user IDs, display names, and join times — all classified as PII by the existing `pii_policy.dart`. A naive cross-room watch API would broadcast that PII to any caller who can name a room. This interface uses **typed sealed projections** to enforce audience-appropriate shapes: full-fidelity presence is available only inside a room you've joined; cross-room (foyer) watching exposes a public projection that reveals less.

```dart
abstract interface class PresenceService {
  /// Watch the high-fidelity presence stream for a room the caller is in.
  /// Caller must be present in the room — implementations check membership.
  /// Returns FullProjection (userId, displayName, avatarUrl).
  Stream<Set<PeerPresence>> watchInRoom(RoomId roomId, RealmUser viewer);

  /// Watch the low-fidelity presence stream for a room the caller is NOT in.
  /// Only emits for rooms whose foyerVisibility = public (private/unlisted
  /// rooms refuse). Returns PublicProjection (count + opaque hashed avatars).
  Stream<Set<PeerPresence>> watchFromFoyer(RoomId roomId, RealmUser viewer);
}

/// Sealed projection. The projection level is determined by the caller's
/// relationship to the room, NOT by the producer's preference. The engine
/// guarantees: a caller who isn't in the room can never receive a FullProjection,
/// even if a buggy World tries to emit one. The PresenceService implementation
/// enforces this; downstream consumers can pattern-match exhaustively.
sealed class PeerPresence {
  const PeerPresence({required this.joinedAt});
  final DateTime joinedAt;
}

class FullProjection extends PeerPresence {
  const FullProjection({
    required this.userId,
    required this.displayName,
    required this.avatarUrl,
    required super.joinedAt,
    this.worldMetadata = const {},
  });
  final UserId userId;            // PII — in-room visibility only
  final String? displayName;      // PII — in-room visibility only
  final Uri? avatarUrl;
  final Map<String, Object?> worldMetadata;  // opaque, parsed by World
}

class PublicProjection extends PeerPresence {
  const PublicProjection({
    required this.userIdHash,     // stable per-room SHA256(roomId || userId)[:8]
    required this.opaqueAvatarRef,  // optional opaque ref the foyer can render
    required super.joinedAt,
  });
  final String userIdHash;        // NOT user-identifying across rooms
  final Uri? opaqueAvatarRef;     // optional; absent if user opted out
}
```

`Set` semantics (not `List`): participants are unique per room; ordering is meaningless; equality is on `userIdHash` (PublicProjection) or `userId` (FullProjection).

**Authorization rules** (enforced by `PresenceService` implementations):
- `watchInRoom` succeeds only if `viewer` is currently present in `roomId` (LiveKit participant check).
- `watchFromFoyer` succeeds only if `roomId.foyerVisibility == public`. Unlisted and private rooms refuse — the foyer cannot enumerate them at all.
- Users may opt out of `opaqueAvatarRef` exposure (a per-user setting); `userIdHash` is always emitted because the foyer needs *some* token to render a presence indicator (otherwise it can't tell "3 people inside" from "0 people inside").
- The hash uses the room ID as salt so the same user appears different across rooms — prevents cross-room user identification via the public projection.

Cheap by design: no media subscription, no data-channel subscription, no voice. Updated when the room's participant list changes.

Must NOT leak: LiveKit's `RemoteParticipant`, `Track`, or `TrackPublication` types.

Ships in Realm:
- `realm_firebase`: `LiveKitPresenceService` (server-side fan-out: a small service polls LiveKit REST API + enforces the projection-by-audience rule + broadcasts via Firestore or similar)
- Reference implementation in `examples/presence-server/` for self-hosters

**Why an engine interface, not a World concern**: presence-of-others is foundational substrate. Every World wants it (foyer especially, but also "see who's online in adjacent rooms"). Building it once in the engine prevents N different presence implementations per World — *and* prevents N different projection-by-audience policies, where one bug becomes a privacy leak.

### Engine-level `World` lifecycle

`World` is an **`abstract interface class`** — not a base class — for one decisive reason: existing `TechWorld` already `extends Flame.World with TapCallbacks`. Dart single-inheritance means TechWorld cannot extend two base classes. Making the engine's `World` an interface (which classes can `implements`) is the only structurally valid path:

```dart
abstract interface class World {
  RoomId get roomId;
  RoomDescriptor get descriptor;

  /// Called once when the user enters the room. Implementations subscribe
  /// to LiveKit, register listeners, initialize world-specific state.
  Future<void> onEnter();

  /// Called when a peer joins the room (their LiveKit participant connected).
  void onPeerJoin(RealmUser peer);

  /// Called when a peer leaves the room. The viewer remains.
  void onPeerLeave(UserId peerId);

  /// Called when the current user leaves the room. Reason enum distinguishes
  /// user-initiated departures from system events. v1 uses .userLeft and
  /// .disconnect; .portalTransit is reserved for v2 federation.
  Future<void> onLeave(LeaveReason reason);

  /// Render a renderer-neutral snapshot of this room's current state for
  /// the foyer. Returns null if this World shouldn't appear in foyers
  /// (FoyerWorld returns null — foyers don't appear in foyers).
  /// **No Flutter types in the return value** — the foyer wraps RoomPreview
  /// in its own renderer. This keeps the engine portable across rendering
  /// stacks (Flame, raw CustomPainter, future 3D, text-mode bots, etc.).
  Future<RoomPreview?> previewSnapshot();
}

enum LeaveReason {
  userLeft('user_left'),
  disconnect('disconnect'),
  portalTransit('portal_transit');  // reserved for v2 federation

  const LeaveReason(this.wire);
  final String wire;
}

/// Renderer-neutral preview value. The foyer renders this however it wants.
/// World implementations populate either `image` (raster snapshot of state)
/// or `vector` (a list of opaque shapes the foyer can interpret) — never
/// both. `worldHints` carries non-rendering metadata the foyer wants for
/// labels and badges.
class RoomPreview {
  const RoomPreview({
    this.image,
    this.vector,
    required this.worldHints,
  });
  final Uint8List? image;             // optional raster (PNG / WebP bytes)
  final List<PreviewShape>? vector;   // optional shape list
  final PreviewHints worldHints;
}

class PreviewHints {
  const PreviewHints({
    required this.participantCount,
    this.activityLabel,       // 'live coding', 'DM running', 'quiet'
    this.voiceActive = false,
  });
  final int participantCount;
  final String? activityLabel;
  final bool voiceActive;
}

/// Opaque shape primitive for vector previews. Foyer renders these.
sealed class PreviewShape { /* circle, rect, text — defined in engine */ }
```

`TechWorld` becomes: `class TechWorld extends flame.World with TapCallbacks implements World`. `RepoBodyWorld` and `FoyerWorld` choose their own renderer base independently — they don't have to extend Flame's World at all.

**Contract versioning**: adding a new method to the `World` interface IS a breaking change for every implementing World — the analyzer will flag missing implementations at compile time. To support additive evolution, new methods land as **default-impl mixins** the interface promises to combine: e.g., `mixin WorldFederationHooks on World` (added in v2) provides default no-op `onPortalTransit()` so v1 Worlds compile against v2 engine. The contract evolution rule: never add abstract methods to `World` after v1.0; always add via mixins consumed by the interface.

## What is NOT in the engine

Explicitly excluded from the Realm contract. These are world-internal:

- **Per-world state stores.** Tech World's `ProgressService` (completed challenges, spellbook state) is Tech-World-specific. It needs a persistence backend, but it's the world's choice. Tech World's reference implementation will use Firestore; a self-hoster who wants a different backend writes a different `TechWorldStateStore` implementation. The engine doesn't see this interface.
- **World vocabulary types.** `WordId`, `PromptChallengeId`, `CodeChallengeId`, `AvatarId`, `DoorState`, `SpeechBubble` — none of these are engine-level. They live in their world's package.
- **Game-loop specifics.** Flame's `FlameGame` and `flame.World` are Tech-World-specific framings. The engine doesn't mandate Flame. A `World` subclass could be built on Flame (Tech World), on raw Flutter `CustomPainter` (the Foyer might), on `flutter_3d_controller`, on anything. The engine just hosts the World and provides substrate primitives.
- **Animation/render systems.** Bubbles, metaballs, video shaders — all Tech World.
- **AI agent integrations.** Clawd, Gremlin, Dreamfinder — Tech World. A world that wants AI participants registers them via its own LiveKit room logic; the engine has no opinion.
- **Rendering modality (visual / audio / text / haptic).** The engine state must be expressible to *any* renderer — that's why `previewSnapshot()` returns `RoomPreview` (renderer-neutral) rather than `Widget`. Accessibility, alternative-modality rendering, screen-reader integration, and keyboard navigation all live in the rendering layer of each World (or in render-layer plugins shared across Worlds). The engine's responsibility is to keep state modality-neutral; the rendering layer's responsibility is to interpret that state for any sense.
The rule: **if you can describe it without mentioning rooms, identity, presence, voice, channels, or blob storage, it's not engine.**

But "not engine" doesn't always mean "World vocabulary" — there's a middle tier worth naming.

## Three tiers: engine, plugins, worlds

| Tier | Where it lives | Examples | Owns |
|---|---|---|---|
| **Engine** | `packages/realm/` | `AuthProvider`, `RoomConfigStore`, `StorageProvider`, `LiveKitTokenEndpoint`, `PresenceService`, `World` base class | Interfaces, lifecycle, no implementations |
| **Plugins** | `packages/realm_<name>/` | `realm_firebase` (provider impl), `realm_github_oauth` (provider impl), `realm_code_editor` (feature, aspirational), `realm_avatars` (feature, aspirational), `realm_tilemaps` (feature, aspirational) | Optional capabilities multiple Worlds might use; implement engine interfaces or extend engine primitives |
| **Worlds** | `worlds/<name>/` | `tech_world`, `repo_body`, `foyer` | One specific World, declares its plugins + its own vocabulary |

The test for "plugin vs World vocabulary" is one question: **would another World plausibly want this?**

- Code editor terminal? Yes — RepoBodyWorld might inspect file contents, a future writing world wants collaborative editing. → plugin candidate.
- Spellbook? No — specifically Tech World magic. → vocabulary.
- Body-anatomy renderer? No — specifically repo-body. → vocabulary.
- Pathfinding on a tile grid? Maybe — any avatar-on-tilemap World wants it. → plugin candidate.
- Foyer window layout? No — specifically the foyer. → vocabulary.

**Plugin extraction discipline: extract on second use, not on speculation.** Until two Worlds want the same capability, the right plugin interface isn't visible. Premature plugin extraction is exactly the speculative abstraction this design philosophy rejects. So in v1: feature plugins are *aspirational namespace reservations*. Provider implementations (`realm_firebase`, `realm_github_oauth`) ARE real plugins from day one because they implement engine-defined interfaces; their shape is known.

**`code_forge_web` as a worked example.** It's a Tech-World dependency in v1 — stays in `worlds/tech_world/pubspec.yaml`. If RepoBodyWorld or any future World wants code editing, that's the moment to extract `realm_code_editor`. Until then, premature.

This also clarifies the Flutter 3.44 / `code_forge_web` incompatibility we just hit: it's a Tech-World-scoped problem. When the engine and worlds are properly separated, FoyerWorld and the engine itself can ride newer Flutter independently of whatever Tech World's plugin stack demands. Today's single-binary build forces lowest-common-denominator SDK, but the architectural ownership is clean.

## Repo structure

Phase 1 (now → extraction stable):

```
tech_world/                       # workspace root (will rename to `realm/` at phase 2)
  pubspec.yaml                    # workspace: [packages/*, worlds/*]
  packages/
    realm/                        # the engine
      pubspec.yaml
      lib/
        realm.dart
        src/
          auth/
          rooms/
          storage/
          livekit/
          presence/
          world_base.dart
      test/
      DESIGN.md (this file → README.md)
    realm_firebase/               # provider plugin: Firebase implementations
      lib/                          (FirebaseAuthProvider, FirestoreRoomConfigStore, FirebaseStorageProvider)
    realm_github_oauth/           # provider plugin: GitHub OAuth (needed for repo-body)
      lib/
  worlds/
    tech_world/                   # the existing Tech World, wrapped as a World
      pubspec.yaml                  (declares: code_forge_web, re_highlight, pathfinding, tiled, …)
      lib/
        tech_world.dart             (class TechWorld extends World)
        src/
          (spellbook, code editor, prompt challenges, doors, dreamfinder, …)
    repo_body/                    # new World, stub-first
      pubspec.yaml                  (declares: http for GitHub API)
      lib/
        repo_body_world.dart        (class RepoBodyWorld extends World)
    foyer/                        # new World, the federation made visible
      pubspec.yaml                  (declares: minimal — just engine)
      lib/
        foyer_world.dart            (class FoyerWorld extends World)
  lib/
    main.dart                     # thin shell: registers Worlds, opens the foyer
```

Migration: the current `lib/` directory in tech_world repo splits three ways — substrate-shaped code → `packages/realm/`, provider implementations → `packages/realm_firebase/`, Tech-World-specific code → `worlds/tech_world/`. The top-level `lib/main.dart` becomes a small launcher that registers all available Worlds and lets the foyer load on app start.

Phase 2 (when interfaces stabilize): rename repo to `enspyrco/realm`. The engine and plugins live at the top level. Worlds either stay in-repo as reference examples or get split to their own repos (Tech World → `enspyrco/tech_world`, repo-body → `enspyrco/repo_body`). External operators can pull `realm` + the plugins they want + whichever Worlds they want, mix and match.

The phase-1 monorepo lets us iterate the engine contract against three real Worlds + multiple provider plugins without cross-repo coordination overhead.

## The three reference worlds

### `TechWorld`

What it is today, wrapped as `class TechWorld extends World`. The migration is mostly mechanical — extract substrate-shaped concerns up to the engine, plugin-shape Firebase implementations into `realm_firebase`, keep everything else as Tech-World vocabulary. The world's voice (spellbook, doors, code editor, prompt challenges, Dreamfinder, the substrate-has-a-body lens) all stays.

Verification target: zero behavior change for existing Tech World users after migration. Same auth flows, same room joining, same gameplay. The migration is invisible to players.

### `FoyerWorld` (new — the federation made visible)

Where new users land. Not a special-cased login screen — a real `World` like any other, just one whose substrate is *the rooms themselves*.

A hall with windows along the walls, one window per public room in the operator's Realm installation. Through each window, you can see the room beyond — a small live scene rendered via `World.previewSnapshot()` of that room. Tech World rooms show a tilemap thumbnail with avatar dots; RepoBodyWorld rooms show a silhouette of the plaza; future Worlds show whatever they want.

Each window is labeled with the room's display name and shows activity badges: count of people present (from `PresenceService`), voice-active indicator, optional world-specific hints ("live coding", "DM running", "quiet"). Walking close to a window reveals the participants' avatars more clearly with names.

Walking through a window enters that room. Walking back to the room's exit returns to the foyer.

The foyer is itself a room with its own LiveKit channel — people standing in the foyer can voice-chat with each other while looking through the windows. It's the lobby of a venue.

**Foyer-first UX**: when a user starts the app, they land in the foyer (unless deep-linked to a specific room). This changes what "new user" means — the first second of Realm is now "you see a hall with several rooms visible," not "you join Tech World directly." The foyer is the engine's face.

Operator config: `RoomDescriptor.worldType: foyer`, `worldConfig: { "watches": ["room-id-1", "room-id-2", ...] }` declares which rooms appear as windows. Self-hosters configure their own.

### `RepoBodyWorld` (new, stub-first)

Org-scoped. The room's `worldConfig` declares `{ "orgName": "enspyrco" }`. The world fetches the org's repos via GitHub API. Each repo renders as a body silhouette in a plaza; the room is a city-of-bodies.

Per-repo body anatomy:
- Spine/core = top-fan-in modules
- Limbs/extremities = leaf modules
- Heartbeat = CI status
- Circulation = recent commits glowing on the body
- Wounds = open issues / failing tests, marked at the file they reference
- Memory strata = git history, scrubbable on a time axis

Multiplayer: engineers in the same org-room see each other walking among the bodies. Voice via LiveKit (same as Tech World). Presence near a body = "I'm reading/touching this repo right now."

Stub-first ship: render a single placeholder body, no GitHub fetch yet. Just enough to prove the engine instantiates a third World type and the foyer picks it up via `previewSnapshot()`. Body computation, plaza layout, GitHub presence, time axis — all stack on top in subsequent PRs.

## Migration plan

A single mechanical refactor PR can't do this — too much surface. The path:

1. **Design note + cage-match** (this doc). Pin the contract.
2. **Workspace scaffold PR**. Create `packages/realm/`, `packages/realm_firebase/`, `worlds/tech_world/` (initially empty), set up Dart workspace, ensure `flutter test` + `flutter analyze --fatal-infos` run across all members. No code moves yet. CI green.
3. **Engine interface PR**. Define `AuthProvider`, `RoomConfigStore`, `StorageProvider`, `LiveKitTokenEndpoint`, `PresenceService` in `packages/realm/`, plus the `World` abstract base class. No implementations yet. CI green.
4. **Provider plugin PR**. Implement Firebase-backed versions in `packages/realm_firebase/`: `FirebaseAuthProvider`, `FirestoreRoomConfigStore`, `FirebaseStorageProvider`. Tech World still calls Firebase directly. CI green.
5. **Consumer migration PRs** (one per consumer, parallel-safe). Move `AuthService` callers to `AuthProvider`. Move Firestore room reads to `RoomConfigStore`. Move `firebase_storage` calls to `StorageProvider`. Each PR is small, cage-matchable.
6. **`TechWorld` wrap PR**. Refactor `TechWorld` → `class TechWorld extends flame.World with TapCallbacks implements World` (per the single-inheritance constraint — World is an interface, not a base class). `RoomSession` reads `worldType` from `RoomConfigStore`, dispatches via `WorldTypeRegistry`. Code moves from `lib/` to `worlds/tech_world/lib/`. CI green. **Behavior change is limited to native bundle paths**: iOS `cc.imagineering.techWorld` bundle ID and Firebase config tied to that ID are preserved; `pubspec.yaml` asset paths require adjustment; `lib/main.dart` stays as a thin shell at the workspace root that wires up worlds. The claim is NOT "zero behavior change for everything" — it's "zero gameplay behavior change for existing Tech World users, with documented native-bundle changes contained to a sub-step (6.5: bundle-path migration)".
7. **`FoyerWorld` + `PresenceService` impl PR**. Add `worlds/foyer/`. Implement `LiveKitPresenceService` (or initial Firestore-backed version). Make Foyer the default landing experience on app start. Existing rooms appear as windows in the foyer.
8. **`RepoBodyWorld` stub PR**. Add `worlds/repo_body/` with placeholder body rendering. Create one Firestore room with `worldType: repo_body`. Verify it appears as a window in the foyer and the placeholder loads when entered.
9. **`RepoBodyWorld` flesh PRs** (many, parallel-safe). `realm_github_oauth` plugin. GitHub repo fetch. Centrality analysis. Body renderer. Plaza layout. Heartbeat (CI). Circulation (commits). Wounds (issues). Time axis (history scrub). Each is its own design-pinned PR.

Each PR after step 1 is cage-match-worthy because every one of them touches a boundary class (auth, room state, world lifecycle, presence). Per the `boundary_class_review_tier` memory: cage-match by default, not by line count.

## Open questions

These are not blockers for the design note but must be answered before the corresponding PR:

1. **Workspace tooling.** Dart workspaces are supported as of 3.6.0 (we're on 3.6). Confirm that `flutter test` runs all member packages from the root, that `flutter analyze --fatal-infos` works workspace-wide, that the existing CI workflow needs minimal change.
2. **iOS/Android Firebase coupling.** `firebase_options.dart` is committed; iOS/Android Firebase SDKs are linked. **Resolved**: `packages/realm/` does NOT depend on `firebase_core` — that dependency is inverted relative to the three-tier model and the no-leak rule. From the first extracted commit, Firebase implementations live in `packages/realm_firebase/`. The engine package's `pubspec.yaml` whitelist (Flutter SDK, `livekit_client`, `http`, branded-type support utilities) is enforced by a `dart pub deps` check in CI — anything else added to the engine package fails the check. The "simpler" phase-1 shortcut (bundle Firebase into the engine) is rejected because day-1 dependency direction is the load-bearing decision; convenience compromises today become the engine's architecture forever.
3. **`World` base class shape.** Abstract class with template methods? Sealed class? Interface with mixin defaults? Mockability for testing matters; so does ease of writing a new World. Resolve when writing the engine interface PR.
4. **Per-world `worldConfig` schema.** `Map<String, Object?>` is opaque-on-purpose at the engine, but each World wants typed access. Pattern: each World declares a `parseConfig(Map) → TypedConfig` method, and `worldConfig` is validated at room creation. Same shape as `LiveKitTopic.parse(String)`. Probably uncontroversial.
5. **Existing `RoomSession` API stability.** It's been heavily DI'd recently. The engine's room-lifecycle abstraction may want to absorb it, or `RoomSession` may stay as a Tech-World-specific orchestrator on top of engine primitives. Resolve when writing the `TechWorld` wrap PR.
6. **PII gate ownership.** The PII gate (`lib/events/pii_policy.dart`) is currently Tech-World-resident. It's substrate-shaped (every world will want it). Move to engine or duplicate per-world? Almost certainly engine. Confirm during interface PR.
7. **`developer.log` bypass note** (from CLAUDE.md) needs to migrate with the PII gate doc.
8. **Test infrastructure.** `RoomSession` uses `@visibleForTesting` DI seams (the LiveKit + Firestore stubs in `room_session_test.dart`). The engine should keep the same testability discipline. The `_FakeLiveKit` pattern is reusable across the engine surface.

## Non-goals for v1

- Replacing LiveKit. The engine assumes LiveKit. Pluggable transports are not a v1 goal.
- Replacing Flame. Tech World uses Flame; future worlds may use it or not. The engine has no opinion.
- Migrating Tech World off Firebase. Tech World keeps using Firebase via the new interfaces. The point is that *others can* swap, not that we do.
- Publishing to pub.dev. The engine ships as path deps within the monorepo until interfaces stabilize.
- Cross-instance federation (rooms federated across separate Realm operators). The v1 engine *prepares for it* (see "Federation, deferred" below) but doesn't ship it.

## Federation, deferred

Cross-instance federation — operators connecting their Realm installations so users can transit between them, see each other's presence across instances, and federate worlds — is **not in v1 scope**. But the v1 design must not preclude it. Adding federation later should be additive (new interface + new method on existing classes), never a breaking refactor of v1's contract.

Three increasingly ambitious federation models, named for vocabulary, none implemented in v1:

| Model | What it is | Voice handling | Approximate lift |
|---|---|---|---|
| **A. Cross-room presence (read-only)** | See who's in other rooms, no transit. Like Slack's online dots across channels. | Voice stays room-local. | Light. Already partly designed via `PresenceService`. |
| **B. Portals** | Each World declares portal positions; walking into one transits you to another room (possibly on another Realm operator). | Voice rejoins on transit. | Medium. Adds transit handoff to `World.onLeave(LeaveReason.portalTransit)`. |
| **C. Federated graph as navigable space** | The graph of rooms is itself a renderable inter-room space (the "universe map"). | Inter-room space has its own ambient layer. | Heavy. v3-or-later territory. |

**The four v1 constraints that preserve federation as a future capability:**

1. **`RoomDescriptor.connectedTo: List<RoomRef>?` is reserved, even if always null in v1.** Adding the field later forces a schema migration; reserving it costs nothing. `RoomRef` is defined as a sealed type from v1 so federation can add operator-spanning references without breaking the contract:

   ```dart
   sealed class RoomRef {
     const RoomRef();
   }
   /// Same-operator room reference (v1 + v2).
   class LocalRoomRef extends RoomRef {
     const LocalRoomRef(this.roomId);
     final RoomId roomId;
   }
   /// Cross-operator federation reference (v2 only; v1 never emits).
   class FederatedRoomRef extends RoomRef {
     const FederatedRoomRef({required this.operatorUri, required this.roomId});
     final Uri operatorUri;
     final RoomId roomId;
   }
   ```

   v1 only constructs `LocalRoomRef`. v2 adds `FederatedRoomRef` as an additive subtype; existing exhaustive switches must opt in to handle it. **Important caveat from cage-match**: reserving fields without consumers also adds contract surface and potential authorization mistakes. We're reserving the *type definition* (cheap, no consumer) but the `connectedTo` field on `RoomDescriptor` stays `null` in v1 — no listing API exposes it, no foyer reads from it. The reservation cost is bounded to the type def; the consumer surface arrives in v2 only.
2. **Presence is engine-owned, not LiveKit-direct.** `PresenceService` is the engine abstraction over participant lists. v1 implementations read from LiveKit room metadata, but the abstraction means future cross-room or cross-instance presence layers don't require rewriting every consumer.
3. **`World.onLeave(LeaveReason)` carries an enum.** v1 reasons: `userLeft`, `disconnect`. Reserved: `portalTransit`. The enum being there from day one means model B can be added without changing the lifecycle contract.
4. **Room IDs are globally unique, not org-namespaced.** If federation eventually crosses operators, room IDs must collide-resist across operators. Use a UUID-shaped opaque ID, not `<org>:<slug>`.

If we honor those four, federation lands as an additive v2 (or v3) feature: new `FederationGraphStore` interface, new portal-related World hooks, new presence broadcasting layer — all without touching v1's contract.

## Naming and prior art

We chose **Realm** for the engine and **World** for the per-room abstraction after considering and rejecting several alternatives. Recording the landscape here so cage-match reviewers don't re-litigate it, and so future maintainers see the prior art.

**Realm name collisions we accepted:**

- **`realm` on pub.dev** is MongoDB's mobile database SDK (Atlas Device Sync + Realm SDKs), actively published by `realm.io`. We cannot publish a package named bare `realm`. Our pub package will be `realm_engine` or compound. **Category distinction makes this tolerable**: their Realm is a database, ours is a multiplayer worldbuilding engine; users searching for one don't find the other. MongoDB's Realm DB was also announced for deprecation in September 2024, which softens the collision over time.
- **"Realm Engine" by Blake Johnson** — a 3D virtual tabletop for RPGs at `realmengine.app`, on Steam since around 2020. Same adjacent space (worldbuilding, multiplayer), but the last meaningful update was years ago and the project momentum is low. SEO for "Realm Engine multiplayer worldbuilding" still surfaces theirs first. We accepted this collision on the theory that sustained activity on our project will rebuild the namespace over time.
- **`Realm-Engine/realm` on GitHub** — a hobby D-language game framework, inactive. Low confusion risk; the org-vs-user namespace separates us.
- **Realm adversary emulation framework** (Rust-based security tool) — different space, low confusion.

**World name collision we navigate:**

- Flame's `flame.World` class is what `TechWorld` currently extends. Our engine's `World` abstraction shares the name. Resolved per-file via import prefix: `import 'package:flame/components.dart' as flame;` then `flame.World` vs plain `World`. Most files only need one.

**Why these names won:**

- "Realm" has the right scope-feel: vast, containing, a domain of authority. Reads naturally for the engine.
- "World" has the right intimacy-feel: a place you inhabit. Reads naturally for the per-room class.
- "Realm hosts Worlds" + "each room is one World" parses as English without explanation.
- Branded "Realm Engine" works as a marketing phrase when the bare brand is ambiguous.

**Why not alternatives we considered:**

- "Engine" alone — too generic, every framework calls itself one.
- "Hearth", "Loom", "Atlas", "Nexus", "Cairn" — evocative but require explanation; no obvious mapping to multiplayer rooms.
- "Realm" for the per-room class, with a different brand for the engine — flipping the assignment loses the "Realm hosts Worlds" elegance and forces compound branding from day one.

## Cage-match hooks

Reviewers should specifically probe:

**Architecture:**
- The no-leak rule — find every place a Firebase type (or LiveKit type for `PresenceService`) would naturally want to leak through the interface and flag it.
- The five-interface decomposition — is it the right cut? Are we missing one? (Telemetry? Push notifications? Schema migrations?) Are any of these five actually the same interface in two costumes?
- The three-tier model (engine / plugins / worlds) — is "plugins" earning its keep as a tier, or is it speculation? If we never extract any feature plugins beyond provider implementations, is the tier still useful?
- The "what's NOT in the engine" list — is anything on it actually engine-shaped in disguise?
- `World.previewSnapshot()` — is `Widget` the right return type, or should it be a platform-neutral image/scene type that doesn't bind the engine to Flutter rendering?

**Repo structure:**
- Should phase 1 already be two repos, given the open-source signaling cost of "engine looks like it's a tech_world subdir"?
- `worlds/` as a top-level directory vs `packages/` — does the visual separation help readers, or just complicate workspace tooling?

**Federation:**
- Are the four v1 constraints actually sufficient? Walk through model A and model B mentally and find where v1 would force a breaking change anyway.
- `LeaveReason` enum — is there a v1 reason we missed that would force enum growth into a breaking change?

**Migration ordering:**
- Is there a step that should happen earlier to de-risk later steps?
- Should `FoyerWorld` come BEFORE the `TechWorld` wrap, since it's smaller and would prove the World abstraction with less surface?

**Naming:**
- Realm/World — does the import-prefix collision with Flame's `World` create enough friction in `worlds/tech_world/` (which uses both heavily) to warrant a different name?

**Business model and license:**
- Six probes already named in the "License and business model" section. Apply them.

**Free tier:**
- Will the free tier actually be the real thing, or will scope-pressure quietly paywall key features and break the adoption funnel?
