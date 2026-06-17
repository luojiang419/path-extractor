class UpdateManifest {
  const UpdateManifest({
    required this.version,
    required this.build,
    required this.publishedAt,
    required this.notes,
    required this.installerName,
    required this.installerUrl,
    required this.installerSha256,
    required this.minimumSupportedVersion,
  });

  factory UpdateManifest.fromJson(Map<String, dynamic> json) {
    return UpdateManifest(
      version: json['version'] as String? ?? '',
      build: _parseBuild(json['build']),
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
      notes: _parseNotes(json['notes']),
      installerName: json['installer_name'] as String? ?? '',
      installerUrl: json['installer_url'] as String? ?? '',
      installerSha256: json['installer_sha256'] as String? ?? '',
      minimumSupportedVersion:
          json['minimum_supported_version'] as String? ?? '',
    );
  }

  final String version;
  final int build;
  final DateTime? publishedAt;
  final String notes;
  final String installerName;
  final String installerUrl;
  final String installerSha256;
  final String minimumSupportedVersion;

  static int _parseBuild(Object? rawValue) {
    if (rawValue is int) return rawValue;
    if (rawValue is String) return int.tryParse(rawValue) ?? 0;
    return 0;
  }

  static String _parseNotes(Object? rawValue) {
    if (rawValue is String) return rawValue;
    if (rawValue is List) {
      return rawValue
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .join('\n');
    }
    return rawValue?.toString() ?? '';
  }
}
