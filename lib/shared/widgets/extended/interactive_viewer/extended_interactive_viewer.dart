import 'package:flutter/widgets.dart' hide TransformationController;

import '/core/models/editor_configs/utils/zoom_configs.dart';
import '../interactive_viewer_scroll_physics.dart';
import 'extended_raw_interactive_viewer.dart';

/// A widget that provides interactive viewing capabilities with zoom and pan
/// functionality.
///
/// The [ExtendedInteractiveViewer] wraps a given child widget and allows users
/// to interact with it through zooming and panning.
/// ```
class ExtendedInteractiveViewer extends StatefulWidget {
  /// Creates an [ExtendedInteractiveViewer] with the given parameters.
  const ExtendedInteractiveViewer({
    super.key,
    required this.child,
    this.enableInteraction = true,
    required this.zoomConfigs,
    required this.onInteractionStart,
    required this.onInteractionUpdate,
    required this.onInteractionEnd,
    this.onMatrix4Change,
    this.initialMatrix4,
    this.startMatrix4,
    this.enableExternalGestureDetector = false,
    this.boundaryMargin = EdgeInsets.zero,
    this.contentInset = EdgeInsets.zero,
    this.minScale = 1.0,
    this.maxScale = 5.0,
  });

  /// Configuration options that control zoom behavior and limits.
  ///
  /// Provides settings such as whether zoom is enabled, min/max scale factors,
  /// double-tap zoom behavior, and boundary constraints.
  final ZoomConfigs zoomConfigs;

  /// The child widget to be displayed and interacted with.
  final Widget child;

  /// Indicates whether user interactions such as panning and zooming are
  /// enabled.
  ///
  /// Default value is `true`.
  final bool enableInteraction;

  /// Determines whether an external gesture detector should be enabled.
  ///
  /// When set to `true`, gesture detection is handled externally, allowing
  /// for custom gesture handling outside of this widget. If `false`, the
  /// widget manages its own gesture detection internally.
  final bool enableExternalGestureDetector;

  /// Called when the user ends a pan or scale gesture on the widget.
  ///
  /// At the time this is called, the [TransformationController] will have
  /// already been updated to reflect the change caused by the interaction,
  /// though a pan may cause an inertia animation after this is called as well.
  ///
  /// {@template flutter.widgets.InteractiveViewer.onInteractionEnd}
  /// Will be called even if the interaction is disabled with [panEnabled] or
  /// [scaleEnabled] for both touch gestures and mouse interactions.
  ///
  /// A [GestureDetector] wrapping the InteractiveViewer will not respond to
  /// [GestureDetector.onScaleStart], [GestureDetector.onScaleUpdate], and
  /// [GestureDetector.onScaleEnd]. Use [onInteractionStart],
  /// [onInteractionUpdate], and [onInteractionEnd] to respond to those
  /// gestures.
  /// {@endtemplate}
  ///
  /// See also:
  ///
  ///  * [onInteractionStart], which handles the start of the same interaction.
  ///  * [onInteractionUpdate], which handles an update to the same interaction.
  final GestureScaleEndCallback? onInteractionEnd;

  /// Called when the user begins a pan or scale gesture on the widget.
  ///
  /// At the time this is called, the [TransformationController] will not have
  /// changed due to this interaction.
  ///
  /// {@macro flutter.widgets.InteractiveViewer.onInteractionEnd}
  ///
  /// The coordinates provided in the details' `focalPoint` and
  /// `localFocalPoint` are normal Flutter event coordinates, not
  /// InteractiveViewer scene coordinates. See
  /// [TransformationController.toScene] for how to convert these coordinates to
  /// scene coordinates relative to the child.
  ///
  /// See also:
  ///
  ///  * [onInteractionUpdate], which handles an update to the same interaction.
  ///  * [onInteractionEnd], which handles the end of the same interaction.
  final GestureScaleStartCallback? onInteractionStart;

  /// Called when the user updates a pan or scale gesture on the widget.
  ///
  /// At the time this is called, the [TransformationController] will have
  /// already been updated to reflect the change caused by the interaction, if
  /// the interaction caused the matrix to change.
  ///
  /// {@macro flutter.widgets.InteractiveViewer.onInteractionEnd}
  ///
  /// The coordinates provided in the details' `focalPoint` and
  /// `localFocalPoint` are normal Flutter event coordinates, not
  /// InteractiveViewer scene coordinates. See
  /// [TransformationController.toScene] for how to convert these coordinates to
  /// scene coordinates relative to the child.
  ///
  /// See also:
  ///
  ///  * [onInteractionStart], which handles the start of the same interaction.
  ///  * [onInteractionEnd], which handles the end of the same interaction.
  final GestureScaleUpdateCallback? onInteractionUpdate;

  /// Called when the Matrix4 value changes.
  final Function(Matrix4 value)? onMatrix4Change;

  /// The initial Matrix4 value.
  final Matrix4? initialMatrix4;

