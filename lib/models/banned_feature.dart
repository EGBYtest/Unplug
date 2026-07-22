class BannedFeature {
  String name;
  List<String> resourceIdPatterns;
  List<String> descriptionPatterns;
  List<String> screenTextPatterns;

  BannedFeature({
    required this.name,
    List<String>? resourceIdPatterns,
    List<String>? descriptionPatterns,
    List<String>? screenTextPatterns,
  })  : resourceIdPatterns = resourceIdPatterns ?? [],
        descriptionPatterns = descriptionPatterns ?? [],
        screenTextPatterns = screenTextPatterns ?? [];

  Map<String, dynamic> toJson() => {
    'name': name,
    if (resourceIdPatterns.isNotEmpty)
      'resourceIdPatterns': resourceIdPatterns,
    if (descriptionPatterns.isNotEmpty)
      'descriptionPatterns': descriptionPatterns,
    if (screenTextPatterns.isNotEmpty)
      'screenTextPatterns': screenTextPatterns,
  };

  factory BannedFeature.fromJson(Map<String, dynamic> json) => BannedFeature(
    name: json['name'] as String,
    resourceIdPatterns: json['resourceIdPatterns'] != null
        ? List<String>.from(json['resourceIdPatterns'] as List)
        : null,
    descriptionPatterns: json['descriptionPatterns'] != null
        ? List<String>.from(json['descriptionPatterns'] as List)
        : null,
    screenTextPatterns: json['screenTextPatterns'] != null
        ? List<String>.from(json['screenTextPatterns'] as List)
        : null,
  );
}
