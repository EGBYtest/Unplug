class BannedFeature {
  String name;
  String? activityPattern;

  BannedFeature({required this.name, this.activityPattern});

  Map<String, dynamic> toJson() => {
    'name': name,
    if (activityPattern != null && activityPattern!.isNotEmpty)
      'activityPattern': activityPattern,
  };

  factory BannedFeature.fromJson(Map<String, dynamic> json) => BannedFeature(
    name: json['name'] as String,
    activityPattern: json['activityPattern'] as String?,
  );
}
