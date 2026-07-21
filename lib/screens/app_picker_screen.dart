import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows a searchable list of all installed apps split into User/System tabs.
/// Returns the selected package name list.
class AppPickerScreen extends StatefulWidget {
  final List<String> initialSelection;
  final String groupName;

  const AppPickerScreen({Key? key, required this.initialSelection, required this.groupName}) : super(key: key);

  @override
  State<AppPickerScreen> createState() => _AppPickerScreenState();
}

class _AppPickerScreenState extends State<AppPickerScreen> {
  static const _channel = MethodChannel('app_closure');

  List<Map<String, String>> _userApps = [];
  List<Map<String, String>> _systemApps = [];
  List<Map<String, String>> _filteredUser = [];
  List<Map<String, String>> _filteredSystem = [];
  Set<String> _selected = {};
  bool _loading = true;
  String _query = '';
  int _tabIndex = 0; // 0 = User, 1 = System

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.initialSelection);
    _loadApps();
  }

  Future<void> _loadApps() async {
    try {
      final List<dynamic> result = await _channel.invokeMethod('getInstalledApps');
      final apps = result.map((e) => Map<String, String>.from(e as Map)).toList();
      apps.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));

      final user = apps.where((a) => a['isSystem'] != 'true').toList();
      final system = apps.where((a) => a['isSystem'] == 'true').toList();

      if (mounted) {
        setState(() {
          _userApps = user;
          _systemApps = system;
          _filteredUser = user;
          _filteredSystem = system;
          _loading = false;
        });
      }
    } catch (e, stack) {
      debugPrint('getInstalledApps failed: $e\n$stack');
      if (mounted) {
        setState(() {
          _loading = false;
          _userApps = [];
          _systemApps = [];
        });
      }
    }
  }

  void _onSearch(String q) {
    final lower = q.toLowerCase();
    setState(() {
      _query = lower;
      _filteredUser = _userApps.where((a) =>
        (a['name'] ?? '').toLowerCase().contains(lower) ||
        (a['packageName'] ?? '').toLowerCase().contains(lower)).toList();
      _filteredSystem = _systemApps.where((a) =>
        (a['name'] ?? '').toLowerCase().contains(lower) ||
        (a['packageName'] ?? '').toLowerCase().contains(lower)).toList();
    });
  }

  void _toggle(String pkg) {
    setState(() {
      if (_selected.contains(pkg)) {
        _selected.remove(pkg);
      } else {
        _selected.add(pkg);
      }
    });
  }

  Widget _buildAppList(List<Map<String, String>> apps) {
    if (_loading) return const Center(child: CupertinoActivityIndicator());
    if (apps.isEmpty) {
      return Center(
        child: Text(
          _query.isEmpty ? 'No apps found' : 'No results for "$_query"',
          style: const TextStyle(color: Colors.white54),
        ),
      );
    }

    return ListView.builder(
      itemCount: apps.length,
      itemBuilder: (_, i) {
        final app = apps[i];
        final pkg = app['packageName'] ?? '';
        final name = app['name'] ?? pkg;
        final isSelected = _selected.contains(pkg);
        return GestureDetector(
          onTap: () => _toggle(pkg),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF0A84FF).withOpacity(0.15)
                  : const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF0A84FF).withOpacity(0.5)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isSelected
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.circle,
                  color: isSelected
                      ? const Color(0xFF0A84FF)
                      : Colors.white30,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        pkg,
                        style: const TextStyle(color: Colors.white30, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentList = _tabIndex == 0 ? _filteredUser : _filteredSystem;

    return CupertinoPageScaffold(
      backgroundColor: Colors.black,
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          'Select Apps — ${widget.groupName}',
          style: const TextStyle(color: Colors.white),
        ),
        previousPageTitle: 'Settings',
        backgroundColor: const Color(0xFF0F0F0F).withOpacity(0.9),
        border: null,
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () {
            // Only keep selected apps that actually exist on the device
            final existingPackages = <String>{};
            existingPackages.addAll(_userApps.map((a) => a['packageName']!));
            existingPackages.addAll(_systemApps.map((a) => a['packageName']!));
            final validSelected = _selected.where((p) => existingPackages.contains(p)).toList();
            Navigator.of(context).pop(validSelected);
          },
          child: Text(
            'Done',
            style: const TextStyle(
              color: Color(0xFF0A84FF),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // ── Search ──
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: CupertinoSearchTextField(
                placeholder: 'Search apps...',
                style: const TextStyle(color: Colors.white),
                onChanged: _onSearch,
              ),
            ),

            // ── User / System Tabs ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: CupertinoSlidingSegmentedControl<int>(
                backgroundColor: const Color(0xFF1C1C1E),
                thumbColor: const Color(0xFF3A3A3C),
                groupValue: _tabIndex,
                onValueChanged: (v) {
                  if (v != null) setState(() => _tabIndex = v);
                },
                children: {
                  0: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(CupertinoIcons.person_fill, size: 14, color: Colors.white70),
                        const SizedBox(width: 6),
                        Text(
                          'User Apps (${_filteredUser.length})',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  1: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(CupertinoIcons.settings, size: 14, color: Colors.white70),
                        const SizedBox(width: 6),
                        Text(
                          'System (${_filteredSystem.length})',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                },
              ),
            ),

            const SizedBox(height: 6),

            // ── App List ──
            Expanded(child: _buildAppList(currentList)),
          ],
        ),
      ),
    );
  }
}
