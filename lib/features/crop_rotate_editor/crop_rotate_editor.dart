// ignore_for_file: deprecated_member_use_from_same_package
// TODO: Remove the deprecated values when releasing version 12.0.0.
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' as vector_math;

import '../../shared/widgets/extended/interactive_viewer_scroll_physics.dart';
import '/core/mixins/converted_callbacks.dart';
import '/core/mixins/converted_configs.dart';
import '/core/mixins/standalone_editor.dart';
import '/core/models/transform_helper.dart';
import '/core/platform/io/io_helper.dart';
import '/features/crop_rotate_editor/widgets/crop_editor_appbar.dart';
import '/features/crop_rotate_editor/widgets/crop_editor_bottombar.dart';
import '/features/crop_rotate_editor/widgets/outside_gestures/crop_rotate_gesture_detector.dart';
import '/features/crop_rotate_editor/widgets/outside_gestures/outside_gesture_listener.dart';
import '/plugins/defer_pointer/defer_pointer.dart';
import '/pro_image_editor.dart';
import '/shared/extensions/double_extension.dart';
import '/shared/mixins/extended_loop.dart';
import '/shared/services/content_recorder/widgets/record_invisible_widget.dart';
import '/shared/services/layer_transform_generator.dart';
import '/shared/utils/file_constructor_utils.dart';
import '/shared/utils/transparent_image_generator_utils.dart';
import '/shared/widgets/extended/extended_custom_paint.dart';
import '/shared/widgets/extended/extended_transform_scale.dart';
import '/shared/widgets/extended/extended_transform_translate.dart';
import '/shared/widgets/extended/mouse_region/extended_rebuild_mouse_region.dart';
import '/shared/widgets/layer/layer_stack.dart';
import '/shared/widgets/screen_resize_detector.dart';
import '/shared/widgets/transform/transformed_content_generator.dart';
import 'enums/crop_area_part.dart';
import 'enums/crop_rotate_angle_side.dart';
import 'mixins/crop_area_history.dart';
import 'services/crop_desktop_interaction_manager.dart';
import 'utils/crop_aspect_ratios.dart';
import 'utils/croppy/fit_polygon_in_quad.dart';
import 'utils/croppy/geometry.dart';
import 'utils/rotate_angle.dart';
import 'widgets/crop_corner_painter.dart';
import 'widgets/outside_gestures/outside_gesture_behavior.dart';

export 'enums/crop_mode.enum.dart';
export 'widgets/crop_aspect_ratio_options.dart';

/// Differentiates between panning and scaling gestures at the end of an interaction.
///
/// Used to explicitly determine the correct physics simulation to apply when a user
/// releases their touch.
enum _GestureType {
  /// Indicates a translation (panning) gesture.
  pan,

  /// Indicates a zoom or rotation (scaling) gesture.
  scale,
}

/// Allows users to edit images with crop, flip, and rotate tools.
///
/// Provides multiple factory constructors for handling different image sources
/// like memory, file, asset, network, or a video controller.
class CropRotateEditor extends StatefulWidget
    with StandaloneEditor<CropRotateEditorInitConfigs> {
  /// Constructs a [CropRotateEditor] widget.
  ///
  /// Enforces that either an [editorImage] or a [videoController] is provided.
  const CropRotateEditor._({
    super.key,
    required this.initConfigs,
    this.editorImage,
    this.videoController,
  }) : assert(
          editorImage != null || videoController != null,
          'Either editorImage or videoController must be provided.',
        );

  /// Constructs a [CropRotateEditor] widget with image data loaded from memory.
  ///
  /// Required for direct byte array manipulation.
  factory CropRotateEditor.memory(
    Uint8List byteArray, {
    Key? key,
    required CropRotateEditorInitConfigs initConfigs,
  }) {
    return CropRotateEditor._(
      key: key,
      editorImage: EditorImage(byteArray: byteArray),
      initConfigs: initConfigs,
    );
  }

  /// Constructs a [CropRotateEditor] widget with an image loaded from a file.
  ///
  /// Accepts a dynamic file instance to support cross-platform implementations.
  factory CropRotateEditor.file(
    dynamic file, {
    Key? key,
    required CropRotateEditorInitConfigs initConfigs,
  }) {
    return CropRotateEditor._(
      key: key,
      editorImage: EditorImage(file: ensureFileInstance(file)),
      initConfigs: initConfigs,
    );
  }

  /// Constructs a [CropRotateEditor] widget with an image loaded from an asset.
  ///
  /// Requires the asset path string defined in the pubspec.
  factory CropRotateEditor.asset(
    String assetPath, {
    Key? key,
    required CropRotateEditorInitConfigs initConfigs,
  }) {
    return CropRotateEditor._(
      key: key,
      editorImage: EditorImage(assetPath: assetPath),
      initConfigs: initConfigs,
    );
  }

  /// Constructs a [CropRotateEditor] widget with an image loaded from a network URL.
  ///
  /// Uses standard network request resolution.
  factory CropRotateEditor.network(
    String networkUrl, {
    Key? key,
    required CropRotateEditorInitConfigs initConfigs,
  }) {
    return CropRotateEditor._(
      key: key,
      editorImage: EditorImage(networkUrl: networkUrl),
      initConfigs: initConfigs,
    );
  }

  /// Constructs a [CropRotateEditor] widget with an image loaded automatically
  /// based on the provided source.
  ///
  /// Dynamically resolves the source to simplify initialization for varying inputs.
  factory CropRotateEditor.autoSource({
    Key? key,
    Uint8List? byteArray,
    dynamic file,
    String? assetPath,
    String? networkUrl,
    EditorImage? editorImage,
    ProVideoController? videoController,
    required CropRotateEditorInitConfigs initConfigs,
  }) {
    return CropRotateEditor._(
      key: key,
      editorImage: videoController != null
          ? null
          : editorImage ??
              EditorImage(
                byteArray: byteArray,
                file: file,
                networkUrl: networkUrl,
                assetPath: assetPath,
              ),
      videoController: videoController,
      initConfigs: initConfigs,
    );
  }

  /// Constructs a [CropRotateEditor] widget with a video player.
  ///
  /// Used exclusively when cropping or rotating video frames.
  factory CropRotateEditor.video(
    ProVideoController videoController, {
    Key? key,
    required CropRotateEditorInitConfigs initConfigs,
  }) {
    return CropRotateEditor._(
      key: key,
      videoController: videoController,
      initConfigs: initConfigs,
    );
  }

  @override
  final CropRotateEditorInitConfigs initConfigs;

  @override
  final EditorImage? editorImage;

  @override
  final ProVideoController? videoController;

  @override
  State<CropRotateEditor> createState() => CropRotateEditorState();
}

