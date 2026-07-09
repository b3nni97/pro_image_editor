import '../styles/helper_line_style.dart';

export '../styles/helper_line_style.dart';

/// The `HelperLineConfigs` class defines the settings for displaying helper
/// lines in the image editor.
/// Helper lines are used to guide users in positioning and rotating layers.
class HelperLineConfigs {
  /// Creates an instance of the `HelperLines` class with the specified
  /// settings.
  const HelperLineConfigs({
    this.showVerticalLine = true,
    this.showHorizontalLine = true,
    this.showRotateLine = true,
    this.showLayerAlignLine = true,
    this.isDisabledAtZoom = false,
    this.releaseThreshold = 10.0,
    this.rotateLineMinIntentDeg = 5.0,
    this.rotateBreakFreeDeg = 10.0,
    this.fastDragSnapSkipThreshold = 1.0,
    this.rotateSnapSkipSpeedDeg = 60.0,
    this.liftJitterTolerance = 10.0,
    this.snapReleaseTolerance = 20.0,
    this.style = const HelperLineStyle(),
  });

  /// Specifies whether to show the vertical helper line.
  final bool showVerticalLine;

  /// Specifies whether to show the horizontal helper line.
  final bool showHorizontalLine;

  /// Specifies whether to show the rotate helper line.
  final bool showRotateLine;

  /// Specifies whether to show the layer align helper line.
  final bool showLayerAlignLine;

  /// Determines whether the helper lines are disabled when the editor is
  /// zoomed in.
  ///
  /// If set to `true`, helper lines will not be displayed when the zoom level
  /// is increased.
  /// If set to `false`, helper lines will remain visible regardless of the
  /// zoom level.
  final bool isDisabledAtZoom;

  /// Style configuration for helper lines.
  final HelperLineStyle style;

  /// The minimum distance in logical pixels that a draggable element must be
  /// released from a helper line for the snapping effect to be deactivated.
  final double releaseThreshold;

  /// The minimum rotation (in degrees) the user must apply within the current
  /// gesture before the rotation guide *line* is shown.
  ///
  /// This only gates the visual line — the rotation snap itself always
  /// engages. It prevents the line from flashing during a pure scaling
  /// gesture (where tiny incidental rotations would otherwise reveal it),
  /// while the object still snaps cleanly to 45° multiples. Set to `0` to
  /// show the line on any rotation.
  final double rotateLineMinIntentDeg;

  /// How far (in degrees) the user must rotate away from a locked snap angle
  /// before the rotation "breaks free" of it.
  ///
  /// A larger value makes the snap stickier: incidental rotation while moving a
  /// layer with two fingers won't unlock (and re-lock) the guide — which would
  /// otherwise re-fire the snap haptic. The default of `10.0` matches the
  /// classic behaviour; raise it (e.g. `20`) if moving a layer keeps
  /// triggering the rotation snap.
  final double rotateBreakFreeDeg;

  /// The smoothed drag speed (in content pixels per frame) above which the
  /// horizontal/vertical position snap is skipped while dragging a layer.
  ///
  /// When the user drags faster than this, the center snap and its helper
  /// lines are suppressed so quick movements aren't interrupted by snapping.
  /// Lower values make snapping give up more eagerly on fast drags; higher
  /// values keep snapping active even during faster drags. Set to
  /// [double.infinity] to never skip the snap based on speed.
  final double fastDragSnapSkipThreshold;

  /// The smoothed rotation speed (in degrees per second) above which the
  /// angle snap (45° multiples) is skipped while rotating a layer.
  ///
  /// When the user rotates faster than this, the layer won't lock onto the
  /// nearest snap angle, so fast spins stay smooth. Lower values make the
  /// snap give up more eagerly on fast rotation; higher values keep it
  /// engaging even during faster rotation. Set to [double.infinity] to never
  /// skip the snap based on speed.
  final double rotateSnapSkipSpeedDeg;

  /// The maximum per-frame movement (in logical pixels) that is treated as
  /// finger-settling and deferred by one frame while dragging slowly, so the
  /// involuntary movement of the final frame before the finger lifts can be
  /// discarded rather than shifting the layer.
  ///
  /// This makes a release look "stable": a slow drag near its end doesn't get
  /// nudged a few pixels as the finger leaves, and — unlike a snap-back — the
  /// stray movement is never rendered in the first place. Only small, slow
  /// movements are deferred, so a deliberate (fast) drag is never affected. The
  /// default of `10.0` roughly matches the ~10pt allowable-movement tolerance
  /// iOS uses for its gesture recognizers. Set to `0` to disable it.
  ///
  /// See [snapReleaseTolerance] for the larger tolerance used to pull a layer
  /// back onto an active snap line.
  final double liftJitterTolerance;

  /// The maximum distance (in logical pixels) a layer may drift off an active
  /// snap line at the moment the finger lifts and still be pulled back exactly
  /// onto the line.
  ///
  /// This is deliberately larger than [liftJitterTolerance]: when a layer was
  /// snapped the user clearly intended it on the line, so the pull-back is more
  /// forgiving. If the layer is farther than this from the snap line (i.e. the
  /// user genuinely dragged away), it is left where it is.
  ///
  /// Applies to both the center guides and the layer-alignment guides. Set to
  /// `0` to disable the release re-snap.
  final double snapReleaseTolerance;

  /// Creates a copy of this `HelperLineConfigs` object with the given fields
  /// replaced with new values.
  ///
  /// The [copyWith] method allows you to create a new instance of
  /// [HelperLineConfigs] with some properties updated while keeping the
  /// others unchanged.
  HelperLineConfigs copyWith({
    bool? showVerticalLine,
    bool? showHorizontalLine,
    bool? showRotateLine,
    bool? showLayerAlignLine,
    bool? isDisabledAtZoom,
    double? releaseThreshold,
    double? rotateLineMinIntentDeg,
    double? rotateBreakFreeDeg,
    double? fastDragSnapSkipThreshold,
    double? rotateSnapSkipSpeedDeg,
    double? liftJitterTolerance,
    double? snapReleaseTolerance,
    HelperLineStyle? style,
  }) {
    return HelperLineConfigs(
      showVerticalLine: showVerticalLine ?? this.showVerticalLine,
      showHorizontalLine: showHorizontalLine ?? this.showHorizontalLine,
      showRotateLine: showRotateLine ?? this.showRotateLine,
      showLayerAlignLine: showLayerAlignLine ?? this.showLayerAlignLine,
      isDisabledAtZoom: isDisabledAtZoom ?? this.isDisabledAtZoom,
      releaseThreshold: releaseThreshold ?? this.releaseThreshold,
      rotateLineMinIntentDeg:
          rotateLineMinIntentDeg ?? this.rotateLineMinIntentDeg,
      rotateBreakFreeDeg: rotateBreakFreeDeg ?? this.rotateBreakFreeDeg,
      fastDragSnapSkipThreshold:
          fastDragSnapSkipThreshold ?? this.fastDragSnapSkipThreshold,
      rotateSnapSkipSpeedDeg:
          rotateSnapSkipSpeedDeg ?? this.rotateSnapSkipSpeedDeg,
      liftJitterTolerance: liftJitterTolerance ?? this.liftJitterTolerance,
      snapReleaseTolerance: snapReleaseTolerance ?? this.snapReleaseTolerance,
      style: style ?? this.style,
    );
  }
}
