import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:unplug/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Test getInstalledApps channel', (WidgetTester tester) async {
    app.main();
    await tester.pumpAndSettle();

    const channel = MethodChannel('app_closure');
    try {
      final List<dynamic> result = await channel.invokeMethod('getInstalledApps');
      debugPrint('=== GET_INSTALLED_APPS_SUCCESS ===');
      debugPrint('Count: ${result.length}');
      if (result.isNotEmpty) {
        debugPrint('First item: ${result.first}');
        debugPrint('First item type: ${result.first.runtimeType}');
      }
      final apps = result.map((e) => Map<String, String>.from(e as Map)).toList();
      debugPrint('=== MAPPING_SUCCESS ===');
      debugPrint('Mapped count: ${apps.length}');
    } catch (e, stack) {
      debugPrint('=== GET_INSTALLED_APPS_ERROR ===');
      debugPrint('Error: $e');
      debugPrint('Stack: $stack');
    }
  });
}
