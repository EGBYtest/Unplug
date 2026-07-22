import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'services/app_closure_handler.dart';
import 'home_screen.dart';
import 'services/storage_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({Key? key}) : super(key: key);

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with WidgetsBindingObserver {
  bool _hasUsageAccess = false;
  bool _hasAccessibility = false;
  bool _isChecking = false;
  String? _manufacturer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initManufacturer();
    _checkPermissions();
  }

  Future<void> _initManufacturer() async {
    final m = await AppClosureHandler().getDeviceManufacturer();
    if (mounted) setState(() => _manufacturer = m?.toLowerCase());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    if (!mounted) return;
    setState(() => _isChecking = true);
    final usageAccess = await AppClosureHandler().hasUsageAccess();
    final accessibility = await AppClosureHandler().hasAccessibilityEnabled();
    if (!mounted) return;
    setState(() {
      _hasUsageAccess = usageAccess;
      _hasAccessibility = accessibility;
      _isChecking = false;
    });
  }

  Future<void> _continueToApp() async {
    await StorageService().setOnboardingComplete();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      CupertinoPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  /// Returns manufacturer-specific accessibility setup instructions.
  String _getAccessibilityInstructions() {
    final m = _manufacturer ?? '';

    if (m.contains('xiaomi') || m.contains('redmi') || m.contains('poco')) {
      return 'Settings → Additional settings → Accessibility → Downloaded apps → Unplug.\n\n'
          'IMPORTANT for MIUI/HyperOS:\n'
          '• Enable "Autostart" in App Info → Autostart.\n'
          '• Set Battery Saver to "No restrictions" in App Info → Battery saver.\n'
          '• Lock Unplug in recent apps (swipe down on app preview).';
    }
    if (m.contains('samsung')) {
      return 'Settings → Accessibility → Installed apps → Unplug.\n\n'
          'Samsung One UI tip: if the switch resets after reboot, go to '
          'Device Care → Battery → Background usage limits → Add Unplug to '
          '"Never sleeping apps".';
    }
    if (m.contains('oppo') || m.contains('oneplus') || m.contains('realme')) {
      return 'Settings → Additional settings → Accessibility → Downloaded services → Unplug.\n\n'
          'ColorOS/OxygenOS tip: lock Unplug in recent apps (tap the lock icon) '
          'to prevent system from killing it.';
    }
    if (m.contains('huawei') || m.contains('honor')) {
      return 'Settings → Accessibility features → Accessibility → Downloaded services → Unplug.\n\n'
          'EMUI tip: go to App Launch in settings and set Unplug to "Manage manually" '
          'with Auto-launch, Secondary launch, and Run in background all enabled.';
    }
    if (m.contains('vivo') || m.contains('iqoo')) {
      return 'Settings → Accessibility → Installed services → Unplug.\n\n'
          'Funtouch OS tip: enable Autostart and disable battery optimization for Unplug.';
    }

    // Pixel, Motorola, Nokia, ASUS, Sony, and other stock/near-stock Android
    return 'Settings → Accessibility → Downloaded apps → Unplug.\n\n'
        'Tap the card above to open Accessibility settings directly. '
        'Look for "Unplug" under Downloaded apps/services and toggle it on.';
  }

  /// Returns extra warnings for specific manufacturers.
  String? _getExtraWarnings() {
    final m = _manufacturer ?? '';

    if (m.contains('xiaomi') || m.contains('redmi') || m.contains('poco')) {
      return 'MIUI/HyperOS may kill the background service even after enabling it. '
          'Follow the tips in the Accessibility card below to prevent this.';
    }
    if (m.contains('oppo') || m.contains('oneplus') || m.contains('realme')) {
      return 'ColorOS/OxygenOS aggressively kills background services. '
          'Lock Unplug in recent apps after setup.';
    }
    if (m.contains('huawei') || m.contains('honor')) {
      return 'EMUI may disable the service after reboot. '
          'Configure App Launch settings as described below.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final allGranted = _hasUsageAccess && _hasAccessibility;
    final extraWarning = _getExtraWarnings();

    return CupertinoPageScaffold(
      backgroundColor: Colors.black,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),

              Center(
                child: Column(
                  children: [
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0A84FF), Color(0xFF30D158)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(color: const Color(0xFF0A84FF).withOpacity(0.4), blurRadius: 30, spreadRadius: 5),
                        ],
                      ),
                      child: const Icon(CupertinoIcons.lock_shield_fill, color: Colors.white, size: 48),
                    ),
                    const SizedBox(height: 20),
                    const Text('Unplug', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -1)),
                    const SizedBox(height: 8),
                    const Text('Take control of your screen time.', style: TextStyle(fontSize: 16, color: Colors.white60)),
                  ],
                ),
              ),

              const SizedBox(height: 48),

              // Play Protect Notice (sideload installs)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFF9F0A).withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(CupertinoIcons.shield_lefthalf_fill, color: Color(0xFFFF9F0A), size: 18),
                        SizedBox(width: 8),
                        Text('Play Protect Notice', style: TextStyle(color: Color(0xFFFF9F0A), fontWeight: FontWeight.w700, fontSize: 15)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Google Play Protect may warn you during install because Unplug uses an Accessibility Service — a sensitive Android permission. '
                      'This is normal for sideloaded apps that monitor app usage.\n\n'
                      'To install: tap "More details" → "Install anyway".\n'
                      'Unplug is fully open-source and does not collect any data.',
                      style: TextStyle(color: Colors.white70, height: 1.6, fontSize: 14),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Privacy / Open Source Notice
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF30D158).withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(CupertinoIcons.lock_fill, color: Color(0xFF30D158), size: 18),
                        SizedBox(width: 8),
                        Text('Private & Open Source', style: TextStyle(color: Color(0xFF30D158), fontWeight: FontWeight.w700, fontSize: 15)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '✓  All data is stored locally on your device.\n'
                      '✓  Nothing is ever sent to any server.\n'
                      '✓  Fully open-source — inspect the code anytime.',
                      style: TextStyle(color: Colors.white70, height: 1.6, fontSize: 14),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              const Text('Required Permissions', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
              const SizedBox(height: 6),
              const Text(
                'Unplug needs these permissions to detect and enforce app limits. Tap each card to open the exact settings page.',
                style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 20),

              _PermissionCard(
                icon: CupertinoIcons.chart_bar_fill,
                title: 'Usage Access',
                description: 'Lets Unplug see how long you\'ve used each app today. '
                    'This is a standard Android permission also used by Digital Wellbeing.\n\n'
                    'Unplug only reads usage stats — it never accesses any other data.',
                isGranted: _hasUsageAccess,
                onTap: () async {
                  await AppClosureHandler().openUsageAccessSettings();
                },
              ),
              const SizedBox(height: 12),

              if (extraWarning != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFF9F0A).withOpacity(0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Color(0xFFFF9F0A), size: 16),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(extraWarning, style: const TextStyle(color: Color(0xFFFF9F0A), fontSize: 13, height: 1.4)),
                      ),
                    ],
                  ),
                ),
              ],

              _PermissionCard(
                icon: CupertinoIcons.eye_fill,
                title: 'Accessibility Service',
                description: _getAccessibilityInstructions(),
                isGranted: _hasAccessibility,
                onTap: () async {
                  await AppClosureHandler().openAccessibilitySettings();
                },
              ),

              const SizedBox(height: 40),

              SizedBox(
                width: double.infinity,
                child: _isChecking
                    ? const Center(child: CupertinoActivityIndicator())
                    : Container(
                        decoration: allGranted
                            ? BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [BoxShadow(color: const Color(0xFF0A84FF).withOpacity(0.4), blurRadius: 24, offset: const Offset(0, 4))],
                              )
                            : null,
                        child: CupertinoButton.filled(
                          borderRadius: BorderRadius.circular(14),
                          onPressed: allGranted ? _continueToApp : null,
                          child: Text(
                            allGranted ? 'Get Started →' : 'Grant permissions above to continue',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
              ),
              if (!allGranted && !_isChecking) ...[
                const SizedBox(height: 12),
                Center(
                  child: CupertinoButton(
                    onPressed: _checkPermissions,
                    child: const Text('Re-check permissions', style: TextStyle(color: Colors.white54)),
                  ),
                ),
              ],
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool isGranted;
  final VoidCallback onTap;

  const _PermissionCard({required this.icon, required this.title, required this.description, required this.isGranted, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isGranted ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isGranted ? const Color(0xFF30D158).withOpacity(0.6) : const Color(0xFF3A3A3C),
            width: 1.5,
          ),
          boxShadow: isGranted ? [BoxShadow(color: const Color(0xFF30D158).withOpacity(0.12), blurRadius: 16)] : [],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isGranted ? const Color(0xFF30D158).withOpacity(0.15) : const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: isGranted ? const Color(0xFF30D158) : Colors.white54, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: isGranted ? const Color(0xFF30D158) : Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(description, style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.4)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              isGranted ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.chevron_right,
              color: isGranted ? const Color(0xFF30D158) : Colors.white30,
              size: isGranted ? 24 : 18,
            ),
          ],
        ),
      ),
    );
  }
}
