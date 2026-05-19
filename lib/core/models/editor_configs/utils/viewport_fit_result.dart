import 'package:flutter/widgets.dart';

/// Result returned by a [ViewportFitBuilder] callback.
///
/// Contains the viewport-fit values that an editor uses to position and
/// scale its content according to the current effective aspect ratio.
@immutable
class ViewportFitResult {
  /// Creates a [ViewportFitResult] with the given viewport-fit values.
  const ViewportFitResult({
    this.boundaryMargin = EdgeInsets.zero,
    this.editorMinScale = 1.0,
    this.editorMaxScale = 5.0,
    this.initialTransform,
    this.viewPadding,
    this.contentInset = EdgeInsets.zero,
  });

  /// A margin for the visible boundaries of the child.
  ///
  /// Any transformation that results in the viewport being able to view
  /// outside of the boundaries will be stopped at the boundary.
  /// The boundaries do not rotate with the rest of the scene, so they are
  /// always aligned with the viewport.
  ///
  /// To produce no boundaries at all, pass infinite [EdgeInsets], such as
  /// `EdgeInsets.all(double.infinity)`.
  ///
  /// Defaults to [EdgeInsets.zero].
  final EdgeInsets boundaryMargin;

  /// The minimum scale factor for the editor.
  ///
  /// Defaults to 1.0.
  final double editorMinScale;

  /// The maximum scale factor for the editor.
  ///
  /// Defaults to 5.0.
  final double editorMaxScale;

  /// The initial transformation matrix applied to the viewport.
  ///
  /// If null, the underlying viewer will fall back to its default
  /// auto-centering behavior.
  final Matrix4? initialTransform;

  /// Defines the padding for the view outside the image boundaries.
  ///
  /// Only used by the crop/rotate editor.
  final EdgeInsets? viewPadding;

  /// The internal padding within the child widget where no actual
  /// content is rendered (e.g., FittedBox letterboxing).
  ///
  /// This is used to tighten pan boundaries when zoomed in, preventing
  /// the visible image from being panned beyond its minScale position.
  /// The insets describe how much empty space exists on each side of the
  /// actual content within the child widget (in child coordinates).
  ///
  /// Defaults to [EdgeInsets.zero] (no letterboxing).
  final EdgeInsets contentInset;

  /// Computes the [contentInset] for a `FittedBox(fit: BoxFit.contain)`
  /// layout given the effective content [aspectRatio] and the
  /// [viewportSize] (which equals the child widget size when
  /// `constrained: true`).
  ///
  /// When the content aspect ratio differs from the viewport aspect
  /// ratio, `FittedBox.contain` creates letterbox padding. This method
  /// calculates that padding so the pan-boundary logic can correctly
  /// clamp the image.
  ///
  /// Returns [EdgeInsets.zero] if [aspectRatio] is `null`, zero,
  /// infinite, or NaN.
  static EdgeInsets computeContentInset({
    required double? aspectRatio,
    required Size viewportSize,
  }) {
    if (aspectRatio == null ||
        aspectRatio <= 0 ||
        aspectRatio.isNaN ||
        aspectRatio.isInfinite ||
        viewportSize.isEmpty) {
      return EdgeInsets.zero;
    }

    final double viewportAR = viewportSize.aspectRatio;

    if (aspectRatio >= viewportAR) {
      // Content is wider than (or equal to) viewport → fills width,
      // letterbox top/bottom.
      final double imageHeight = viewportSize.width / aspectRatio;
      final double verticalInset = (viewportSize.height - imageHeight) / 2;
      return EdgeInsets.symmetric(vertical: verticalInset);
    } else {
      // Content is taller than viewport → fills height,
      // letterbox left/right.
      final double imageWidth = viewportSize.height * aspectRatio;
      final double horizontalInset = (viewportSize.width - imageWidth) / 2;
      return EdgeInsets.symmetric(horizontal: horizontalInset);
    }
  }
}

/// Signature for the viewport fit builder callback.
///
/// Called by an editor with the current effective [aspectRatio].
/// The [aspectRatio] is `null` when the editor does not yet know the
/// aspect ratio (e.g. during `initState` before the image is decoded).
///
/// Return a [ViewportFitResult] with the appropriate viewport-fit values
/// for the given aspect ratio.
typedef ViewportFitBuilder = ViewportFitResult Function(double? aspectRatio);
