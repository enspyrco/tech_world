import 'package:error_correction_in_perception/error_correction_in_perception.dart';
import 'package:framing_in_perception/framing_in_perception.dart';
import 'package:abstractions/identity.dart';
import 'package:abstractions/beliefs.dart';
import 'package:abstractions/error_correction.dart';
import 'package:abstractions/framing.dart';
import 'package:percepts/percepts.dart';

import '../challenges/models/challenge_model.dart';
import '../game/game_state.dart';

class AppBeliefs
    implements
        CoreBeliefs,
        FramingConcept,
        ErrorCorrectionConcept,
        IdentityConcept {
  AppBeliefs({
    required this.identity,
    required this.error,
    required this.framing,
    // required Settings settings,
    // ProfileData? profile,
    required this.game,
    this.challenge,
  });

  @override
  final IdentityBeliefs identity;
  @override
  final DefaultErrorCorrectionBeliefs error;
  @override
  final DefaultFramingBeliefs framing;

  // final Settings settings;
  // final ProfileData? profile;

  final GameState game;
  final ChallengeModel? challenge;

  static AppBeliefs get initial => AppBeliefs(
        identity: DefaultIdentityBeliefs.initial,
        error: DefaultErrorCorrectionBeliefs.initial,
        framing: DefaultFramingBeliefs.initial,
        // settings: Settings.initial,
        game: GameState.initial,
      );

  @override
  AppBeliefs copyWith({
    DefaultFramingBeliefs? framing,
    DefaultErrorCorrectionBeliefs? error,
    IdentityBeliefs? identity,
    GameState? game,
    ChallengeModel? challenge,
  }) =>
      AppBeliefs(
        framing: framing ?? this.framing,
        identity: identity ?? this.identity,
        error: error ?? this.error,
        game: game ?? this.game,
        challenge: challenge ?? this.challenge,
      );

  @override
  toJson() => {
        'navigation': framing.toJson(),
        'identity': identity.toJson(),
        'error': error.toJson(),
        'game': game.toJson(),
        'challenge': challenge?.toJson(),
      };
}
