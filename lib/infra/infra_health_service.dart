import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:tech_world/infra/infra_health_state.dart';
import 'package:tech_world/livekit/livekit_service.dart';

final _log = Logger('InfraHealthService');

/// Monitors infrastructure health via the `infra-health` LiveKit data channel.
///
/// The Dreamfinder agent publishes health snapshots every ~10 seconds.
/// This service maintains the latest snapshot and exposes it as a
/// [ValueNotifier] for UI/component consumption.
///
/// Also handles the request side: [requestHeal] publishes an `infra-heal`
/// message to the agent, which executes the self-heal action and reports
/// the result on `infra-heal-result`.
class InfraHealthService {
  InfraHealthService({required LiveKitService liveKitService})
      : _liveKitService = liveKitService {
    _healthSubscription = _liveKitService.dataReceived
        .where((msg) => msg.topic == 'infra-health')
        .listen(_onHealthMessage);

    _healResultSubscription = _liveKitService.dataReceived
        .where((msg) => msg.topic == 'infra-heal-result')
        .listen(_onHealResult);

    _bootSubscription = _liveKitService.dataReceived
        .where((msg) => msg.topic == 'infra-boot')
        .listen(_onBootMessage);
  }

  final LiveKitService _liveKitService;
  StreamSubscription<DataChannelMessage>? _healthSubscription;
  StreamSubscription<DataChannelMessage>? _healResultSubscription;
  StreamSubscription<DataChannelMessage>? _bootSubscription;

  /// Latest health snapshot. Starts empty (all unknown).
  final healthState = ValueNotifier<InfraHealthSnapshot>(
    InfraHealthSnapshot.empty,
  );

  /// Emits heal results as they arrive from the agent.
  Stream<HealResult> get healResults => _healResultController.stream;
  final _healResultController = StreamController<HealResult>.broadcast();

  /// Emits boot sequences when Dreamfinder joins the room.
  Stream<BootSequence> get bootSequences => _bootController.stream;
  final _bootController = StreamController<BootSequence>.broadcast();

  void _onHealthMessage(DataChannelMessage msg) {
    final json = msg.json;
    if (json == null) return;

    try {
      healthState.value = InfraHealthSnapshot.fromJson(json);
    } catch (e) {
      _log.warning('Failed to parse infra-health message: $e');
    }
  }

  void _onHealResult(DataChannelMessage msg) {
    final json = msg.json;
    if (json == null) return;

    try {
      _healResultController.add(HealResult.fromJson(json));
    } catch (e) {
      _log.warning('Failed to parse infra-heal-result: $e');
    }
  }

  void _onBootMessage(DataChannelMessage msg) {
    final json = msg.json;
    if (json == null) return;

    try {
      _bootController.add(BootSequence.fromJson(json));
    } catch (e) {
      _log.warning('Failed to parse infra-boot: $e');
    }
  }

  /// Request the agent to heal a broken service.
  ///
  /// Publishes on the `infra-heal` topic targeted at the Dreamfinder agent.
  /// The result will arrive on [healResults].
  Future<void> requestHeal(String serviceId) async {
    _log.info('Requesting heal for $serviceId');
    await _liveKitService.publishJson(
      {'service': serviceId, 'action': 'restart'},
      topic: 'infra-heal',
    );
  }

  void dispose() {
    _healthSubscription?.cancel();
    _healResultSubscription?.cancel();
    _bootSubscription?.cancel();
    _healResultController.close();
    _bootController.close();
  }
}

/// Result of a self-heal action from the agent.
class HealResult {
  const HealResult({
    required this.serviceId,
    required this.success,
    this.detail = '',
  });

  final String serviceId;
  final bool success;
  final String detail;

  factory HealResult.fromJson(Map<String, dynamic> json) {
    return HealResult(
      serviceId: json['service'] as String? ?? '',
      success: json['ok'] as bool? ?? false,
      detail: json['d'] as String? ?? '',
    );
  }
}

/// Boot sequence sent by the agent when Dreamfinder joins the room.
///
/// Each step specifies a service and a delay (ms) before it should
/// light up on the infrastructure overlay.
class BootSequence {
  const BootSequence({required this.steps});

  final List<BootStep> steps;

  factory BootSequence.fromJson(Map<String, dynamic> json) {
    final sequence = json['sequence'] as List<dynamic>? ?? [];
    return BootSequence(
      steps: sequence
          .map((s) => BootStep.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// A single step in the boot sequence.
class BootStep {
  const BootStep({required this.serviceId, required this.delayMs});

  final String serviceId;
  final int delayMs;

  factory BootStep.fromJson(Map<String, dynamic> json) {
    return BootStep(
      serviceId: json['service'] as String? ?? '',
      delayMs: json['delay'] as int? ?? 0,
    );
  }
}
