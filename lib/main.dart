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

  // Initialize core services before runApp
  await StorageService().init();
  await AdRewardSystem().initializeAds();

  runApp(const ScreenTimeLockApp());
}

class ScreenTimeLockApp extends StatefulWidget {
  const ScreenTimeLockApp({Key? key}) : super(key: key);

  @override
  State<ScreenTimeLockApp> createState() => _ScreenTimeLockAppState();
}

class _ScreenTimeLockAppState extends State<ScreenTimeLockApp> {
  static const MethodChannel _channel = MethodChannel('app_closure');
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // Listen for native → Flutter lock screen requests
    // (fired by AccessibilityService when a blocked app is opened)
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'showLockScreen') {
        final String appName =
            (call.arguments is Map ? call.arguments['appName'] : null) ??
                'App';
        final context = navigatorKey.currentContext;
        if (context != null) {
          AppClosureHandler().showLockScreen(context, appName);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Skip onboarding if already completed
    final bool skipOnboarding = StorageService().onboardingComplete;

    return CupertinoApp(
      navigatorKey: navigatorKey,
      title: 'ScreenTimeLock',
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
