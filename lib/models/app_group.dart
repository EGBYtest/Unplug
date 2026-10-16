class BannedFeature {
  final String id;
  final String name;
  final String packageName;
  bool isEnabled;
  final List<String> contentKeywords;
  final String? activityPattern;

  BannedFeature({
    required this.id,
    required this.name,
    required this.packageName,
    this.isEnabled = true,
    required this.contentKeywords,
    this.activityPattern,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'packageName': packageName,
    'isEnabled': isEnabled,
    'contentKeywords': contentKeywords,
    if (activityPattern != null) 'activityPattern': activityPattern,
  };

  factory BannedFeature.fromJson(Map<String, dynamic> json) => BannedFeature(
    id: json['id'] as String? ?? json['name'] as String,
    name: json['name'] as String,
    packageName: json['packageName'] as String? ?? '',
    isEnabled: json['isEnabled'] as bool? ?? true,
    contentKeywords: json['contentKeywords'] != null
        ? List<String>.from(json['contentKeywords'] as List)
        : [],
    activityPattern: json['activityPattern'] as String?,
  );
}

class AppGroup {
  String name;
  List<String> packageNames;
  int timeLimitMinutes;
  List<BannedFeature> bannedFeatures;

  /// Ask "was this meant to be a long sit or a quick check?" once the user has
  /// been in one of this group's apps continuously for
  /// [breakReminderMinutes]. Off by default — it is friction the user opts
  /// into per group, never something a new group silently inherits.
  bool breakReminderEnabled;

  /// Gate every launch of this group's apps behind a short countdown with an
  /// explicit "Open X" / "Go back" choice. Off by default, same reasoning.
  bool openGateEnabled;

  /// How long continuous use must last before the break reminder fires.
  /// Minutes, matching [timeLimitMinutes] so both are read on the same scale.
  /// Clamped on read, so a hand-edited value cannot make the reminder fire
  /// instantly or effectively never.
  int breakReminderMinutes;

  static const int defaultBreakReminderMinutes = 10;
  static const int minBreakReminderMinutes = 1;
  static const int maxBreakReminderMinutes = 60;

  AppGroup({
    required this.name,
    required this.packageNames,
    required this.timeLimitMinutes,
    List<BannedFeature>? bannedFeatures,
    this.breakReminderEnabled = false,
    this.openGateEnabled = false,
    int breakReminderMinutes = defaultBreakReminderMinutes,
  })  : bannedFeatures = bannedFeatures ?? [],
        breakReminderMinutes = breakReminderMinutes.clamp(
          minBreakReminderMinutes,
          maxBreakReminderMinutes,
        );

  int getRemainingTime(int totalUsageMinutes, {int bonusMinutes = 0}) {
    final effective = timeLimitMinutes + bonusMinutes - totalUsageMinutes;
    return effective < 0 ? 0 : effective;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'packageNames': packageNames,
    'timeLimitMinutes': timeLimitMinutes,
    'bannedFeatures': bannedFeatures.map((b) => b.toJson()).toList(),
    'breakReminderEnabled': breakReminderEnabled,
    'openGateEnabled': openGateEnabled,
    'breakReminderMinutes': breakReminderMinutes,
  };

  // Every field above the flags is required, but a stored payload written by an
  // older build simply has no break-reminder or open-gate keys. They default
  // to off rather than being inferred, so upgrading never turns friction on for
  // someone who never asked for it. The Kotlin side reads them with optBoolean
  // for the same reason — see UsageAccessibilityService.
  factory AppGroup.fromJson(Map<String, dynamic> json) => AppGroup(
        name: json['name'] as String,
        packageNames: List<String>.from(json['packageNames'] as List),
        timeLimitMinutes: json['timeLimitMinutes'] as int,
        bannedFeatures: json['bannedFeatures'] != null
            ? (json['bannedFeatures'] as List)
                .map((e) => BannedFeature.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList()
            : [],
        breakReminderEnabled: json['breakReminderEnabled'] as bool? ?? false,
        openGateEnabled: json['openGateEnabled'] as bool? ?? false,
        breakReminderMinutes: (json['breakReminderMinutes'] as int?) ??
            defaultBreakReminderMinutes,
      );
}

