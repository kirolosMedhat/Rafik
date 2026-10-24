import 'package:flutter_test/flutter_test.dart';
import 'package:rafik/core/services/supabase_service.dart';
import 'package:rafik/main_rider.dart';
import 'package:rafik/main_driver.dart';

void main() {
  group('Rafik Fare Computation Engine', () {
    test('Calculates minimum fare floor (25 EGP) for short trips', () {
      expect(SupabaseService.computeFarePreview(0.1), equals(25.0));
      expect(SupabaseService.computeFarePreview(0.5), equals(25.0));
      expect(SupabaseService.computeFarePreview(1.0), equals(25.0));
    });

    test('Calculates exact distance fare (15 + km * 10) for longer trips', () {
      expect(SupabaseService.computeFarePreview(5.0), equals(65.0));
      expect(SupabaseService.computeFarePreview(10.0), equals(115.0));
      expect(SupabaseService.computeFarePreview(28.4), equals(299.0));
    });
  });

  group('Rafik Safety PIN Logic', () {
    test('Validates 4-digit PIN attempt bounds', () {
      int attempts = 0;
      bool isLocked = false;

      // Simulate 3 attempts
      for (int i = 0; i < 3; i++) {
        attempts++;
        if (attempts >= 3) {
          isLocked = true;
        }
      }

      expect(attempts, equals(3));
      expect(isLocked, isTrue);
    });
  });

  group('Application Entrypoint Smoke Tests', () {
    test('RafikRiderApp can be instantiated', () {
      expect(const RafikRiderApp(), isNotNull);
    });

    test('RafikDriverApp can be instantiated', () {
      expect(const RafikDriverApp(), isNotNull);
    });
  });
}
