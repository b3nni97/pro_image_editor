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