  /// The transform the viewer starts at, when it differs from
  /// [initialMatrix4].
  ///
  /// [initialMatrix4] stays the reset target ([ExtendedInteractiveViewerState
  /// .reset] and relative zoom/pan calculations), so a viewer seeded with a
  /// carried-over zoom still resets back to its fit transform.
  final Matrix4? startMatrix4;

  /// The boundary margin for the interactive viewer.
  ///
  /// This defines the margin around the child content that determines
  /// the panning limits.
  final EdgeInsets boundaryMargin;

  /// The internal padding within the child widget where no actual
  /// content is rendered (e.g., FittedBox letterboxing).
  ///
  /// Used to tighten pan boundaries when zoomed in.
  final EdgeInsets contentInset;

  /// The minimum scale the interactive viewer can be zoomed to.
  final double minScale;

  /// The maximum scale the interactive viewer can be zoomed to.
  final double maxScale;

  @override
  State<ExtendedInteractiveViewer> createState() =>
      ExtendedInteractiveViewerState();
}

/// The state for [ExtendedInteractiveViewer], managing the interactivity state.
class ExtendedInteractiveViewerState extends State<ExtendedInteractiveViewer>
    with TickerProviderStateMixin {
  final _rawViewerKey = GlobalKey<ExtendedRawInteractiveViewerState>();
  late TransformationController _transformCtrl;
  // Allows access to the [TransformationController]
  TransformationController? get transformationController => _transformCtrl;
  late final AnimationController _animationCtrl;
  late bool _enableInteraction;

  /// A getter that indicates whether interaction is enabled for the viewer.
  bool get isInteractionEnabled => _enableInteraction;

  @override
  void initState() {
    super.initState();
    final initialTransformation = widget.startMatrix4 ?? widget.initialMatrix4;

    _transformCtrl = TransformationController(initialTransformation)
      ..addListener(() {
        widget.onMatrix4Change?.call(_transformCtrl.value);
      });
    _animationCtrl = AnimationController(
      vsync: this,
      duration: widget.zoomConfigs.doubleTapZoomDuration,
    );
    _enableInteraction = widget.enableInteraction;
  }

  @override
  void didUpdateWidget(covariant ExtendedInteractiveViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The base fit ([initialMatrix4]) can change while the viewer stays mounted
    // — e.g. when the crop/aspect ratio changes and the sub-editor is rebuilt
    // with a new fit. Adopt the new fit, but only when the viewer is still
    // sitting at the previous fit (the user hasn't zoomed/panned away and no
    // shared-zoom start matrix is active); otherwise their zoom is preserved.
    //
    // Uses an element-wise tolerance instead of `==` because Matrix4 equality
    // is unreliable here (identity vs value, float drift from recomputing the
    // fit each build).
    final Matrix4? oldInitial = oldWidget.initialMatrix4;
    final Matrix4? newInitial = widget.initialMatrix4;
    if (newInitial != null &&
        oldInitial != null &&
        !_matricesClose(newInitial, oldInitial) &&
        _matricesClose(_transformCtrl.value, oldInitial)) {
      _transformCtrl.value = newInitial;
    }
  }

  /// Whether two 4x4 matrices are equal within a small tolerance.
  bool _matricesClose(Matrix4 a, Matrix4 b, [double eps = 1e-4]) {
    for (int i = 0; i < 16; i++) {
      if ((a.storage[i] - b.storage[i]).abs() > eps) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _transformCtrl.dispose();
    _animationCtrl.dispose();
    super.dispose();
  }

  /// Gets the current transform matrix.
  Matrix4 get transformMatrix4 => _transformCtrl.value;

  /// The initial (fit / default) transform the viewer starts at and resets to.
  /// Used to compute the user's zoom/pan *relative* to the default view.
  Matrix4 get initialMatrix4 => widget.initialMatrix4 ?? Matrix4.identity();

  /// Sets the transform matrix.
  set transformMatrix4(Matrix4 value) => _transformCtrl.value = value;

  /// Sets the interaction state to the given value and updates the UI
  /// accordingly.
  void setEnableInteraction(bool value) {
    if (_enableInteraction != value) {
      _enableInteraction = value;
      // When interaction is handed off (e.g. a layer is grabbed) mid-bounce,
      // finish settling the pan to bounds so the image isn't left stuck at an
      // out-of-bounds position until the next viewer gesture.
      if (!value) {
        _rawViewerKey.currentState?.settleToBounds();
      }
      setState(() {});
    }
  }

  /// Animates the pan back within bounds, cancelling any in-flight inertia.
  void settleToBounds() {
    _rawViewerKey.currentState?.settleToBounds();
  }

  /// Reset the transformations to the initial state.
  void reset() {
    _transformCtrl.value = widget.initialMatrix4 ?? Matrix4.identity();
  }

  /// Instantly sets the zoom transformation to a specific [offset] and [scale].
  ///
  /// If [offset] is null, [Offset.zero] is used. If [scale] is null, 1.0 is
  /// used.
  /// This method bypasses animation and immediately updates the view.
  void zoomTo({Offset? offset, double? scale}) {
    final effectiveOffset = offset ?? Offset.zero;
    final effectiveScale = scale ?? 1.0;

    _transformCtrl.value = Matrix4.identity()
      ..translateByDouble(effectiveOffset.dx, effectiveOffset.dy, 0.0, 1.0)
      ..scaleByDouble(effectiveScale, effectiveScale, effectiveScale, 1.0);
  }

  /// Animates zooming to a specific [offset] and [scale] over [duration].
  ///
  /// The transition uses the provided [curve] to control easing. If [offset]
  /// or [scale] is null, they default to [Offset.zero] and 1.0 respectively.
  Future<void> animateZoomToPoint({
    Offset? offset,
    double? scale,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
  }) async {
    if (_animationCtrl.isAnimating) return;
    final effectiveOffset = offset ?? Offset.zero;
    final effectiveScale = scale ?? 1.0;

    final targetMatrix = Matrix4.identity()
      ..translateByDouble(effectiveOffset.dx, effectiveOffset.dy, 0.0, 1.0)
      ..scaleByDouble(effectiveScale, effectiveScale, effectiveScale, 1.0);

    final tween = Matrix4Tween(
      begin: _transformCtrl.value,
      end: targetMatrix,
    );

    _animationCtrl
      ..duration = duration
      ..reset();

    final animation = tween.animate(CurvedAnimation(
      parent: _animationCtrl,
      curve: curve,
    ));

    void listener() {
      _transformCtrl.value = animation.value;
    }

    _animationCtrl.addListener(listener);
    await _animationCtrl.forward();
    _animationCtrl.removeListener(listener);
  }

  /// Quickly toggles zoom in or out based on the current [scaleFactor].
  ///
  /// If the view is currently zoomed in (scale > 1), this will reset to the
  /// default scale and position. Otherwise, it will zoom in to [scale] centered
  /// around the given [offset]. Uses animation with optional [duration] and
  /// [curve].
  Future<void> quickZoomTo(
    Offset offset,
    double scale, {
    Duration? duration,
    Curve? curve,
  }) async {
    if (!_enableInteraction) return;
    if (scaleFactor > 1) {
      await animateZoomToPoint(offset: Offset.zero, scale: 1);
    } else {
      await animateZoomToPoint(offset: -offset, scale: scale);
    }
  }

  /// The factor by which the current transformation is scaled.
  /// Returns the maximum scale factor applied on any axis.
  double get scaleFactor {
    return _transformCtrl.value.getMaxScaleOnAxis();
  }

  /// The current translation offset applied to the transformation.
  /// Returns an [Offset] representing the translation values on the x and y
  /// axes.
  Offset get offset {
    final vector3 = _transformCtrl.value.getTranslation();

    return Offset(vector3.x, vector3.y);
  }

  bool _helperScaledStarted = false;

  /// Handles the start of a scaling gesture by forwarding the [details]
  /// to the underlying raw viewer's `onScaleStart` method.
  void onScaleStart(ScaleStartDetails details) {
    _helperScaledStarted = true;
    if (!widget.zoomConfigs.enableZoom) return;
    _rawViewerKey.currentState?.onScaleStart(details);
  }

  /// Handles the scale update gesture by forwarding the [details] to the
  /// underlying interactive viewer's state. This allows for updating the
  /// scale (zoom) and position of the content in response to user gestures
  /// such as pinch-to-zoom or drag.
  ///
  /// [details] contains information about the current state of the scale
  /// gesture.
  void onScaleUpdate(ScaleUpdateDetails details) {
    if (!widget.zoomConfigs.enableZoom) return;
    _rawViewerKey.currentState?.onScaleUpdate(details);
  }

  /// Handles the end of a scaling gesture by forwarding the [details]
  /// to the underlying raw viewer's `onScaleEnd` method.
  ///
  /// This method is typically called when the user completes a pinch or zoom
  /// gesture, allowing the widget to perform any necessary cleanup or state
  /// updates related to the gesture.
  ///
  /// [details] contains information about the velocity and focal point of the
  /// gesture.
  void onScaleEnd(ScaleEndDetails details) {
    if (!_helperScaledStarted || !widget.zoomConfigs.enableZoom) return;
    _helperScaledStarted = false;
    _rawViewerKey.currentState?.onScaleEnd(details);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.zoomConfigs.enableZoom) return widget.child;

    return InteractiveViewerScrollPhysics(
      boundaryMargin: widget.boundaryMargin,
      contentInset: widget.contentInset,
      transformationController: _transformCtrl,
      panEnabled: _enableInteraction,
      scaleEnabled: _enableInteraction,
      minScale: widget.minScale,
      maxScale: widget.maxScale,
      onInteractionStart: widget.onInteractionStart,
      onInteractionUpdate: widget.onInteractionUpdate,
      onInteractionEnd: widget.onInteractionEnd,
      // enableExternalGestureDetector: widget.enableExternalGestureDetector,
      // invertTrackpadDirection: widget.zoomConfigs.invertTrackpadDirection,
      scrollPhysics: const BouncingScrollPhysics(),
      child: widget.child,
    );
  }
}
