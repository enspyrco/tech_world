import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/editor/challenge.dart';
import 'package:tech_world/flame/shared/speaker_role.dart';
import 'package:tech_world/infra/infra_health_state.dart';
import 'package:tech_world/livekit/livekit_topic.dart';
import 'package:tech_world/map_editor/crdt/map_edit_op.dart';
import 'package:tech_world/prompt/prompt_challenge.dart';
import 'package:tech_world/spellbook/word_of_power.dart';

/// Round-trip (adjunction unit) tests for all enhanced enums.
///
/// The parse/wire pair on each enum forms a Free-Forgetful adjunction:
///   wire: Enum -> String   (forgetful functor)
///   parse: String -> Enum? (free functor, partial)
///
/// The adjunction unit is: parse(x.wire) == x for every x.
/// The partial inverse property: parse('nonsense') == null.
void main() {
  group('LiveKitTopic round-trip', () {
    for (final topic in LiveKitTopic.values) {
      test('tryParse(${topic.wire}) == $topic', () {
        expect(LiveKitTopic.tryParse(topic.wire), equals(topic));
      });
    }
    test('tryParse(nonsense) == null', () {
      expect(LiveKitTopic.tryParse('nonsense'), isNull);
    });
    test('tryParse(empty) == null', () {
      expect(LiveKitTopic.tryParse(''), isNull);
    });
  });

  group('SpeakerRole round-trip', () {
    for (final role in SpeakerRole.values) {
      test('tryParse(${role.wire}) == $role', () {
        expect(SpeakerRole.tryParse(role.wire), equals(role));
      });
    }
    test('tryParse(nonsense) == null', () {
      expect(SpeakerRole.tryParse('nonsense'), isNull);
    });
    test('tryParse(null) == null', () {
      expect(SpeakerRole.tryParse(null), isNull);
    });
  });

  group('WordId round-trip', () {
    for (final word in WordId.values) {
      test('parse(${word.name}) == $word', () {
        expect(WordId.parse(word.name), equals(word));
      });
    }
    test('parse(nonsense) == null', () {
      expect(WordId.parse('nonsense'), isNull);
    });
    test('parse(empty) == null', () {
      expect(WordId.parse(''), isNull);
    });
  });

  group('OpLayer round-trip', () {
    for (final layer in OpLayer.values) {
      test('tryParse(${layer.name}) == $layer', () {
        expect(OpLayer.tryParse(layer.name), equals(layer));
      });
    }
    test('tryParse(nonsense) == null', () {
      expect(OpLayer.tryParse('nonsense'), isNull);
    });
  });

  group('PromptChallengeId round-trip', () {
    for (final id in PromptChallengeId.values) {
      test('parse(${id.wireName}) == $id', () {
        expect(PromptChallengeId.parse(id.wireName), equals(id));
      });
    }
    test('parse(nonsense) == null', () {
      expect(PromptChallengeId.parse('nonsense'), isNull);
    });
    test('parse(empty) == null', () {
      expect(PromptChallengeId.parse(''), isNull);
    });
  });

  group('CodeChallengeId round-trip', () {
    for (final id in CodeChallengeId.values) {
      test('parse(${id.wireName}) == $id', () {
        expect(CodeChallengeId.parse(id.wireName), equals(id));
      });
    }
    test('parse(nonsense) == null', () {
      expect(CodeChallengeId.parse('nonsense'), isNull);
    });
    test('parse(empty) == null', () {
      expect(CodeChallengeId.parse(''), isNull);
    });
  });

  group('ServiceStatus round-trip', () {
    // ServiceStatus uses .name for wire and fromString for parse.
    for (final status in ServiceStatus.values) {
      if (status == ServiceStatus.unknown) {
        // 'unknown' maps to itself via fromString fallback
        test('fromString(${status.name}) == unknown', () {
          expect(ServiceStatus.fromString(status.name), equals(status));
        });
      } else {
        test('fromString(${status.name}) == $status', () {
          expect(ServiceStatus.fromString(status.name), equals(status));
        });
      }
    }
    test('fromString(nonsense) == unknown', () {
      expect(ServiceStatus.fromString('nonsense'), ServiceStatus.unknown);
    });
  });
}
