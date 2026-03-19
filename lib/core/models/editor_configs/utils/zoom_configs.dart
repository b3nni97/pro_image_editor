import 'package:flutter/widgets.dart';

import 'viewport_fit_result.dart';

export 'viewport_fit_result.dart';

/// Configuration interface for zoom behavior in an editor or viewer.
///
/// Provides control over zoom enablement, double-tap behavior,
/// and a [viewportFitBuilder] callback that dynamically computes
/// boundary margin, scale limits, and initial transform based on
/// the current effective aspect ratio.
abstract class ZoomConfigs {
  /// Creates a set of zoom configuration options.
  const ZoomConfigs({
    this.enableZoom = false,
    this.enableDoubleTapZoom = true,
    this.doubleTapZoomFactor = 2,
    this.doubleTapZoomDuration = const Duration(milliseconds: 180),
    this.doubleTapZoomCurve = Curves.easeInOut,
    this.invertTrackpadDirection = false,
    this.viewportFitBuilder,
  });

  /// {@template enableZoom}
  /// Indicates whether the editor supports zoom functionality.
  ///
  /// When set to `true`, the editor allows users to zoom in and out, providing
  /// enhanced accessibility and usability, especially on smaller screens or for
  /// users with visual impairments. If set to `false`, the zoom functionality
  /// is disabled, and the editor's content remains at a fixed scale.
  ///
  /// Default value is `false`.
  /// {@endtemplate}
  final bool enableZoom;

  /// Whether double-tap to zoom is enabled.
  ///
  /// If `true`, users can double-tap to zoom in or out based on the current
  /// zoom level. If `false`, double-tap gestures are ignored.
  final bool enableDoubleTapZoom;

  /// The zoom scale factor applied on double-tap.
  ///
  /// This determines how much to zoom in or out when the user double-taps.
  /// For example, a value of 2.0 doubles the current scale.
  final double doubleTapZoomFactor;

  /// The duration of the zoom animation on double-tap.
  ///
  /// Controls how long the zoom animation takes to complete when a
  /// double-tap gesture is detected.
  final Duration doubleTapZoomDuration;

  /// The animation curve used for double-tap zooming.
  ///
  /// Defines the easing curve of the zoom animation triggered by
  /// double-tapping.
  final Curve doubleTapZoomCurve;

  /// Determines if the trackpad scroll direction should be inverted for
  /// panning gestures.
  ///
  /// When set to `true`, trackpad panning will use natural scrolling
  /// (pan left moves content left, pan up moves content up).
  /// When set to `false`, trackpad panning will use traditional scrolling
  /// (pan left moves content right, pan up moves content down).
  ///
  /// This setting only affects trackpad panning on desktop platforms and
  /// has no effect on touch gestures, mouse wheel, or other input methods.
  ///
  /// Defaults to `false` (traditional scrolling behavior).
  final bool invertTrackpadDirection;

  /// A callback that dynamically computes viewport-fit values (boundary
  /// margin, scale limits, initial transform) based on the current
  /// effective aspect ratio.
  ///
  /// The [aspectRatio] parameter will be `null` when the editor does not
  /// yet know the aspect ratio (e.g. during `initState` before the image
  /// is decoded). When it becomes available, the editor will call this
  /// callback again.
  ///
  /// If this is `null`, the editor uses default values from
  /// [ViewportFitResult()].
  final ViewportFitBuilder? viewportFitBuilder;
}
