// Flutter imports:
import 'package:flutter/widgets.dart';

/// How a helper line is drawn.
enum HelperLineType {
  /// A continuous, solid line.
  solid,

  /// A dashed line.
  dashed,
}

/// The `HelperLineStyle` class defines the style for helper lines in the image
/// editor.
/// Helper lines are used to assist with alignment and positioning of elements
/// in the editor.
///
/// Usage:
///
/// ```dart
/// HelperLineStyle HelperLineStyle = HelperLineStyle(
///   horizontalColor: Colors.blue,
///   verticalColor: Colors.red,
///   rotateColor: Colors.pink,
/// );
/// ```
///
/// Properties:
///
/// - `horizontalColor`: Color of horizontal helper lines.
///
/// - `verticalColor`: Color of vertical helper lines.
///
/// - `rotateColor`: Color of rotation helper lines.
///
/// Example Usage:
///
/// ```dart
/// HelperLineStyle HelperLineStyle = HelperLineStyle(
///   horizontalColor: Colors.blue,
///   verticalColor: Colors.red,
///   rotateColor: Colors.pink,
/// );
///
/// Color horizontalColor = HelperLineStyle.horizontalColor;
/// Color verticalColor = HelperLineStyle.verticalColor;
/// // Access other style properties...
/// ```
class HelperLineStyle {
  /// Creates an instance of the `HelperLineStyle` class with the specified
  /// style properties.
  const HelperLineStyle({
    this.horizontalColor = const Color(0xFF1565C0),
    this.verticalColor = const Color(0xFF1565C0),
    this.rotateColor = const Color(0xFFE91E63),
    this.layerAlignColor = const Color(0xFF7C4DFF),
    this.strokeWidth = 1.25,
    this.horizontalStrokeWidth,
    this.verticalStrokeWidth,
    this.rotateStrokeWidth,
    this.layerAlignStrokeWidth,
    this.horizontalLineType = HelperLineType.solid,
    this.verticalLineType = HelperLineType.solid,
    this.rotateLineType = HelperLineType.solid,
    this.layerAlignLineType = HelperLineType.solid,
  });

  /// Color of horizontal helper lines.
  final Color horizontalColor;

  /// Color of vertical helper lines.
  final Color verticalColor;

  /// Color of rotation helper lines.
  final Color rotateColor;

  /// Color of layer align helper lines.
  final Color layerAlignColor;

  /// Stroke width of all helper lines, unless overridden per line below.
  final double strokeWidth;

  /// Stroke width of the horizontal helper line. Falls back to [strokeWidth]
  /// when `null`.
  final double? horizontalStrokeWidth;

  /// Stroke width of the vertical helper line. Falls back to [strokeWidth].
  final double? verticalStrokeWidth;

  /// Stroke width of the rotation helper line. Falls back to [strokeWidth].
  final double? rotateStrokeWidth;

  /// Stroke width of the layer-alignment helper lines. Falls back to
  /// [strokeWidth].
  final double? layerAlignStrokeWidth;

  /// Whether the horizontal helper line is drawn [HelperLineType.solid] or
  /// [HelperLineType.dashed].
  final HelperLineType horizontalLineType;

  /// Whether the vertical helper line is solid or dashed.
  final HelperLineType verticalLineType;

  /// Whether the rotation helper line is solid or dashed.
  final HelperLineType rotateLineType;

  /// Whether the layer-alignment helper lines are solid or dashed.
  final HelperLineType layerAlignLineType;

  /// Creates a copy of this `HelperLineStyle` object with the given fields
  /// replaced with new values.
  ///
  /// The [copyWith] method allows you to create a new instance of
  /// [HelperLineStyle] with some properties updated while keeping the
  /// others unchanged.
  HelperLineStyle copyWith({
    Color? horizontalColor,
    Color? verticalColor,
    Color? rotateColor,
    Color? layerAlignColor,
    double? strokeWidth,
    double? horizontalStrokeWidth,
    double? verticalStrokeWidth,
    double? rotateStrokeWidth,
    double? layerAlignStrokeWidth,
    HelperLineType? horizontalLineType,
    HelperLineType? verticalLineType,
    HelperLineType? rotateLineType,
    HelperLineType? layerAlignLineType,
  }) {
    return HelperLineStyle(
      horizontalColor: horizontalColor ?? this.horizontalColor,
      verticalColor: verticalColor ?? this.verticalColor,
      rotateColor: rotateColor ?? this.rotateColor,
      layerAlignColor: layerAlignColor ?? this.layerAlignColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      horizontalStrokeWidth:
          horizontalStrokeWidth ?? this.horizontalStrokeWidth,
      verticalStrokeWidth: verticalStrokeWidth ?? this.verticalStrokeWidth,
      rotateStrokeWidth: rotateStrokeWidth ?? this.rotateStrokeWidth,
      layerAlignStrokeWidth:
          layerAlignStrokeWidth ?? this.layerAlignStrokeWidth,
      horizontalLineType: horizontalLineType ?? this.horizontalLineType,
      verticalLineType: verticalLineType ?? this.verticalLineType,
      rotateLineType: rotateLineType ?? this.rotateLineType,
      layerAlignLineType: layerAlignLineType ?? this.layerAlignLineType,
    );
  }
}
