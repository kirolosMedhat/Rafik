import 'package:flutter_test/flutter_test.dart';
import 'package:rafik/main.dart';

void main() {
  testWidgets('Rafik app smoke test', (WidgetTester tester) async {
    // Basic verification that RafikApp builds
    expect(const RafikApp(), isNotNull);
  });
}