/// Handles the state and UI for an image editor supporting cropping, rotating, and scaling.
///
/// Orchestrates touch gestures, transformations, and tool execution.
class CropRotateEditorState extends State<CropRotateEditor>
    with
        TickerProviderStateMixin,
        ImageEditorConvertedConfigs,
        ImageEditorConvertedCallbacks,
        StandaloneEditorState<CropRotateEditor, CropRotateEditorInitConfigs>,
        ExtendedLoop,
        CropAreaHistory {
  /// Identifies the editor content widget to allow retrieving its render box for global offset calculations.
  final GlobalKey _editorContentKey = GlobalKey();

  /// Identifies the extended rebuild mouse region to control mouse cursor state.
  final GlobalKey<ExtendedRebuildMouseRegionState> _mouseCursorsKey =
      GlobalKey<ExtendedRebuildMouseRegionState>();

  /// Notifies listeners of crop painter updates.
  late final ValueNotifier<CropCornerPainter?> _cropPainterNotifier;

  /// Identifies the crop rotate gesture detector to control raw gesture states.
  final GlobalKey<CropRotateGestureDetectorState> _gestureKey =
      GlobalKey<CropRotateGestureDetectorState>();

  /// Controls the scrolling behavior of the bottom navigation bar.
  late final ScrollController _bottomBarScrollCtrl;

  /// Prevents rapid consecutive scale end triggers by debouncing the event.
  late final Debounce _onScaleEndDebounce;

  /// Debounces scale updates to prevent excessive calculations during rapid gestures.
  late final Debounce _onScaleAllowUpdateDebounce;

  /// Debounces scroll history actions to prevent filling the undo stack unnecessarily.
  late final Debounce _scrollHistoryDebounce;

  /// Drives the fling animations when panning ends with significant velocity.
  late final AnimationController _flingCtrl;

  /// Defines the area considered for interactive corner gestures, loaded from configuration.
  late final double _interactiveCornerArea;

  /// Manages keyboard interaction states for desktop environments.
  late final CropDesktopInteractionManager _desktopInteractionManager;

  /// Determines which crop-rotate tools are currently available in the editor.
  late final List<CropRotateTool> tools;

  /// Defines the configuration for the fake hero transformation used during transitions.
  late TransformConfigs _fakeHeroTransformConfigs;

  /// Contains the list of layers applied over the image.
  late List<Layer> _layers;

  /// Contains the list of raw layers without any active transformation applied.
  late List<Layer> _rawLayers;

  /// Stores tap down details needed to calculate offsets during double-tap gestures.
  late TapDownDetails _doubleTapDetails;

  /// Drives the physics simulation for inertial scrolling on the X-axis.
  Simulation? _simulationX;

  /// Drives the physics simulation for inertial scrolling on the Y-axis.
  Simulation? _simulationY;

  /// Combines individual axis simulations for synchronized execution.
  Simulation? _combinedSimulation;

  /// Drives the physics simulation for inertial scaling (zoom).
  Simulation? _simulationScale;

  /// Caches the pan boundaries for perspective mode to avoid per-frame jitter.
  Rect? _cachedPerspectiveBounds;

  /// Stores the scale value at the start of a scaling gesture for relative calculations.
  double? _scaleStart;

  /// Tracks the scale applied during the last update frame.
  double _lastScale = 1.0;

  /// Counter to prevent overlapping scale/cropRect animations during rapid changes.
  int _animationId = 0;

  /// Tracks the minimum allowed scale considering the active perspective transform.
  double _perspectiveMinScale = 1.0;

  /// Calculates the scale required to hide empty spaces caused by straightening.
  double _straightenScale = 1.0;

  /// Defines the vertical space required outside the crop area.
  double _cropSpaceVertical = 0.0;

  /// Defines the horizontal space required outside the crop area.
  double _cropSpaceHorizontal = 0.0;

  /// Tracks the painter's opacity during fade-in animations.
  double _painterOpacity = 0.0;

  /// Tracks the interaction progress applied to opacity transitions.
  double _interactionOpacityProgress = 0.0;

  /// Tracks the blur interaction opacity (only fades when crop handles are dragged).
  double _blurInteractionOpacity = 0.0;

  /// Stores the initial scale value before a pinch gesture begins.
  double _startingPinchScale = 1.0;

  /// Temporarily stores the scale zoom limit needed during pointer registration.
  double _scaleStartZoomHelper = 1.0;

  /// Caches the previous perspective X value to determine boundary invalidation.
  double _cachedBoundsPerspectiveX = 0.0;

  /// Caches the previous perspective Y value to determine boundary invalidation.
  double _cachedBoundsPerspectiveY = 0.0;

  /// Caches the previous straighten angle to determine boundary invalidation.
  double _cachedBoundsStraightenAngle = 0.0;

  /// Stores the current view rectangle representing the visible area of the crop.
  Rect _viewRect = Rect.zero;

  /// Stores the starting translate offset before gestures begin.
  Offset _startingTranslate = Offset.zero;

  /// Caches the focal point from the previous gesture update frame.
  Offset _lastFocal = Offset.zero;

  /// Tracks the editor's screen offset needed when embedded inside nested screens.
  Offset _editorScreenOffsetHelper = Offset.zero;

  /// Defines the constraints applied to the rendered image box.
  BoxConstraints _renderedImgConstraints = const BoxConstraints();

  /// Identifies the type of gesture active at the end of an interaction.
  _GestureType? _gestureType;

  /// Tracks the currently active part of the crop area being manipulated.
  CropAreaPart _currentCropAreaPart = CropAreaPart.none;

  /// Stores the currently applied mouse cursor state.
  MouseCursor _mouseCursor = SystemMouseCursors.basic;

  /// Defines the currently selected crop mode constraint.
  late CropMode _cropMode;

  /// Determines if a fake hero animation should be shown during initial rendering.
  bool _showFakeHero = true;

  /// Prevents recursive updates by blocking simultaneous interaction flows.
  bool _blockInteraction = false;

  /// Indicates if a scale gesture has officially commenced.
  bool _scaleStarted = false;

  /// Indicates if an active interaction flow is currently ongoing.
  bool _interactionActive = false;

  /// Indicates whether an active scale out gesture logic is currently running.
  bool _activeScaleOut = false;

  /// Indicates whether the image needs internal decoding before manipulation.
  bool _imageNeedDecode = false;

  /// Indicates whether the image size has successfully finished decoding.
  bool _imageSizeIsDecoded = true;

  /// Tracks if a fake hero transition is enabled via configuration.
  bool enableFakeHero = false;

  /// Delays updates for one frame to allow outer listeners accurate event detection.
  bool _scaleAllowUpdateHelper = false;

  /// Tracks the number of active touch points currently registering inputs.
  int _activePointers = 0;

  /// Indicates if the user interface provides a visible top toolbar.
  bool _hasToolbar = true;

  /// Indicates whether the screen size constraints have dynamically changed.
  bool _isScreenResized = false;

  /// Indicates if the straightening adjustment mode is actively visible.
  bool _isStraightenModeActive = false;

  /// Indicates if the perspective adjustment mode is actively visible.
  bool _isPerspectiveModeActive = false;

  /// Tracks whether the underlying video player has finalized its initialization.
  bool _isVideoPlayerReady = true;

  /// Tracks whether the blur is currently faded out for straighten/perspective adjustment.
  bool _isAdjustmentBlurActive = false;

  /// Determines if the image layout tightly conforms to the screen width.
  ///
  /// Required to calculate correct bounding offsets during layout shifts.
  bool get imageSticksToScreenWidth => _imgWidth >= editorBodySize.width;

  /// Gets the width of the main image representation.
  ///
  /// Ensures safe retrieval of layout data.
  double get _imgWidth => _mainImageSize.width;

  /// Gets the height of the main image representation.
  ///
  /// Ensures safe retrieval of layout data.
  double get _imgHeight => _mainImageSize.height;

  /// Calculates the transformation ratio applied to the crop calculations.
  ///
  /// Derived from the current layout aspect ratio compared against the actual image dimensions.
  double get _ratio =>
      1 / (aspectRatio == 0.0 ? _mainImageSize.aspectRatio : aspectRatio);

  /// Computes the correct target size of the rendered image, accounting for rotations.
  ///
  /// Used heavily for boundary bounding calculations.
  Size get _renderedImgSize => Size(
        _rotated90deg
            ? _renderedImgConstraints.maxHeight
            : _renderedImgConstraints.maxWidth,
        _rotated90deg
            ? _renderedImgConstraints.maxWidth
            : _renderedImgConstraints.maxHeight,
      );

  /// Retrieves the absolute size of the original unedited image.
  ///
  /// Used to map layer coordinate offsets back to the source coordinate space.
  Size get _mainImageSize =>
      mainImageSize ?? imageInfos?.renderedSize ?? Size.zero;

  /// The original aspect ratio (width / height) of the source image.
  double get originalAspectRatio => _mainImageSize.aspectRatio;

  /// Indicates whether the image is visually rotated by an odd multiple of 90 degrees.
  ///
  /// Reverses axis boundaries if true.
  bool get _rotated90deg => rotationCount % 2 != 0;

  /// Calculates the necessary scale to assist coordinate translations.
  ///
  /// Used to properly place injected layers inside the layout constraints.
  double get _transformHelperScale => originalSize.isEmpty
      ? 1.0
      : TransformHelper(
          mainBodySize: (mainBodySize ?? editorBodySize),
          mainImageSize: _mainImageSize,
          editorBodySize: originalSize,
        ).scale;

  /// Defines whether active perspective changes are applied to the view context.
  ///
  /// If true, boundaries switch from linear clamps to polygon-based geometry validations.
  bool get _hasPerspective => perspectiveX != 0.0 || perspectiveY != 0.0;

  /// Retrieves the smallest permitted scale configuration, respecting perspective logic.
  ///
  /// Necessary to prevent infinite shrink gaps.
  double get _effectiveMinScale => _hasPerspective ? _perspectiveMinScale : 1.0;

  /// Computes the alignment for Transform.scale so that scaling is centered
  /// on the content area (within viewPadding) rather than the body center.
  ///
  /// This is critical when viewPadding is asymmetric (e.g. top ≠ bottom),
  /// because Alignment.center would scale around the body center, causing
  /// the crop rect to shift away from the viewPadding boundaries.
  Alignment get _contentCenterAlignment {
    final EdgeInsets margin = cropRotateEditorConfigs.viewPadding ??
        cropRotateEditorConfigs.boundaryMargin;
    final double bodyW = editorBodySize.width;
    final double bodyH = editorBodySize.height;
    if (bodyW <= 0 || bodyH <= 0) return Alignment.center;
    final double contentCenterX = margin.left + (bodyW - margin.horizontal) / 2;
    final double contentCenterY = margin.top + (bodyH - margin.vertical) / 2;
    return Alignment(
      (contentCenterX - bodyW / 2) / (bodyW / 2),
      (contentCenterY - bodyH / 2) / (bodyH / 2),
    );
  }

  /// Retrieves the current mouse cursor state.
  ///
  /// Abstracts direct access to keep the getter implementation generic.
  MouseCursor get _cursor => _mouseCursor;

  /// Sets the current mouse cursor style and updates the underlying region.
  ///
  /// Automatically triggers a hardware cursor change in desktop environments.
  set _cursor(MouseCursor cursor) {
    _mouseCursor = cursor;
    _mouseCursorsKey.currentState?.setCursor(cursor);
  }

  /// Calculates the absolute maximum scale allowed before perspective clipping occurs.
  ///
  /// Solves the perspective projection matrix against the near-clip plane limit.
  double get _effectiveMaxScale {
    final double maxUserConfigScale = cropRotateEditorConfigs.maxScale;
    if (!_hasPerspective) return maxUserConfigScale;

    final Size imgSize = Size(
      _renderedImgConstraints.maxWidth,
      _renderedImgConstraints.maxHeight,
    );

    if (imgSize.isEmpty || imgSize.isInfinite) return maxUserConfigScale;

    final double imgHalfWidth = imgSize.width / 2;
    final double imgHalfHeight = imgSize.height / 2;

    final Matrix4 prMatrix = _calculateStraightenAndPerspectiveMatrix(
      angle: straightenAngle,
      perspectiveX: perspectiveX,
      perspectiveY: perspectiveY,
    );

    final double m30 = prMatrix.storage[3].abs();
    final double m31 = prMatrix.storage[7].abs();
    final double sBase = _straightenScale;

    final double A = 2.0 * sBase * (m30 * imgHalfWidth + m31 * imgHalfHeight);

    if (A <= 0.0) return maxUserConfigScale;

    final double viewHalfW = _viewRect.isEmpty ? 0.0 : _viewRect.width / 2;
    final double viewHalfH = _viewRect.isEmpty ? 0.0 : _viewRect.height / 2;
    final double B = sBase * (m30 * viewHalfW + m31 * viewHalfH);

    final double minAllowedUserScale = (B + 0.9899) / A;

    return max(
      _effectiveMinScale,
      min(maxUserConfigScale, minAllowedUserScale),
    );
  }

  /// Computes the simulated depth value required for accurate perspective distortion.
  ///
  /// Normalizes against the longest image side to maintain consistent perceived depth.
  double get _perspectiveDepth {
    final double longestSide = max(
      _renderedImgConstraints.maxWidth,
      _renderedImgConstraints.maxHeight,
    );
    if (longestSide <= 0.0 || longestSide.isInfinite) return 0.001;
    return 0.001 / (longestSide / 1000.0);
  }

  @override
  CropMode get cropMode => _cropMode;

  @override
  set cropMode(CropMode value) => setCropMode(value);

  @override
  CropCornerPainter? get backgroundCropPainter {
    return showWidgets
        ? CropCornerPainter(
            offset: translate,
            cropRect: cropRect,
            viewRect: _viewRect,
            scaleFactor: userScaleFactor *
                max(1.0, _straightenScale) *
                max(1.0, _perspectiveMinScale),
            rotationScaleFactor: scaleAnimation.value,
            interactionOpacity: _interactionOpacityProgress,
            screenSize: Size(
              editorBodySize.width,
              editorBodySize.height,
            ),
            fadeInOpacity: _painterOpacity,
            style: cropRotateEditorConfigs.style,
            drawCircle: cropMode == CropMode.oval,
            background:
                cropRotateEditorConfigs.style.background?.call(context) ??
                    kImageEditorBackground,
            helperLineColor:
                cropRotateEditorConfigs.style.helperLineColor?.call(context) ??
                    const Color(0xFF000000),
            cropCornerColor:
                cropRotateEditorConfigs.style.cropCornerColor?.call(context) ??
                    kImageEditorPrimaryColor,
            cropOverlayColor:
                cropRotateEditorConfigs.style.cropOverlayColor?.call(context) ??
                    const Color(0xFF000000),
            renderedImageSize: _renderedImgSize,
            straightenAngle: straightenAngle,
            perspectiveX: perspectiveX,
            perspectiveY: perspectiveY,
            perspectiveDepth: _perspectiveDepth,
            straightenScale: _straightenScale,
            drawCropOverlay: false,
          )
        : null;
  }

  /// The straightening angle applied via the slider
  double get straightenValue => straightenAngle;

  /// The horizontal perspective applied to the image.
  double get perspectiveXValue => perspectiveX;

  /// The vertical perspective applied to the image.
  double get perspectiveYValue => perspectiveY;

  @override
  void initState() {
    super.initState();
    _initializeVideoEditor();

    _onScaleEndDebounce = Debounce(const Duration(milliseconds: 10));
    _onScaleAllowUpdateDebounce = Debounce(const Duration(milliseconds: 1));
    _scrollHistoryDebounce = Debounce(const Duration(milliseconds: 350));

    _bottomBarScrollCtrl = ScrollController();
    _flingCtrl = AnimationController(vsync: this);
    _fakeHeroTransformConfigs =
        initialTransformConfigs ?? TransformConfigs.empty();
    _interactiveCornerArea = isDesktop
        ? cropRotateEditorConfigs.desktopCornerDragArea
        : cropRotateEditorConfigs.mobileCornerDragArea;
    _desktopInteractionManager =
        CropDesktopInteractionManager(context: context);
    ServicesBinding.instance.keyboard.addHandler(_onKeyEvent);

    _imageNeedDecode = mainImageSize == null;
    _imageSizeIsDecoded = !_imageNeedDecode;
    _layers = initConfigs.layers ?? [];
    _cropPainterNotifier = ValueNotifier(null);
    _setRawLayers();

    final double initAngle = initialTransformConfigs?.angle ?? 0.0;
    rotateCtrl = AnimationController(
        duration: cropRotateEditorConfigs.animationDuration, vsync: this);

    rotateCtrl.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        if (_blockInteraction) {
          addHistory(scaleRotation: oldScaleFactor);
        }
        _blockInteraction = false;
        cropRotateEditorCallbacks?.handleRotateEnd(rotateAnimation.value);
      }
    });

    rotateAnimation =
        Tween<double>(begin: initAngle, end: initAngle).animate(rotateCtrl);

    final double initScale = (initialTransformConfigs?.scaleRotation ?? 1.0);
    scaleCtrl = AnimationController(
        duration: cropRotateEditorConfigs.animationDuration, vsync: this);

    scaleAnimation = AlwaysStoppedAnimation(initScale);

    straightenAngle = initialTransformConfigs?.straightenAngle ?? 0.0;
    _straightenScale = _calculateStraightenScale(straightenAngle);

    aspectRatio =
        cropRotateEditorConfigs.initAspectRatio ?? CropAspectRatios.custom;

    if (widget.initConfigs.convertToUint8List) {
      setImageInfos(activeHistory: activeHistory);
    }

    if (initialTransformConfigs != null &&
        initialTransformConfigs!.isNotEmpty) {
      rotationCount = (initialTransformConfigs!.angle * 2 / pi).abs().toInt();
      flipX = initialTransformConfigs!.flipX;
      flipY = initialTransformConfigs!.flipY;
      translate = initialTransformConfigs!.offset;
      userScaleFactor = initialTransformConfigs!.scaleUser;
      aspectRatio = initialTransformConfigs!.aspectRatio;
      cropRect = initialTransformConfigs!.cropRect;
      _viewRect = initialTransformConfigs!.cropRect;
      oldScaleFactor = initialTransformConfigs!.scaleRotation;
      setInitHistory(initialTransformConfigs!);
    }

    enableFakeHero = initConfigs.enableFakeHero;
    _showFakeHero = enableFakeHero;

    tools = [...cropRotateEditorConfigs.tools];
    _cropMode = widget.initConfigs.transformConfigs?.cropMode ??
        cropRotateEditorConfigs.initialCropMode;

    cropRotateEditorCallbacks?.onInit?.call();

    // TODO: Remove when releasing version 12.0.0.
    tools.removeWhere((CropRotateTool el) {
      switch (el) {
        case CropRotateTool.rotate:
          return !cropRotateEditorConfigs.showRotateButton;
        case CropRotateTool.flip:
          return !cropRotateEditorConfigs.showFlipButton;
        case CropRotateTool.aspectRatio:
          return !cropRotateEditorConfigs.showAspectRatioButton;
        case CropRotateTool.perspective:
          return false;
        case CropRotateTool.reset:
          return !cropRotateEditorConfigs.showResetButton;
        case CropRotateTool.straighten:
          return false;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((Duration timeStamp) {
      cropRotateEditorCallbacks?.onAfterViewInit?.call();
      initialized = true;

      if (initialTransformConfigs != null &&
          initialTransformConfigs!.isNotEmpty &&
          initialTransformConfigs!.aspectRatio < 0.0) {
        aspectRatio = initialTransformConfigs!.cropRect.size.aspectRatio;
        _clampInitialFreeAspectRatio();
        calcCropRect(onlyViewRect: initialTransformConfigs?.isEmpty == false);
        aspectRatio = -1.0;
      } else {
        if (aspectRatio < 0.0) _clampInitialFreeAspectRatio();
        calcCropRect(onlyViewRect: initialTransformConfigs?.isEmpty == false);
        if (aspectRatio != -1.0 &&
                cropRotateEditorConfigs.initAspectRatio == null ||
            cropRotateEditorConfigs.initAspectRatio == -1.0) {
          aspectRatio = -1.0;
        }
      }

      if (!enableFakeHero) hideFakeHero();
      _updateAllStates();
      _setRawLayers();

      final Size? originalSizeVal = initialTransformConfigs?.originalSize;

      if (originalSizeVal != null && !originalSizeVal.isInfinite) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final double oldScaleAnimationValue = scaleAnimation.value;
          scaleCtrl.duration = Duration.zero;
          calcFitToScreen();
          scaleCtrl.duration = cropRotateEditorConfigs.animationDuration;
          _setCropRectBounding(oldScaleAnimationValue: oldScaleAnimationValue);
        });
      }
    });
  }

  void _clampInitialFreeAspectRatio() {
    if (aspectRatio < 0.0 &&
        _mainImageSize.width > 0 &&
        _mainImageSize.height > 0) {
      final double actRatio = _mainImageSize.aspectRatio;
      if (cropRotateEditorConfigs.minAspectRatio != null &&
          actRatio < cropRotateEditorConfigs.minAspectRatio!) {
        aspectRatio = cropRotateEditorConfigs.minAspectRatio!;
      } else if (cropRotateEditorConfigs.maxAspectRatio != null &&
          actRatio > cropRotateEditorConfigs.maxAspectRatio!) {
        aspectRatio = cropRotateEditorConfigs.maxAspectRatio!;
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _setCropPainter();
  }

  @override
  void setState(void Function() fn) {
    rebuildController.add(null);
    super.setState(fn);
  }

  /// Initiates the image generation process, applying all modifications.
  ///
  /// Orchestrates byte conversions, callback triggers, and dialogue popups.
  Future<void> done() async {
    if (_interactionActive ||
        (!_imageSizeIsDecoded && initConfigs.convertToUint8List)) {
      return;
    }

    _interactionActive = true;
    initConfigs.callbacks.onImageEditingStarted?.call();

    if (!canUndo &&
        cropRotateEditorConfigs.initAspectRatio != CropAspectRatios.custom) {
      addHistory();
    }

    final TransformConfigs transformC =
        !canRedo && !canUndo && initialTransformConfigs != null
            ? initialTransformConfigs!
            : activeHistory;

    _showFakeHero = enableFakeHero;
    _fakeHeroTransformConfigs = transformC;
    _updateAllStates();

    if (!initConfigs.convertToUint8List) {
      final List<Layer> updatedLayers = LayerTransformGenerator(
        layers: initConfigs.layers ?? [],
        activeTransformConfigs:
            initConfigs.transformConfigs ?? TransformConfigs.empty(),
        newTransformConfigs: transformC,
        layerDrawAreaSize: originalSize,
        fitToScreenFactor: _transformHelperScale,
        undoChanges: false,
      ).updatedLayers;

      _layers = updatedLayers;
      _updateAllStates();

      if (cropRotateEditorConfigs.enableProvideImageInfos &&
          imageInfos == null) {
        await setImageInfos(activeHistory: activeHistory);
      }

      await initConfigs.onDone
          ?.call(transformC, _transformHelperScale, imageInfos);

      if (mounted && initConfigs.enablePopWhenDone) {
        Navigator.pop(context, transformC);
      }
    } else {
      LoadingDialog.instance.show(
        context,
        configs: configs,
        theme: theme,
        message: i18n.doneLoadingMsg,
      );

      if (imageInfos == null) {
        await setImageInfos(activeHistory: activeHistory);
      }

      if (!mounted) {
        LoadingDialog.instance.hide();
        return;
      }

      Uint8List? bytes;
      int retry = 0;

      do {
        if (retry > 0) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (!mounted) return;
        }

        setState(() {
          _imageNeedDecode = true;
          rotationCount = 0;
          rotateAnimation =
              Tween<double>(begin: 0.0, end: 0.0).animate(rotateCtrl);
          straightenAngle = 0.0;
          _straightenScale = 1.0;
          perspectiveX = 0.0;
          perspectiveY = 0.0;
          _perspectiveMinScale = 1.0;
          userScaleFactor = 1.0;
          cropRect = initialTransformConfigs?.cropRect ??
              Rect.fromLTWH(
                0.0,
                0.0,
                imageInfos!.renderedSize.width,
                imageInfos!.renderedSize.height,
              );
        });

        bytes = await screenshotCtrl.captureFinalScreenshot(
          imageInfos: imageInfos!,
          context: context,
          widget: _screenshotWidget(transformC),
          targetSize: _rotated90deg
              ? imageInfos!.renderedSize.flipped
              : imageInfos!.renderedSize,
          backgroundScreenshot:
              screenshotHistoryPosition >= screenshotHistory.length
                  ? null
                  : screenshotHistory[screenshotHistoryPosition],
        );

        retry++;
      } while (bytes == null && retry < 7 && mounted);

      if (!mounted) return;

      final Uint8List imageBytes = bytes ?? Uint8List.fromList([]);

      await initConfigs.callbacks.onImageEditingComplete?.call(imageBytes);

      if (!mounted) return;

      if (initConfigs.callbacks.onCompleteWithParameters != null) {
        final completeParams =
            await getCompleteParameters(imageBytes: imageBytes);

        await callbacks.onCompleteWithParameters?.call(completeParams);
      }

      LoadingDialog.instance.hide();
      initConfigs.callbacks.onCloseEditor?.call(EditorMode.cropRotate);
    }

    cropRotateEditorCallbacks?.handleDone();
    _interactionActive = false;
  }

  /// Takes an immediate internal screenshot to retain interaction history.
  ///
  /// Necessary for fast undo/redo transitions relying on rendered snapshots.
  @override
  void takeScreenshot() async {
    if (!widget.initConfigs.convertToUint8List) return;

    await setImageInfos(activeHistory: activeHistory, forceUpdate: true);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (initialTransformConfigs == null &&
          history.length == 1 &&
          history.first.isEmpty) {
        setInitHistory(
          TransformConfigs(
            angle: rotateAnimation.value,
            cropRect: cropRect,
            originalSize: originalSize,
            cropEditorScreenRatio: cropEditorScreenRatio,
            scaleUser: userScaleFactor,
            scaleRotation: scaleAnimation.value,
            aspectRatio: aspectRatio,
            flipX: flipX,
            flipY: flipY,
            offset: translate,
            cropMode: cropMode,
          ),
        );
      }

      final TransformConfigs transformC =
          !canRedo && !canUndo && initialTransformConfigs != null
              ? initialTransformConfigs!
              : activeHistory;

      await screenshotCtrl.capture(
        imageInfos: imageInfos!,
        screenshots: screenshotHistory,
        widget: _screenshotWidget(transformC),
      );
    });
  }

  /// Toggles horizontal or vertical axis flipping based on visual rotation state.
  ///
  /// Adapts flipping logic seamlessly against orthogonal orientation context.
  void flip() {
    if (rotationCount % 2 != 0) {
      flipY = !flipY;
    } else {
      flipX = !flipX;
    }

    cropRotateEditorCallbacks?.handleFlip(flipX, flipY);
    addHistory();
    _updateAllStates();
  }

  /// Initiates an animated 90-degree orthogonal rotation operation.
  ///
  /// Triggers structural updates to bounding constraints and recalculates fit scaling.
  void rotate() {
    _blockInteraction = true;
    final double piHelper =
        cropRotateEditorConfigs.rotateDirection == RotateDirection.left
            ? -pi
            : pi;

    rotationCount++;

    rotateAnimation = Tween<double>(
            begin: rotateAnimation.value, end: rotationCount * piHelper / 2.0)
        .animate(
      CurvedAnimation(
        parent: rotateCtrl,
        curve: cropRotateEditorConfigs.rotateAnimationCurve,
      ),
    );

    rotateCtrl
      ..reset()
      ..forward();

    calcFitToScreen();
    cropRotateEditorCallbacks?.handleRotateStart(rotateAnimation.value);
  }

  /// Adjusts the angular rotation mapped via a fine-tune straightening slider.
  ///
  /// Clamps boundaries against layout clipping to maintain an edge-to-edge frame.
  void setStraightenAngle(double angle) {
    fadeOutBlur();

    const double maxAngle = pi / 4.0;
    final double clampedAngle = angle.clamp(-maxAngle, maxAngle);
    straightenAngle = clampedAngle;

    _straightenScale = _calculateStraightenScale(clampedAngle);
    _invalidatePerspectiveBoundsCache();
    if (_hasPerspective) {
      _fitToScreen();
    } else {
      _setOffsetLimits();
    }
    _updateAllStates();
    addHistory(scaleRotation: oldScaleFactor);
  }

  /// Toggles the user interface to display the manual straightening widget.
  ///
  /// Auto-hides conflicting secondary modification panels.
  void toggleStraightenMode() {
    _isStraightenModeActive = !_isStraightenModeActive;
    _isPerspectiveModeActive = false;
    setState(() {});
  }

  /// Toggles the user interface to display the manual perspective mapping widget.
  ///
  /// Auto-hides conflicting secondary modification panels.
  void togglePerspectiveMode() {
    _isPerspectiveModeActive = !_isPerspectiveModeActive;
    _isStraightenModeActive = false;
    setState(() {});
  }

  /// Updates structural 3D transformations simulating a slanted focal plane.
  ///
  /// Triggers heavy polygon intersection calculations to revalidate frame fit.
  void setPerspective(double x, double y) {
    if (perspectiveX == x && perspectiveY == y) return;
    fadeOutBlur();

    const double maxAngle = pi / 6.0;

    perspectiveX = x.clamp(-maxAngle, maxAngle);
    perspectiveY = y.clamp(-maxAngle, maxAngle);
    _invalidatePerspectiveBoundsCache();
    _fitToScreen();
  }

  void fadeOutBlur() {
    if (_isAdjustmentBlurActive) return;
    _isAdjustmentBlurActive = true;
    loopWithTransitionTiming(
      (double curveT) {
        _blurInteractionOpacity = 1.0 * curveT;
        _setCropPainter();
      },
      mounted: mounted,
      transitionFunction: Curves.decelerate.transform,
      duration: cropRotateEditorConfigs.opacityOutsideCropAreaDuration,
    );
  }

  void fadeInBlur() {
    _isAdjustmentBlurActive = false;
    Future.delayed(cropRotateEditorConfigs.cropDragOutOfBoundsDelay, () {
      if (!mounted) return;
      loopWithTransitionTiming(
        (double curveT) {
          _blurInteractionOpacity = 1.0 - 1.0 * curveT;
          _setCropPainter();
        },
        mounted: mounted,
        duration: cropRotateEditorConfigs.opacityOutsideCropAreaDuration,
      );
    });
  }

  @override
  void calcFitToScreen({
    Curve? curve,
    Size? imageSize,
    bool animated = true,
    Duration? duration,
    Rect? customOldCropRect,
    Offset? oldTranslate,
    Offset? targetTranslate,
  }) {
    if (!animated) {
      scaleCtrl.duration = Duration.zero;
    } else if (duration != null) {
      scaleCtrl.duration = duration;
    } else {
      scaleCtrl.duration = cropRotateEditorConfigs.animationDuration;
    }

    _animationId++;
    final int currentAnimationId = _animationId;

    final EdgeInsets margin = cropRotateEditorConfigs.viewPadding ??
        cropRotateEditorConfigs.boundaryMargin;

    final Size contentSize = Size(
      editorBodySize.width - margin.horizontal,
      editorBodySize.height - margin.vertical,
    );

    final double activeCropSpaceHorizontal =
        _rotated90deg ? _cropSpaceVertical : _cropSpaceHorizontal;

    final double activeCropSpaceVertical =
        _rotated90deg ? _cropSpaceHorizontal : _cropSpaceVertical;

    final Size renderedSize = imageSize ?? _renderedImgSize;

    double boxWidth = renderedSize.width - activeCropSpaceHorizontal;
    double boxHeight = renderedSize.height - activeCropSpaceVertical;

    final double scaleX = contentSize.width / boxWidth;
    final double scaleY = contentSize.height / boxHeight;

    final double scale = min(scaleX, scaleY);

    final double targetScale = scale;
    final double startScale = scaleAnimation.value;

    scaleCtrl
      ..reset()
      ..forward();

    oldScaleFactor = scale;

    final Rect startCropRect = customOldCropRect ?? cropRect;
    final Rect targetCropRect = cropRect;

    _setCropPainter();

    if (!targetScale.isInfinite && !targetScale.isNaN) {
      final Curve animCurve =
          curve ?? cropRotateEditorConfigs.rotateAnimationCurve;

      scaleAnimation =
          Tween<double>(begin: startScale, end: targetScale).animate(
        CurvedAnimation(
          parent: scaleCtrl,
          curve: animCurve,
        ),
      );

      final Animation<Rect?>? cropRectAnim = customOldCropRect != null
          ? RectTween(begin: startCropRect, end: targetCropRect).animate(
              CurvedAnimation(
                parent: scaleCtrl,
                curve: animCurve,
              ),
            )
          : null;

      final Animation<Offset?>? translateAnim = (oldTranslate != null &&
              targetTranslate != null)
          ? Tween<Offset>(begin: oldTranslate, end: targetTranslate).animate(
              CurvedAnimation(
                parent: scaleCtrl,
                curve: animCurve,
              ),
            )
          : null;

      void onScaleTick() {
        if (!mounted || _animationId != currentAnimationId) return;

        bool needsFullUpdate = false;

        if (cropRectAnim != null && cropRectAnim.value != null) {
          cropRect = cropRectAnim.value!;
          needsFullUpdate = true;
        }

        if (translateAnim != null && translateAnim.value != null) {
          translate = translateAnim.value!;
          needsFullUpdate = true;
        }

        if (needsFullUpdate) {
          _updateAllStates();
        } else {
          _setCropPainter();
        }
      }

      scaleCtrl.addListener(onScaleTick);
      scaleCtrl.addStatusListener(
        (status) {
          if (status == AnimationStatus.completed) {
            scaleCtrl.removeListener(onScaleTick);
          }
        },
      );
    } else {
      scaleAnimation = AlwaysStoppedAnimation(targetScale);
    }

    if (!animated) {
      scaleCtrl.duration = cropRotateEditorConfigs.animationDuration;
    }
  }

  /// Triggers a modal bottom sheet explicitly requesting predefined aspect layouts.
  ///
  /// Evaluates callbacks and executes corresponding structural size recalculations.
  void openAspectRatioOptions() {
    showModalBottomSheet<double>(
      context: context,
      backgroundColor:
          cropRotateEditorConfigs.style.aspectRatioSheetBackgroundColor,
      isScrollControlled: true,
      builder: (BuildContext context) => SafeArea(
        child: cropRotateEditorConfigs.widgets.aspectRatioOptions?.call(
              this,
              rebuildController.stream,
              aspectRatio,
              _mainImageSize.aspectRatio,
            ) ??
            CropAspectRatioOptions(
              aspectRatio: aspectRatio,
              configs: configs,
              originalAspectRatio: _mainImageSize.aspectRatio,
            ),
      ),
    ).then((double? value) {
      if (value != null) {
        updateAspectRatio(value);
      }
    });
  }

  /// Sets the currently active aspect ratio dimension target for the crop boundary.
  ///
  /// Emits updates cascading to bounding validation routines.
  void updateAspectRatio(double value) {
    if (value == 0.0) {
      double originalRatio = _mainImageSize.aspectRatio;
      if (cropRotateEditorConfigs.minAspectRatio != null &&
          originalRatio < cropRotateEditorConfigs.minAspectRatio!) {
        value = cropRotateEditorConfigs.minAspectRatio!;
      } else if (cropRotateEditorConfigs.maxAspectRatio != null &&
          originalRatio > cropRotateEditorConfigs.maxAspectRatio!) {
        value = cropRotateEditorConfigs.maxAspectRatio!;
      }
    }

    aspectRatio = value;
    cropRotateEditorCallbacks?.handleRatioSelected(value);

    final Rect oldCropRect = cropRect;
    final Offset oldTranslate = translate;

    if (value < 0.0) {
      calcCropRect(onlyViewRect: true);

      // Clamp existing cropRect to the newly calculated _viewRect bounds
      double clampedWidth = cropRect.width.clamp(0.0, _viewRect.width);
      double clampedHeight = cropRect.height.clamp(0.0, _viewRect.height);

      // Also ensure the cropRect aspect ratio itself doesn't exceed min/max config
      double currentRectRatio = clampedWidth / clampedHeight;
      if (cropRotateEditorConfigs.minAspectRatio != null &&
          currentRectRatio < cropRotateEditorConfigs.minAspectRatio!) {
        currentRectRatio = cropRotateEditorConfigs.minAspectRatio!;
        if (clampedHeight * currentRectRatio <= _viewRect.width) {
          clampedWidth = clampedHeight * currentRectRatio;
        } else {
          clampedWidth = _viewRect.width;
          clampedHeight = clampedWidth / currentRectRatio;
        }
      } else if (cropRotateEditorConfigs.maxAspectRatio != null &&
          currentRectRatio > cropRotateEditorConfigs.maxAspectRatio!) {
        currentRectRatio = cropRotateEditorConfigs.maxAspectRatio!;
        if (clampedWidth / currentRectRatio <= _viewRect.height) {
          clampedHeight = clampedWidth / currentRectRatio;
        } else {
          clampedHeight = _viewRect.height;
          clampedWidth = clampedHeight * currentRectRatio;
        }
      }

      cropRect = Rect.fromCenter(
        center: cropRect.center,
        width: clampedWidth,
        height: clampedHeight,
      );
    } else {
      calcCropRect();
    }
    final Rect targetCropRect = cropRect;

    // Compute target translate by clamping with the new viewRect
    _setOffsetLimits();
    final Offset targetTranslate = translate;

    // Record history with target state
    addHistory(scaleRotation: oldScaleFactor);

    if (oldCropRect != targetCropRect) {
      // NOTE: calcFitToScreen reads cropRect (= targetCropRect) to determine
      // the animation end state, so we call it BEFORE resetting.
      calcFitToScreen(
        duration: cropRotateEditorConfigs.aspectRatioChangeAnimationDuration,
        curve: cropRotateEditorConfigs.aspectRatioChangeAnimationCurve,
        customOldCropRect: oldCropRect,
        oldTranslate: oldTranslate,
        targetTranslate: targetTranslate,
      );

      // Reset to old state so the first rendered frame matches the pre-switch
      // visual. The animation's onScaleTick will immediately start driving
      // cropRect and translate from old → target on subsequent frames.
      cropRect = oldCropRect;
      translate = oldTranslate;
    } else {
      calcFitToScreen();
      // Only clamp immediately if nothing is animating
      _setOffsetLimits();
    }

    _updateAllStates();
  }

  @override
  void setCropMode(
    CropMode value, {
    bool updateStates = true,
    bool updateHistory = true,
  }) {
    _cropMode = value;
    if (updateStates) _updateAllStates();
    if (updateHistory) addHistory();
  }

  @override
  void calcCropRect({bool onlyViewRect = false, double? newRatio}) {
    final double imgSizeRatio = _imgHeight / _imgWidth;
    final Size imgConstraints = _renderedImgConstraints.biggest.isInfinite
        ? imageInfos?.renderedSize ?? _renderedImgConstraints.biggest
        : _renderedImgConstraints.biggest;

    final double imgW = imgConstraints.width;
    final double imgH = imgConstraints.height;
    double realImgW = imageSticksToScreenWidth ? imgW : imgH / imgSizeRatio;
    double realImgH = imageSticksToScreenWidth ? imgW * imgSizeRatio : imgH;

    final double ratio;
    if (_ratio <= 0.0) {
      // Freeform mode. We clamp the "view bounds" ratio.
      double freeformBoundRatio = imgSizeRatio;
      if (cropRotateEditorConfigs.minAspectRatio != null &&
          1 / freeformBoundRatio < cropRotateEditorConfigs.minAspectRatio!) {
        freeformBoundRatio = 1 / cropRotateEditorConfigs.minAspectRatio!;
      } else if (cropRotateEditorConfigs.maxAspectRatio != null &&
          1 / freeformBoundRatio > cropRotateEditorConfigs.maxAspectRatio!) {
        freeformBoundRatio = 1 / cropRotateEditorConfigs.maxAspectRatio!;
      }
      ratio = newRatio ?? freeformBoundRatio;
    } else {
      ratio = newRatio ?? _ratio;
    }
    double left = 0.0;
    double top = 0.0;

    if (imgSizeRatio >= ratio) {
      final double newH = realImgW * ratio;
      top = (realImgH - newH) / 2.0;
      realImgH = newH;
    } else {
      final double newW = realImgH / ratio;
      left = (realImgW - newW) / 2.0;
      realImgW = newW;
    }

    _cropSpaceVertical = top * 2.0;
    _cropSpaceHorizontal = left * 2.0;

    if (!onlyViewRect) {
      cropRect = Rect.fromLTWH(left, top, realImgW, realImgH);
    }

    _viewRect = Rect.fromLTWH(left, top, realImgW, realImgH);

    _setCropPainter();
  }

  void _setCropPainter() {
    final painter = backgroundCropPainter;
    _cropPainterNotifier.value = painter;
    cropPainterKey.currentState?.setForegroundPainter(painter);
  }

  void _updateCropPainter() {
    final painter = backgroundCropPainter;
    _cropPainterNotifier.value = painter;
    cropPainterKey.currentState?.update(
      foregroundPainter: painter,
      isComplex: showWidgets,
      willChange: showWidgets,
    );
  }

  void _setRawLayers({bool refit = false}) {
    if (refit) calcFitToScreen(animated: false);

    _rawLayers = LayerTransformGenerator(
      layers: _layers,
      activeTransformConfigs: _fakeHeroTransformConfigs,
      newTransformConfigs: TransformConfigs.empty(),
      layerDrawAreaSize: originalSize.isInfinite || originalSize.isEmpty
          ? mainBodySize ?? Size.zero
          : originalSize,
      undoChanges: true,
      fitToScreenFactor: _transformHelperScale,
      transformHelperScale: _transformHelperScale,
    ).updatedLayers;
  }

  void _updateAllStates() {
    userScaleKey.currentState?.setScale(userScaleFactor);
    _updateCropPainter();
    translateKey.currentState?.setOffset(translate);
    setState(() {});
  }

  void _initializeVideoEditor() async {
    if (!isVideoEditor || !initConfigs.convertToUint8List) return;
    _isVideoPlayerReady = false;

    widget.videoController!.initialize(
      configsFunction: () => configs.videoEditor,
      callbacksFunction: () =>
          callbacks.videoEditorCallbacks ?? VideoEditorCallbacks(),
    );

    final Size resolution = widget.videoController!.initialResolution;

    videoBackgroundImage = EditorImage(
      byteArray: await createTransparentImage(resolution),
    );

    _isVideoPlayerReady = true;

    if (!mounted) return;
    setState(() {});
    await _decodeImage();
  }

  Future<void> _decodeImage() async {
    if (!_isVideoPlayerReady && isVideoEditor) return;
    _imageSizeIsDecoded = false;
    _imageNeedDecode = false;

    final ui.Image decodedImage =
        await decodeImageFromList(await editorImage!.safeByteArray(context));

    if (!mounted) return;

    final int w = decodedImage.width;
    final int h = decodedImage.height;
    final double widthRatio = w.toDouble() / editorBodySize.width;
    final double heightRatio = h.toDouble() / editorBodySize.height;
    final double pixelRatio = max(heightRatio, widthRatio);
    final Size renderedSize = Size(w / pixelRatio, h / pixelRatio);

    imageInfos = ImageInfos(
      rawSize: Size(w.toDouble(), h.toDouble()),
      renderedSize: renderedSize,
      originalRenderedSize: renderedSize,
      cropRectSize: cropRect.size,
      isRotated: _rotated90deg,
      pixelRatio: pixelRatio,
    );

    calcCropRect();
    _updateAllStates();

    Future.delayed(const Duration(milliseconds: 60), () {
      calcCropRect();
      calcFitToScreen();
      _imageSizeIsDecoded = true;
      _updateAllStates();
      cropRotateEditorCallbacks?.handleUpdateUI();
    });
  }

  void hideFakeHero() {
    _showFakeHero = false;
    showWidgets = true;

    cropPainterKey.currentState?.update(
      isComplex: showWidgets,
      willChange: showWidgets,
    );

    loopWithTransitionTiming(
      (double curveT) {
        _painterOpacity = 1.0 * curveT;
        _updateCropPainter();
      },
      mounted: mounted,
      transitionFunction:
          cropRotateEditorConfigs.fadeInOutsideCropAreaAnimationCurve.transform,
      duration: cropRotateEditorConfigs.fadeInOutsideCropAreaAnimationDuration,
      onDone: takeScreenshot,
    );

    _updateAllStates();
  }

  bool _onKeyEvent(KeyEvent event) {
    return _desktopInteractionManager.onKey(
      event,
      onRotate: rotate,
      onFlip: flip,
      onTranslate: (Offset offset) async {
        final double radianAngle = rotateAnimation.value;
        final double cosAngle = cos(radianAngle);
        final double sinAngle = sin(radianAngle);
        double dx = offset.dy * sinAngle + offset.dx * cosAngle;
        double dy = offset.dy * cosAngle - offset.dx * sinAngle;

        dx *= (flipX ? -1.0 : 1.0);
        dy *= (flipY ? -1.0 : 1.0);

        Offset startOffset = translate;
        final Offset targetOffset = translate += Offset(dx, dy);

        await loopWithTransitionTiming(
          (double curveT) {
            translate = Offset(
              ui.lerpDouble(startOffset.dx, targetOffset.dx, curveT)!,
              ui.lerpDouble(startOffset.dy, targetOffset.dy, curveT)!,
            );
            _setOffsetLimits();
          },
          mounted: mounted,
          duration: cropRotateEditorConfigs.animationDuration,
          transitionFunction:
              cropRotateEditorConfigs.scaleAnimationCurve.transform,
        );

        startOffset = targetOffset;
        _setOffsetLimits();
        addHistory();
      },
      onScale: (double scale) async {
        double startZoom = userScaleFactor;
        final double targetZoom = (userScaleFactor + scale)
            .clamp(_effectiveMinScale, cropRotateEditorConfigs.maxScale);

        await loopWithTransitionTiming(
          (double curveT) {
            userScaleFactor = startZoom + (targetZoom - startZoom) * curveT;
            _setOffsetLimits();
          },
          mounted: mounted,
          duration: cropRotateEditorConfigs.animationDuration,
          transitionFunction:
              cropRotateEditorConfigs.scaleAnimationCurve.transform,
        );

        startZoom = targetZoom;
        _setOffsetLimits();
        addHistory();
      },
      onUndoRedo: (bool undo) {
        if (undo) {
          undoAction();
        } else {
          redoAction();
        }
      },
    );
  }

  double _calculateStraightenScale(double straightenAngle) {
    if (straightenAngle == 0.0) return 1.0;

    final double absAngle = straightenAngle.abs();
    final double width = _viewRect.width;
    final double height = _viewRect.height;

    if (width == 0.0 || height == 0.0) return 1.0;

    final double cosAngle = cos(absAngle);
    final double sinAngle = sin(absAngle);

    final double boundingWidth = width * cosAngle + height * sinAngle;
    final double boundingHeight = width * sinAngle + height * cosAngle;

    final double scaleX = boundingWidth / width;
    final double scaleY = boundingHeight / height;

    return max(scaleX, scaleY);
  }

  void _fitToScreen() {
    setState(() {
      _imageNeedDecode = false;
    });

    _applyPerspectiveSolver();
  }

  /// Calculates and applies the optimal scale and translation bounds for the current 3D perspective.
  /// Solves iteratively to guarantee the image continuously covers the viewport polygon, mutating the internal state to clamp manual user interactions and prevent out-of-bounds rendering.
  void _applyPerspectiveSolver() {
    final Size imageSize = Size(
      _renderedImgConstraints.maxWidth,
      _renderedImgConstraints.maxHeight,
    );

    if (_viewRect.isEmpty || imageSize.isEmpty || imageSize.isInfinite) {
      return;
    }

    final bool isAutoScaled =
        (userScaleFactor - _perspectiveMinScale).abs() < 0.001;

    final Offset viewCenter = _viewRect.center;
    final Offset imageCenter = imageSize.center(Offset.zero);
    final Offset viewOffset = viewCenter - imageCenter;

    final double viewWidth = _viewRect.width;
    final double viewHeight = _viewRect.height;
    final double viewHalfWidth = viewWidth / 2.0;
    final double viewHalfHeight = viewHeight / 2.0;

    final List<vector_math.Vector2> viewportVertices = <vector_math.Vector2>[
      vector_math.Vector2(
          -viewHalfWidth + viewOffset.dx, -viewHalfHeight + viewOffset.dy),
      vector_math.Vector2(
          viewHalfWidth + viewOffset.dx, -viewHalfHeight + viewOffset.dy),
      vector_math.Vector2(
          viewHalfWidth + viewOffset.dx, viewHalfHeight + viewOffset.dy),
      vector_math.Vector2(
          -viewHalfWidth + viewOffset.dx, viewHalfHeight + viewOffset.dy),
    ];

    final Matrix4 perspectiveMatrix = _calculateStraightenAndPerspectiveMatrix(
      angle: straightenAngle,
      perspectiveX: perspectiveX,
      perspectiveY: perspectiveY,
    );

    final double m00 = perspectiveMatrix.storage[0];
    final double m10 = perspectiveMatrix.storage[1];
    final double m30 = perspectiveMatrix.storage[3];
    final double m01 = perspectiveMatrix.storage[4];
    final double m11 = perspectiveMatrix.storage[5];
    final double m31 = perspectiveMatrix.storage[7];

    double minP = double.infinity;
    double maxP = double.negativeInfinity;
    double minQ = double.infinity;
    double maxQ = double.negativeInfinity;

    bool wIsNegative = false;

    for (final v in viewportVertices) {
      final double u = v.x;
      final double y_v = v.y; // 'v' coordinate in (u,v)

      final double M11 = m00 - u * m30;
      final double M12 = m01 - u * m31;
      final double M21 = m10 - y_v * m30;
      final double M22 = m11 - y_v * m31;

      final double D = M11 * M22 - M12 * M21;
      if (D.abs() < 1e-6) {
        wIsNegative = true;
        break;
      }

      final double P = (M22 * u - M12 * y_v) / D;
      final double Q = (-M21 * u + M11 * y_v) / D;

      final double w = m30 * P + m31 * Q + 1.0;
      if (w <= 0.0001) {
        wIsNegative = true;
        break;
      }

      if (P < minP) minP = P;
      if (P > maxP) maxP = P;
      if (Q < minQ) minQ = Q;
      if (Q > maxQ) maxQ = Q;
    }

    double newMinimumScale = 0.01;

    if (!wIsNegative) {
      final double sMinX = (maxP - minP) / imageSize.width;
      final double sMinY = (maxQ - minQ) / imageSize.height;
      final double sMin = max(sMinX, sMinY);

      newMinimumScale = sMin / _straightenScale;
    } else {
      newMinimumScale = max(100.0, userScaleFactor);
    }

    setState(() {
      _perspectiveMinScale = newMinimumScale;

      if (!_interactionActive &&
          !_scaleStarted &&
          !scaleCtrl.isAnimating &&
          !_blockInteraction) {
        final double oldUserScale = userScaleFactor;
        final Offset oldTranslate = translate;

        if (isAutoScaled) {
          userScaleFactor = newMinimumScale;
        } else {
          if (userScaleFactor < newMinimumScale) {
            userScaleFactor = newMinimumScale;
          }
        }

        translate = _clampTranslateWithPerspective(
          proposedTranslate: translate,
          scale: userScaleFactor,
        );
      }
    });
  }

  Offset _clampTranslateWithPerspective({
    required Offset proposedTranslate,
    required double scale,
  }) {
    final Size imgSize = Size(
      _renderedImgConstraints.maxWidth,
      _renderedImgConstraints.maxHeight,
    );

    if (_viewRect.isEmpty || imgSize.isEmpty || imgSize.isInfinite) {
      return proposedTranslate;
    }

    final Offset viewCenter = _viewRect.center;
    final Offset imageCenter = imgSize.center(Offset.zero);
    final Offset viewOffset = viewCenter - imageCenter;

    final double imgHalfWidth = imgSize.width / 2.0;
    final double imgHalfHeight = imgSize.height / 2.0;

    final List<vector_math.Vector3> imgCorners = [
      vector_math.Vector3(-imgHalfWidth, -imgHalfHeight, 0.0),
      vector_math.Vector3(imgHalfWidth, -imgHalfHeight, 0.0),
      vector_math.Vector3(imgHalfWidth, imgHalfHeight, 0.0),
      vector_math.Vector3(-imgHalfWidth, imgHalfHeight, 0.0),
    ];

    final double viewWidth = _viewRect.width;
    final double viewHeight = _viewRect.height;
    final Polygon2 viewportPoly = Polygon2([
      vector_math.Vector2(
          -viewWidth / 2.0 + viewOffset.dx, -viewHeight / 2.0 + viewOffset.dy),
      vector_math.Vector2(
          viewWidth / 2.0 + viewOffset.dx, -viewHeight / 2.0 + viewOffset.dy),
      vector_math.Vector2(
          viewWidth / 2.0 + viewOffset.dx, viewHeight / 2.0 + viewOffset.dy),
      vector_math.Vector2(
          -viewWidth / 2.0 + viewOffset.dx, viewHeight / 2.0 + viewOffset.dy),
    ]);

    double currentScale = scale * _straightenScale;
    Offset currentTranslate = proposedTranslate;
    if (currentScale <= 0.0) currentScale = 1.0;

    final Matrix4 prMatrix = _calculateStraightenAndPerspectiveMatrix(
      angle: straightenAngle,
      perspectiveX: perspectiveX,
      perspectiveY: perspectiveY,
    );

    final double m30 = prMatrix.storage[3];
    final double m31 = prMatrix.storage[7];

    const double minW = 0.0101;
    for (int i = 0; i < 4; i++) {
      final vector_math.Vector3 v = imgCorners[i];
      final double currentW = m30 * (v.x + currentTranslate.dx) * currentScale +
          m31 * (v.y + currentTranslate.dy) * currentScale +
          1.0;

      if (currentW < minW) {
        final double Wdiff = minW - currentW;
        final double lenSq = m30 * m30 + m31 * m31;
        if (lenSq > 1e-6) {
          final double shiftK = Wdiff / (lenSq * currentScale);
          currentTranslate += Offset(m30 * shiftK, m31 * shiftK);
        }
      }
    }

    final Offset wClippedTranslate = currentTranslate;
    bool solverFailed = false;
    double prevCorrectionDist = double.infinity;

    for (int i = 0; i < 10; i++) {
      final Matrix4 iterationMatrix = _calculateStraightenAndPerspectiveMatrix(
        angle: straightenAngle,
        perspectiveX: perspectiveX,
        perspectiveY: perspectiveY,
      );

      final List<vector_math.Vector3> transformedCorners =
          imgCorners.map((vector_math.Vector3 v) {
        final vector_math.Vector3 vTranslated = v +
            vector_math.Vector3(currentTranslate.dx, currentTranslate.dy, 0.0);
        final vector_math.Vector3 vScaled = vTranslated * currentScale;

        return iterationMatrix.perspectiveTransform(vScaled);
      }).toList();

      final Quad2 imageQuad = Quad2(
        transformedCorners[0].vector2,
        transformedCorners[1].vector2,
        transformedCorners[2].vector2,
        transformedCorners[3].vector2,
      );

      final vector_math.Aabb2 resultAabb = FitPolygonInQuadSolver.solve(
          viewportPoly, imageQuad,
          enableResize: false);

      final Offset screenShift =
          (viewportPoly.boundingBox.center - resultAabb.center).offset;

      final double cosA = cos(straightenAngle);
      final double sinA = sin(straightenAngle);
      final double localDx = screenShift.dx * cosA - screenShift.dy * sinA;
      final double localDy = screenShift.dx * sinA + screenShift.dy * cosA;

      final Offset translateCorrection =
          Offset(localDx, localDy) / currentScale;

      if (translateCorrection.dx.isNaN || translateCorrection.dy.isNaN) {
        solverFailed = true;
        break;
      }

      final double corrDist = translateCorrection.distance;
      if (i > 0 && corrDist > prevCorrectionDist * 1.5 && corrDist > 1.0) {
        solverFailed = true;
        break;
      }
      prevCorrectionDist = corrDist;

      currentTranslate += translateCorrection;

      if (translateCorrection.distanceSquared < 0.01) {
        break;
      }
    }

    if (solverFailed) {
      return wClippedTranslate;
    }

    return currentTranslate;
  }

  void _setCropRectBounding({
    double? oldScaleAnimationValue,
  }) {
    if (cropRect.isEmpty) {
      return;
    }

    if (!_renderedImgSize.isInfinite) {
      bool fitToWidth =
          (cropRect.width + _cropSpaceHorizontal) > _renderedImgSize.width;

      bool fitToHeight =
          (cropRect.height + _cropSpaceVertical) > _renderedImgSize.height;

      final double ratio = cropRect.size.aspectRatio;

      if ((fitToWidth && fitToHeight) ||
          (!fitToHeight &&
              !fitToWidth &&
              cropRect.width < _renderedImgSize.width &&
              cropRect.height < _renderedImgSize.height)) {
        fitToHeight = ratio < editorBodySize.aspectRatio;
        fitToWidth = !fitToHeight;
      }

      if (!fitToWidth && !fitToHeight) return;

      final Size oldSize = cropRect.size;
      calcCropRect(newRatio: 1.0 / ratio);
      calcFitToScreen(animated: false);

      final double scaleFactor = fitToHeight
          ? cropRect.height / oldSize.height
          : cropRect.width / oldSize.width;

      translate = Offset(
        translate.dx * scaleFactor,
        translate.dy * scaleFactor,
      );

      if (translate.dx.isNaN || translate.dx.isInfinite) {
        throw ArgumentError('Hmmm');
      }

      _setOffsetLimits();
    }
  }

  Offset _getCropHandleHitOffset(Offset globalPosition) {
    if (cropPainterKey.currentContext == null) return Offset.zero;
    final RenderObject? renderObject =
        cropPainterKey.currentContext!.findRenderObject();
    if (renderObject is! RenderBox) return Offset.zero;

    final Offset localPos = renderObject.globalToLocal(globalPosition);
    final Offset center =
        Offset(renderObject.size.width / 2.0, renderObject.size.height / 2.0);
    return localPos - center;
  }

  CropAreaPart _determineCropAreaPart(Offset globalPosition) {
    final Offset offset = _getCropHandleHitOffset(globalPosition);

    final double dx = offset.dx;
    final double dy = offset.dy;

    if (cropMode == CropMode.oval) {
      final double halfWidth = cropRect.width / 2.0;
      final double halfHeight = cropRect.height / 2.0;
      final double halfInteractiveCornerArea = _interactiveCornerArea / 2.0;

      final double ellipseHitX = dx / (halfWidth + halfInteractiveCornerArea);
      final double ellipseHitY = dy / (halfHeight + halfInteractiveCornerArea);
      final bool isWithinHitArea =
          (ellipseHitX * ellipseHitX + ellipseHitY * ellipseHitY) <= 1.0;

      final double normalizedX = dx / (halfWidth - halfInteractiveCornerArea);
      final double normalizedY = dy / (halfHeight - halfInteractiveCornerArea);
      final bool isInsideEllipse =
          (normalizedX * normalizedX + normalizedY * normalizedY) <= 1.0;

      if (isWithinHitArea) {
        final double cursorAreaHitWidth = halfWidth * 0.5;
        final double cursorAreaHitHeight = halfHeight * 0.5;

        final bool nearTopEdge = dy < -cursorAreaHitHeight;
        final bool nearBottomEdge = dy > cursorAreaHitHeight;
        final bool nearLeftEdge = dx < -cursorAreaHitWidth;
        final bool nearRightEdge = dx > cursorAreaHitWidth;

        if (isInsideEllipse) return CropAreaPart.inside;
        if (nearBottomEdge && nearLeftEdge) return CropAreaPart.bottomLeft;
        if (nearBottomEdge && nearRightEdge) return CropAreaPart.bottomRight;
        if (nearTopEdge && nearLeftEdge) return CropAreaPart.topLeft;
        if (nearTopEdge && nearRightEdge) return CropAreaPart.topRight;
        if (nearBottomEdge) return CropAreaPart.bottom;
        if (nearTopEdge) return CropAreaPart.top;
        if (nearLeftEdge) return CropAreaPart.left;
        if (nearRightEdge) return CropAreaPart.right;

        return CropAreaPart.inside;
      } else {
        return CropAreaPart.none;
      }
    }

    final Rect rect = Rect.fromCenter(
      center: Offset.zero,
      width: cropRect.width + _interactiveCornerArea,
      height: cropRect.height + _interactiveCornerArea,
    );

    final double halfCropWidth = rect.width / 2.0;
    final double halfCropHeight = rect.height / 2.0;
    final double left = dx + halfCropWidth;
    final double right = dx - halfCropWidth;
    final double top = dy + halfCropHeight;
    final double bottom = dy - halfCropHeight;

    final bool nearLeftEdge = left.abs() <= _interactiveCornerArea;
    final bool nearRightEdge = right.abs() <= _interactiveCornerArea;
    final bool nearTopEdge = top.abs() <= _interactiveCornerArea;
    final bool nearBottomEdge = bottom.abs() <= _interactiveCornerArea;

    if (rect.contains(offset)) {
      if (nearLeftEdge && nearTopEdge) return CropAreaPart.topLeft;
      if (nearRightEdge && nearTopEdge) return CropAreaPart.topRight;
      if (nearLeftEdge && nearBottomEdge) return CropAreaPart.bottomLeft;
      if (nearRightEdge && nearBottomEdge) return CropAreaPart.bottomRight;
      if (nearLeftEdge) return CropAreaPart.left;
      if (nearRightEdge) return CropAreaPart.right;
      if (nearTopEdge) return CropAreaPart.top;
      if (nearBottomEdge) return CropAreaPart.bottom;
      return CropAreaPart.inside;
    } else {
      return CropAreaPart.none;
    }
  }

  void _zoomOutside() async {
    const int frameHelper = 1000 ~/ 60;

    while (userScaleFactor > _effectiveMinScale && _activeScaleOut) {
      final double oldZoom = userScaleFactor;
      const double zoomFactor = 0.025;
      userScaleFactor -= zoomFactor;
      userScaleFactor = max(_effectiveMinScale, userScaleFactor);

      final double zoomOutsideWidth =
          _viewRect.width / oldZoom * userScaleFactor;
      final double zoomOutsideHeight =
          _viewRect.height / oldZoom * userScaleFactor;
      double offsetHelperX = 0.0;
      double offsetHelperY = 0.0;

      if (_currentCropAreaPart == CropAreaPart.left ||
          _currentCropAreaPart == CropAreaPart.topLeft ||
          _currentCropAreaPart == CropAreaPart.bottomLeft ||
          _currentCropAreaPart == CropAreaPart.right ||
          _currentCropAreaPart == CropAreaPart.topRight ||
          _currentCropAreaPart == CropAreaPart.bottomRight) {
        offsetHelperX = zoomOutsideWidth - _viewRect.width;

        if (_currentCropAreaPart == CropAreaPart.right ||
            _currentCropAreaPart == CropAreaPart.topRight ||
            _currentCropAreaPart == CropAreaPart.bottomRight) {
          offsetHelperX *= -1.0;
        }
      }

      if (_currentCropAreaPart == CropAreaPart.top ||
          _currentCropAreaPart == CropAreaPart.topLeft ||
          _currentCropAreaPart == CropAreaPart.topRight ||
          _currentCropAreaPart == CropAreaPart.bottom ||
          _currentCropAreaPart == CropAreaPart.bottomLeft ||
          _currentCropAreaPart == CropAreaPart.bottomRight) {
        offsetHelperY = zoomOutsideHeight - _viewRect.height;

        if (_currentCropAreaPart == CropAreaPart.bottom ||
            _currentCropAreaPart == CropAreaPart.bottomLeft ||
            _currentCropAreaPart == CropAreaPart.bottomRight) {
          offsetHelperY *= -1.0;
        }
      }

      final Offset offsetHelper = Offset(offsetHelperX, offsetHelperY);
      translate -= offsetHelper / userScaleFactor / 2.0;

      calcCropRect();
      _setOffsetLimits();

      await Future.delayed(const Duration(milliseconds: frameHelper));
    }

    _activeScaleOut = false;
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (_blockInteraction || details.pointerCount > 2) return;
    _blockInteraction = true;
    _stopFlingAnimation();

    _editorScreenOffsetHelper = _calculateEditorScreenOffset();
    _scaleStart = userScaleFactor;
    _startingPinchScale = userScaleFactor;
    _startingTranslate = translate;
    _lastFocal = details.focalPoint;
    _lastScale = 1.0;

    if (!_scaleStarted) {
      if (!isDesktop) {
        _currentCropAreaPart = _determineCropAreaPart(details.focalPoint);
      }

      final bool isTouchingHandle = _currentCropAreaPart != CropAreaPart.none &&
          _currentCropAreaPart != CropAreaPart.inside;

      loopWithTransitionTiming(
        (double curveT) {
          _interactionOpacityProgress = 1.0 * curveT;
          _setCropPainter();
        },
        mounted: mounted,
        transitionFunction: Curves.decelerate.transform,
        duration: cropRotateEditorConfigs.opacityOutsideCropAreaDuration,
      );

      if (isTouchingHandle) {
        fadeOutBlur();
      }
    }

    _scaleAllowUpdateHelper = false;
    _onScaleAllowUpdateDebounce(() {
      _scaleAllowUpdateHelper = true;
    });

    _interactionActive = true;
    _scaleStarted = true;
    _blockInteraction = false;
  }

  Offset _calculateEditorScreenOffset() {
    if (_editorContentKey.currentContext == null) return Offset.zero;

    final RenderBox renderBox =
        _editorContentKey.currentContext!.findRenderObject() as RenderBox;
    final Offset position = renderBox.localToGlobal(Offset.zero);

    return position;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_blockInteraction ||
        details.pointerCount > 2 ||
        !_scaleAllowUpdateHelper) {
      return;
    }

    _blockInteraction = true;

    _gestureType ??=
        details.scale == 1.0 ? _GestureType.pan : _GestureType.scale;

    final bool isTouchingCropHandle =
        _currentCropAreaPart != CropAreaPart.none &&
            _currentCropAreaPart != CropAreaPart.inside;

    if (!isTouchingCropHandle) {
      bool handledPerspectiveOrStraighten = false;
      if (_isStraightenModeActive) {
        final Offset delta = details.focalPoint - _lastFocal;
        _lastFocal = details.focalPoint;

        final double distance = editorBodySize.width;
        double newAngle = straightenAngle + delta.dx / distance * pi / 1.5;

        // Limiting angle to +/- 45 degrees
        double maxAngle = pi / 4;
        newAngle = newAngle.clamp(-maxAngle, maxAngle);

        setStraightenAngle(newAngle);
        handledPerspectiveOrStraighten = true;
      }
      if (_isPerspectiveModeActive) {
        final Offset delta = details.focalPoint - _lastFocal;
        _lastFocal = details.focalPoint;

        final double distanceX = editorBodySize.width;
        final double distanceY = editorBodySize.height;

        double newX = perspectiveX + delta.dx / distanceX * pi / 1.5;
        double newY = perspectiveY + delta.dy / distanceY * pi / 1.5;

        // Limit angle to +/- 30 degrees
        double maxAngle = pi / 6;
        newX = newX.clamp(-maxAngle, maxAngle);
        newY = newY.clamp(-maxAngle, maxAngle);

        setPerspective(newX, newY);
        handledPerspectiveOrStraighten = true;
      }

      if (handledPerspectiveOrStraighten) return;
    }

    if (details.pointerCount == 2) {
      final double desiredScale = _scaleStart! * details.scale;

      double newZoom =
          _applyScaleChange(desiredScale / userScaleFactor) * userScaleFactor;

      if (newZoom < 0.01) newZoom = 0.01;

      final Offset center =
          Offset(editorBodySize.width / 2.0, editorBodySize.height / 2.0);
      final Offset focalNewLocal =
          details.focalPoint - _editorScreenOffsetHelper;
      final Offset focalOldLocal = _lastFocal - _editorScreenOffsetHelper;

      final Offset panDelta = (focalNewLocal - focalOldLocal) / newZoom;
      final Offset zoomDelta =
          (focalOldLocal - center) * (1.0 / newZoom - 1.0 / userScaleFactor);

      translate += zoomDelta;

      translate += _getPhysicsAppliedDelta(panDelta);

      userScaleFactor = newZoom;
      _lastFocal = details.focalPoint;

      cropRotateEditorCallbacks?.handleScale();
      _updateCropPainter();
    } else {
      if (_currentCropAreaPart != CropAreaPart.none &&
          _currentCropAreaPart != CropAreaPart.inside) {
        final Offset offset = _getCropHandleHitOffset(details.focalPoint);

        final double imgW = _renderedImgConstraints.maxWidth;
        final double imgH = _renderedImgConstraints.maxHeight;

        final double halfSpaceHorizontal = _cropSpaceHorizontal / 2.0;
        final double halfSpaceVertical = _cropSpaceVertical / 2.0;

        final EdgeInsets margin = cropRotateEditorConfigs.viewPadding ??
            cropRotateEditorConfigs.boundaryMargin;
        final double cornerGap =
            cropRotateEditorConfigs.style.cropCornerLength * 2.25;
        final double minCornerDistance = cornerGap;

        final double halfViewRectW = _viewRect.width / 2.0;
        final double halfViewRectH = _viewRect.height / 2.0;
        double circleGapX = 0.0;
        double circleGapY = 0.0;

        if (cropMode == CropMode.oval) {
          circleGapX = sqrt(pow(halfViewRectW, 2.0) -
                  pow(min(offset.dy.abs(), halfViewRectW), 2.0)) -
              halfViewRectW;

          circleGapY = sqrt(pow(halfViewRectH, 2.0) -
                  pow(min(offset.dx.abs(), halfViewRectH), 2.0)) -
              halfViewRectH;

          circleGapX *= -offset.dx.sign;
          circleGapY *= -offset.dy.sign;
        }

        final double dx =
            offset.dx + halfViewRectW + halfSpaceHorizontal + circleGapX;
        final double dy =
            offset.dy + halfViewRectH + halfSpaceVertical + circleGapY;

        final double maxRight = cropRect.right - minCornerDistance;
        final double maxBottom = cropRect.bottom - minCornerDistance;
        double minLeft = halfSpaceHorizontal;
        double minRight = imgW - halfSpaceHorizontal;
        double minTop = halfSpaceVertical;
        double minBottom = imgH - halfSpaceVertical;

        final bool isFreeAspectRatio = _ratio < 0.0;

        if (isFreeAspectRatio) {
          minLeft = -(imgW * userScaleFactor / 2.0 -
              _viewRect.width / 2.0 -
              halfSpaceHorizontal -
              translate.dx * userScaleFactor);

          minRight = imgW +
              (imgW * userScaleFactor / 2.0 -
                  _viewRect.width / 2.0 -
                  halfSpaceHorizontal +
                  translate.dx * userScaleFactor);

          minTop = -(imgH * userScaleFactor / 2.0 -
              _viewRect.height / 2.0 -
              halfSpaceVertical -
              translate.dy * userScaleFactor);

          minBottom = imgH +
              (imgH * userScaleFactor / 2.0 -
                  _viewRect.height / 2.0 -
                  halfSpaceVertical +
                  translate.dy * userScaleFactor);
        }

        final EdgeInsets dragMargin = cropRotateEditorConfigs.viewPadding ??
            cropRotateEditorConfigs.boundaryMargin;

        // Convert viewPadding (global screen insets) to crop-local coords.
        // Since dy/dx and focalPoint go through the same globalToLocal
        // transform, the transform mostly cancels out. However, the
        // cropPainter sits inside Transform.scale(scaleAnimation.value),
        // so we must divide by scaleAnimation.value to match the local
        // coordinate scale.
        final Size screenSize = MediaQuery.sizeOf(context);
        final double scale = scaleAnimation.value;
        final double dyBase = dy - circleGapY;
        final double dxBase = dx - circleGapX;

        final double vpTop =
            dyBase + (dragMargin.top - details.focalPoint.dy) / scale;
        final double vpBottom = dyBase +
            (screenSize.height - dragMargin.bottom - details.focalPoint.dy) /
                scale;
        final double vpLeft =
            dxBase + (dragMargin.left - details.focalPoint.dx) / scale;
        final double vpRight = dxBase +
            (screenSize.width - dragMargin.right - details.focalPoint.dx) /
                scale;

        minTop = max(minTop, vpTop);
        minBottom = min(minBottom, vpBottom);
        minLeft = max(minLeft, vpLeft);
        minRight = min(minRight, vpRight);

        Size realViewRectSize = _viewRect.size * scaleAnimation.value;

        if (_rotated90deg) {
          realViewRectSize =
              Size(realViewRectSize.height, realViewRectSize.width);
        }

        final double doubleInteractiveArea = _interactiveCornerArea * 2.0;

        final double zoomOutHitAreaX = max(
            margin.left / 2.0,
            (editorBodySize.width - realViewRectSize.width) / 2.0 -
                doubleInteractiveArea);

        final double zoomOutHitAreaY = max(
            margin.top / 2.0,
            (editorBodySize.height - realViewRectSize.height) / 2.0 -
                doubleInteractiveArea);

        final double outsideHitPosY = details.focalPoint.dy -
            _editorScreenOffsetHelper.dy -
            (_hasToolbar ? kToolbarHeight : 0.0) -
            MediaQuery.paddingOf(context).top;

        final bool outsideLeft =
            details.focalPoint.dx - _editorScreenOffsetHelper.dx <
                zoomOutHitAreaX;

        final bool outsideRight =
            details.focalPoint.dx - _editorScreenOffsetHelper.dx >
                editorBodySize.width - zoomOutHitAreaX;

        final bool outsideTop = outsideHitPosY < zoomOutHitAreaY;
        final bool outsideBottom =
            outsideHitPosY > editorBodySize.height - zoomOutHitAreaY;

        if (!isFreeAspectRatio &&
            !_hasPerspective &&
            userScaleFactor <= _effectiveMinScale &&
            (outsideLeft || outsideRight || outsideTop || outsideBottom)) {
          if (!_activeScaleOut) {
            _activeScaleOut = true;
            _zoomOutside();
          }
        } else {
          if (_activeScaleOut) {
            _activeScaleOut = false;
          }
        }

        if (!_activeScaleOut || _currentCropAreaPart != CropAreaPart.inside) {
          switch (_currentCropAreaPart) {
            case CropAreaPart.topLeft:
              cropRect = Rect.fromLTRB(
                dx.safeMinClamp(minLeft, maxRight),
                dy.safeMinClamp(minTop, maxBottom),
                cropRect.right,
                cropRect.bottom,
              );
              break;

            case CropAreaPart.topRight:
              cropRect = Rect.fromLTRB(
                cropRect.left,
                dy.safeMinClamp(minTop, maxBottom),
                dx.safeMinClamp(cornerGap + cropRect.left, minRight),
                cropRect.bottom,
              );
              break;

            case CropAreaPart.bottomLeft:
              cropRect = Rect.fromLTRB(
                dx.safeMinClamp(minLeft, maxRight),
                cropRect.top,
                cropRect.right,
                dy.safeMinClamp(cornerGap + cropRect.top, minBottom),
              );
              break;

            case CropAreaPart.bottomRight:
              cropRect = Rect.fromLTRB(
                cropRect.left,
                cropRect.top,
                dx.safeMinClamp(cornerGap + cropRect.left, minRight),
                dy.safeMinClamp(cornerGap + cropRect.top, minBottom),
              );
              break;

            case CropAreaPart.left:
              cropRect = Rect.fromLTRB(
                dx.safeMinClamp(minLeft, maxRight),
                cropRect.top,
                cropRect.right,
                cropRect.bottom,
              );
              _setOffsetLimits();
              break;

            case CropAreaPart.right:
              cropRect = Rect.fromLTRB(
                cropRect.left,
                cropRect.top,
                dx.safeMinClamp(cornerGap + cropRect.left, minRight),
                cropRect.bottom,
              );
              break;

            case CropAreaPart.top:
              cropRect = Rect.fromLTRB(
                cropRect.left,
                dy.safeMaxClamp(minTop, maxBottom),
                cropRect.right,
                cropRect.bottom,
              );
              break;

            case CropAreaPart.bottom:
              cropRect = Rect.fromLTRB(
                cropRect.left,
                cropRect.top,
                cropRect.right,
                dy.safeMinClamp(cornerGap + cropRect.top, minBottom),
              );
              break;

            default:
              break;
          }

          double targetRatio = _ratio;

          if (isFreeAspectRatio) {
            final double currentRectRatio = cropRect.size.aspectRatio;
            if (cropRotateEditorConfigs.minAspectRatio != null &&
                currentRectRatio < cropRotateEditorConfigs.minAspectRatio!) {
              targetRatio = 1.0 / cropRotateEditorConfigs.minAspectRatio!;
            } else if (cropRotateEditorConfigs.maxAspectRatio != null &&
                currentRectRatio > cropRotateEditorConfigs.maxAspectRatio!) {
              targetRatio = 1.0 / cropRotateEditorConfigs.maxAspectRatio!;
            }
          }

          if (targetRatio >= 0.0 && cropRect.size.aspectRatio != targetRatio) {
            if (_currentCropAreaPart == CropAreaPart.left ||
                _currentCropAreaPart == CropAreaPart.right) {
              double newWidth = cropRect.width;
              double newHeight = newWidth * targetRatio;

              double maxDistTop = cropRect.center.dy - minTop;
              double maxDistBottom = minBottom - cropRect.center.dy;
              double maxAllowedHeight = 2.0 * min(maxDistTop, maxDistBottom);

              if (newHeight > maxAllowedHeight) {
                newHeight = maxAllowedHeight;
                newWidth = newHeight / targetRatio;
              }

              if (_currentCropAreaPart == CropAreaPart.left) {
                cropRect = Rect.fromLTRB(
                  cropRect.right - newWidth,
                  cropRect.center.dy - newHeight / 2.0,
                  cropRect.right,
                  cropRect.center.dy + newHeight / 2.0,
                );
              } else {
                cropRect = Rect.fromLTRB(
                  cropRect.left,
                  cropRect.center.dy - newHeight / 2.0,
                  cropRect.left + newWidth,
                  cropRect.center.dy + newHeight / 2.0,
                );
              }
            } else if (_currentCropAreaPart == CropAreaPart.top ||
                _currentCropAreaPart == CropAreaPart.bottom) {
              double newHeight = cropRect.height;
              double newWidth = newHeight / targetRatio;

              double maxDistLeft = cropRect.center.dx - minLeft;
              double maxDistRight = minRight - cropRect.center.dx;
              double maxAllowedWidth = 2.0 * min(maxDistLeft, maxDistRight);

              if (newWidth > maxAllowedWidth) {
                newWidth = maxAllowedWidth;
                newHeight = newWidth * targetRatio;
              }

              if (_currentCropAreaPart == CropAreaPart.top) {
                cropRect = Rect.fromLTRB(
                  cropRect.center.dx - newWidth / 2.0,
                  cropRect.bottom - newHeight,
                  cropRect.center.dx + newWidth / 2.0,
                  cropRect.bottom,
                );
              } else {
                cropRect = Rect.fromLTRB(
                  cropRect.center.dx - newWidth / 2.0,
                  cropRect.top,
                  cropRect.center.dx + newWidth / 2.0,
                  cropRect.top + newHeight,
                );
              }
            } else if (_currentCropAreaPart == CropAreaPart.topLeft ||
                _currentCropAreaPart == CropAreaPart.topRight ||
                _currentCropAreaPart == CropAreaPart.bottomLeft ||
                _currentCropAreaPart == CropAreaPart.bottomRight) {
              double newWidth =
                  (cropRect.width + cropRect.height / targetRatio) / 2.0;

              if (_currentCropAreaPart == CropAreaPart.topLeft) {
                double maxWidth = cropRect.right - minLeft;
                double maxHeight = cropRect.bottom - minTop;
                if (newWidth > maxWidth) newWidth = maxWidth;
                if (newWidth * targetRatio > maxHeight) {
                  newWidth = maxHeight / targetRatio;
                }
                double newHeight = newWidth * targetRatio;

                cropRect = Rect.fromLTRB(
                  cropRect.right - newWidth,
                  cropRect.bottom - newHeight,
                  cropRect.right,
                  cropRect.bottom,
                );
              } else if (_currentCropAreaPart == CropAreaPart.topRight) {
                double maxWidth = minRight - cropRect.left;
                double maxHeight = cropRect.bottom - minTop;
                if (newWidth > maxWidth) newWidth = maxWidth;
                if (newWidth * targetRatio > maxHeight) {
                  newWidth = maxHeight / targetRatio;
                }
                double newHeight = newWidth * targetRatio;

                cropRect = Rect.fromLTRB(
                  cropRect.left,
                  cropRect.bottom - newHeight,
                  cropRect.left + newWidth,
                  cropRect.bottom,
                );
              } else if (_currentCropAreaPart == CropAreaPart.bottomLeft) {
                double maxWidth = cropRect.right - minLeft;
                double maxHeight = minBottom - cropRect.top;
                if (newWidth > maxWidth) newWidth = maxWidth;
                if (newWidth * targetRatio > maxHeight) {
                  newWidth = maxHeight / targetRatio;
                }
                double newHeight = newWidth * targetRatio;

                cropRect = Rect.fromLTRB(
                  cropRect.right - newWidth,
                  cropRect.top,
                  cropRect.right,
                  cropRect.top + newHeight,
                );
              } else if (_currentCropAreaPart == CropAreaPart.bottomRight) {
                double maxWidth = minRight - cropRect.left;
                double maxHeight = minBottom - cropRect.top;
                if (newWidth > maxWidth) newWidth = maxWidth;
                if (newWidth * targetRatio > maxHeight) {
                  newWidth = maxHeight / targetRatio;
                }
                double newHeight = newWidth * targetRatio;

                cropRect = Rect.fromLTRB(
                  cropRect.left,
                  cropRect.top,
                  cropRect.left + newWidth,
                  cropRect.top + newHeight,
                );
              }
            }
          }
        }

        _updateCropPainter();
      } else {
        final double scaleFactor = userScaleFactor / _scaleStartZoomHelper;

        final Offset delta =
            Offset(details.focalPointDelta.dx, details.focalPointDelta.dy) /
                scaleFactor *
                (cropRotateEditorConfigs.invertDragDirection ? -1.0 : 1.0);

        final Offset physicsDelta = _getPhysicsAppliedDelta(delta);
        translate += physicsDelta;

        cropRotateEditorCallbacks?.handleMove();
        _updateCropPainter();
      }
    }

    _blockInteraction = false;
  }

  Offset _getPhysicsAppliedDelta(Offset panDelta) {
    final Offset currentOffset = translate * -1.0;
    final ScrollMetrics metricsX =
        _calculateScrollMetrics(currentOffset.dx, AxisDirection.right);
    final ScrollMetrics metricsY =
        _calculateScrollMetrics(currentOffset.dy, AxisDirection.down);

    final double proposedX = currentOffset.dx - panDelta.dx;
    final double proposedY = currentOffset.dy - panDelta.dy;

    final double overscrollX = panDelta.dx == 0.0
        ? 0.0
        : cropRotateEditorConfigs.scrollPhysics
            .applyBoundaryConditions(metricsX, proposedX);

    final double overscrollY = panDelta.dy == 0.0
        ? 0.0
        : cropRotateEditorConfigs.scrollPhysics
            .applyBoundaryConditions(metricsY, proposedY);

    if (overscrollX == 0.0 && overscrollY == 0.0) {
      final double dx = panDelta.dx == 0.0
          ? 0.0
          : cropRotateEditorConfigs.scrollPhysics
              .applyPhysicsToUserOffset(metricsX, panDelta.dx);

      final double dy = panDelta.dy == 0.0
          ? 0.0
          : cropRotateEditorConfigs.scrollPhysics
              .applyPhysicsToUserOffset(metricsY, panDelta.dy);

      return Offset(dx, dy);
    } else {
      return Offset(panDelta.dx + overscrollX, panDelta.dy + overscrollY);
    }
  }

  double _applyScaleChange(double scale) {
    final double currentScale = userScaleFactor;
    final double scaleChange = scale;
    final double desiredScale = currentScale * scale;
    final double effectiveMaxScale = _effectiveMaxScale;

    if (!_shouldAllowScale(desiredScale)) {
      final double clampedTotalScale =
          clampDouble(desiredScale, _effectiveMinScale, effectiveMaxScale);
      final double clampedScale = clampedTotalScale / currentScale;
      return clampedScale;
    }

    final double scaleRatio = scaleChange / _lastScale;
    _lastScale = scaleChange;
    final double incrementalScale = currentScale * scaleRatio;

    if (((desiredScale < _effectiveMinScale) ||
        (desiredScale > effectiveMaxScale))) {
      final Size contentSize = _renderedImgConstraints.biggest;

      final double contentWidth = contentSize.width * currentScale;
      final double desiredContentWidth = contentSize.width * incrementalScale;
      final double contentHeight = contentSize.height * currentScale;
      final double desiredContentHeight = contentSize.height * incrementalScale;

      final ScrollMetrics metricsX = FixedScrollMetrics(
        pixels: contentWidth,
        minScrollExtent: contentSize.width * _effectiveMinScale,
        maxScrollExtent: contentSize.width * effectiveMaxScale,
        viewportDimension: contentSize.width * effectiveMaxScale,
        axisDirection: AxisDirection.right,
        devicePixelRatio: 1.0,
      );

      final ScrollMetrics metricsY = FixedScrollMetrics(
        pixels: contentHeight,
        minScrollExtent: contentSize.height * _effectiveMinScale,
        maxScrollExtent: contentSize.height * effectiveMaxScale,
        viewportDimension: contentSize.height * effectiveMaxScale,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 1.0,
      );

      final double deltaX = desiredContentWidth - contentWidth;
      final double deltaY = desiredContentHeight - contentHeight;

      final double adjustedX = cropRotateEditorConfigs.scrollPhysics
              .applyPhysicsToUserOffset(metricsX, deltaX / 2.0) *
          2.0;

      final double adjustedY = cropRotateEditorConfigs.scrollPhysics
              .applyPhysicsToUserOffset(metricsY, deltaY / 2.0) *
          2.0;

      final double newScaleX = (contentWidth + adjustedX) / contentWidth;
      final double newScaleY = (contentHeight + adjustedY) / contentHeight;
      final double factor = (newScaleX + newScaleY) / 2.0;

      return factor;
    } else {
      final double clampedTotalScale =
          clampDouble(desiredScale, 1.0, effectiveMaxScale);

      final double clampedScale = clampedTotalScale / currentScale;
      return clampedScale;
    }
  }

  bool _shouldAllowScale(double proposedScale) {
    final Size contentSize = _renderedImgConstraints.biggest;
    final double currentScale = userScaleFactor;

    final double contentWidth = contentSize.width * currentScale;
    final double desiredContentWidth = contentSize.width * proposedScale;
    final double contentHeight = contentSize.height * currentScale;
    final double desiredContentHeight = contentSize.height * proposedScale;

    final double effectiveMaxScale = _effectiveMaxScale;

    final ScrollMetrics metricsX = FixedScrollMetrics(
      pixels: contentWidth,
      minScrollExtent: contentSize.width * _effectiveMinScale,
      maxScrollExtent: contentSize.width * effectiveMaxScale,
      viewportDimension: _viewRect.width,
      axisDirection: AxisDirection.right,
      devicePixelRatio: 1.0,
    );

    final ScrollMetrics metricsY = FixedScrollMetrics(
      pixels: contentHeight,
      minScrollExtent: contentSize.height * _effectiveMinScale,
      maxScrollExtent: contentSize.height * effectiveMaxScale,
      viewportDimension: _viewRect.height,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1.0,
    );

    final double adjustmentX = cropRotateEditorConfigs.scrollPhysics
        .applyBoundaryConditions(metricsX, desiredContentWidth);

    final double adjustmentY = cropRotateEditorConfigs.scrollPhysics
        .applyBoundaryConditions(metricsY, desiredContentHeight);

    return adjustmentX == 0.0 && adjustmentY == 0.0;
  }

  void _handleCombinedAnimation() {
    if (!_flingCtrl.isAnimating) {
      _flingCtrl.removeListener(_handleCombinedAnimation);
      return;
    }

    final double t = _flingCtrl.lastElapsedDuration!.inMilliseconds / 1000.0;
    final double x = _simulationX?.x(t) ?? translate.dx * -1.0;
    final double y = _simulationY?.x(t) ?? translate.dy * -1.0;

    translate = Offset(-x, -y);

    if (_simulationScale != null) {
      final double simulatedScrollPos = _simulationScale!.x(t);
      final double scale = simulatedScrollPos / 1000.0;
      userScaleFactor = scale;
    }
    _updateCropPainter();
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_blockInteraction) return;
    _blockInteraction = true;
    _interactionActive = false;

    _onScaleEndDebounce(() {
      if (_activePointers <= 0) {
        _scaleStarted = false;

        if (cropRect == _viewRect) {
          loopWithTransitionTiming(
            (double curveT) {
              _interactionOpacityProgress = 1.0 - 1.0 * curveT;
              _setCropPainter();
            },
            mounted: mounted,
            duration: cropRotateEditorConfigs.opacityOutsideCropAreaDuration,
          );
          if (_isAdjustmentBlurActive) fadeInBlur();
        }
      }
    });

    _activeScaleOut = false;

    if (cropRect != _viewRect) {
      Rect interpolatedRect(Rect initRect, Rect targetRect, double curveT) {
        return Rect.fromLTRB(
          ui.lerpDouble(initRect.left, targetRect.left, curveT)!,
          ui.lerpDouble(initRect.top, targetRect.top, curveT)!,
          ui.lerpDouble(initRect.right, targetRect.right, curveT)!,
          ui.lerpDouble(initRect.bottom, targetRect.bottom, curveT)!,
        );
      }

      if (cropRect.isEmpty) {
        _blockInteraction = false;
        return;
      }

      final Rect initRect = Rect.fromCenter(
          center: _viewRect.center,
          width: _viewRect.width,
          height: _viewRect.height);

      final Duration animationDuration =
          cropRotateEditorConfigs.cropDragAnimationDuration;

      final Curve animationCurve =
          cropRotateEditorConfigs.cropDragAnimationCurve;

      if (_ratio < 0.0) {
        calcCropRect(
          onlyViewRect: true,
          newRatio: 1.0 / cropRect.size.aspectRatio,
        );
      }

      final Rect startCropRect = cropRect;
      final Rect targetCropRect = _viewRect;
      final double startZoom = userScaleFactor;

      final Offset C = Offset(
        _renderedImgConstraints.maxWidth / 2.0,
        _renderedImgConstraints.maxHeight / 2.0,
      );

      final Matrix4 perspectiveMatrix =
          _calculateStraightenAndPerspectiveMatrix(
        angle: straightenAngle,
        perspectiveX: perspectiveX,
        perspectiveY: perspectiveY,
      );

      final Matrix4 inversePerspective =
          Matrix4.tryInvert(perspectiveMatrix) ?? Matrix4.identity();

      Offset unprojectPoint(Offset p) {
        final vector_math.Vector3 p3 =
            vector_math.Vector3(p.dx - C.dx, p.dy - C.dy, 0.0);
        final vector_math.Vector3 unp =
            inversePerspective.perspectiveTransform(p3);
        return Offset(unp.x, unp.y);
      }

      double getUnprojectedWidth(Rect rect) {
        final Offset topLeft = unprojectPoint(rect.topLeft);
        final Offset topRight = unprojectPoint(rect.topRight);
        final Offset bottomLeft = unprojectPoint(rect.bottomLeft);
        final Offset bottomRight = unprojectPoint(rect.bottomRight);
        final double topW = (topRight - topLeft).distance;
        final double bottomW = (bottomRight - bottomLeft).distance;
        return max(topW, bottomW);
      }

      double getUnprojectedHeight(Rect rect) {
        final Offset topLeft = unprojectPoint(rect.topLeft);
        final Offset topRight = unprojectPoint(rect.topRight);
        final Offset bottomLeft = unprojectPoint(rect.bottomLeft);
        final Offset bottomRight = unprojectPoint(rect.bottomRight);
        final double leftH = (bottomLeft - topLeft).distance;
        final double rightH = (bottomRight - topRight).distance;
        return max(leftH, rightH);
      }

      final double unpStartW = getUnprojectedWidth(startCropRect);
      final double unpStartH = getUnprojectedHeight(startCropRect);
      final double unpTargetW = getUnprojectedWidth(targetCropRect);
      final double unpTargetH = getUnprojectedHeight(targetCropRect);

      final double scaleRatio = max(
        unpTargetW / max(1.0, unpStartW),
        unpTargetH / max(1.0, unpStartH),
      );

      final double targetZoom = max(
        _perspectiveMinScale,
        min(
          startZoom * scaleRatio,
          cropRotateEditorConfigs.maxScale,
        ),
      );

      final Offset startOffset = translate;
      final Offset startCenterUnp = unprojectPoint(startCropRect.center);
      final Offset targetCenterUnp = unprojectPoint(targetCropRect.center);

      final Offset unclampedTargetOffset = startOffset +
          targetCenterUnp / (_straightenScale * targetZoom) -
          startCenterUnp / (_straightenScale * startZoom);

      final Offset targetOffset = _clampTranslateWithPerspective(
        proposedTranslate: unclampedTargetOffset,
        scale: targetZoom,
      );

      final Offset clampDelta = targetOffset - unclampedTargetOffset;

      Future.delayed(cropRotateEditorConfigs.cropDragOutOfBoundsDelay, () {
        if (!mounted) return;

        loopWithTransitionTiming(
          (double curveT) {
            _interactionOpacityProgress = 1.0 - 1.0 * curveT;
            _blurInteractionOpacity = 1.0 - 1.0 * curveT;
            userScaleFactor = ui.lerpDouble(startZoom, targetZoom, curveT)!;
            cropRect = interpolatedRect(startCropRect, targetCropRect, curveT);

            // Force the translation to map directly to the unprojected crop box focal point at this exact frame, eliminating drift.
            final Offset currentCenterUnp = unprojectPoint(cropRect.center);
            final Offset unclampedTranslate = startOffset +
                currentCenterUnp / (_straightenScale * userScaleFactor) -
                startCenterUnp / (_straightenScale * startZoom);

            translate = unclampedTranslate + clampDelta * curveT;

            _setCropPainter();
          },
          mounted: mounted,
          duration: animationDuration,
          transitionFunction: animationCurve.transform,
        ).whenComplete(() {
          cropRect = targetCropRect;
          translate = targetOffset;
          userScaleFactor = targetZoom;

          _setOffsetLimits();
          cropRotateEditorCallbacks?.handleResize();
          addHistory();
          _blockInteraction = false;
          _isAdjustmentBlurActive = false;
        });
      });

      return;
    }

    addHistory();

    if (details.pointerCount <= 0) {
      _stopAllAnimations();
      _invalidatePerspectiveBoundsCache();
      addHistory();

      final double minScale = _effectiveMinScale;
      final double maxScale = _effectiveMaxScale;

      final ScrollMetrics scaleMetrics = FixedScrollMetrics(
        pixels: userScaleFactor * 1000.0,
        minScrollExtent: minScale * 1000.0,
        maxScrollExtent: maxScale * 1000.0,
        viewportDimension: 0.0,
        axisDirection: AxisDirection.down,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      );

      _simulationScale = cropRotateEditorConfigs.scrollPhysics
          .createBallisticSimulation(scaleMetrics, 0.0);

      final Offset adjustedOffset = translate * -1.0;
      final double targetScale =
          userScaleFactor.clamp(_effectiveMinScale, maxScale);
      final double currentScale = userScaleFactor;

      final double flingVelocityX = min(
              (details.velocity.pixelsPerSecond.dx / currentScale).abs(),
              cropRotateEditorConfigs.scrollPhysics.maxFlingVelocity) *
          details.velocity.pixelsPerSecond.dx.sign;

      final double flingVelocityY = min(
              (details.velocity.pixelsPerSecond.dy / currentScale).abs(),
              cropRotateEditorConfigs.scrollPhysics.maxFlingVelocity) *
          details.velocity.pixelsPerSecond.dy.sign;

      final ScrollMetrics metricsX = _calculateScrollMetrics(
          adjustedOffset.dx, AxisDirection.right,
          scale: targetScale);
      final ScrollMetrics metricsY = _calculateScrollMetrics(
          adjustedOffset.dy, AxisDirection.down,
          scale: targetScale);

      _simulationX = cropRotateEditorConfigs.scrollPhysics
          .createBallisticSimulation(metricsX, -flingVelocityX);

      _simulationY = cropRotateEditorConfigs.scrollPhysics
          .createBallisticSimulation(metricsY, -flingVelocityY);

      _combinedSimulation = _getCombinedSimulation(
        _simulationX,
        _simulationY,
        _simulationScale,
      );

      final bool isScaleInBounds = (userScaleFactor - targetScale).abs() < 0.01;

      if (_combinedSimulation == null && isScaleInBounds) {
        _interactionActive = false;
        _blockInteraction = false;
        return;
      }

      _flingCtrl
        ..reset()
        ..addListener(_handleCombinedAnimation);

      if (_combinedSimulation != null) {
        _flingCtrl.animateWith(_combinedSimulation!);
      } else {
        _flingCtrl.duration = const Duration(milliseconds: 250);
        _flingCtrl.forward();
      }

      _flingCtrl.addStatusListener((AnimationStatus status) {
        if (status == AnimationStatus.completed ||
            status == AnimationStatus.dismissed) {
          _interactionActive = false;
          _blockInteraction = false;
        }
      });
    } else {
      _interactionActive = false;
    }

    _blockInteraction = false;
  }

  void _stopAllAnimations() {
    _flingCtrl.stop();
  }

  Offset _getMaxOffset(double scale, {Rect? viewRect}) {
    final Rect r = viewRect ?? _viewRect;

    final double straightenScale = _straightenScale;

    final double cosAngle = cos(straightenAngle);
    final double sinAngle = sin(straightenAngle);

    final double rotatedWidth =
        r.width * cosAngle.abs() + r.height * sinAngle.abs();
    final double rotatedHeight =
        r.width * sinAngle.abs() + r.height * cosAngle.abs();

    final double effectiveCropWidth = rotatedWidth / straightenScale;
    final double effectiveCropHeight = rotatedHeight / straightenScale;

    return Offset(
      (_renderedImgConstraints.maxWidth * scale - effectiveCropWidth) /
          2.0 /
          scale,
      (_renderedImgConstraints.maxHeight * scale - effectiveCropHeight) /
          2.0 /
          scale,
    );
  }

  Rect _panBoundaries(double scale) {
    final Offset linearMax = _getMaxOffset(scale);

    if (straightenAngle == 0.0 && perspectiveX == 0.0 && perspectiveY == 0.0) {
      return Rect.fromLTRB(
        -max(0.0, linearMax.dx),
        -max(0.0, linearMax.dy),
        max(0.0, linearMax.dx),
        max(0.0, linearMax.dy),
      );
    }

    final Size imgSize = Size(
      _renderedImgConstraints.maxWidth,
      _renderedImgConstraints.maxHeight,
    );
    final Offset viewCenter = _viewRect.center;
    final Offset imageCenter = imgSize.center(Offset.zero);
    final Offset viewOffset = viewCenter - imageCenter;

    final double imgHalfWidth = imgSize.width / 2.0;
    final double imgHalfHeight = imgSize.height / 2.0;

    final List<vector_math.Vector3> imgCorners = [
      vector_math.Vector3(-imgHalfWidth, -imgHalfHeight, 0.0),
      vector_math.Vector3(imgHalfWidth, -imgHalfHeight, 0.0),
      vector_math.Vector3(imgHalfWidth, imgHalfHeight, 0.0),
      vector_math.Vector3(-imgHalfWidth, imgHalfHeight, 0.0),
    ];

    final double viewWidth = _viewRect.width;
    final double viewHeight = _viewRect.height;
    final Polygon2 viewportPoly = Polygon2([
      vector_math.Vector2(
          -viewWidth / 2.0 + viewOffset.dx, -viewHeight / 2.0 + viewOffset.dy),
      vector_math.Vector2(
          viewWidth / 2.0 + viewOffset.dx, -viewHeight / 2.0 + viewOffset.dy),
      vector_math.Vector2(
          viewWidth / 2.0 + viewOffset.dx, viewHeight / 2.0 + viewOffset.dy),
      vector_math.Vector2(
          -viewWidth / 2.0 + viewOffset.dx, viewHeight / 2.0 + viewOffset.dy),
    ]);

    double currentScale = scale * _straightenScale;
    if (currentScale <= 0.0) currentScale = 1.0;

    final Matrix4 prMatrix = _calculateStraightenAndPerspectiveMatrix(
      angle: straightenAngle,
      perspectiveX: perspectiveX,
      perspectiveY: perspectiveY,
    );

    final double m30 = prMatrix.storage[3];
    final double m31 = prMatrix.storage[7];

    bool isValid(Offset testTranslate) {
      for (int i = 0; i < 4; i++) {
        final vector_math.Vector3 v = imgCorners[i];
        final double currentW = m30 * (v.x + testTranslate.dx) * currentScale +
            m31 * (v.y + testTranslate.dy) * currentScale +
            1.0;
        if (currentW < 0.0101) {
          return false;
        }
      }

      final List<vector_math.Vector3> transformedCorners =
          imgCorners.map((vector_math.Vector3 v) {
        final vector_math.Vector3 vTranslated =
            v + vector_math.Vector3(testTranslate.dx, testTranslate.dy, 0.0);
        final vector_math.Vector3 vScaled = vTranslated * currentScale;
        return prMatrix.perspectiveTransform(vScaled);
      }).toList();

      final Quad2 imageQuad = Quad2(
        transformedCorners[0].vector2,
        transformedCorners[1].vector2,
        transformedCorners[2].vector2,
        transformedCorners[3].vector2,
      );

      final vector_math.Aabb2 resultAabb = FitPolygonInQuadSolver.solve(
          viewportPoly, imageQuad,
          enableResize: false);

      final Offset screenShift =
          (viewportPoly.boundingBox.center - resultAabb.center).offset;

      final double allowedDistanceSquared = 4.0 * max(1.0, currentScale);
      return screenShift.distanceSquared < allowedDistanceSquared;
    }

    Offset validCenter = _clampTranslateWithPerspective(
        proposedTranslate: translate, scale: scale);

    if (!isValid(validCenter)) {
      bool found = false;
      for (double f = 0.95; f >= 0.0; f -= 0.05) {
        if (isValid(validCenter * f)) {
          validCenter = validCenter * f;
          found = true;
          break;
        }
      }
      if (!found) {
        if (isValid(Offset.zero)) {
          validCenter = Offset.zero;
        } else if (isValid(translate)) {
          validCenter = translate;
        }
      }
    }

    double searchBoundary(Offset start, Offset dir) {
      double maxDist = 1.0 / currentScale;
      bool foundInvalid = false;
      for (int limit = 0; limit < 20; limit++) {
        if (!isValid(start + dir * maxDist)) {
          foundInvalid = true;
          break;
        }
        maxDist *= 2.0;
      }

      if (foundInvalid && maxDist <= 1.0 / currentScale) {
        return 0.0;
      }

      double low = foundInvalid ? maxDist / 2.0 : 0.0;
      double high = maxDist;

      for (int i = 0; i < 15; i++) {
        final double mid = (low + high) / 2.0;
        if (isValid(start + dir * mid)) {
          low = mid;
        } else {
          high = mid;
        }
      }

      return low;
    }

    final double rightDist = searchBoundary(validCenter, const Offset(1, 0));
    final double leftDist = searchBoundary(validCenter, const Offset(-1, 0));
    final double bottomDist = searchBoundary(validCenter, const Offset(0, 1));
    final double topDist = searchBoundary(validCenter, const Offset(0, -1));

    final double minX = validCenter.dx - leftDist;
    final double minY = validCenter.dy - topDist;
    final double maxX = validCenter.dx + rightDist;
    final double maxY = validCenter.dy + bottomDist;

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Rect _getPerspectivePanBoundaries(double scale) {
    final bool perspectiveChanged = _cachedBoundsPerspectiveX != perspectiveX ||
        _cachedBoundsPerspectiveY != perspectiveY ||
        _cachedBoundsStraightenAngle != straightenAngle;

    if (_cachedPerspectiveBounds != null && !perspectiveChanged) {
      return _cachedPerspectiveBounds!;
    }

    final Rect bounds = _panBoundaries(scale);

    _cachedPerspectiveBounds = bounds;
    _cachedBoundsPerspectiveX = perspectiveX;
    _cachedBoundsPerspectiveY = perspectiveY;
    _cachedBoundsStraightenAngle = straightenAngle;

    return bounds;
  }

  void _invalidatePerspectiveBoundsCache() {
    _cachedPerspectiveBounds = null;
  }

  ScrollMetrics _calculateScrollMetrics(
    double pixels,
    AxisDirection axisDirection, {
    double? scale,
  }) {
    final double effectiveScale = scale ?? userScaleFactor;

    final Rect bounds = _hasPerspective
        ? _getPerspectivePanBoundaries(effectiveScale)
        : _panBoundaries(effectiveScale);

    final Axis axis = (axisDirection == AxisDirection.left ||
            axisDirection == AxisDirection.right)
        ? Axis.horizontal
        : Axis.vertical;

    final double rawMinExtent =
        axis == Axis.horizontal ? -bounds.right : -bounds.bottom;
    final double rawMaxExtent =
        axis == Axis.horizontal ? -bounds.left : -bounds.top;

    final double minVal = min(rawMinExtent, rawMaxExtent);
    final double maxVal = max(rawMinExtent, rawMaxExtent);

    return FixedScrollMetrics(
      pixels: pixels,
      minScrollExtent: minVal,
      maxScrollExtent: max(minVal, maxVal),
      viewportDimension:
          axis == Axis.horizontal ? _viewRect.width : _viewRect.height,
      axisDirection: axisDirection,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
  }

  Simulation? _getCombinedSimulation(
    Simulation? simulationX,
    Simulation? simulationY,
    Simulation? simulationScale,
  ) {
    if (simulationX == null && simulationY == null && simulationScale == null) {
      return null;
    }

    return CombinedSimulation(
      simulationX: simulationX ?? simulationY ?? simulationScale!,
      simulationY: simulationY ?? simulationX ?? simulationScale!,
      simulationScale: simulationScale ?? simulationX ?? simulationY!,
    );
  }

  void _handleFlingAnimation() {
    if (!_flingCtrl.isAnimating) {
      _flingCtrl.removeListener(_handleFlingAnimation);
      return;
    }

    final double t = _flingCtrl.lastElapsedDuration!.inMilliseconds / 1000.0;
    final double x = _simulationX != null ? -_simulationX!.x(t) : translate.dx;
    final double y = _simulationY != null ? -_simulationY!.x(t) : translate.dy;

    translate = Offset(x, y);
    _updateCropPainter();
  }

  void _stopFlingAnimation() {
    if (_flingCtrl.isAnimating) {
      _flingCtrl
        ..stop()
        ..removeListener(_handleFlingAnimation);
    }
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapDetails = details;
  }

  void _handleDoubleTap() async {
    double clampValue(double value, double minVal, double maxVal) {
      if (value < minVal) {
        return minVal;
      } else if (value > maxVal) {
        return maxVal;
      } else {
        return value;
      }
    }

    if (!cropRotateEditorConfigs.enableDoubleTap || _blockInteraction) return;
    _blockInteraction = true;
    cropRotateEditorCallbacks?.handleDoubleTap();

    final bool zoomInside = userScaleFactor <= _effectiveMinScale;
    final double startZoom = userScaleFactor;
    final double targetZoom = zoomInside
        ? cropRotateEditorConfigs.doubleTapScaleFactor
        : _effectiveMinScale;

    final Offset startOffset = translate;
    Offset targetOffset = zoomInside
        ? (translate -
            Offset(
              _doubleTapDetails.localPosition.dx -
                  _renderedImgConstraints.maxWidth / 2.0,
              _doubleTapDetails.localPosition.dy -
                  _renderedImgConstraints.maxHeight / 2.0,
            ))
        : Offset.zero;

    final Offset maxOffset = _getMaxOffset(targetZoom);
    final double maxOffsetX = maxOffset.dx;
    final double maxOffsetY = maxOffset.dy;

    targetOffset = Offset(
      clampValue(targetOffset.dx, -maxOffsetX, maxOffsetX),
      clampValue(targetOffset.dy, -maxOffsetY, maxOffsetY),
    );

    await loopWithTransitionTiming(
      (double curveT) {
        userScaleFactor = startZoom + (targetZoom - startZoom) * curveT;

        translate = startOffset +
            (targetOffset - startOffset) *
                targetZoom /
                userScaleFactor *
                curveT;
      },
      mounted: mounted,
      duration: cropRotateEditorConfigs.animationDuration,
      transitionFunction: Curves.decelerate.transform,
    );

    userScaleFactor = targetZoom;
    translate = targetOffset;

    _setOffsetLimits();
    addHistory();
    _blockInteraction = false;
  }

  void _setOffsetLimits({Rect? rect}) {
    if (_hasPerspective && rect == null) {
      translate = _clampTranslateWithPerspective(
        proposedTranslate: translate,
        scale: userScaleFactor,
      );
      return;
    }
    final Offset maxOffset = _getMaxOffset(userScaleFactor, viewRect: rect);
    final double minX = maxOffset.dx;
    final double minY = maxOffset.dy;
    final Offset offset = translate;

    if (offset.dx > minX) {
      translate = Offset(minX, translate.dy);
    }

    if (offset.dx < -minX) {
      translate = Offset(-minX, translate.dy);
    }

    if (offset.dy > minY) {
      translate = Offset(translate.dx, minY);
    }

    if (offset.dy < -minY) {
      translate = Offset(translate.dx, -minY);
    }
  }

  void _mouseScroll(PointerSignalEvent event) async {
    if (_blockInteraction) return;

    if (event is PointerScrollEvent) {
      final double factor = cropRotateEditorConfigs.mouseScaleFactor *
          (event.scrollDelta.dy / 50.0).abs().clamp(0.5, 2.0);

      final double deltaY = event.scrollDelta.dy *
          (cropRotateEditorConfigs.invertMouseScroll ? -1.0 : 1.0);

      final double startZoom = userScaleFactor;
      double newZoom = userScaleFactor;

      if (deltaY > 0.0) {
        newZoom -= factor;
        newZoom = max(_effectiveMinScale, newZoom);
      } else if (deltaY < 0.0) {
        newZoom += factor;
        newZoom = min(cropRotateEditorConfigs.maxScale, newZoom);
      }

      final Offset centerOffset = translate +
          _getRealHitPoint(zoom: startZoom, position: event.localPosition) /
              startZoom;

      final Offset centerZoomOffset = centerOffset * startZoom / newZoom;

      translate -= centerOffset - centerZoomOffset;
      userScaleFactor = newZoom;

      _setOffsetLimits();
      _setMouseCursor();

      _scrollHistoryDebounce(() {
        addHistory();
        cropRotateEditorCallbacks?.handleScale();
        _setCropPainter();
      });
    }
  }

  void _setMouseCursor() {
    SystemMouseCursor getCornerCursor(int cursorNo) {
      int no = cursorNo;

      if (flipX && !flipY) {
        no += cursorNo == 0 || cursorNo == 2 ? 1 : -1;
      } else if (!flipX && flipY) {
        no -= cursorNo == 0 || cursorNo == 2 ? 1 : -1;
      } else if (flipX && flipY) {
        no += cursorNo == 0 || cursorNo == 2 ? 2 : -2;
      }

      final RotateAngleSide angle = getRotateAngleSide(rotateAnimation.value);

      if (angle == RotateAngleSide.left) {
        no--;
      } else if (angle == RotateAngleSide.bottom) {
        no -= 2;
      } else if (angle == RotateAngleSide.right) {
        no -= 3;
      }

      switch (no % 4) {
        case 0:
          return SystemMouseCursors.resizeDownRight;
        case 1:
          return SystemMouseCursors.resizeDownLeft;
        case 2:
          return SystemMouseCursors.resizeUpLeft;
        case 3:
          return SystemMouseCursors.resizeUpRight;
        default:
          if (kDebugMode) {
            throw ArgumentError('Invalid cursor number!');
          } else {
            return SystemMouseCursors.basic;
          }
      }
    }

    SystemMouseCursor getSideCursor(int cursorNo) {
      int no = cursorNo;

      if (flipX && !flipY) {
        no += cursorNo == 0 || cursorNo == 2 ? 2 : 0;
      } else if (!flipX && flipY) {
        no -= cursorNo == 0 || cursorNo == 2 ? 0 : 2;
      } else if (flipX && flipY) {
        no += cursorNo == 0 || cursorNo == 2 ? 2 : -2;
      }

      final RotateAngleSide angle = getRotateAngleSide(rotateAnimation.value);

      if (angle == RotateAngleSide.left) {
        no--;
      } else if (angle == RotateAngleSide.bottom) {
        no -= 2;
      } else if (angle == RotateAngleSide.right) {
        no -= 3;
      }

      switch (no % 4) {
        case 0:
          return SystemMouseCursors.resizeRight;
        case 1:
          return SystemMouseCursors.resizeDown;
        case 2:
          return SystemMouseCursors.resizeLeft;
        case 3:
          return SystemMouseCursors.resizeUp;
        default:
          if (kDebugMode) {
            throw ArgumentError('Invalid cursor number!');
          } else {
            return SystemMouseCursors.basic;
          }
      }
    }

    int cursorNumber = -1;

    switch (_currentCropAreaPart) {
      case CropAreaPart.topLeft:
        cursorNumber = 0;
        break;
      case CropAreaPart.topRight:
        cursorNumber = 1;
        break;
      case CropAreaPart.bottomRight:
        cursorNumber = 2;
        break;
      case CropAreaPart.bottomLeft:
        cursorNumber = 3;
        break;
      case CropAreaPart.left:
        cursorNumber = 4;
        break;
      case CropAreaPart.top:
        cursorNumber = 5;
        break;
      case CropAreaPart.right:
        cursorNumber = 6;
        break;
      case CropAreaPart.bottom:
        cursorNumber = 7;
        break;
      case CropAreaPart.inside:
      case CropAreaPart.none:
        if (userScaleFactor > 1.0 ||
            cropRect.size.aspectRatio.toStringAsFixed(3) !=
                (_rotated90deg
                        ? 1.0 / _renderedImgSize.aspectRatio
                        : _renderedImgSize.aspectRatio)
                    .toStringAsFixed(3)) {
          _cursor = SystemMouseCursors.move;
        } else {
          _cursor = SystemMouseCursors.basic;
        }
        return;
    }

    _cursor = cursorNumber <= 3
        ? getCornerCursor(cursorNumber)
        : getSideCursor(cursorNumber - 4);
  }

  Offset _getRealHitPoint({
    required double zoom,
    required Offset position,
  }) {
    final double imgW = _renderedImgConstraints.maxWidth;
    final double imgH = _renderedImgConstraints.maxHeight;

    final Offset transformedLocalPosition = position * zoom;

    final Size transformedImgSize = Size(imgW, imgH) * zoom;

    return Offset(
      transformedLocalPosition.dx - transformedImgSize.width / 2.0,
      transformedLocalPosition.dy - transformedImgSize.height / 2.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      key: _editorContentKey,
      top: cropRotateEditorConfigs.safeArea.top,
      bottom: cropRotateEditorConfigs.safeArea.bottom,
      left: cropRotateEditorConfigs.safeArea.left,
      right: cropRotateEditorConfigs.safeArea.right,
      child: RecordInvisibleWidget(
        controller: screenshotCtrl,
        child: ExtendedPopScope(
          canPop: cropRotateEditorConfigs.enableGesturePop,
          onPopInvokedWithResult: (bool didPop, dynamic _) {
            _showFakeHero = true;
            _updateAllStates();
          },
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: cropRotateEditorConfigs.style.uiOverlayStyle,
                child: Theme(
                  data: theme.copyWith(
                    tooltipTheme:
                        theme.tooltipTheme.copyWith(preferBelow: true),
                  ),
                  child: Scaffold(
                    resizeToAvoidBottomInset: false,
                    backgroundColor: cropRotateEditorConfigs.style.background
                            ?.call(context) ??
                        kImageEditorBackground,
                    appBar: _buildAppBar(constraints),
                    body: Center(
                      child: SizedBox(
                        width: constraints.maxWidth *
                            (cropRotateEditorConfigs.maxWidthFactor ??
                                (!kIsWeb && Platform.isAndroid ? 0.9 : 1.0)),
                        child: Stack(
                          children: [
                            _buildBody(),
                            Positioned(
                              bottom: 0,
                              child: _buildBottomAppBar() ?? Container(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cropPainterNotifier.dispose();
    _onScaleEndDebounce.dispose();
    _onScaleAllowUpdateDebounce.dispose();
    _bottomBarScrollCtrl.dispose();
    _flingCtrl.dispose();
    rotateCtrl.dispose();
    scaleCtrl.dispose();
    ServicesBinding.instance.keyboard.removeHandler(_onKeyEvent);
    super.dispose();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<CropRotateEditorInitConfigs>(
          'initConfigs', widget.initConfigs))
      ..add(
          DiagnosticsProperty<EditorImage?>('editorImage', widget.editorImage))
      ..add(DiagnosticsProperty<ProVideoController?>(
          'videoController', widget.videoController))
      ..add(
          DiagnosticsProperty<TransformConfigs>('activeHistory', activeHistory))
      ..add(IntProperty('rotationCount', rotationCount))
      ..add(FlagProperty('flipX', value: flipX, ifTrue: 'flipped X'))
      ..add(FlagProperty('flipY', value: flipY, ifTrue: 'flipped Y'))
      ..add(DoubleProperty('aspectRatio', aspectRatio))
      ..add(EnumProperty<CropMode>('cropMode', cropMode))
      ..add(DoubleProperty('userScaleFactor', userScaleFactor))
      ..add(DoubleProperty('oldScaleFactor', oldScaleFactor))
      ..add(DoubleProperty('animatedScale', scaleAnimation.value))
      ..add(DiagnosticsProperty<Offset>('translate', translate))
      ..add(DiagnosticsProperty<Rect>('cropRect', cropRect))
      ..add(DiagnosticsProperty<Rect>('viewRect', _viewRect))
      ..add(FlagProperty('showFakeHero',
          value: _showFakeHero, ifTrue: 'showing fake hero'))
      ..add(FlagProperty('enableFakeHero',
          value: enableFakeHero, ifTrue: 'fake hero enabled'))
      ..add(FlagProperty('imageNeedDecode',
          value: _imageNeedDecode, ifTrue: 'image needs decode'))
      ..add(FlagProperty('imageSizeIsDecoded',
          value: _imageSizeIsDecoded, ifTrue: 'image size decoded'))
      ..add(FlagProperty('interactionActive',
          value: _interactionActive, ifTrue: 'interaction active'))
      ..add(FlagProperty('scaleStarted',
          value: _scaleStarted, ifTrue: 'scale started'))
      ..add(DiagnosticsProperty<Size>('editorBodySize', editorBodySize))
      ..add(DiagnosticsProperty<Size>('mainImageSize', _mainImageSize))
      ..add(DiagnosticsProperty<Size>('renderedImgSize', _renderedImgSize))
      ..add(DiagnosticsProperty<BoxConstraints>(
          'renderedImgConstraints', _renderedImgConstraints))
      ..add(DiagnosticsProperty<MouseCursor>('mouseCursor', _mouseCursor))
      ..add(IntProperty('activePointers', _activePointers));
  }

  /// Builds the top app bar for the editor interface.
  ///
  /// Connects navigation, undo logic, and completion buttons.
  PreferredSizeWidget? _buildAppBar(BoxConstraints constraints) {
    if (cropRotateEditorConfigs.widgets.appBar != null) {
      final PreferredSizeWidget? customToolbar = cropRotateEditorConfigs
          .widgets.appBar!
          .call(this, rebuildController.stream);

      _hasToolbar = customToolbar != null;
      return customToolbar;
    }

    _hasToolbar = true;

    return CropEditorAppbar(
      configs: configs.cropRotateEditor,
      i18n: i18n.cropRotateEditor,
      enableCloseButton: initConfigs.enableCloseButton,
      canUndo: canUndo,
      canRedo: canRedo,
      onDone: done,
      onClose: close,
      onUndo: undoAction,
      onRedo: redoAction,
    );
  }

  /// Builds the bottom toolbar interface housing the distinct modification controls.
  ///
  /// Disables rendering if all tool parameters are hidden via configuration.
  Widget? _buildBottomAppBar() {
    if (cropRotateEditorConfigs.widgets.bottomBar != null) {
      return cropRotateEditorConfigs.widgets.bottomBar!
          .call(this, rebuildController.stream);
    }

    return tools.isNotEmpty
        ? CropEditorBottombar(
            bottomBarScrollCtrl: _bottomBarScrollCtrl,
            i18n: i18n.cropRotateEditor,
            configs: cropRotateEditorConfigs,
            theme: theme,
            tools: tools,
            isStraightenModeActive: _isStraightenModeActive,
            straightenAngle: straightenAngle,
            rebuildController: rebuildController,
            editorState: this,
            onRotate: rotate,
            onFlip: flip,
            onOpenAspectRatioOptions: openAspectRatioOptions,
            onReset: reset,
            onStraighten: toggleStraightenMode,
            onStraightenChanged: (double angle) {
              setStraightenAngle(angle);
            },
            onStraightenChangeEnd: (double angle) {
              setStraightenAngle(angle);
              addHistory();
              fadeInBlur();
            },
            isPerspectiveModeActive: _isPerspectiveModeActive,
            perspectiveX: perspectiveX,
            perspectiveY: perspectiveY,
            onPerspective: togglePerspectiveMode,
            onPerspectiveChanged: (double x, double y) {
              setPerspective(x, y);
            },
            onPerspectiveChangeEnd: (double x, double y) {
              setPerspective(x, y);
              addHistory();
              fadeInBlur();
            },
          )
        : null;
  }

  /// Constructs the primary visual interactive layer encompassing the crop and boundary region.
  ///
  /// Observes resize events to seamlessly adapt constraint adjustments.
  Widget _buildBody() {
    return SafeArea(
      top: cropRotateEditorConfigs.safeArea.top,
      bottom: cropRotateEditorConfigs.safeArea.bottom,
      left: cropRotateEditorConfigs.safeArea.left,
      right: cropRotateEditorConfigs.safeArea.right,
      child: ScreenResizeDetector(
        ignoreSafeArea: false,
        onResizeUpdate: (ResizeEvent event) {
          if (event.oldContentSize != event.newContentSize &&
              !event.oldContentSize.isEmpty) {
            _isScreenResized = true;
          }

          if (editorBodySize != event.newContentSize) {
            editorBodySize = event.newContentSize;
            _setCropPainter();
          }

          final EdgeInsets margin = cropRotateEditorConfigs.viewPadding ??
              cropRotateEditorConfigs.boundaryMargin;

          cropEditorScreenRatio = Size(
            editorBodySize.width - margin.horizontal,
            editorBodySize.height - margin.vertical,
          ).aspectRatio;
        },
        onResizeEnd: (ResizeEvent event) {
          if (_imageNeedDecode) _decodeImage();

          WidgetsBinding.instance.addPostFrameCallback((_) async {
            _setCropRectBounding();
            _updateAllStates();
          });
        },
        child: Stack(
          children: [
            if (_showFakeHero)
              _buildFakeHero()
            else if (!_imageSizeIsDecoded && initConfigs.convertToUint8List)
              Align(
                alignment: Alignment.center,
                child: SizedBox(
                  width: 60.0,
                  height: 60.0,
                  child: FittedBox(
                    child: PlatformCircularProgressIndicator(configs: configs),
                  ),
                ),
              ),
            AnimatedOpacity(
              duration: !initConfigs.convertToUint8List
                  ? Duration.zero
                  : const Duration(milliseconds: 160),
              opacity: _showFakeHero || !_imageSizeIsDecoded ? 0.0 : 1.0,
              child: HeroMode(
                enabled: false,
                child: _buildMouseCursor(
                  child: DeferredPointerHandler(
                    child: _buildRotationTransform(
                      child: _buildFlipTransform(
                        child: _buildRotationScaleTransform(
                          child: _buildPaintContainer(
                            child: _buildBackgroundCropPainter(
                              child: _buildStraightenAndPerspectiveTransform(
                                child: _buildStraightenScaleTransform(
                                  child: _buildUserScaleTransform(
                                    child: _buildTranslate(
                                      child: DeferPointer(
                                        child: _buildEventListener(
                                          child: _buildGestureDetector(
                                            child: _buildImage(),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _buildDarkenOverlay(),
            _buildBlurOverlay(),
            _buildSharpCropRestore(),
            // Crop handles above blur so they're not blurred
            Positioned.fill(
              child: AnimatedBuilder(
                animation: scaleCtrl,
                builder: (context, child) {
                  return Transform.scale(
                    scale: scaleAnimation.value,
                    alignment: _contentCenterAlignment,
                    child: child,
                  );
                },
                child: ValueListenableBuilder<CropCornerPainter?>(
                  valueListenable: _cropPainterNotifier,
                  builder: (context, painter, _) {
                    if (painter == null) return const SizedBox.shrink();
                    final EdgeInsets margin =
                        cropRotateEditorConfigs.viewPadding ??
                            cropRotateEditorConfigs.boundaryMargin;
                    final Size imgSize = _renderedImgSize;
                    final Size bodySize = editorBodySize;
                    final double imgOriginX = margin.left +
                        (bodySize.width - margin.horizontal - imgSize.width) /
                            2;
                    final double imgOriginY = margin.top +
                        (bodySize.height - margin.vertical - imgSize.height) /
                            2;

                    return Stack(
                      children: [
                        Positioned(
                          left: imgOriginX,
                          top: imgOriginY,
                          width: imgSize.width,
                          height: imgSize.height,
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: painter.copy(drawCropOverlay: true),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            // Crop corner widget – outside Transform.scale so it
            // keeps its fixed size regardless of scale animations.
            if (cropRotateEditorConfigs.widgets.cropCornerWidget != null)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: scaleCtrl,
                  builder: (context, _) {
                    return ValueListenableBuilder<CropCornerPainter?>(
                      valueListenable: _cropPainterNotifier,
                      builder: (context, painter, _) {
                        if (painter == null) {
                          return const SizedBox.shrink();
                        }
                        final EdgeInsets margin =
                            cropRotateEditorConfigs.viewPadding ??
                                cropRotateEditorConfigs.boundaryMargin;
                        final Size imgSize = _renderedImgSize;
                        final Size bodySize = editorBodySize;
                        final double imgOriginX = margin.left +
                            (bodySize.width -
                                    margin.horizontal -
                                    imgSize.width) /
                                2;
                        final double imgOriginY = margin.top +
                            (bodySize.height -
                                    margin.vertical -
                                    imgSize.height) /
                                2;

                        // Compute the unscaled position
                        final double rawX = imgOriginX + painter.cropRect.right;
                        final double rawY = imgOriginY + painter.cropRect.top;

                        // Apply the same scale transform as the
                        // crop handles overlay uses
                        final double s = scaleAnimation.value;
                        final Alignment a = _contentCenterAlignment;
                        final double cx = bodySize.width * (0.5 + a.x / 2);
                        final double cy = bodySize.height * (0.5 + a.y / 2);
                        final double scaledX = cx + (rawX - cx) * s;
                        final double scaledY = cy + (rawY - cy) * s;

                        return Stack(
                          children: [
                            Positioned(
                              left: scaledX,
                              top: scaledY,
                              child: FractionalTranslation(
                                translation: const Offset(-1, 0),
                                child: IgnorePointer(
                                  child: cropRotateEditorConfigs
                                      .widgets.cropCornerWidget!(
                                    this,
                                    rebuildController.stream,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            if (cropRotateEditorConfigs.widgets.bodyItems != null)
              ...cropRotateEditorConfigs.widgets.bodyItems!(
                  this, rebuildController.stream),
          ],
        ),
      ),
    );
  }

  /// Constructs the visual cursor binding allowing specialized cursor styling via interactions.
  ///
  /// Separates dependency logic from the main build stream.
  Widget _buildMouseCursor({required Widget child}) {
    return ExtendedRebuildMouseRegion(
      key: _mouseCursorsKey,
      initCursor: _cursor,
      child: child,
    );
  }

  /// Builds the gesture layer allowing control over complex scale, pan, and interactive boundary shifts.
  ///
  /// Funnels standard gesture properties onto the primary layout manipulation keys.
  Widget _buildEventListener({required Widget child}) {
    return OutsideListener(
      behavior: OutsideHitTestBehavior.all,
      onPointerDown: (PointerDownEvent event) {
        _gestureKey.currentState!.rawKey.currentState!.handlePointerDown(event);

        if (_activePointers == 0) _scaleStartZoomHelper = userScaleFactor;

        _activePointers++;
        _stopFlingAnimation();
      },
      onPointerUp: (PointerUpEvent event) {
        _activePointers--;
      },
      onPointerCancel: (PointerCancelEvent event) {
        _activePointers--;
      },
      onPointerPanZoomStart: (PointerPanZoomStartEvent event) {
        _gestureKey.currentState!.rawKey.currentState!
            .handlePointerPanZoomStart(event);
      },
      onPointerSignal: isDesktop ? _mouseScroll : null,
      onPointerHover: isDesktop
          ? (PointerHoverEvent event) {
              final CropAreaPart area = _determineCropAreaPart(event.position);
              if (area != _currentCropAreaPart) {
                _currentCropAreaPart = area;
                _setMouseCursor();
              }
            }
          : null,
      child: child,
    );
  }

  /// Orchestrates the primary structural gesture callbacks onto the inner interaction plane.
  ///
  /// Required for passing standard coordinate scale data.
  Widget _buildGestureDetector({required Widget child}) {
    return CropRotateGestureDetector(
      key: _gestureKey,
      onScaleStart: _onScaleStart,
      onScaleEnd: _onScaleEnd,
      onScaleUpdate: _onScaleUpdate,
      onDoubleTapDown: _handleDoubleTapDown,
      onDoubleTap: _handleDoubleTap,
      child: child,
    );
  }

  /// Applies structural 2D rotation transformations onto the inner view context.
  ///
  /// Connects the raw interaction state logic directly to rendering updates.
  AnimatedBuilder _buildRotationTransform({required Widget child}) {
    return AnimatedBuilder(
      animation: rotateAnimation,
      builder: (BuildContext context, Widget? mappedChild) => Transform.rotate(
        angle: rotateAnimation.value,
        alignment: Alignment.center,
        child: mappedChild,
      ),
      child: child,
    );
  }

  /// Applies horizontal and vertical mirroring logic to the current view hierarchy.
  ///
  /// Executes static or animated matrix transformations dynamically.
  Widget _buildFlipTransform({required Widget child}) {
    if (!cropRotateEditorConfigs.enableFlipAnimation) {
      return Transform.flip(
        flipX: flipX,
        flipY: flipY,
        child: child,
      );
    }

    return TweenAnimationBuilder<double>(
      duration: cropRotateEditorConfigs.animationDuration,
      tween: Tween<double>(begin: 1.0, end: flipX ? -1.0 : 1.0),
      curve: cropRotateEditorConfigs.flipAnimationCurve,
      builder: (BuildContext context, double scaleX, Widget? mappedChild) {
        return TweenAnimationBuilder<double>(
          duration: cropRotateEditorConfigs.animationDuration,
          tween: Tween<double>(begin: 1.0, end: flipY ? -1.0 : 1.0),
          curve: cropRotateEditorConfigs.flipAnimationCurve,
          builder: (BuildContext context, double scaleY, Widget? innerChild) {
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(scaleX, scaleY, 1.0),
              child: innerChild,
            );
          },
          child: mappedChild,
        );
      },
      child: child,
    );
  }

  /// Encompasses dynamic scale variations triggered by internal user inputs.
  ///
  /// Prevents global layout reflows by encapsulating specific render logic.
  Widget _buildUserScaleTransform({required Widget child}) {
    return ExtendedTransformScale(
      key: userScaleKey,
      initScale: userScaleFactor,
      alignment: Alignment.center,
      child: child,
    );
  }

  /// Encompasses pan and translation offsets triggered by interaction dynamics.
  ///
  /// Optimizes render cycles when dragging the internal surface.
  Widget _buildTranslate({required Widget child}) {
    return ExtendedTransformTranslate(
      key: translateKey,
      initOffset: translate,
      child: child,
    );
  }

  /// Injects scale mapping generated from the structural rotational compensation.
  ///
  /// Keeps the image locked to boundaries dynamically while turning.
  Widget _buildRotationScaleTransform({required Widget child}) {
    return AnimatedBuilder(
      animation: scaleCtrl,
      builder: (context, child) {
        return Transform.scale(
          scale: scaleAnimation.value,
          alignment: _contentCenterAlignment,
          child: child,
        );
      },
      child: child,
    );
  }

  /// Applies a specialized scale to maintain full crop area coverage while straightening.
  ///
  /// Prevents blank boundary pixels inside the selection window.
  Widget _buildStraightenScaleTransform({required Widget child}) {
    return Transform.scale(
      scale: _straightenScale,
      alignment: Alignment.center,
      child: child,
    );
  }

  /// Computes and assigns the final active transformation matrix.
  ///
  /// Fuses Z-axis rotation and X/Y depth configurations into a single valid perspective space.
  Matrix4 _calculateStraightenAndPerspectiveMatrix({
    required double angle,
    required double perspectiveX,
    required double perspectiveY,
  }) {
    return Matrix4.identity()
      ..setEntry(3, 2, _perspectiveDepth)
      ..rotateX(-perspectiveX)
      ..rotateY(perspectiveY)
      ..rotateZ(-angle);
  }

  /// Conditionally applies complex straightening and perspective mapping matrices.
  ///
  /// Skips transformation computations entirely if properties are inactive.
  Widget _buildStraightenAndPerspectiveTransform({required Widget child}) {
    if (straightenAngle == 0.0 && perspectiveX == 0.0 && perspectiveY == 0.0) {
      return child;
    }

    return Transform(
      transform: _calculateStraightenAndPerspectiveMatrix(
        angle: straightenAngle,
        perspectiveX: perspectiveX,
        perspectiveY: perspectiveY,
      ),
      alignment: Alignment.center,
      child: child,
    );
  }

  /// Paints the image without darken overlay or crop overlay.
  /// Darken and crop overlay are now separate Stack layers.
  Widget _buildBackgroundCropPainter({required Widget child}) {
    return ExtendedCustomPaint(
      key: cropPainterKey,
      initIsComplex: showWidgets,
      initWillChange: showWidgets,
      initForegroundPainter: backgroundCropPainter?.copy(),
      child: child,
    );
  }

  /// Uniform darken overlay covering the entire body area.
  /// Sits between the image and the blur so BackdropFilter blurs
  /// a uniformly darkened image (no transition = no artifacts).
  Widget _buildDarkenOverlay() {
    return Positioned.fill(
      child: ValueListenableBuilder<CropCornerPainter?>(
        valueListenable: _cropPainterNotifier,
        builder: (context, painter, _) {
          if (painter == null) return const SizedBox.shrink();

          final Color interpolatedColor = Color.lerp(
            painter.background,
            painter.cropOverlayColor,
            painter.fadeInOpacity,
          )!;

          final double opacity = painter.style.cropOverlayOpacity -
              painter.style.cropOverlayInteractionOpacity *
                  painter.interactionOpacity;
          final double fadeInFactor =
              (1 - opacity) * (1 - painter.fadeInOpacity);

          return IgnorePointer(
            child: ColoredBox(
              color: interpolatedColor.withValues(
                alpha: (opacity + fadeInFactor).clamp(0, 1),
              ),
              child: const SizedBox.expand(),
            ),
          );
        },
      ),
    );
  }

  /// Full-area blur. Since the darken overlay is uniform (no crop rect
  /// transition), there are no edge artifacts. The sharp restore layer
  /// on top handles showing the clear image inside the crop rect.
  Widget _buildBlurOverlay() {
    return Positioned.fill(
      child: ValueListenableBuilder<CropCornerPainter?>(
        valueListenable: _cropPainterNotifier,
        builder: (context, painter, _) {
          if (painter == null || painter.style.cropOverlayBlur <= 0) {
            return const SizedBox.shrink();
          }

          return Opacity(
            opacity: (1.0 - _blurInteractionOpacity).clamp(0.0, 1.0),
            child: IgnorePointer(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: painter.style.cropOverlayBlur,
                  sigmaY: painter.style.cropOverlayBlur,
                  tileMode: TileMode.mirror,
                  bounds: Offset.zero & editorBodySize,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Restores the sharp (un-blurred, un-darkened) image inside the crop rect
  /// on top of the uniformly-darkened and blurred backdrop.
  Widget _buildSharpCropRestore() {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: scaleCtrl,
        builder: (context, child) {
          return Transform.scale(
            scale: scaleAnimation.value,
            alignment: _contentCenterAlignment,
            child: child,
          );
        },
        child: ValueListenableBuilder<CropCornerPainter?>(
          valueListenable: _cropPainterNotifier,
          builder: (context, painter, _) {
            if (painter == null || painter.style.cropOverlayBlur <= 0) {
              return const SizedBox.shrink();
            }

            final EdgeInsets margin = cropRotateEditorConfigs.viewPadding ??
                cropRotateEditorConfigs.boundaryMargin;
            final Size imgSize = _renderedImgSize;
            final Size bodySize = editorBodySize;
            final double imgOriginX = margin.left +
                (bodySize.width - margin.horizontal - imgSize.width) / 2;
            final double imgOriginY = margin.top +
                (bodySize.height - margin.vertical - imgSize.height) / 2;

            return IgnorePointer(
              child: ClipPath(
                clipper: _CropInsideClipper(
                  cropRect: painter.cropRect,
                  drawCircle: painter.drawCircle,
                  imageOffset: Offset(imgOriginX, imgOriginY),
                ),
                child: _buildSharpRestoreContent(),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Non-interactive image with the same visual transforms,
  /// used to restore the sharp view inside the crop rect.
  Widget _buildSharpRestoreContent() {
    return _buildRotationTransform(
      child: _buildFlipTransform(
        child: Align(
          alignment: Alignment.center,
          child: Padding(
            padding: cropRotateEditorConfigs.viewPadding ??
                cropRotateEditorConfigs.boundaryMargin,
            child: _buildStraightenAndPerspectiveTransform(
              child: Transform.scale(
                scale: _straightenScale,
                alignment: Alignment.center,
                child: Transform.scale(
                  scale: userScaleFactor,
                  alignment: Alignment.center,
                  child: Transform.translate(
                    offset: translate,
                    child: _buildSharpRestoreImage(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Lightweight image for the sharp crop rect restore layer.
  Widget _buildSharpRestoreImage() {
    final EdgeInsets margin = cropRotateEditorConfigs.viewPadding ??
        cropRotateEditorConfigs.boundaryMargin;
    final double availableHeight = editorBodySize.height - margin.vertical;
    final double availableWidth = editorBodySize.width - margin.horizontal;
    final double maxWidth = _imgWidth / _imgHeight * availableHeight;
    final double maxHeight = availableWidth * _imgHeight / _imgWidth;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxWidth.isNaN ? _imgWidth : maxWidth,
        maxHeight: maxHeight.isNaN ? _imgHeight : maxHeight,
      ),
      child: FilteredWidget(
        filters: appliedFilters,
        tuneAdjustments: appliedTuneAdjustments,
        blurFactor: appliedBlurFactor,
        configs: configs,
        width: _imgWidth,
        height: _imgHeight,
        image: editorImage,
        videoPlayer: videoController?.videoPlayer,
        blankSize: initConfigs.mainImageSize,
      ),
    );
  }

  /// Houses the inner paint components, injecting global boundary padding constraints.
  ///
  /// Assures clipping limits map neatly.
  Widget _buildPaintContainer({required Widget child}) {
    return Align(
      alignment: Alignment.center,
      child: Padding(
        padding: cropRotateEditorConfigs.viewPadding ??
            cropRotateEditorConfigs.boundaryMargin,
        child: child,
      ),
    );
  }

  /// Calculates core image boundaries and orchestrates the primary background rendering space.
  ///
  /// Filters layout layers and bounds against structural constraints.
  Widget _buildImage() {
    final EdgeInsets margin = cropRotateEditorConfigs.viewPadding ??
        cropRotateEditorConfigs.boundaryMargin;
    final double availableHeight = editorBodySize.height - margin.vertical;
    final double availableWidth = editorBodySize.width - margin.horizontal;

    final double maxWidth = _imgWidth / _imgHeight * availableHeight;
    final double maxHeight = availableWidth * _imgHeight / _imgWidth;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxWidth.isNaN ? _imgWidth : maxWidth,
        maxHeight: maxHeight.isNaN ? _imgHeight : maxHeight,
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          _renderedImgConstraints = constraints;
          originalSize = constraints.biggest;

          return Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              FilteredWidget(
                filters: appliedFilters,
                tuneAdjustments: appliedTuneAdjustments,
                blurFactor: appliedBlurFactor,
                configs: configs,
                width: _imgWidth,
                height: _imgHeight,
                image: editorImage,
                videoPlayer: videoController?.videoPlayer,
                blankSize: initConfigs.mainImageSize,
              ),
              if (cropRotateEditorConfigs.showLayers &&
                  cropRotateEditorConfigs.enableTransformLayers &&
                  layers != null &&
                  !_isScreenResized)
                ClipRRect(
                  clipBehavior: Clip.hardEdge,
                  child: LayerStack(
                    cutOutsideImageArea: false,
                    transformHelper: TransformHelper(
                      mainBodySize: Size.zero,
                      mainImageSize: Size.zero,
                      editorBodySize: originalSize,
                    ),
                    configs: configs,
                    layers: _rawLayers,
                    clipBehavior: Clip.none,
                    overlayColor: cropRotateEditorConfigs.style.background
                            ?.call(context) ??
                        kImageEditorBackground,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Replicates an un-interactive transition visual representing the previous view boundary.
  ///
  /// Allows seamless transition animations before unlocking the editor interaction grid.
  Widget _buildFakeHero() {
    return Padding(
      padding: cropRotateEditorConfigs.boundaryMargin *
          cropRotateEditorConfigs.editorMinScale,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return Stack(
            alignment: Alignment.center,
            fit: StackFit.expand,
            children: [
              Hero(
                tag: heroTag,
                createRectTween: (Rect? begin, Rect? end) =>
                    RectTween(begin: begin, end: end),
                child: TransformedContentGenerator(
                  isVideoPlayer: videoController != null,
                  transformConfigs: _fakeHeroTransformConfigs,
                  configs: configs,
                  child: FilteredWidget(
                    width: _mainImageSize.width,
                    height: _mainImageSize.height,
                    configs: configs,
                    image: editorImage,
                    videoPlayer: videoController?.videoPlayer,
                    blankSize: initConfigs.mainImageSize,
                    filters: appliedFilters,
                    tuneAdjustments: appliedTuneAdjustments,
                    blurFactor: appliedBlurFactor,
                  ),
                ),
              ),
              if (cropRotateEditorConfigs.showLayers && layers != null)
                LayerStack(
                  transformHelper: TransformHelper(
                    mainBodySize: (mainBodySize ?? editorBodySize),
                    mainImageSize: _mainImageSize,
                    editorBodySize: constraints.biggest,
                    transformConfigs: initialTransformConfigs,
                  ),
                  configs: configs,
                  layers: _layers,
                  clipBehavior: Clip.none,
                  overlayColor:
                      cropRotateEditorConfigs.style.background?.call(context) ??
                          kImageEditorBackground,
                ),
            ],
          );
        },
      ),
    );
  }

  /// Builds a headless rendering framework configured identically to the internal view.
  ///
  /// Used explicitly for final visual captures generated invisibly from user state data.
  Widget _screenshotWidget(TransformConfigs transformC) {
    final Size size =
        _rotated90deg ? imageInfos!.rawSize.flipped : imageInfos!.rawSize;
    final double w = size.width;
    final double h = size.height;

    return SizedBox(
      width: w,
      height: h,
      child: TransformedContentGenerator(
        isVideoPlayer: videoController != null,
        transformConfigs: transformC,
        configs: configs,
        child: FilteredWidget(
          width: w,
          height: h,
          configs: configs,
          image: editorImage,
          videoPlayer: isVideoEditor && initConfigs.convertToUint8List
              ? const SizedBox.shrink()
              : videoController?.videoPlayer,
          blankSize: initConfigs.mainImageSize,
          filters: appliedFilters,
          tuneAdjustments: appliedTuneAdjustments,
          blurFactor: appliedBlurFactor,
        ),
      ),
    );
  }
}

/// Clips the blur effect to everything outside the crop rect,
/// mapping crop rect coordinates from image space to body space.
class _CropBlurClipper extends CustomClipper<Path> {
  final Rect cropRect;
  final bool drawCircle;
  final Offset imageOffset;

  _CropBlurClipper({
    required this.cropRect,
    required this.drawCircle,
    required this.imageOffset,
  });

  @override
  Path getClip(Size size) {
    // Map crop rect from image coords to body coords
    final Rect bodyCropRect =
        cropRect.translate(imageOffset.dx, imageOffset.dy);

    Path path = Path()..fillType = PathFillType.evenOdd;

    if (drawCircle) {
      path.addOval(bodyCropRect);
    } else {
      path.addRect(bodyCropRect);
    }

    path.addRect(Offset.zero & size);

    return path;
  }

  @override
  bool shouldReclip(covariant _CropBlurClipper oldClipper) {
    return oldClipper.cropRect != cropRect ||
        oldClipper.drawCircle != drawCircle ||
        oldClipper.imageOffset != imageOffset;
  }
}

/// Clips to INSIDE the crop rect only (the inverse of [_CropBlurClipper]).
/// Used for the sharp-image restore layer on top of the blur.
class _CropInsideClipper extends CustomClipper<Path> {
  final Rect cropRect;
  final bool drawCircle;
  final Offset imageOffset;

  _CropInsideClipper({
    required this.cropRect,
    required this.drawCircle,
    required this.imageOffset,
  });

  @override
  Path getClip(Size size) {
    final Rect bodyCropRect =
        cropRect.translate(imageOffset.dx, imageOffset.dy);

    if (drawCircle) {
      return Path()..addOval(bodyCropRect);
    } else {
      return Path()..addRect(bodyCropRect);
    }
  }

  @override
  bool shouldReclip(covariant _CropInsideClipper oldClipper) {
    return oldClipper.cropRect != cropRect ||
        oldClipper.drawCircle != drawCircle ||
        oldClipper.imageOffset != imageOffset;
  }
}
