class ThumbnailViewSettings {
  static const double defaultGridSize = 120;
  static const double minGridSize = 96;
  static const double maxGridSize = 220;
  static const double sliderStep = 4;
  static const double wheelStep = 12;
  static const double tileAspectRatio = 0.85;
  static const double tileSpacing = 8;

  const ThumbnailViewSettings({required this.gridSize});

  factory ThumbnailViewSettings.initial() =>
      const ThumbnailViewSettings(gridSize: defaultGridSize);

  factory ThumbnailViewSettings.fromJson(Map<String, dynamic> json) {
    final rawGridSize = json['gridSize'];
    final gridSize = rawGridSize is num
        ? rawGridSize.toDouble()
        : defaultGridSize;
    return ThumbnailViewSettings(gridSize: clampGridSize(gridSize));
  }

  final double gridSize;

  double get tileWidth => gridSize;

  double get tileHeight => gridSize / tileAspectRatio;

  bool get isDefault => gridSize == defaultGridSize;

  Map<String, dynamic> toJson() => {'gridSize': gridSize};

  ThumbnailViewSettings copyWith({double? gridSize}) {
    return ThumbnailViewSettings(
      gridSize: clampGridSize(gridSize ?? this.gridSize),
    );
  }

  static double clampGridSize(double value) {
    return value.clamp(minGridSize, maxGridSize).toDouble();
  }
}
