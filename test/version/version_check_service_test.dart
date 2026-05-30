import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tech_world/version/version_check_service.dart';

/// Helper: build a [MockClient] that returns a `version.json`-shaped body
/// containing [build]. Records each request URL in [hits] so the test can
/// assert polling cadence + cache-busting.
MockClient _mockClient(String build, List<Uri> hits, {int status = 200}) {
  return MockClient((request) async {
    hits.add(request.url);
    return http.Response(
      jsonEncode({'build': build, 'deployedAt': '2026-05-30T00:00:00Z'}),
      status,
    );
  });
}

void main() {
  group('VersionCheckService', () {
    test('updateAvailable stays false when server build matches runtime',
        () async {
      final hits = <Uri>[];
      final svc = VersionCheckService(
        runtimeBuild: 'abc123',
        versionJsonUrl: 'version.json',
        httpClient: _mockClient('abc123', hits),
      );
      await svc.checkOnce();
      expect(svc.updateAvailable.value, isFalse);
      expect(hits, hasLength(1));
      svc.dispose();
    });

    test('updateAvailable flips true when server build differs', () async {
      final hits = <Uri>[];
      final svc = VersionCheckService(
        runtimeBuild: 'abc123',
        versionJsonUrl: 'version.json',
        httpClient: _mockClient('def456', hits),
      );
      await svc.checkOnce();
      expect(svc.updateAvailable.value, isTrue);
      svc.dispose();
    });

    test('non-200 responses are treated as no signal', () async {
      final hits = <Uri>[];
      final svc = VersionCheckService(
        runtimeBuild: 'abc123',
        versionJsonUrl: 'version.json',
        httpClient: _mockClient('def456', hits, status: 503),
      );
      await svc.checkOnce();
      expect(svc.updateAvailable.value, isFalse);
      svc.dispose();
    });

    test('malformed JSON does not throw and does not set flag', () async {
      final hits = <Uri>[];
      final svc = VersionCheckService(
        runtimeBuild: 'abc123',
        versionJsonUrl: 'version.json',
        httpClient: MockClient((req) async {
          hits.add(req.url);
          return http.Response('not json', 200);
        }),
      );
      await svc.checkOnce();
      expect(svc.updateAvailable.value, isFalse);
      svc.dispose();
    });

    test('once latched, subsequent polls are no-ops', () async {
      final hits = <Uri>[];
      final svc = VersionCheckService(
        runtimeBuild: 'abc123',
        versionJsonUrl: 'version.json',
        httpClient: _mockClient('def456', hits),
      );
      await svc.checkOnce();
      expect(svc.updateAvailable.value, isTrue);
      expect(hits, hasLength(1));
      await svc.checkOnce();
      // Still 1 hit — the latch short-circuits the network call.
      expect(hits, hasLength(1));
      svc.dispose();
    });

    test('each poll cache-busts with ?t=<timestamp>', () async {
      final hits = <Uri>[];
      var clockMs = 1000;
      final svc = VersionCheckService(
        runtimeBuild: 'abc123',
        versionJsonUrl: 'version.json',
        httpClient: _mockClient('abc123', hits),
        now: () =>
            DateTime.fromMillisecondsSinceEpoch(clockMs += 1000, isUtc: true),
      );
      await svc.checkOnce();
      await svc.checkOnce();
      expect(hits, hasLength(2));
      expect(hits[0].queryParameters['t'], isNotNull);
      expect(hits[1].queryParameters['t'], isNotNull);
      expect(hits[0].queryParameters['t'],
          isNot(equals(hits[1].queryParameters['t'])));
      svc.dispose();
    });

    test('start() schedules periodic polls at the configured interval', () {
      fakeAsync((async) {
        final hits = <Uri>[];
        final svc = VersionCheckService(
          runtimeBuild: 'abc123',
          versionJsonUrl: 'version.json',
          httpClient: _mockClient('abc123', hits),
          pollInterval: const Duration(minutes: 5),
        );
        svc.start();
        // Initial fire is scheduled via unawaited Future; flush async work.
        async.flushMicrotasks();
        expect(hits, hasLength(1));

        async.elapse(const Duration(minutes: 5));
        expect(hits, hasLength(2));

        async.elapse(const Duration(minutes: 5));
        expect(hits, hasLength(3));

        svc.dispose();
      });
    });
  });
}
