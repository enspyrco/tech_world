import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/livekit/data_topic.dart';
import 'package:tech_world/livekit/livekit_topic.dart';

/// Parity guard between the two topic enums that address the *same* LiveKit
/// data channel.
///
/// `DataTopic` and `LiveKitTopic` are duplicate namespaces pending unification
/// (see the Cleanup TODO in CLAUDE.md). Until one is deleted, several logical
/// topics are addressed through *both* types — `chat` has 5 `LiveKitTopic` call
/// sites and 1 `DataTopic` site; `helpRequest` has one of each. Those channels
/// work only because the two wire strings happen to be equal, and they are
/// maintained independently.
///
/// The pre-existing per-enum contract tests cannot catch this: each pins its own
/// enum to its own fixture and neither compares the two. They stay green no
/// matter how far apart the enums drift — which is exactly what happened.
///
/// These tests are the missing cross-check. [_knownOneSided] is a debt ledger,
/// not an exemption: it may only shrink, and the third test fails if an entry
/// is fixed but left behind.
void main() {
  /// Wire strings that exist in exactly one enum, as of 2026-08-20.
  ///
  /// Every entry is a topic one namespace never learned about. `emote` is the
  /// clearest example — it shipped in 061742b5 and was only ever added to
  /// `LiveKitTopic`. Unification (see CLAUDE.md TODO) drives this to empty.
  const knownOneSided = <String>{
    // LiveKitTopic only:
    'agent-hello',
    'df-proximity',
    'emote',
    'mention-ack',
    'room-timer',
    // DataTopic only:
    'dreamfinder-audio',
    'dreamfinder-mood',
  };

  final dataWires = {for (final t in DataTopic.values) t.name: t.wireName};
  final livekitWires = {for (final t in LiveKitTopic.values) t.name: t.wire};

  test(
    'a topic named in both enums has the SAME wire string in both',
    () {
      // The live hazard. `chat` and `helpRequest` are published through one
      // enum and consumed through the other, so a rename on one side breaks the
      // channel silently at runtime while every existing test stays green.
      final shared = dataWires.keys.toSet().intersection(
        livekitWires.keys.toSet(),
      );
      expect(
        shared,
        isNotEmpty,
        reason: 'sanity: the two enums should overlap while both exist',
      );

      for (final name in shared) {
        expect(
          livekitWires[name],
          equals(dataWires[name]),
          reason:
              'Topic "$name" has diverging wire strings: '
              'DataTopic.$name = "${dataWires[name]}" but '
              'LiveKitTopic.$name = "${livekitWires[name]}". '
              'These two enums address the same data channel — a mismatch '
              'breaks the channel at runtime with no other test failing.',
        );
      }
    },
  );

  test('no NEW topic is added to only one of the two enums', () {
    final data = dataWires.values.toSet();
    final livekit = livekitWires.values.toSet();
    final oneSided = data.difference(livekit).union(livekit.difference(data));

    expect(
      oneSided.difference(knownOneSided),
      isEmpty,
      reason:
          'A topic was added to one enum but not the other. While both enums '
          'exist they must stay in lockstep — add it to both, or unify the '
          'enums (CLAUDE.md > TODO > Cleanup). Do NOT simply extend '
          'knownOneSided: that ledger may only shrink.',
    );
  });

  test('the knownOneSided ledger contains no already-fixed entries', () {
    // Keeps the ledger honest: once a topic is added to both enums it must be
    // removed from the list, so the remaining count is always the real debt.
    final data = dataWires.values.toSet();
    final livekit = livekitWires.values.toSet();
    final stillOneSided = data.difference(livekit).union(
      livekit.difference(data),
    );

    expect(
      knownOneSided.difference(stillOneSided),
      isEmpty,
      reason:
          'These wire strings are now present in BOTH enums but are still '
          'listed in knownOneSided. Remove them from the ledger so the '
          'remaining entries reflect the real outstanding debt.',
    );
  });
}
