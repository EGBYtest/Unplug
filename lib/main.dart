import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';
import 'services/ad_reward_system.dart';
import 'services/storage_service.dart';
import 'services/app_closure_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await StorageService().init();
  await _trackInstall();
  await AdRewardSystem().initializeAds();

  runApp(const UnplugApp());
}

const _appVersion = '1.2.0';

Future<void> _trackInstall() async {
  final storage = StorageService();
  if (storage.installReported) return;

  try {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);

    // Total installs
    final r1 = await client.getUrl(
      Uri.parse('https://api.counterapi.dev/v1/unplug/installs/up'),
    );
    await r1.close();

    // Per-version installs
    final r2 = await client.getUrl(
      Uri.parse('https://api.counterapi.dev/v1/unplug/installs_v$_appVersion/up'),
    );
    await r2.close();

    await storage.setInstallReported();
    client.close();
  } catch (_) {
    // Silently fail — install tracking is non-critical
  }
}

class UnplugApp extends StatefulWidget {
  const UnplugApp({Key? key}) : super(key: key);

  @override
  State<UnplugApp> createState() => _UnplugAppState();
}

class _UnplugAppState extends State<UnplugApp> {
  static const MethodChannel _channel = MethodChannel('app_closure');
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // Listen for native → Flutter lock screen requests
    // (fired by AccessibilityService when a blocked app is opened)
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'showLockScreen') {
        final args = call.arguments is Map ? call.arguments as Map : {};
        final appName = args['appName'] ?? 'App';
        final bannedFeature = args['bannedFeature'] as String?;
        final context = navigatorKey.currentContext;
        if (context != null) {
          await AppClosureHandler().showLockScreen(
            context,
            appName as String,
            bannedFeature: (bannedFeature != null && bannedFeature.isNotEmpty) ? bannedFeature : null,
          );
          _channel.invokeMethod('lockScreenDismissed');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool skipOnboarding = StorageService().onboardingComplete;

    return CupertinoApp(
      navigatorKey: navigatorKey,
      title: 'Unplug',
      theme: const CupertinoThemeData(
        brightness: Brightness.dark,
        primaryColor: CupertinoColors.activeBlue,
        scaffoldBackgroundColor: CupertinoColors.black,
        barBackgroundColor: Color(0xFF121212),
        textTheme: CupertinoTextThemeData(
          primaryColor: CupertinoColors.white,
        ),
      ),
      home: skipOnboarding ? const HomeScreen() : const OnboardingScreen(),
      localizationsDelegates: const [
        DefaultMaterialLocalizations.delegate,
        DefaultCupertinoLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
    );
  }
}
