// ignore_for_file: deprecated_member_use_from_same_package
// TODO: Remove the deprecated values when releasing version 12.0.0.

// Dart imports:
import 'dart:math';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter/services.dart';

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
import 'utils/rotate_angle.dart';
import 'widgets/crop_corner_painter.dart';
import 'widgets/outside_gestures/outside_gesture_behavior.dart';

export 'enums/crop_mode.enum.dart';
export 'widgets/crop_aspect_ratio_options.dart';

/// Enum zur Unterscheidung der Gesten am Ende der Interaktion.
enum _GestureType { pan, scale }

/// The `CropRotateEditor` widget allows users to editing images with crop, flip
/// and rotate tools.
///
/// You can create a `CropRotateEditor` using one of the factory methods
/// provided:
/// - `CropRotateEditor.file`: Loads an image from a file.
/// - `CropRotateEditor.asset`: Loads an image from an asset.
/// - `CropRotateEditor.network`: Loads an image from a network URL.
/// - `CropRotateEditor.memory`: Loads an image from memory as a `Uint8List`.
/// - `CropRotateEditor.autoSource`: Automatically selects the source based on
/// provided parameters.
class CropRotateEditor extends StatefulWidget
    with StandaloneEditor<CropRotateEditorInitConfigs> {
  /// Constructs a `CropRotateEditor` widget.
  ///
  /// The [key] parameter is used to provide a key for the widget.
  /// The [editorImage] parameter specifies the image to be edited.
  /// The [initConfigs] parameter specifies the initialization configurations
  /// for the editor.
  const CropRotateEditor._({
    super.key,
    required this.initConfigs,
    this.editorImage,
    this.videoController,
  }) : assert(editorImage != null || videoController != null,
            'Either editorImage or videoController must be provided.');

  /// Constructs a `CropRotateEditor` widget with image data loaded from memory.
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

  /// Constructs a `CropRotateEditor` widget with an image loaded from a file.
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

  /// Constructs a `CropRotateEditor` widget with an image loaded from an asset.
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

  /// Constructs a `CropRotateEditor` widget with an image loaded from a
  /// network URL.
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

  /// Constructs a `CropRotateEditor` widget with an image loaded automatically
  /// based on the provided source.
  ///
  /// Either [byteArray], [file], [networkUrl], or [assetPath] must be provided.
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

  /// Constructs a `CropRotateEditor` widget with an video player.
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

/// A state class for ImageCropRotateEditor widget.
///
/// This class handles the state and UI for an image editor
/// that supports cropping, rotating, and aspect ratio adjustments.
class CropRotateEditorState extends State<CropRotateEditor>
    with
        TickerProviderStateMixin,
        ImageEditorConvertedConfigs,
        ImageEditorConvertedCallbacks,
        StandaloneEditorState<CropRotateEditor, CropRotateEditorInitConfigs>,
        ExtendedLoop,
        CropAreaHistory {
  /// A global key used to identify the editor content widget.
  final _editorContentKey = GlobalKey();

  /// An offset helper to keep track of the editor's screen offset.
  /// This is required for the case the editor is embedded inside the screen.
  /// Initialized to `Offset.zero`.
  Offset _editorScreenOffsetHelper = Offset.zero;

  final _mouseCursorsKey = GlobalKey<ExtendedRebuildMouseRegionState>();

  /// A key used to access the state of the CropRotateGestureDetector widget.
  final _gestureKey = GlobalKey<CropRotateGestureDetectorState>();

  /// A ScrollController for controlling the scrolling behavior of the bottom
  /// navigation bar.
  late ScrollController _bottomBarScrollCtrl;

  /// Debounce object for handling the end of a scaling gesture.
  late final Debounce _onScaleEndDebounce;

  /// Debounce object for allowing updates during a scaling gesture.
  late final Debounce _onScaleAllowUpdateDebounce;

  /// A debounce object for scroll history actions.
  late final Debounce _scrollHistoryDebounce;

  /// Controller used for fling animations when panning ends with velocity.
  late AnimationController _flingCtrl;

  /// Simulations for inertial scrolling on each axis.
  Simulation? _simulationX;
  Simulation? _simulationY;
  Simulation? _combinedSimulation;
  Simulation? _simulationScale;

  double? _scaleStart; // Scale value at start of scaling gesture.
  double _lastScale = 1.0;

  Offset _lastFocal = Offset.zero; // Brennpunkt aus dem vorigen Update
  _GestureType? _gestureType;

  /// Indicates whether to show the fake hero animation.
  bool _showFakeHero = true;

  /// Indicates whether interaction is currently blocked.
  bool _blockInteraction = false;

  /// Indicates whether scaling has started.
  bool _scaleStarted = false;

  /// Indicates whether interaction is currently active.
  bool _interactionActive = false;

  /// Determines if the image sticks to the screen width based on the image
  /// width and content constraints.
  bool get imageSticksToScreenWidth => _imgWidth >= editorBodySize.width;

  /// Determines if the image is rotated 90 degrees based on the rotation count.
  bool get _rotated90deg => rotationCount % 2 != 0;

  /// Indicates whether an active scale out gesture is in progress.
  bool _activeScaleOut = false;

  /// Indicates whether the image needs to be decoded.
  bool _imageNeedDecode = false;

  /// Indicates whether the image size has been decoded.
  bool _imageSizeIsDecoded = true;

  /// Generate a fake hero widget to animate between screens.
  bool enableFakeHero = false;

  /// Skip the first update because the outside listener needs one frame
  /// to correctly detect events.
  bool _scaleAllowUpdateHelper = false;

  /// The number of active pointers (touch points).
  int _activePointers = 0;

  /// The area considered for interactive corner gestures.
  late final double _interactiveCornerArea;

  /// Gets the width of the main image.
  double get _imgWidth => _mainImageSize.width;

  /// Gets the height of the main image.
  double get _imgHeight => _mainImageSize.height;

  /// The vertical space for cropping.
  double _cropSpaceVertical = 0;

  /// The horizontal space for cropping.
  double _cropSpaceHorizontal = 0;

  /// The ratio used for cropping, based on the aspect ratio and main image
  /// size.
  double get _ratio =>
      1 / (aspectRatio == 0 ? _mainImageSize.aspectRatio : aspectRatio);

  /// The opacity of the painter.
  double _painterOpacity = 0;

  /// The interaction progress for opacity.
  double _interactionOpacityProgress = 0;

  /// The starting scale value for pinch gestures.
  double _startingPinchScale = 1;

  /// Helper variable to store the initial scale value at the start of a
  /// scaling gesture.
  double _scaleStartZoomHelper = 1;

  /// The starting translate offset for gestures.
  Offset _startingTranslate = Offset.zero;

  /// The view rectangle for the cropping area.
  Rect _viewRect = Rect.zero;

  /// Gets the size of the rendered image based on the constraints and rotation
  /// state.
  Size get _renderedImgSize => Size(
        _rotated90deg
            ? _renderedImgConstraints.maxHeight
            : _renderedImgConstraints.maxWidth,
        _rotated90deg
            ? _renderedImgConstraints.maxWidth
            : _renderedImgConstraints.maxHeight,
      );

  /// Gets the size of the main image, using decoded dimensions if not provided.
  Size get _mainImageSize =>
      mainImageSize ?? imageInfos?.renderedSize ?? Size.zero;

  /// The constraints for the rendered image.
  late BoxConstraints _renderedImgConstraints = const BoxConstraints();

  /// Details of the tap down event for double-tap gestures.
  late TapDownDetails _doubleTapDetails;

  /// The current part of the crop area being interacted with.
  CropAreaPart _currentCropAreaPart = CropAreaPart.none;

  /// Manager class for handling desktop interactions.
  late final CropDesktopInteractionManager _desktopInteractionManager;

  /// Configuration for the fake hero transformation.
  late TransformConfigs _fakeHeroTransformConfigs;

  /// List of layers in the image.
  late List<Layer> _layers;

  /// List of raw layers without any transformation.
  late List<Layer> _rawLayers;

  /// The current cursor style.
  MouseCursor _mouseCursor = SystemMouseCursors.basic;

  bool _hasToolbar = true;

  /// A flag indicating whether the screen has been resized.
  bool _isScreenResized = false;

  /// Sets the current mouse cursor and updates the widget that manages the
  /// cursor.
  set _cursor(MouseCursor cursor) {
    _mouseCursor = cursor;
    _mouseCursorsKey.currentState?.setCursor(cursor);
  }

  double _rotationScaleFactor = 1;

  @override
  CropCornerPainter? get cropPainter {
    return showWidgets
        ? CropCornerPainter(
            offset: translate,
            cropRect: cropRect,
            viewRect: _viewRect,
            scaleFactor: userScaleFactor,
            rotationScaleFactor: _rotationScaleFactor,
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
          )
        : null;
  }

  /// Returns the current mouse cursor style.
  MouseCursor get _cursor => _mouseCursor;

  bool _isVideoPlayerReady = true;

  /// Defines which crop-rotate tools are available in the editor.
  late List<CropRotateTool> tools = [...cropRotateEditorConfigs.tools];

  @override
  void initState() {
    super.initState();

    _initializeVideoEditor();
    // Initialize debounce
    _onScaleEndDebounce = Debounce(const Duration(milliseconds: 10));
    _onScaleAllowUpdateDebounce = Debounce(const Duration(milliseconds: 1));
    _scrollHistoryDebounce = Debounce(const Duration(milliseconds: 350));

    // Initialize controllers
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

    // Initialize image and layers
    _imageNeedDecode = mainImageSize == null;
    _imageSizeIsDecoded = !_imageNeedDecode;
    _layers = initConfigs.layers ?? [];
    _setRawLayers();

    // Initialize rotate animation
    double initAngle = initialTransformConfigs?.angle ?? 0.0;
    rotateCtrl = AnimationController(
        duration: cropRotateEditorConfigs.animationDuration, vsync: this);
    rotateCtrl.addStatusListener((status) {
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

    // Initialize scale animation
    double initScale = (initialTransformConfigs?.scaleRotation ?? 1);
    scaleCtrl = AnimationController(
        duration: cropRotateEditorConfigs.animationDuration, vsync: this);
    scaleAnimation =
        Tween<double>(begin: initScale, end: initScale).animate(scaleCtrl);

    // Initialize aspect ratio
    aspectRatio =
        cropRotateEditorConfigs.initAspectRatio ?? CropAspectRatios.custom;

    // Set pixel ratio if needed
    if (widget.initConfigs.convertToUint8List) {
      setImageInfos(activeHistory: activeHistory);
    }

    // Initialize transform configs if available
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
      _rotationScaleFactor = oldScaleFactor;

      setInitHistory(initialTransformConfigs!);
    }

    // Initialize fake hero settings
    enableFakeHero = initConfigs.enableFakeHero;
    _showFakeHero = enableFakeHero;

    // Perform post-frame initialization
    cropRotateEditorCallbacks?.onInit?.call();

    // TODO: Remove when releasing version 12.0.0.
    tools.removeWhere((el) {
      switch (el) {
        case CropRotateTool.rotate:
          return !cropRotateEditorConfigs.showRotateButton;
        case CropRotateTool.flip:
          return !cropRotateEditorConfigs.showFlipButton;
        case CropRotateTool.aspectRatio:
          return !cropRotateEditorConfigs.showAspectRatioButton;
        case CropRotateTool.reset:
          return !cropRotateEditorConfigs.showResetButton;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      cropRotateEditorCallbacks?.onAfterViewInit?.call();
      initialized = true;
      if (initialTransformConfigs != null &&
          initialTransformConfigs!.isNotEmpty &&
          initialTransformConfigs!.aspectRatio < 0) {
        aspectRatio = initialTransformConfigs!.cropRect.size.aspectRatio;
        calcCropRect(onlyViewRect: initialTransformConfigs?.isEmpty == false);
        aspectRatio = -1;
      } else {
        calcCropRect(onlyViewRect: initialTransformConfigs?.isEmpty == false);
      }

      if (!enableFakeHero) hideFakeHero();
      _updateAllStates();
      _setRawLayers();

      /// Skip one frame to ensure the image is correctly transformed
      Size? originalSize = initialTransformConfigs?.originalSize;
      if (originalSize != null && !originalSize.isInfinite) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          /// Fit to the screen and set duration to zero
          double oldScaleAnimationValue = scaleAnimation.value;
          scaleCtrl.duration = Duration.zero;
          calcFitToScreen();
          scaleCtrl.duration = cropRotateEditorConfigs.animationDuration;

          _setCropRectBounding(oldScaleAnimationValue: oldScaleAnimationValue);
        });
      }
    });
  }

  @override
  void dispose() {
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
  void setState(void Function() fn) {
    rebuildController.add(null);
    super.setState(fn);
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

  double get _transformHelperScale => originalSize.isEmpty
      ? 1
      : TransformHelper(
          mainBodySize: (mainBodySize ?? editorBodySize),
          mainImageSize: _mainImageSize,
          editorBodySize: originalSize,
        ).scale;

  void _updateAllStates() {
    userScaleKey.currentState?.setScale(userScaleFactor);
    cropPainterKey.currentState?.update(
      foregroundPainter: cropPainter,
      isComplex: showWidgets,
      willChange: showWidgets,
    );
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

    final resolution = widget.videoController!.initialResolution;

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

    var decodedImage =
        await decodeImageFromList(await editorImage!.safeByteArray(context));

    if (!mounted) return;
    var w = decodedImage.width;
    var h = decodedImage.height;

    var widthRatio = w.toDouble() / editorBodySize.width;
    var heightRatio = h.toDouble() / editorBodySize.height;
    var pixelRatio = max(heightRatio, widthRatio);
    var renderedSize = Size(w / pixelRatio, h / pixelRatio);

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
    // Skip a few frames to ensure image constraints are set correctly
    Future.delayed(const Duration(milliseconds: 60), () {
      calcCropRect();
      calcFitToScreen();
      _imageSizeIsDecoded = true;
      _updateAllStates();
      cropRotateEditorCallbacks?.handleUpdateUI();
    });
  }

  /// Hides the fake hero widget and updates the related UI states.
  void hideFakeHero() {
    /// Set the fake hero visibility flag to false.
    _showFakeHero = false;

    /// Show other widgets by setting the flag to true.
    showWidgets = true;

    /// Update the state of the crop painter with the current widget visibility.
    cropPainterKey.currentState?.update(
      isComplex: showWidgets,
      willChange: showWidgets,
    );

    /// Animate the opacity transition for the painter.
    loopWithTransitionTiming(
      (double curveT) {
        /// Adjust the painter opacity based on the transition curve.
        _painterOpacity = 1 * curveT;

        /// Update the crop painter with the new opacity.
        cropPainterKey.currentState?.update(foregroundPainter: cropPainter);
      },
      mounted: mounted,
      transitionFunction:
          cropRotateEditorConfigs.fadeInOutsideCropAreaAnimationCurve.transform,
      duration: cropRotateEditorConfigs.fadeInOutsideCropAreaAnimationDuration,
      onDone: takeScreenshot,
    );

    /// Call the method to update all states.
    _updateAllStates();
  }

  bool _onKeyEvent(KeyEvent event) {
    return _desktopInteractionManager.onKey(
      event,
      onRotate: rotate,
      onFlip: flip,
      onTranslate: (offset) async {
        // Calculate correct offset even image is rotated or flipped
        double radianAngle = rotateAnimation.value;
        double cosAngle = cos(radianAngle);
        double sinAngle = sin(radianAngle);

        double dx = offset.dy * sinAngle + offset.dx * cosAngle;
        double dy = offset.dy * cosAngle - offset.dx * sinAngle;

        dx *= (flipX ? -1 : 1);
        dy *= (flipY ? -1 : 1);

        Offset startOffset = translate;
        Offset targetOffset = translate += Offset(dx, dy);

        await loopWithTransitionTiming(
          (double curveT) {
            translate = Offset(
              lerpDouble(startOffset.dx, targetOffset.dx, curveT)!,
              lerpDouble(startOffset.dy, targetOffset.dy, curveT)!,
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
      onScale: (scale) async {
        double startZoom = userScaleFactor;
        double targetZoom = (userScaleFactor + scale)
            .clamp(1, cropRotateEditorConfigs.maxScale);

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
      onUndoRedo: (undo) {
        if (undo) {
          undoAction();
        } else {
          redoAction();
        }
      },
    );
  }

  /// Handles the crop image operation.
  Future<void> done() async {
    if (_interactionActive ||
        (!_imageSizeIsDecoded && initConfigs.convertToUint8List)) {
      return;
    }
    _interactionActive = true;
    initConfigs.callbacks.onImageEditingStarted?.call();

    /// If the user set a custom initAspectRatio we need to enforce add
    /// a history even there was no changes
    if (!canUndo &&
        cropRotateEditorConfigs.initAspectRatio != CropAspectRatios.custom) {
      addHistory();
    }

    TransformConfigs transformC =
        !canRedo && !canUndo && initialTransformConfigs != null
            ? initialTransformConfigs!
            : activeHistory;

    _showFakeHero = enableFakeHero;
    _fakeHeroTransformConfigs = transformC;
    _updateAllStates();

    if (!initConfigs.convertToUint8List) {
      List<Layer> updatedLayers = LayerTransformGenerator(
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

      /// Read the image information in the case the user require them
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
          debugPrint('Generation failed! Retry $retry');

          /// Cooldown for the case the image generation failed
          await Future.delayed(const Duration(milliseconds: 500));
          if (!mounted) return;
        }
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

      if (bytes == null) {
        debugPrint('Failed to capture the final image.');
      }

      if (!mounted) return;

      var imageBytes = bytes ?? Uint8List.fromList([]);

      await initConfigs.callbacks.onImageEditingComplete?.call(imageBytes);

      if (!mounted) return;

      /// Return complete parameters if requested
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

  /// Takes a screenshot of the current editor state.
  @override
  void takeScreenshot() async {
    if (!widget.initConfigs.convertToUint8List) return;

    await setImageInfos(activeHistory: activeHistory, forceUpdate: true);
    // Capture the screenshot in a post-frame callback to ensure the UI is
    //fully rendered.
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

      TransformConfigs transformC =
          !canRedo && !canUndo && initialTransformConfigs != null
              ? initialTransformConfigs!
              : activeHistory;

      await screenshotCtrl.capture(
        imageInfos: imageInfos!,
        screenshots: screenshotHistory,
        /*   targetSize: _rotated90deg
            ? imageInfos!.renderedSize.flipped
            : imageInfos!.renderedSize, */
        widget: _screenshotWidget(transformC),
      );
    });
  }

  /// Flip the image horizontally
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

  /// Rotates the image clockwise.
  void rotate() {
    _blockInteraction = true;
    var piHelper =
        cropRotateEditorConfigs.rotateDirection == RotateDirection.left
            ? -pi
            : pi;

    rotationCount++;
    rotateAnimation = Tween<double>(
            begin: rotateAnimation.value, end: rotationCount * piHelper / 2)
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

  @override
  calcFitToScreen({
    Curve? curve,
    Size? imageSize,
    bool animated = true,
  }) {
    if (!animated) scaleCtrl.duration = Duration.zero;

    final EdgeInsets margin = cropRotateEditorConfigs.boundaryMargin;
    Size contentSize = Size(
      editorBodySize.width - margin.horizontal,
      editorBodySize.height - margin.vertical,
    );

    double cropSpaceHorizontal =
        _rotated90deg ? _cropSpaceVertical : _cropSpaceHorizontal;
    double cropSpaceVertical =
        _rotated90deg ? _cropSpaceHorizontal : _cropSpaceVertical;

    Size renderedSize = imageSize ?? _renderedImgSize;

    double scaleX =
        contentSize.width / (renderedSize.width - cropSpaceHorizontal);
    double scaleY =
        contentSize.height / (renderedSize.height - cropSpaceVertical);

    double scale = min(scaleX, scaleY);

    scaleAnimation = Tween<double>(begin: oldScaleFactor, end: scale).animate(
      CurvedAnimation(
        parent: scaleCtrl,
        curve: curve ?? cropRotateEditorConfigs.rotateAnimationCurve,
      ),
    );
    scaleCtrl
      ..reset()
      ..forward();

    double startRotateFactor = oldScaleFactor;
    double targetRotateFactor = scale;

    oldScaleFactor = scale;

    cropPainterKey.currentState?.setForegroundPainter(cropPainter);

    if (!startRotateFactor.isInfinite &&
        !startRotateFactor.isNaN &&
        !targetRotateFactor.isInfinite &&
        !targetRotateFactor.isNaN) {
      loopWithTransitionTiming(
        (double curveT) {
          _rotationScaleFactor =
              lerpDouble(startRotateFactor, targetRotateFactor, curveT)!;
          cropPainterKey.currentState?.setForegroundPainter(cropPainter);
        },
        mounted: mounted,
        duration: cropRotateEditorConfigs.animationDuration,
        transitionFunction:
            (curve ?? cropRotateEditorConfigs.rotateAnimationCurve).transform,
      );
    } else {
      _rotationScaleFactor = 1;
    }

    if (!animated) {
      scaleCtrl.duration = cropRotateEditorConfigs.animationDuration;
    }
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
      double ratio = cropRect.size.aspectRatio;

      /// If the cropRect is to small or it will fit to both sizes we choose
      /// from the aspect ratio.
      if ((fitToWidth && fitToHeight) ||
          (!fitToHeight &&
              !fitToWidth &&
              cropRect.width < _renderedImgSize.width &&
              cropRect.height < _renderedImgSize.height)) {
        fitToHeight = ratio < editorBodySize.aspectRatio;
        fitToWidth = !fitToHeight;
      }

      /// return if the cropRect has already the correct size
      if (!fitToWidth && !fitToHeight) return;

      Size oldSize = cropRect.size;

      calcCropRect(newRatio: 1 / ratio);

      /// Fit to the screen and set duration to zero
      calcFitToScreen(animated: false);

      double scaleFactor = fitToHeight
          ? cropRect.height / oldSize.height
          : cropRect.width / oldSize.width;

      /// Seems like this calculation is not required but it there is an issue
      /// we should multiply it below with the scaleFactor
      /// double scaleFitFactor = oldScaleAnimationValue == null ||
      /// _renderedImgSize.aspectRatio < ratio ?
      ///     1 :
      ///     scaleAnimation.value / oldScaleAnimationValue;

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

  /// Opens a dialog to select from predefined aspect ratios.
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
            )).then((value) {
      if (value != null) {
        updateAspectRatio(value);
      }
    });
  }

  /// Updates the current aspect ratio with a new value and adds a new history
  /// entry.
  ///
  /// This method performs the following steps:
  /// 1. Resets the editor state while skipping the addition of a history entry.
  /// 2. Updates the aspect ratio to the provided value.
  /// 3. Triggers any necessary callbacks related to the new aspect ratio.
  /// 4. Recalculates the crop rectangle and fits it to the screen.
  /// 5. Adds a new history entry with the current scale factor and a rotation
  /// angle of zero.
  /// 6. Updates all relevant states in the editor.
  void updateAspectRatio(double value) {
    aspectRatio = value;
    cropRotateEditorCallbacks?.handleRatioSelected(value);

    calcCropRect();
    calcFitToScreen();
    _setOffsetLimits();
    addHistory(scaleRotation: oldScaleFactor);
    _updateAllStates();
  }

  late CropMode _cropMode = widget.initConfigs.transformConfigs?.cropMode ??
      cropRotateEditorConfigs.initialCropMode;

  /// Gets the current crop mode.
  ///
  /// Returns [CropMode.circular] if the round cropper is enabled,
  /// otherwise returns [CropMode.rectangular].
  @override
  CropMode get cropMode => _cropMode;

  /// Sets the crop mode.
  ///
  /// If [value] is [CropMode.circular], it enables the round cropper,
  /// sets the aspect ratio to 1 (square), and updates the internal state.
  /// If [value] is [CropMode.rectangular], it disables the round cropper
  /// and updates the internal state accordingly.
  @override
  set cropMode(CropMode value) => setCropMode(value);

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
    double imgSizeRatio = _imgHeight / _imgWidth;

    var imgConstraints = _renderedImgConstraints.biggest.isInfinite
        ? imageInfos?.renderedSize ?? _renderedImgConstraints.biggest
        : _renderedImgConstraints.biggest;

    double imgW = imgConstraints.width;
    double imgH = imgConstraints.height;

    double realImgW = imageSticksToScreenWidth ? imgW : imgH / imgSizeRatio;
    double realImgH = imageSticksToScreenWidth ? imgW * imgSizeRatio : imgH;

    // Rect stick horizontal
    double ratio = newRatio ?? (_ratio > 0 ? _ratio : imgSizeRatio);
    double left = 0;
    double top = 0;

    if (imgSizeRatio >= ratio) {
      double newH = realImgW * ratio;
      top = (realImgH - newH) / 2;
      realImgH = newH;
    }
    // Rect stick vertical
    else {
      double newW = realImgH / ratio;
      left = (realImgW - newW) / 2;
      realImgW = newW;
    }

    _cropSpaceVertical = top * 2;
    _cropSpaceHorizontal = left * 2;

    if (!onlyViewRect) {
      cropRect = Rect.fromLTWH(left, top, realImgW, realImgH);
    }
    _viewRect = Rect.fromLTWH(left, top, realImgW, realImgH);
    cropPainterKey.currentState?.setForegroundPainter(cropPainter);
  }

  CropAreaPart _determineCropAreaPart(Offset localPosition) {
    Offset offset =
        _getRealHitPoint(zoom: userScaleFactor, position: localPosition) +
            translate * userScaleFactor;
    double dx = offset.dx;
    double dy = offset.dy;
    if (cropMode == CropMode.oval) {
      double halfWidth = cropRect.width / 2;
      double halfHeight = cropRect.height / 2;
      double halfInteractiveCornerArea = _interactiveCornerArea / 2;

      // Normalize against expanded ellipse for hit area
      double ellipseHitX = dx / (halfWidth + halfInteractiveCornerArea);
      double ellipseHitY = dy / (halfHeight + halfInteractiveCornerArea);
      bool isWithinHitArea =
          (ellipseHitX * ellipseHitX + ellipseHitY * ellipseHitY) <= 1;

      // Normalize against exact ellipse for inside check
      double normalizedX = dx / (halfWidth - halfInteractiveCornerArea);
      double normalizedY = dy / (halfHeight - halfInteractiveCornerArea);
      bool isInsideEllipse =
          (normalizedX * normalizedX + normalizedY * normalizedY) <= 1;

      if (isWithinHitArea) {
        double cursorAreaHitWidth = halfWidth * 0.5;
        double cursorAreaHitHeight = halfHeight * 0.5;

        bool nearTopEdge = dy < -cursorAreaHitHeight;
        bool nearBottomEdge = dy > cursorAreaHitHeight;
        bool nearLeftEdge = dx < -cursorAreaHitWidth;
        bool nearRightEdge = dx > cursorAreaHitWidth;

        if (isInsideEllipse) {
          return CropAreaPart.inside;
        }
        // Bottom Left
        else if (nearBottomEdge && nearLeftEdge) {
          return CropAreaPart.bottomLeft;
        }
        // Bottom Right
        else if (nearBottomEdge && nearRightEdge) {
          return CropAreaPart.bottomRight;
        }
        // Top Left
        else if (nearTopEdge && nearLeftEdge) {
          return CropAreaPart.topLeft;
        }
        // Top Right
        else if (nearTopEdge && nearRightEdge) {
          return CropAreaPart.topRight;
        }
        // Bottom
        else if (nearBottomEdge) {
          return CropAreaPart.bottom;
        }
        // Top
        else if (nearTopEdge) {
          return CropAreaPart.top;
        }
        // Left
        else if (nearLeftEdge) {
          return CropAreaPart.left;
        }
        // Right
        else if (nearRightEdge) {
          return CropAreaPart.right;
        }

        return CropAreaPart.inside;
      } else {
        return CropAreaPart.none;
      }
    }

    Rect rect = Rect.fromCenter(
      center: cropRect.center - translate,
      width: cropRect.width + _interactiveCornerArea,
      height: cropRect.height + _interactiveCornerArea,
    );

    double halfCropWidth = rect.width / 2;
    double halfCropHeight = rect.height / 2;

    double left = dx + halfCropWidth;
    double right = dx - halfCropWidth;
    double top = dy + halfCropHeight;
    double bottom = dy - halfCropHeight;

    bool nearLeftEdge = left.abs() <= _interactiveCornerArea;
    bool nearRightEdge = right.abs() <= _interactiveCornerArea;
    bool nearTopEdge = top.abs() <= _interactiveCornerArea;
    bool nearBottomEdge = bottom.abs() <= _interactiveCornerArea;

    if (rect.contains(localPosition)) {
      if (nearLeftEdge && nearTopEdge) {
        return CropAreaPart.topLeft;
      } else if (nearRightEdge && nearTopEdge) {
        return CropAreaPart.topRight;
      } else if (nearLeftEdge && nearBottomEdge) {
        return CropAreaPart.bottomLeft;
      } else if (nearRightEdge && nearBottomEdge) {
        return CropAreaPart.bottomRight;
      } else if (nearLeftEdge) {
        return CropAreaPart.left;
      } else if (nearRightEdge) {
        return CropAreaPart.right;
      } else if (nearTopEdge) {
        return CropAreaPart.top;
      } else if (nearBottomEdge) {
        return CropAreaPart.bottom;
      } else {
        return CropAreaPart.inside;
      }
    } else {
      return CropAreaPart.none;
    }
  }

  // /// Updates the scale factor for the image based on a pinch gesture value.
  // ///
  // /// This method calculates the new zoom level by multiplying the starting
  // /// pinch scale with the provided [value] and clamping it between 1.0 and
  // /// the configured maximum scale. It also adjusts the translation offset to
  // /// maintain the focal point at the center of the zoom operation.
  // ///
  // /// The method performs the following steps:
  // /// 1. Calculates the new zoom level within allowed bounds
  // /// 2. Computes the center offset to preserve the zoom focal point
  // /// 3. Updates the translation and user scale factor
  // /// 4. Applies offset limits and triggers scale callbacks
  // void setScale(double value) {
  //   double newZoom = (_startingPinchScale * value)
  //       .clamp(1.0, cropRotateEditorConfigs.maxScale);

  //   // Calculate the center offset point from the new zoomed view
  //   Offset centerZoomOffset =
  //       _startingCenterOffset * _startingPinchScale / newZoom;

  //   // Update translation and zoom values
  //   translate = _startingTranslate - _startingCenterOffset + centerZoomOffset;
  //   userScaleFactor = newZoom;

  //   // Set offset limits and trigger widget rebuild
  //   _setOffsetLimits();
  //   cropRotateEditorCallbacks?.handleScale();
  // }

  void _zoomOutside() async {
    const int frameHelper = 1000 ~/ 60;
    while (userScaleFactor > 1 && _activeScaleOut) {
      double oldZoom = userScaleFactor;

      double zoomFactor = 0.025;
      userScaleFactor -= zoomFactor;
      userScaleFactor = max(1, userScaleFactor);

      var zoomOutsideWidth = _viewRect.width / oldZoom * userScaleFactor;
      var zoomOutsideHeight = _viewRect.height / oldZoom * userScaleFactor;

      double offsetHelperX = 0;
      double offsetHelperY = 0;

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
          offsetHelperX *= -1;
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
          offsetHelperY *= -1;
        }
      }

      Offset offsetHelper = Offset(offsetHelperX, offsetHelperY);

      translate -= offsetHelper / userScaleFactor / 2;

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
    _lastScale = 1.0; // Reset für neue Gesture

    if (!_scaleStarted) {
      /// On desktop devices we detect always in `onPointerHover` events.
      if (!isDesktop) {
        _currentCropAreaPart = _determineCropAreaPart(details.localFocalPoint);
      }

      loopWithTransitionTiming(
        (double curveT) {
          _interactionOpacityProgress = 1 * curveT;
          cropPainterKey.currentState!.setForegroundPainter(cropPainter);
        },
        mounted: mounted,
        transitionFunction: Curves.decelerate.transform,
        duration: cropRotateEditorConfigs.opacityOutsideCropAreaDuration,
      );
    }

    _scaleAllowUpdateHelper = false;
    _onScaleAllowUpdateDebounce(() {
      _scaleAllowUpdateHelper = true;
    });

    _interactionActive = true;
    _scaleStarted = true;
    _blockInteraction = false;
  }

  /// Calculates the offset of the editor screen.
  ///
  /// This method determines the position of the editor content on the screen
  /// by converting the local coordinates of the render box to global
  /// coordinates.
  ///
  /// Returns an [Offset] representing the position of the editor content.
  /// If the editor content context is null, it returns [Offset.zero].
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

    if (details.pointerCount == 2) {
      final double desiredScale = _scaleStart! * details.scale;
      double newZoom =
          _applyScaleChange(desiredScale / userScaleFactor) * userScaleFactor;

      if (newZoom < 0.01) newZoom = 0.01;

      final Offset center =
          Offset(editorBodySize.width / 2, editorBodySize.height / 2);
      final Offset focalNewLocal =
          details.focalPoint - _editorScreenOffsetHelper;
      final Offset focalOldLocal = _lastFocal - _editorScreenOffsetHelper;

      final Offset panDelta = (focalNewLocal - focalOldLocal) / newZoom;
      final Offset zoomDelta =
          (focalOldLocal - center) * (1 / newZoom - 1 / userScaleFactor);

      translate += zoomDelta;
      translate += _getPhysicsAppliedDelta(panDelta);

      userScaleFactor = newZoom;
      _lastFocal = details.focalPoint;

      cropRotateEditorCallbacks?.handleScale();
    } else {
      if (_currentCropAreaPart != CropAreaPart.none &&
          _currentCropAreaPart != CropAreaPart.inside) {
        Offset offset = _getRealHitPoint(
              zoom: _startingPinchScale,
              position: details.localFocalPoint,
            ) +
            _startingTranslate * _startingPinchScale;

        double imgW = _renderedImgConstraints.maxWidth;
        double imgH = _renderedImgConstraints.maxHeight;

        double halfSpaceHorizontal = _cropSpaceHorizontal / 2;
        double halfSpaceVertical = _cropSpaceVertical / 2;

        final EdgeInsets margin = cropRotateEditorConfigs.boundaryMargin;

        double cornerGap =
            cropRotateEditorConfigs.style.cropCornerLength * 2.25;
        double minCornerDistance = cornerGap;

        double halfViewRectW = _viewRect.width / 2;
        double halfViewRectH = _viewRect.height / 2;

        double circleGapX = 0;
        double circleGapY = 0;

        if (cropMode == CropMode.oval) {
          circleGapX = sqrt(pow(halfViewRectW, 2) -
                  pow(min(offset.dy.abs(), halfViewRectW), 2)) -
              halfViewRectW;
          circleGapY = sqrt(pow(halfViewRectH, 2) -
                  pow(min(offset.dx.abs(), halfViewRectH), 2)) -
              halfViewRectH;

          circleGapX *= -offset.dx.sign;
          circleGapY *= -offset.dy.sign;
        }

        double dx =
            offset.dx + halfViewRectW + halfSpaceHorizontal + circleGapX;
        double dy = offset.dy + halfViewRectH + halfSpaceVertical + circleGapY;

        double maxRight = cropRect.right + margin.right - minCornerDistance;
        double maxBottom = cropRect.bottom + margin.bottom - minCornerDistance;

        double minLeft = halfSpaceHorizontal;
        double minRight = imgW - halfSpaceHorizontal;
        double minTop = halfSpaceVertical;
        double minBottom = imgH - halfSpaceVertical;

        bool isFreeAspectRatio = _ratio < 0;
        if (isFreeAspectRatio) {
          minLeft = -(imgW * userScaleFactor / 2 -
              _viewRect.width / 2 -
              halfSpaceHorizontal -
              translate.dx * userScaleFactor);
          minRight = imgW +
              (imgW * userScaleFactor / 2 -
                  _viewRect.width / 2 -
                  halfSpaceHorizontal +
                  translate.dx * userScaleFactor);
          minTop = -(imgH * userScaleFactor / 2 -
              _viewRect.height / 2 -
              halfSpaceVertical -
              translate.dy * userScaleFactor);
          minBottom = imgH +
              (imgH * userScaleFactor / 2 -
                  _viewRect.height / 2 -
                  halfSpaceVertical +
                  translate.dy * userScaleFactor);
        }

        Size realViewRectSize = _viewRect.size * scaleAnimation.value;
        if (_rotated90deg) {
          realViewRectSize =
              Size(realViewRectSize.height, realViewRectSize.width);
        }

        double doubleInteractiveArea = _interactiveCornerArea * 2;

        double zoomOutHitAreaX = max(
            margin.left / 2,
            (editorBodySize.width - realViewRectSize.width) / 2 -
                doubleInteractiveArea);
        double zoomOutHitAreaY = max(
            margin.top / 2,
            (editorBodySize.height - realViewRectSize.height) / 2 -
                doubleInteractiveArea);

        double outsideHitPosY = details.focalPoint.dy -
            _editorScreenOffsetHelper.dy -
            (_hasToolbar ? kToolbarHeight : 0) -
            MediaQuery.paddingOf(context).top;

        bool outsideLeft =
            details.focalPoint.dx - _editorScreenOffsetHelper.dx <
                zoomOutHitAreaX;
        bool outsideRight =
            details.focalPoint.dx - _editorScreenOffsetHelper.dx >
                editorBodySize.width - zoomOutHitAreaX;
        bool outsideTop = outsideHitPosY < zoomOutHitAreaY;
        bool outsideBottom =
            outsideHitPosY > editorBodySize.height - zoomOutHitAreaY;

        // Scale outside when the user move outside the scale area
        if (!isFreeAspectRatio &&
            (outsideLeft || outsideRight || outsideTop || outsideBottom)) {
          if (!_activeScaleOut) {
            _activeScaleOut = true;
            _zoomOutside();
          }
        } else if (!_activeScaleOut ||
            (offset.dx.abs() < _viewRect.width / 2 - _interactiveCornerArea)) {
          _activeScaleOut = false;
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

          if (_ratio >= 0 && cropRect.size.aspectRatio != _ratio) {
            if (_currentCropAreaPart == CropAreaPart.left ||
                _currentCropAreaPart == CropAreaPart.right) {
              cropRect = Rect.fromCenter(
                center: cropRect.center,
                width: cropRect.width,
                height: cropRect.width * _ratio,
              );
            } else if (_currentCropAreaPart == CropAreaPart.top ||
                _currentCropAreaPart == CropAreaPart.bottom) {
              cropRect = Rect.fromCenter(
                center: cropRect.center,
                width: cropRect.height / _ratio,
                height: cropRect.height,
              );
            } else if (_currentCropAreaPart == CropAreaPart.topLeft ||
                _currentCropAreaPart == CropAreaPart.topRight) {
              double gapBottom = _viewRect.height - cropRect.bottom;
              cropRect = Rect.fromLTRB(
                cropRect.left,
                _viewRect.height - gapBottom - cropRect.width * _ratio,
                cropRect.right,
                cropRect.bottom,
              );
            } else if (_currentCropAreaPart == CropAreaPart.bottomLeft ||
                _currentCropAreaPart == CropAreaPart.bottomRight) {
              cropRect = Rect.fromLTRB(
                cropRect.left,
                cropRect.top,
                cropRect.right,
                cropRect.width * _ratio + cropRect.top,
              );
            }
          }
        }

        cropPainterKey.currentState!.update(foregroundPainter: cropPainter);
      } else {
        double scaleFactor = userScaleFactor / _scaleStartZoomHelper;

        Offset delta =
            Offset(details.focalPointDelta.dx, details.focalPointDelta.dy) /
                scaleFactor *
                (cropRotateEditorConfigs.invertDragDirection ? -1 : 1);
        translate += _getPhysicsAppliedDelta(delta);

        cropRotateEditorCallbacks?.handleMove();

        cropPainterKey.currentState!.update(foregroundPainter: cropPainter);
      }
    }
    _blockInteraction = false;
  }

  Offset _getPhysicsAppliedDelta(Offset panDelta) {
    final Offset currentOffset = translate * -1;
    final ScrollMetrics metricsX =
        _calculateScrollMetrics(currentOffset.dx, AxisDirection.right);
    final ScrollMetrics metricsY =
        _calculateScrollMetrics(currentOffset.dy, AxisDirection.down);

    final double proposedX = currentOffset.dx - panDelta.dx;
    final double proposedY = currentOffset.dy - panDelta.dy;

    final double overscrollX = panDelta.dx == 0
        ? 0
        : cropRotateEditorConfigs.scrollPhysics
            .applyBoundaryConditions(metricsX, proposedX);
    final double overscrollY = panDelta.dy == 0
        ? 0
        : cropRotateEditorConfigs.scrollPhysics
            .applyBoundaryConditions(metricsY, proposedY);

    if (overscrollX == 0 && overscrollY == 0) {
      final double dx = panDelta.dx == 0
          ? 0
          : cropRotateEditorConfigs.scrollPhysics
              .applyPhysicsToUserOffset(metricsX, panDelta.dx);
      final double dy = panDelta.dy == 0
          ? 0
          : cropRotateEditorConfigs.scrollPhysics
              .applyPhysicsToUserOffset(metricsY, panDelta.dy);
      return Offset(dx, dy);
    } else {
      return Offset(panDelta.dx + overscrollX, panDelta.dy + overscrollY);
    }
  }

  double _applyScaleChange(double scale) {
    // Compute current and desired scales
    final double currentScale = userScaleFactor;
    // scale provided is a desired change in scale between the current scale
    // and the start of the gesture
    final double scaleChange = scale;

    // desired but not necessarily achieved if physics is applied
    final double desiredScale = currentScale * scale;

    // Early return if not allowed to zoom outside bounds
    if (!_shouldAllowScale(desiredScale)) {
      // Clamp the overall scale
      final double clampedTotalScale =
          clampDouble(desiredScale, 1, cropRotateEditorConfigs.maxScale);
      final double clampedScale = clampedTotalScale / currentScale;
      return clampedScale;
    }

    // Compute ratio of this update's scale to the previous update
    final double scaleRatio = scaleChange / _lastScale;
    // Store for next frame
    _lastScale = scaleChange;
    // Physics requires the incremental scale change since last update
    final double incrementalScale = currentScale * scaleRatio;

    if (((desiredScale < 1) ||
        (desiredScale > cropRotateEditorConfigs.maxScale))) {
      final contentSize = _renderedImgConstraints.biggest;

      // Compute current and desired absolute scale
      final double contentWidth = contentSize.width * currentScale;
      final double desiredContentWidth = contentSize.width * incrementalScale;
      final double contentHeight = contentSize.height * currentScale;
      final double desiredContentHeight = contentSize.height * incrementalScale;

      // Build horizontal and vertical metrics
      final ScrollMetrics metricsX = FixedScrollMetrics(
        pixels: contentWidth,
        minScrollExtent: contentSize.width * 1,
        maxScrollExtent: contentSize.width * cropRotateEditorConfigs.maxScale,
        viewportDimension: contentSize.width * cropRotateEditorConfigs.maxScale,
        axisDirection: AxisDirection.right,
        devicePixelRatio: 1.0,
      );
      final ScrollMetrics metricsY = FixedScrollMetrics(
        pixels: contentHeight,
        minScrollExtent: contentSize.height * 1,
        maxScrollExtent: contentSize.height * cropRotateEditorConfigs.maxScale,
        viewportDimension:
            contentSize.height * cropRotateEditorConfigs.maxScale,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 1.0,
      );

      // Compute content deltas
      final double deltaX = desiredContentWidth - contentWidth;
      final double deltaY = desiredContentHeight - contentHeight;

      // Apply scroll physics half the delta to simulate exeeding a boundary
      // on one side
      final double adjustedX = cropRotateEditorConfigs.scrollPhysics
              .applyPhysicsToUserOffset(metricsX, deltaX / 2) *
          2;
      final double adjustedY = cropRotateEditorConfigs.scrollPhysics
              .applyPhysicsToUserOffset(metricsY, deltaY / 2) *
          2;

      // Convert back to scale factors
      final double newScaleX = (contentWidth + adjustedX) / contentWidth;
      final double newScaleY = (contentHeight + adjustedY) / contentHeight;
      final double factor = (newScaleX + newScaleY) / 2;

      return factor;
    } else {
      final double clampedTotalScale =
          clampDouble(desiredScale, 1, cropRotateEditorConfigs.maxScale);
      final double clampedScale = clampedTotalScale / currentScale;

      // Apply the scale factor to the matrix
      return clampedScale;
    }
  }

  /// Determines whether [proposedScale] can be applied without clamping,
  /// by probing the widget.scrollPhysics.
  bool _shouldAllowScale(double proposedScale) {
    final contentSize = _renderedImgConstraints.biggest;

    final double currentScale = userScaleFactor;
    final double contentWidth = contentSize.width * currentScale;
    final double desiredContentWidth = contentSize.width * proposedScale;
    final double contentHeight = contentSize.height * currentScale;
    final double desiredContentHeight = contentSize.height * proposedScale;

    final ScrollMetrics metricsX = FixedScrollMetrics(
      pixels: contentWidth,
      minScrollExtent: contentSize.width * 1,
      maxScrollExtent: contentSize.width * cropRotateEditorConfigs.maxScale,
      viewportDimension: _viewRect.width,
      axisDirection: AxisDirection.right,
      devicePixelRatio: 1.0,
    );
    final ScrollMetrics metricsY = FixedScrollMetrics(
      pixels: contentHeight,
      minScrollExtent: contentSize.height * 1,
      maxScrollExtent: contentSize.height * cropRotateEditorConfigs.maxScale,
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
    final double x = _simulationX?.x(t) ?? translate.dx * -1;
    final double y = _simulationY?.x(t) ?? translate.dy * -1;
    translate = Offset(-x, -y);

    if (_simulationScale != null) {
      final double simulatedScrollPos = _simulationScale!.x(t);
      final scale = simulatedScrollPos / 1000;
      userScaleFactor = scale;
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_blockInteraction) return;
    _blockInteraction = true;
    _interactionActive = false;

    _onScaleEndDebounce(() {
      if (_activePointers <= 0) {
        _scaleStarted = false;
        loopWithTransitionTiming(
          (double curveT) {
            _interactionOpacityProgress = 1 - 1 * curveT;
            cropPainterKey.currentState!.setForegroundPainter(cropPainter);
          },
          mounted: mounted,
          duration: cropRotateEditorConfigs.opacityOutsideCropAreaDuration,
        );
      }
    });

    _activeScaleOut = false;

    if (cropRect != _viewRect) {
      Rect interpolatedRect(Rect initRect, Rect targetRect, double curveT) {
        return Rect.fromLTRB(
          lerpDouble(initRect.left, targetRect.left, curveT)!,
          lerpDouble(initRect.top, targetRect.top, curveT)!,
          lerpDouble(initRect.right, targetRect.right, curveT)!,
          lerpDouble(initRect.bottom, targetRect.bottom, curveT)!,
        );
      }

      if (cropRect.isEmpty) {
        _blockInteraction = false;
        return;
      }

      Rect initRect = Rect.fromCenter(
          center: _viewRect.center,
          width: _viewRect.width,
          height: _viewRect.height);
      Duration animationDuration =
          cropRotateEditorConfigs.cropDragAnimationDuration;
      Curve animationCurve = cropRotateEditorConfigs.cropDragAnimationCurve;

      /// Recalculate crop rect when aspect ratio is set to `free`
      if (_ratio < 0) {
        calcCropRect(
          onlyViewRect: true,
          newRatio: 1 / cropRect.size.aspectRatio,
        );
        scaleCtrl.duration = animationDuration;
        calcFitToScreen(curve: animationCurve);
        scaleCtrl.duration = cropRotateEditorConfigs.animationDuration;
      }

      Rect startCropRect = cropRect;
      Rect targetCropRect = _viewRect;

      double startZoom = userScaleFactor;
      double targetZoom = min(
        userScaleFactor *
            targetCropRect.size.longestSide /
            startCropRect.size.longestSide,
        cropRotateEditorConfigs.maxScale,
      );

      Offset startOffset = translate;
      Offset targetOffset = startOffset -
          Offset(
                (startCropRect.left -
                    (targetCropRect.right - startCropRect.right) -
                    _cropSpaceHorizontal / 2),
                (startCropRect.top -
                    (targetCropRect.bottom - startCropRect.bottom) -
                    _cropSpaceVertical / 2),
              ) /
              startZoom /
              2;

      loopWithTransitionTiming(
        (double curveT) {
          userScaleFactor = lerpDouble(startZoom, targetZoom, curveT)!;
          translate = Offset.lerp(startOffset, targetOffset, curveT)!;
          cropRect = interpolatedRect(startCropRect, targetCropRect, curveT);
          _setOffsetLimits(
            rect: _ratio < 0
                ? interpolatedRect(initRect, targetCropRect, curveT)
                : null,
          );
        },
        mounted: mounted,
        duration: animationDuration,
        transitionFunction: animationCurve.transform,
      ).whenComplete(() {
        cropRect = targetCropRect;
        translate = targetOffset;
        userScaleFactor = targetZoom;
        _setOffsetLimits();
        calcFitToScreen();
        cropRotateEditorCallbacks?.handleResize();
        addHistory();
        _blockInteraction = false;
      });
      return;
    }
    addHistory();

    if (details.pointerCount <= 0) {
      _stopAllAnimations();
      addHistory();

      const double minScale = 1.0;
      final double maxScale = cropRotateEditorConfigs.maxScale;

      final ScrollMetrics scaleMetrics = FixedScrollMetrics(
        pixels: userScaleFactor * 1000,
        minScrollExtent: minScale * 1000,
        maxScrollExtent: maxScale * 1000,
        viewportDimension: 0,
        axisDirection: AxisDirection.down,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      );

      _simulationScale = cropRotateEditorConfigs.scrollPhysics
          .createBallisticSimulation(scaleMetrics, 0.0);

      final Offset adjustedOffset = translate * -1;
      final double targetScale =
          userScaleFactor.clamp(1.0, cropRotateEditorConfigs.maxScale);
      final double currentScale = userScaleFactor;
      final double flingVelocityX = math.min(
              (details.velocity.pixelsPerSecond.dx / currentScale).abs(),
              cropRotateEditorConfigs.scrollPhysics.maxFlingVelocity) *
          details.velocity.pixelsPerSecond.dx.sign;
      final double flingVelocityY = math.min(
              (details.velocity.pixelsPerSecond.dy / currentScale).abs(),
              cropRotateEditorConfigs.scrollPhysics.maxFlingVelocity) *
          details.velocity.pixelsPerSecond.dy.sign;

      final ScrollMetrics metricsX =
          _calculateScrollMetrics(adjustedOffset.dx, AxisDirection.right);
      final ScrollMetrics metricsY =
          _calculateScrollMetrics(adjustedOffset.dy, AxisDirection.down);

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

      _flingCtrl.addStatusListener((status) {
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

  /// Calculate pan boundaries based on current scale and view rect.
  Rect _panBoundaries(double scale) {
    final double maxX =
        (_renderedImgConstraints.maxWidth * scale - _viewRect.width) /
            2 /
            scale;
    final double maxY =
        (_renderedImgConstraints.maxHeight * scale - _viewRect.height) /
            2 /
            scale;
    return Rect.fromLTRB(
      -max(0.0, maxX),
      -max(0.0, maxY),
      max(0, maxX),
      max(0, maxY),
    );
  }

  /// Build scroll metrics for applying [ScrollPhysics].
  ScrollMetrics _calculateScrollMetrics(
    double pixels,
    AxisDirection axisDirection, {
    double? scale,
  }) {
    final Rect bounds = _panBoundaries(scale ?? userScaleFactor);
    final Axis axis = (axisDirection == AxisDirection.left ||
            axisDirection == AxisDirection.right)
        ? Axis.horizontal
        : Axis.vertical;
    return FixedScrollMetrics(
      pixels: pixels,
      minScrollExtent: axis == Axis.horizontal ? bounds.left : bounds.top,
      maxScrollExtent: axis == Axis.horizontal ? bounds.right : bounds.bottom,
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
    double clampValue(double value, double min, double max) {
      if (value < min) {
        return min;
      } else if (value > max) {
        return max;
      } else {
        return value;
      }
    }

    if (!cropRotateEditorConfigs.enableDoubleTap || _blockInteraction) return;
    _blockInteraction = true;

    cropRotateEditorCallbacks?.handleDoubleTap();

    bool zoomInside = userScaleFactor <= 1;
    double startZoom = userScaleFactor;
    double targetZoom =
        zoomInside ? cropRotateEditorConfigs.doubleTapScaleFactor : 1;
    Offset startOffset = translate;

    Offset targetOffset = zoomInside
        ? (translate -
            Offset(
              _doubleTapDetails.localPosition.dx -
                  _renderedImgConstraints.maxWidth / 2,
              _doubleTapDetails.localPosition.dy -
                  _renderedImgConstraints.maxHeight / 2,
            ))
        : Offset.zero;

    double maxOffsetX =
        (_renderedImgConstraints.maxWidth * targetZoom - _viewRect.width) /
            2 /
            targetZoom;
    double maxOffsetY =
        (_renderedImgConstraints.maxHeight * targetZoom - _viewRect.height) /
            2 /
            targetZoom;

    /// direct double clamp trigger an error on android samsung s10 so better
    /// use own solution to clamp
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
    Rect r = rect ?? _viewRect;

    double cropWidth = r.width;
    double cropHeight = r.height;

    double minX =
        (_renderedImgConstraints.maxWidth * userScaleFactor - cropWidth) /
            2 /
            userScaleFactor;
    double minY =
        (_renderedImgConstraints.maxHeight * userScaleFactor - cropHeight) /
            2 /
            userScaleFactor;

    Offset offset = translate;

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
    // Check if interaction is blocked
    if (_blockInteraction) return;

    if (event is PointerScrollEvent) {
      // Define zoom factor and extract vertical scroll delta
      double factor = cropRotateEditorConfigs.mouseScaleFactor *
          (event.scrollDelta.dy / 50).abs().clamp(0.5, 2);

      double deltaY = event.scrollDelta.dy *
          (cropRotateEditorConfigs.invertMouseScroll ? -1 : 1);

      double startZoom = userScaleFactor;
      double newZoom = userScaleFactor;
      // Adjust zoom based on scroll direction
      if (deltaY > 0) {
        newZoom -= factor;
        newZoom = max(1, newZoom);
      } else if (deltaY < 0) {
        newZoom += factor;
        newZoom = min(cropRotateEditorConfigs.maxScale, newZoom);
      }

      // Calculate the center offset point from the old zoomed view
      Offset centerOffset = translate +
          _getRealHitPoint(zoom: startZoom, position: event.localPosition) /
              startZoom;
      // Calculate the center offset point from the new zoomed view
      Offset centerZoomOffset = centerOffset * startZoom / newZoom;

      // Update translation and zoom values
      translate -= centerOffset - centerZoomOffset;
      userScaleFactor = newZoom;

      // Set offset limits and trigger widget rebuild
      _setOffsetLimits();
      _setMouseCursor();
      _scrollHistoryDebounce(() {
        addHistory();
        cropRotateEditorCallbacks?.handleScale();
        cropPainterKey.currentState!.setForegroundPainter(cropPainter);
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

      RotateAngleSide angle = getRotateAngleSide(rotateAnimation.value);
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
            debugPrint('Invalid cursor number!');
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

      RotateAngleSide angle = getRotateAngleSide(rotateAnimation.value);
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
            debugPrint('Invalid cursor number!');
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
        if (userScaleFactor > 1 ||
            cropRect.size.aspectRatio.toStringAsFixed(3) !=
                (_rotated90deg
                        ? 1 / _renderedImgSize.aspectRatio
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
    double imgW = _renderedImgConstraints.maxWidth;
    double imgH = _renderedImgConstraints.maxHeight;

    // Calculate the transformed local position of the pointer
    Offset transformedLocalPosition = position * zoom;
    // Calculate the size of the transformed image
    Size transformedImgSize = Size(imgW, imgH) * zoom;

    // Calculate the center offset point from the old zoomed view
    return Offset(
      transformedLocalPosition.dx - transformedImgSize.width / 2,
      transformedLocalPosition.dy - transformedImgSize.height / 2,
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
          onPopInvokedWithResult: (didPop, _) {
            _showFakeHero = true;
            _updateAllStates();
          },
          child: LayoutBuilder(builder: (context, constraints) {
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: cropRotateEditorConfigs.style.uiOverlayStyle,
              child: Theme(
                data: theme.copyWith(
                    tooltipTheme:
                        theme.tooltipTheme.copyWith(preferBelow: true)),
                child: Scaffold(
                  resizeToAvoidBottomInset: false,
                  backgroundColor:
                      cropRotateEditorConfigs.style.background?.call(context) ??
                          kImageEditorBackground,
                  appBar: _buildAppBar(constraints),
                  body: Center(
                    child: SizedBox(
                      width: constraints.maxWidth *
                          (cropRotateEditorConfigs.maxWidthFactor ??
                              (!kIsWeb && Platform.isAndroid ? 0.9 : 1)),
                      child: _buildBody(),
                    ),
                  ),
                  bottomNavigationBar: _buildBottomAppBar(),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  /// Builds the app bar for the editor, including buttons for actions such as
  /// back, rotate, aspect ratio, and done.
  PreferredSizeWidget? _buildAppBar(BoxConstraints constraints) {
    if (cropRotateEditorConfigs.widgets.appBar != null) {
      var customToolbar = cropRotateEditorConfigs.widgets.appBar!
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
            onRotate: rotate,
            onFlip: flip,
            onOpenAspectRatioOptions: openAspectRatioOptions,
            onReset: reset,
          )
        : null;
  }

  Widget _buildBody() {
    return SafeArea(
      top: cropRotateEditorConfigs.safeArea.top,
      bottom: cropRotateEditorConfigs.safeArea.bottom,
      left: cropRotateEditorConfigs.safeArea.left,
      right: cropRotateEditorConfigs.safeArea.right,
      child: ScreenResizeDetector(
        ignoreSafeArea: false,
        onResizeUpdate: (event) {
          if (event.oldContentSize != event.newContentSize &&
              !event.oldContentSize.isEmpty) {
            _isScreenResized = true;
          }

          if (editorBodySize != event.newContentSize) {
            editorBodySize = event.newContentSize;
            cropPainterKey.currentState?.setForegroundPainter(cropPainter);
          }

          final EdgeInsets margin = cropRotateEditorConfigs.boundaryMargin;
          cropEditorScreenRatio = Size(
            editorBodySize.width - margin.horizontal,
            editorBodySize.height - margin.vertical,
          ).aspectRatio;
        },
        onResizeEnd: (event) {
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
                  width: 60,
                  height: 60,
                  child: FittedBox(
                    child: PlatformCircularProgressIndicator(configs: configs),
                  ),
                ),
              ),
            AnimatedOpacity(
              duration: !initConfigs.convertToUint8List
                  ? Duration.zero
                  : const Duration(milliseconds: 160),
              opacity: _showFakeHero || !_imageSizeIsDecoded ? 0 : 1,
              child: HeroMode(
                enabled: false,
                child: _buildMouseCursor(
                  child: DeferredPointerHandler(
                    child: _buildRotationTransform(
                      child: _buildFlipTransform(
                        child: _buildRotationScaleTransform(
                          child: _buildPaintContainer(
                            child: _buildCropPainter(
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
            if (cropRotateEditorConfigs.widgets.bodyItems != null)
              ...cropRotateEditorConfigs.widgets.bodyItems!(
                  this, rebuildController.stream),
          ],
        ),
      ),
    );
  }

  Widget _buildMouseCursor({required Widget child}) {
    return ExtendedRebuildMouseRegion(
      key: _mouseCursorsKey,
      initCursor: _cursor,
      child: child,
    );
  }

  Widget _buildEventListener({required Widget child}) {
    /// Control the GestureDetector directly from this OutsideListener that
    /// both listeners can't block the events between them
    return OutsideListener(
      behavior: OutsideHitTestBehavior.all,
      onPointerDown: (event) {
        _gestureKey.currentState!.rawKey.currentState!.handlePointerDown(event);
        if (_activePointers == 0) _scaleStartZoomHelper = userScaleFactor;
        _activePointers++;
        _stopFlingAnimation();
      },
      onPointerUp: (event) {
        _activePointers--;
      },
      onPointerPanZoomStart: (event) {
        _gestureKey.currentState!.rawKey.currentState!
            .handlePointerPanZoomStart(event);
      },
      onPointerSignal: isDesktop ? _mouseScroll : null,
      onPointerHover: isDesktop
          ? (event) {
              var area = _determineCropAreaPart(event.localPosition);
              if (area != _currentCropAreaPart) {
                _currentCropAreaPart = area;
                _setMouseCursor();
              }
            }
          : null,
      child: child,
    );
  }

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

  AnimatedBuilder _buildRotationTransform({required Widget child}) {
    return AnimatedBuilder(
      animation: rotateAnimation,
      builder: (context, child) => Transform.rotate(
        angle: rotateAnimation.value,
        alignment: Alignment.center,
        child: child,
      ),
      child: child,
    );
  }

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
      builder: (context, scaleX, child) {
        return TweenAnimationBuilder<double>(
          duration: cropRotateEditorConfigs.animationDuration,
          tween: Tween<double>(begin: 1.0, end: flipY ? -1.0 : 1.0),
          curve: cropRotateEditorConfigs.flipAnimationCurve,
          builder: (context, scaleY, child) {
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(scaleX, scaleY, 1),
              child: child,
            );
          },
          child: child,
        );
      },
      child: child,
    );
  }

  Widget _buildUserScaleTransform({required Widget child}) {
    return ExtendedTransformScale(
      key: userScaleKey,
      initScale: userScaleFactor,
      alignment: Alignment.center,
      child: child,
    );
  }

  Widget _buildTranslate({required Widget child}) {
    return ExtendedTransformTranslate(
      key: translateKey,
      initOffset: translate,
      child: child,
    );
  }

  Widget _buildRotationScaleTransform({required Widget child}) {
    return AnimatedBuilder(
      animation: scaleAnimation,
      builder: (context, child) => Transform.scale(
        scale: scaleAnimation.value,
        alignment: Alignment.center,
        child: child,
      ),
      child: child,
    );
  }

  Widget _buildCropPainter({required Widget child}) {
    return ExtendedCustomPaint(
      key: cropPainterKey,
      initIsComplex: showWidgets,
      initWillChange: showWidgets,
      initForegroundPainter: cropPainter?.copy(),
      child: child,
    );
  }

  Widget _buildPaintContainer({required Widget child}) {
    return Align(
      alignment: Alignment.center,
      child: Padding(
        padding: EdgeInsets.zero ?? cropRotateEditorConfigs.boundaryMargin,
        child: child,
      ),
    );
  }

  Widget _buildImage() {
    final EdgeInsets margin = cropRotateEditorConfigs.boundaryMargin;
    final double availableHeight = editorBodySize.height - margin.vertical;
    final double availableWidth = editorBodySize.width - margin.horizontal;
    double maxWidth = _imgWidth / _imgHeight * availableHeight;
    double maxHeight = availableWidth * _imgHeight / _imgWidth;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxWidth.isNaN ? _imgWidth : maxWidth,
        maxHeight: maxHeight.isNaN ? _imgHeight : maxHeight,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
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
                      /// set size to zero that no scale factor will be applied
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

  Widget _buildFakeHero() {
    return Padding(
      padding: cropRotateEditorConfigs.boundaryMargin,
      child: LayoutBuilder(builder: (context, constraints) {
        return Stack(
          alignment: Alignment.center,
          fit: StackFit.expand,
          children: [
            Hero(
              tag: heroTag,
              createRectTween: (begin, end) =>
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
      }),
    );
  }

  Widget _screenshotWidget(TransformConfigs transformC) {
    Size size =
        _rotated90deg ? imageInfos!.rawSize.flipped : imageInfos!.rawSize;

    double w = size.width;
    double h = size.height;
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

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);

    properties
      // General configuration
      ..add(DiagnosticsProperty<CropRotateEditorInitConfigs>(
          'initConfigs', widget.initConfigs))
      ..add(
          DiagnosticsProperty<EditorImage?>('editorImage', widget.editorImage))
      ..add(DiagnosticsProperty<ProVideoController?>(
          'videoController', widget.videoController))

      // Crop/Transform state
      ..add(
          DiagnosticsProperty<TransformConfigs>('activeHistory', activeHistory))
      ..add(IntProperty('rotationCount', rotationCount))
      ..add(FlagProperty('flipX', value: flipX, ifTrue: 'flipped X'))
      ..add(FlagProperty('flipY', value: flipY, ifTrue: 'flipped Y'))
      ..add(DoubleProperty('aspectRatio', aspectRatio))
      ..add(EnumProperty<CropMode>('cropMode', cropMode))
      ..add(DoubleProperty('userScaleFactor', userScaleFactor))
      ..add(DoubleProperty('oldScaleFactor', oldScaleFactor))
      ..add(DoubleProperty('rotationScaleFactor', _rotationScaleFactor))
      ..add(DiagnosticsProperty<Offset>('translate', translate))
      ..add(DiagnosticsProperty<Rect>('cropRect', cropRect))
      ..add(DiagnosticsProperty<Rect>('viewRect', _viewRect))

      // Status flags
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

      // Sizes
      ..add(DiagnosticsProperty<Size>('editorBodySize', editorBodySize))
      ..add(DiagnosticsProperty<Size>('mainImageSize', _mainImageSize))
      ..add(DiagnosticsProperty<Size>('renderedImgSize', _renderedImgSize))
      ..add(DiagnosticsProperty<BoxConstraints>(
          'renderedImgConstraints', _renderedImgConstraints))

      // Input
      ..add(DiagnosticsProperty<MouseCursor>('mouseCursor', _mouseCursor))
      ..add(IntProperty('activePointers', _activePointers));
  }
}
