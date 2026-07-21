import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:app_idea/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Test getInstalledApps channel', (WidgetTester tester) async {
    app.main();
    await tester.pumpAndSettle();

    const channel = MethodChannel('app_closure');
    try {
      final List<dynamic> result = await channel.invokeMethod('getInstalledApps');
      print('=== GET_INSTALLED_APPS_SUCCESS ===');
      print('Count: ${result.length}');
      if (result.isNotEmpty) {
        print('First item: ${result.first}');
        print('First item type: ${result.first.runtimeType}');
      }
      final apps = result.map((e) => Map<String, String>.from(e as Map)).toList();
      print('=== MAPPING_SUCCESS ===');
      print('Mapped count: ${apps.length}');
    } catch (e, stack) {
      print('=== GET_INSTALLED_APPS_ERROR ===');
      print('Error: $e');
      print('Stack: $stack');
    }
  });
}
