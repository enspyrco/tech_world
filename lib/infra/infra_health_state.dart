/// Data model for infrastructure health monitoring.
///
/// Health snapshots arrive from the Dreamfinder agent via the
/// `infra-health` LiveKit data channel topic. Each snapshot contains
/// the status of every monitored service.
library;

/// Health status of a monitored service.
enum ServiceStatus {
  /// Service is operating normally.
  up,

  /// Service is responding but degraded (slow, reconnecting, etc.).
  warn,

  /// Service is unreachable or crashed.
  down,

  /// No health data received yet.
  unknown;

  /// Parse from the short status string used in data channel messages.
  static ServiceStatus fromString(String s) => switch (s) {
        'up' => up,
        'warn' => warn,
        'down' => down,
        _ => unknown,
      };
}

/// Health state of a single service at a point in time.
class ServiceHealth {
  const ServiceHealth({
    required this.serviceId,
    required this.status,
    this.detail = '',
  });

  /// Identifier matching the service IDs in [InfraTopology].
  final String serviceId;

  /// Current health status.
  final ServiceStatus status;

  /// Human-readable detail (e.g. "heartbeat 2s ago", "WS closed").
  final String detail;

  factory ServiceHealth.fromJson(String serviceId, Map<String, dynamic> json) {
    return ServiceHealth(
      serviceId: serviceId,
      status: ServiceStatus.fromString(json['s'] as String? ?? ''),
      detail: json['d'] as String? ?? '',
    );
  }
}

/// Snapshot of all service health states at a point in time.
class InfraHealthSnapshot {
  const InfraHealthSnapshot({
    required this.services,
    required this.timestamp,
  });

  /// Health state keyed by service ID.
  final Map<String, ServiceHealth> services;

  /// When the agent published this snapshot.
  final DateTime? timestamp;

  /// All services default to [ServiceStatus.unknown].
  static const empty = InfraHealthSnapshot(
    services: {},
    timestamp: null,
  );

  /// Look up a single service. Returns [ServiceStatus.unknown] if absent.
  ServiceStatus statusOf(String serviceId) =>
      services[serviceId]?.status ?? ServiceStatus.unknown;

  factory InfraHealthSnapshot.fromJson(Map<String, dynamic> json) {
    final servicesJson = json['services'] as Map<String, dynamic>? ?? {};
    final services = <String, ServiceHealth>{};
    for (final entry in servicesJson.entries) {
      services[entry.key] = ServiceHealth.fromJson(
        entry.key,
        entry.value as Map<String, dynamic>,
      );
    }
    return InfraHealthSnapshot(
      services: services,
      timestamp: DateTime.tryParse(json['ts'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
