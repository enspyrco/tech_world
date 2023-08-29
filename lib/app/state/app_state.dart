import 'package:identity_in_perception/identity_in_perception.dart';
import 'package:error_correction_in_perception/error_correction_in_perception.dart';
import 'package:framing_in_perception/framing_in_perception.dart';
import 'package:abstractions/identity.dart';
import 'package:abstractions/beliefs.dart';
import 'package:abstractions/error_correction.dart';
import 'package:abstractions/framing.dart';

import '../../challenges/models/challenge_model.dart';
import '../../game/game_state.dart';

class AppState
    implements
        CoreBeliefs,
        FramingConcept,
        ErrorCorrectionConcept,
        IdentityConcept {
  AppState({
    required this.auth,
    required this.error,
    required this.framing,
    // required Settings settings,
    // ProfileData? profile,
    required this.game,
    this.challenge,
  });

  @override
  final IdentityBeliefs auth;
  @override
  final DefaultErrorCorrectionBeliefs error;
  @override
  final DefaultFramingBeliefs framing;

  // final Settings settings;
  // final ProfileData? profile;

  final GameState game;
  final ChallengeModel? challenge;

  static AppState get initial => AppState(
        auth: AuthBeliefSystem.initialBeliefs(),
        error: DefaultErrorCorrectionBeliefs.initial,
        framing: DefaultFramingBeliefs.initial,
        // settings: Settings.initial,
        game: GameState.initial,
      );

  @override
  AppState copyWith({
    DefaultFramingBeliefs? framing,
    DefaultErrorCorrectionBeliefs? error,
    IdentityBeliefs? auth,
    GameState? game,
    ChallengeModel? challenge,
  }) =>
      AppState(
        framing: framing ?? this.framing,
        auth: auth ?? this.auth,
        error: error ?? this.error,
        game: game ?? this.game,
        challenge: challenge ?? this.challenge,
      );

  @override
  toJson() => {
        'navigation': framing.toJson(),
        'auth': auth.toJson(),
        'error': error.toJson(),
        'game': game.toJson(),
        'challenge': challenge?.toJson(),
      };
}
