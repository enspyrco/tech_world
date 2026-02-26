import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/tiles/terrain_bitmask.dart';

void main() {
  group('Bitmask direction constants', () {
    test('has correct bit values for 8 directions', () {
      expect(Bitmask.n, 1);
      expect(Bitmask.ne, 2);
      expect(Bitmask.e, 4);
      expect(Bitmask.se, 8);
      expect(Bitmask.s, 16);
      expect(Bitmask.sw, 32);
      expect(Bitmask.w, 64);
      expect(Bitmask.nw, 128);
    });

    test('offsets list has 8 entries matching N, NE, E, SE, S, SW, W, NW', () {
      expect(Bitmask.offsets, hasLength(8));
      // N=1 → (0, -1)
      expect(Bitmask.offsets[0], (0, -1));
      // NE=2 → (1, -1)
      expect(Bitmask.offsets[1], (1, -1));
      // E=4 → (1, 0)
      expect(Bitmask.offsets[2], (1, 0));
      // SE=8 → (1, 1)
      expect(Bitmask.offsets[3], (1, 1));
      // S=16 → (0, 1)
      expect(Bitmask.offsets[4], (0, 1));
      // SW=32 → (-1, 1)
      expect(Bitmask.offsets[5], (-1, 1));
      // W=64 → (-1, 0)
      expect(Bitmask.offsets[6], (-1, 0));
      // NW=128 → (-1, -1)
      expect(Bitmask.offsets[7], (-1, -1));
    });
  });

  group('computeRawBitmask', () {
    test('all neighbors same terrain returns 255', () {
      bool isMatch(int x, int y) => true;
      expect(computeRawBitmask(5, 5, isMatch), 255);
    });

    test('no neighbors same terrain returns 0', () {
      bool isMatch(int x, int y) => false;
      expect(computeRawBitmask(5, 5, isMatch), 0);
    });

    test('only north neighbor returns N bit', () {
      bool isMatch(int x, int y) => (x == 5 && y == 4);
      expect(computeRawBitmask(5, 5, isMatch), Bitmask.n);
    });

    test('north and east neighbors returns N|E', () {
      bool isMatch(int x, int y) =>
          (x == 5 && y == 4) || (x == 6 && y == 5);
      expect(computeRawBitmask(5, 5, isMatch), Bitmask.n | Bitmask.e);
    });

    test('all edges but no corners returns N|E|S|W = 85', () {
      bool isMatch(int x, int y) {
        if (x == 5 && y == 4) return true; // N
        if (x == 6 && y == 5) return true; // E
        if (x == 5 && y == 6) return true; // S
        if (x == 4 && y == 5) return true; // W
        return false;
      }
      expect(
        computeRawBitmask(5, 5, isMatch),
        Bitmask.n | Bitmask.e | Bitmask.s | Bitmask.w,
      );
    });
  });

  group('simplifyBitmask', () {
    test('all bits set stays 255', () {
      expect(simplifyBitmask(255), 255);
    });

    test('no bits stays 0', () {
      expect(simplifyBitmask(0), 0);
    });

    test('NE is masked out when N is missing', () {
      // NE=2 alone → NE requires N and E → becomes 0
      expect(simplifyBitmask(Bitmask.ne), 0);
    });

    test('NE is masked out when E is missing', () {
      // N=1 + NE=2 → NE requires E too → masked to just N
      expect(simplifyBitmask(Bitmask.n | Bitmask.ne), Bitmask.n);
    });

    test('NE kept when both N and E are set', () {
      final raw = Bitmask.n | Bitmask.ne | Bitmask.e;
      expect(simplifyBitmask(raw), raw);
    });

    test('SE is masked out when S or E is missing', () {
      expect(simplifyBitmask(Bitmask.se), 0);
      expect(simplifyBitmask(Bitmask.s | Bitmask.se), Bitmask.s);
      expect(simplifyBitmask(Bitmask.e | Bitmask.se), Bitmask.e);
    });

    test('SE kept when both S and E are set', () {
      final raw = Bitmask.s | Bitmask.se | Bitmask.e;
      expect(simplifyBitmask(raw), raw);
    });

    test('SW is masked out when S or W is missing', () {
      expect(simplifyBitmask(Bitmask.sw), 0);
      expect(simplifyBitmask(Bitmask.s | Bitmask.sw), Bitmask.s);
      expect(simplifyBitmask(Bitmask.w | Bitmask.sw), Bitmask.w);
    });

    test('SW kept when both S and W are set', () {
      final raw = Bitmask.s | Bitmask.sw | Bitmask.w;
      expect(simplifyBitmask(raw), raw);
    });

    test('NW is masked out when N or W is missing', () {
      expect(simplifyBitmask(Bitmask.nw), 0);
      expect(simplifyBitmask(Bitmask.n | Bitmask.nw), Bitmask.n);
      expect(simplifyBitmask(Bitmask.w | Bitmask.nw), Bitmask.w);
    });

    test('NW kept when both N and W are set', () {
      final raw = Bitmask.n | Bitmask.nw | Bitmask.w;
      expect(simplifyBitmask(raw), raw);
    });

    test('edge bits are never masked', () {
      // Edge bits (N, E, S, W) are always preserved.
      expect(simplifyBitmask(Bitmask.n), Bitmask.n);
      expect(simplifyBitmask(Bitmask.e), Bitmask.e);
      expect(simplifyBitmask(Bitmask.s), Bitmask.s);
      expect(simplifyBitmask(Bitmask.w), Bitmask.w);
    });
  });

  group('simplifyBitmask produces exactly 47 unique values', () {
    test('enumerating all 256 raw bitmasks yields 47 unique simplified values',
        () {
      final uniqueValues = <int>{};
      for (var raw = 0; raw < 256; raw++) {
        uniqueValues.add(simplifyBitmask(raw));
      }
      expect(uniqueValues.length, 47);
    });
  });

  group('computeBitmask', () {
    test('combines raw + simplify in one call', () {
      // All neighbors match → raw 255 → simplified 255.
      bool allMatch(int x, int y) => true;
      expect(computeBitmask(5, 5, allMatch), 255);
    });

    test('isolated cell returns 0', () {
      bool noneMatch(int x, int y) => false;
      expect(computeBitmask(5, 5, noneMatch), 0);
    });

    test('L-shaped neighbor pattern simplifies correctly', () {
      // N and E set, NE set too → NE is relevant → kept.
      bool isMatch(int x, int y) =>
          (x == 5 && y == 4) || // N
          (x == 6 && y == 4) || // NE
          (x == 6 && y == 5); // E
      expect(
        computeBitmask(5, 5, isMatch),
        Bitmask.n | Bitmask.ne | Bitmask.e,
      );
    });

    test('corner neighbor without adjacent edges is masked', () {
      // Only NE set → no N or E → NE is masked → 0.
      bool isMatch(int x, int y) => (x == 6 && y == 4);
      expect(computeBitmask(5, 5, isMatch), 0);
    });
  });

  group('allSimplifiedBitmasks', () {
    test('contains exactly 47 values', () {
      expect(allSimplifiedBitmasks.length, 47);
    });

    test('contains 0 (isolated) and 255 (fully surrounded)', () {
      expect(allSimplifiedBitmasks, contains(0));
      expect(allSimplifiedBitmasks, contains(255));
    });

    test('all values are in range 0-255', () {
      for (final v in allSimplifiedBitmasks) {
        expect(v, greaterThanOrEqualTo(0));
        expect(v, lessThanOrEqualTo(255));
      }
    });
  });
}
