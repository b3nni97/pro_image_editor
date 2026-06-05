/// Enumeration for controlling the background color mode of the text layer.
enum LayerBackgroundMode {
  /// Display only the background without affecting the text color.
  background,

  /// Display the background and change the text color.
  backgroundAndColor,

  /// Display the background and change the text color with added opacity.
  backgroundAndColorWithOpacity,

  /// Change only the text color without displaying the background.
  onlyColor,

  /// Use a harmonized background color derived from the primary (text) color.
  ///
  /// The background is computed via [ColorScheme.fromSeed] to create a
  /// visually pleasing contrast that isn't just black or white.
  harmonized,
}
