class BannedFeature {
  String name;
  String? activityPattern;
  List<String> screenTextPatterns;

  BannedFeature({
    required this.name,
    this.activityPattern,
    List<String>? screenTextPatterns,
  }) : screenTextPatterns = screenTextPatterns ?? [];

  Map<String, dynamic> toJson() => {
    'name': name,
    if (activityPattern != null && activityPattern!.isNotEmpty)
      'activityPattern': activityPattern,
    if (screenTextPatterns.isNotEmpty)
      'screenTextPatterns': screenTextPatterns,
  };

  factory BannedFeature.fromJson(Map<String, dynamic> json) => BannedFeature(
    name: json['name'] as String,
    activityPattern: json['activityPattern'] as String?,
    screenTextPatterns: json['screenTextPatterns'] != null
        ? List<String>.from(json['screenTextPatterns'] as List)
        : [],
  );
}
