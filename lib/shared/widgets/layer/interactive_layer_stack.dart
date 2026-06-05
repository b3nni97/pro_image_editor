import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '/core/models/editor_callbacks/pro_image_editor_callbacks.dart';
import '/core/models/editor_configs/pro_image_editor_configs.dart';
import '/core/models/layers/layer.dart';
import '/core/models/transform_helper.dart';
import '/core/services/mouse_service.dart';
import '/core/utils/size_utils.dart';
import '/features/crop_rotate_editor/enums/crop_mode.enum.dart';
import '/features/crop_rotate_editor/widgets/crop_layer_painter.dart';
import '/features/main_editor/services/layer_interaction_manager.dart';
import '/plugins/defer_pointer/defer_pointer.dart';
import '/shared/utils/debounce.dart';
import '/shared/utils/unique_id_generator.dart';
import '/shared/widgets/extended/interactive_viewer/extended_interactive_viewer.dart';
import '/shared/widgets/extended/mouse_region/extended_rebuild_mouse_region.dart';
import '/shared/widgets/layer/layer_widget.dart';
import '/shared/widgets/layer/services/sub_editor_layer_interaction_service.dart';

/// An interactive layer stack that provides full layer interaction support
/// including selection, move, scale, rotate, helper lines, and remove area.
///
/// Used by both the main editor and sub-editors (Tune, Filter, Blur).
/// All features are built-in — the host editor just passes config and
/// callbacks. No separate helper line or remove area widgets needed.
class InteractiveLayerStack extends StatefulWidget {
  /// Creates an [InteractiveLayerStack].
  const InteractiveLayerStack({
    super.key,
    required this.configs,
    required this.layers,
    required this.overlayColor,
    required this.editorBodySize,
    this.interactiveViewerKey,
    this.callbacks = const ProImageEditorCallbacks(),
    this.transformHelper = const TransformHelper(
      editorBodySize: Size.zero,
      mainBodySize: Size.zero,
      mainImageSize: Size.zero,
    ),
    this.cutOutsideImageArea,
    this.clipBehavior = Clip.hardEdge,
    this.onTextLayerTap,
    this.onPaintLayerEdit,
    this.onLayerRemoved,
    this.onLayersChanged,
    this.onBeforeLayerChange,
    // ──── Shared features ────
    this.layerInteractionManager,
    this.mouseService,
    this.isInteractive = true,
    this.enableHero = false,
    this.enableHelperLines = true,
    this.enableRemoveArea = true,
    this.heroResetStream,
    this.uiLayerStream,
    this.onCheckInteractiveViewer,
    this.onAddHistory,
    this.onUIUpdate,
    this.onLayerTapDown,
    this.onLayerTapUp,
    this.onEditSticker,
    this.onDuplicateLayer,
    this.onContextMenuToggled,
    this.onHoverRemoveAreaChange,
    this.onTakeScreenshot,
    this.onRemoveLayer,
    this.getActiveLayers,
    this.getEnableMultiSelectMode,
    this.isDragSelectionActive = false,
    this.editorSize,
    this.appBarHeight = 0,
    this.bottomBarHeight = 0,
  });

  // ──────────── Required parameters ──────────────

  /// The configuration settings for the image editor.
  final ProImageEditorConfigs configs;

  /// Editor callbacks.
  final ProImageEditorCallbacks callbacks;

  /// The mutable list of layers to be displayed and interacted with.
  final List<Layer> layers;

  /// The outside overlay color for layers.
  final Color overlayColor;

  /// The size of the editor body.
  final Size editorBodySize;

  // ──────────── Common optional parameters ──────────────

  /// The clipping behavior applied to the layer stack.
  final Clip clipBehavior;

  /// Transformation helper for calculating layer positions.
  final TransformHelper transformHelper;

  /// Determines whether to cut content outside the image area.
  final bool? cutOutsideImageArea;

  /// Key for the [ExtendedInteractiveViewer] so we can manually
  /// enable/disable its interaction and forward gesture events.
  final GlobalKey<ExtendedInteractiveViewerState>? interactiveViewerKey;

  /// Called when a text layer is tapped for editing.
  final void Function(TextLayer layer)? onTextLayerTap;

  /// Called when a paint layer is tapped for editing.
  final void Function(PaintLayer layer)? onPaintLayerEdit;

  /// Called when a layer is removed via the service (e.g. delete button).
  final void Function(Layer layer)? onLayerRemoved;

  /// Called when layers have been modified (moved, scaled, rotated).
  final VoidCallback? onLayersChanged;

  /// Called once before a layer interaction starts (drag, scale, remove).
  /// The host editor should save the current state to history here.
  final VoidCallback? onBeforeLayerChange;

  // ──────────── Layer interaction features ──────────────

  /// An external [LayerInteractionManager] to use instead of creating one.
  final LayerInteractionManager? layerInteractionManager;

  /// Mouse service for desktop pointer event handling.
  final MouseService? mouseService;

  /// Whether layers are interactive.
  final bool isInteractive;

  /// Whether to enable hero animations on layers.
  final bool enableHero;

  /// Whether to show helper lines during layer dragging.
  final bool enableHelperLines;

  /// Whether to show the remove area when dragging layers.
  final bool enableRemoveArea;

  /// Stream that triggers a hero-reset (hides layers momentarily).
  final Stream<bool>? heroResetStream;

  /// Stream that triggers layer UI rebuilds from outside.
  final Stream<void>? uiLayerStream;

  /// Called to check and toggle the InteractiveViewer state.
  final VoidCallback? onCheckInteractiveViewer;

  /// Called to add a history entry (for undo/redo).
  final void Function(List<Layer> layers)? onAddHistory;

  /// Called for additional UI updates (stream notifications).
  final VoidCallback? onUIUpdate;

  /// Called when a layer receives a tap-down event.
  final void Function(Layer layer)? onLayerTapDown;

  /// Called when a layer receives a tap-up event.
  final void Function(Layer layer)? onLayerTapUp;

  /// Called when a sticker/widget layer is tapped for editing.
  final void Function(Layer layer)? onEditSticker;

  /// Called when a layer should be duplicated.
  final void Function(Layer layer)? onDuplicateLayer;

  /// Called when a context menu is toggled on a layer.
  final void Function(bool isOpen)? onContextMenuToggled;

  /// Called when the hover state of the remove area changes.
  final void Function(bool isHovering)? onHoverRemoveAreaChange;

  /// Called to take a screenshot after layer interaction ends.
  /// If [replaceLastScreenshot] is true, the last screenshot is replaced.
  final void Function({bool replaceLastScreenshot})? onTakeScreenshot;

  /// Called when layers are removed via drag-to-delete.
  /// Unlike [onLayerRemoved], this handles the full removal flow
  /// (removing from list, clearing selection, callbacks).
  final void Function(Layer layer)? onRemoveLayer;

  /// Returns the currently active layers.
  final List<Layer> Function()? getActiveLayers;

  /// Returns whether multi-select mode is enabled externally.
  final bool Function()? getEnableMultiSelectMode;

  /// Whether drag selection is currently active (disables mouse cursor).
  final bool isDragSelectionActive;

  /// The full editor size (including toolbars). Used for helper lines.
  /// Defaults to [editorBodySize] if not provided.
  final Size? editorSize;

  /// Height of the app bar, used for helper line margins.
  final double appBarHeight;

  /// Height of the bottom bar, used for helper line margins.
  final double bottomBarHeight;

  @override
  State<InteractiveLayerStack> createState() => _InteractiveLayerStackState();
}

class _InteractiveLayerStackState extends State<InteractiveLayerStack> {
  late final LayerInteractionManager _layerInteractionManager;
  late final LayerInteractionService _layersService;
  late final StreamController<void> _uiLayerCtrl;
  late final StreamController<void> _helperLineCtrl;
  late final StreamController<void> _removeBtnCtrl;

  final GlobalKey _removeAreaKey = GlobalKey();
  final _mouseCursorsKey = GlobalKey<ExtendedRebuildMouseRegionState>();
  final _deferId = ValueNotifier(generateUniqueId());

  Size _editorBodySize = Size.infinite;
  bool _isLayerBeingTransformed = false;

  /// Number of fingers currently touching the layer stack area.
  int _activePointerCount = 0;

  /// Whether this has an external manager (e.g. main editor).
  bool get _isMainEditorMode => widget.layerInteractionManager != null;

  bool get _cutOutsideImageArea =>
      widget.cutOutsideImageArea ??
      widget.configs.imageGeneration.cropToImageBounds;

  TransformConfigs? get _transformConfigs =>
      widget.transformHelper.transformConfigs?.isNotEmpty == true
          ? widget.transformHelper.transformConfigs
          : null;

  List<Layer> get _selectedLayers => widget.layers
      .where((l) => _layerInteractionManager.selectedLayerIds.contains(l.id))
      .toList();

  bool get _hasSelectedLayers =>
      _layerInteractionManager.selectedLayerIds.isNotEmpty;

  ExtendedInteractiveViewerState? get _viewer =>
      widget.interactiveViewerKey?.currentState;

  double get _editorScaleFactor =>
      (_viewer?.scaleFactor ?? 1.0) * widget.transformHelper.scale;

  Offset get _editorScaleOffset => _viewer?.offset ?? Offset.zero;

  // ── Drift tracking (debug) ──
  Offset _debugInitialLayerOffset = Offset.zero;
  Offset _debugCumulativeDelta = Offset.zero;
  Offset _debugInitialFocal = Offset.zero;
  double _debugInitialScale = 1.0;

  /// Tracks the previous pointer count to detect 2→1 finger transitions.
  int _lastPointerCount = 0;

  /// When a 2→1 pointer drop is detected, records the focal point position.
  /// Movement is suppressed until the finger moves > 5px from this point.
  Offset? _pointerDropFocal;

  HelperLineConfigs get _helperLines => widget.configs.helperLines;

  Size get _editorSize => widget.editorSize ?? _editorBodySize;

  @override
  void initState() {
    super.initState();
    _uiLayerCtrl = StreamController.broadcast();
    _helperLineCtrl = StreamController.broadcast();
    _removeBtnCtrl = StreamController.broadcast();

    // Use external manager if provided, otherwise create our own.
    _layerInteractionManager = widget.layerInteractionManager ??
        LayerInteractionManager(
          configs: widget.configs,
          helperLinesCallbacks: null,
          onSelectedLayersChanged: (_) {},
        );

    if (widget.layerInteractionManager == null) {
      _layerInteractionManager.scaleDebounce = Debounce(
        const Duration(milliseconds: 100),
      );
    }

    _layersService = LayerInteractionService(
      configs: widget.configs,
      layerInteraction: _layerInteractionManager,
      mouseService: widget.mouseService,
      getIsMounted: () => mounted,
      getActiveLayers: widget.getActiveLayers ?? () => widget.layers,
      onCheckInteractiveViewer:
          widget.onCheckInteractiveViewer ?? _checkInteractiveViewer,
      getIsLayerBeingTransformed: () => _isLayerBeingTransformed,
      getEnableMultiSelectMode: widget.getEnableMultiSelectMode,
      onUpdateState: () {
        if (mounted) setState(() {});
      },
      onTextLayerTap: widget.onTextLayerTap,
      onPaintLayerEdit: widget.onPaintLayerEdit,
      onLayerRemoved: (layer) {
        widget.onBeforeLayerChange?.call();
        widget.layers.remove(layer);
        widget.onLayerRemoved?.call(layer);
        widget.onLayersChanged?.call();
        if (mounted) setState(() {});
      },
      onAddHistory: widget.onAddHistory,
      onUIUpdate: () {
        _uiLayerCtrl.add(null);
        widget.onUIUpdate?.call();
      },
      onLayerTapDownCallback: widget.onLayerTapDown,
      onLayerTapUpCallback: (layer) {
        widget.onLayerTapUp?.call(layer);
        if (_isMainEditorMode) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _deferId.value = generateUniqueId();
          });
        }
      },
      onEditSticker: widget.onEditSticker,
    )..init();
  }

  @override
  void dispose() {
    _uiLayerCtrl.close();
    _helperLineCtrl.close();
    _removeBtnCtrl.close();
    super.dispose();
  }

  // ───────── Gesture Routing ─────────────────────────────────────

  void _checkInteractiveViewer() {
    _viewer?.setEnableInteraction(!_hasSelectedLayers);
  }

  /// Called when a pointer lifts. If all fingers are gone on mobile,
  /// deselect layers so the InteractiveViewer becomes usable.
  void _onAllPointersUp() {
    if (_activePointerCount > 0) return;
    if (!_hasSelectedLayers) return;
    if (isDesktop) return;

    _layerInteractionManager.clearSelectedLayers();
    _checkInteractiveViewer();
    setState(() {});
  }

  void _onScaleStart(ScaleStartDetails details) {

    if (!_hasSelectedLayers) {
      _viewer?.onScaleStart(details);
      return;
    }

    // Save history before the interaction.
    widget.onBeforeLayerChange?.call();
    if (widget.onAddHistory != null) {
      widget.onAddHistory!(widget.layers);
    }

    _checkInteractiveViewer();
    _isLayerBeingTransformed = _hasSelectedLayers;
    _layerInteractionManager.onScaleStart(
      details: details,
      selectedLayers: _selectedLayers,
    );

    // Debug: record starting state for drift tracking
    if (_selectedLayers.isNotEmpty) {
      _debugInitialLayerOffset = _selectedLayers.first.offset;
      _debugCumulativeDelta = Offset.zero;
      _debugInitialFocal = details.focalPoint;
      _debugInitialScale = _editorScaleFactor;
    }

    setState(() {});
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (!_hasSelectedLayers) {
      _viewer?.onScaleUpdate(details);
      return;
    }

    final int pointerCount = details.pointerCount;

    bool beforeShowHorizontalHelperLine =
        _layerInteractionManager.showHorizontalHelperLine;
    bool beforeShowVerticalHelperLine =
        _layerInteractionManager.showVerticalHelperLine;
    bool beforeShowRotationHelperLine =
        _layerInteractionManager.showRotationHelperLine;

    void checkUpdateHelperLineUI() {
      if (beforeShowHorizontalHelperLine !=
              _layerInteractionManager.showHorizontalHelperLine ||
          beforeShowVerticalHelperLine !=
              _layerInteractionManager.showVerticalHelperLine ||
          beforeShowRotationHelperLine !=
              _layerInteractionManager.showRotationHelperLine) {
        _helperLineCtrl.add(null);
      }
    }

    if (_layerInteractionManager.rotateScaleLayerSizeHelper != null) {
      _layerInteractionManager.calculateInteractiveButtonScaleRotate(
        configs: widget.configs,
        selectedLayers: _selectedLayers,
        details: details,
        editorSize: _editorBodySize,
        layerTheme: widget.configs.layerInteraction.style,
        editorScaleFactor: _editorScaleFactor,
        editorScaleOffset: _editorScaleOffset,
      );
      for (Layer layer in _selectedLayers) {
        layer.key.currentState?.setState(() {});
      }
      checkUpdateHelperLineUI();
      return;
    }

    _layerInteractionManager.enabledHitDetection = false;

    // Detect 2→1 pointer transition (one finger lifted from pinch).
    // Use a distance-based dead zone to prevent accidental displacement:
    // movement is suppressed until the remaining finger moves > 5px
    // from where it was at the moment the second finger lifted.
    if (_lastPointerCount == 2 && pointerCount == 1) {
      _pointerDropFocal = details.localFocalPoint;
    }
    _lastPointerCount = pointerCount;

    if (pointerCount == 1) {
      // Skip movement until finger has moved beyond the dead zone.
      if (_pointerDropFocal != null) {
        final dist = (details.localFocalPoint - _pointerDropFocal!).distance;
        if (dist < 5.0) {
          return;
        }
        // Dead zone cleared — allow movement from now on.
        _pointerDropFocal = null;
      }
      _debugCumulativeDelta += details.focalPointDelta;
      _layerInteractionManager.calculateMovement(
        editorScaleFactor: _editorScaleFactor,
        removeAreaKey: _removeAreaKey,
        selectedLayers: _selectedLayers,
        layerList: widget.layers,
        context: context,
        detail: details,
        onHoveredRemoveChanged: (value) {
          _removeBtnCtrl.add(null);
          widget.onHoverRemoveAreaChange?.call(value);
        },
        helperLineCtrl: _helperLineCtrl,
      );

    } else if (pointerCount == 2) {
      _layerInteractionManager.calculateScaleRotate(
        configs: widget.configs,
        selectedLayers: _selectedLayers,
        detail: details,
        editorSize: _editorBodySize,
        screenPaddingHelper: EdgeInsets.zero,
        editorScaleFactor: _editorScaleFactor,
      );
    }

    for (Layer layer in _selectedLayers) {
      layer.key.currentState?.setState(() {});
    }
    checkUpdateHelperLineUI();
    widget.onLayersChanged?.call();
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _layerInteractionManager.activeInteractionLayer = null;

    // Check if layers should be removed (drag-to-delete).
    if (_layerInteractionManager.hoverRemoveBtn) {
      for (Layer layer in _layerInteractionManager.selectedLayersScaleStart) {
        widget.layers.remove(layer);
        widget.onRemoveLayer?.call(layer);
      }
      _layerInteractionManager.clearSelectedLayers();
    }

    if (!_hasSelectedLayers) {
      _viewer?.onScaleEnd(details);

      // Check for non-selectable layer transform.
      if (!isDesktop &&
          _layerInteractionManager.layerWasTransformed &&
          widget.configs.layerInteraction.selectable !=
              LayerInteractionSelectable.enabled) {
        widget.onTakeScreenshot?.call(replaceLastScreenshot: true);
      }
    } else {
      // Take screenshot since history was already added in onScaleStart.
      widget.onTakeScreenshot?.call(replaceLastScreenshot: true);
      if (!widget.configs.layerInteraction.keepSelectionOnInteraction) {
        _layerInteractionManager.clearSelectedLayers();
      }
    }

    _isLayerBeingTransformed = false;
    _checkInteractiveViewer();
    _uiLayerCtrl.add(null);
    _layerInteractionManager.onScaleEnd();

    setState(() {});
  }

  void _handleMouseHover(PointerHoverEvent event) {
    final bool hasHit = widget.layers
        .any((element) => element is PaintLayer && element.item.hit);

    final activeCursor = _mouseCursorsKey.currentState!.currentCursor;
    final moveCursor = widget.configs.layerInteraction.style.hoverCursor;

    if (hasHit && activeCursor != moveCursor) {
      _mouseCursorsKey.currentState!.setCursor(moveCursor);
    } else if (!hasHit && activeCursor != SystemMouseCursors.basic) {
      _mouseCursorsKey.currentState!.setCursor(SystemMouseCursors.basic);
    }
  }

  // ─────────────────────────── Build ───────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final innerContent = LayoutBuilder(builder: (context, constraints) {
      _editorBodySize = getValidSizeOrDefault(
        widget.editorBodySize,
        constraints.biggest,
      );
      return _buildLayerContent();
    });

    // Wrap with hero-reset stream if provided.
    if (widget.heroResetStream != null) {
      return StreamBuilder<bool>(
        stream: widget.heroResetStream,
        initialData: false,
        builder: (_, resetSnapshot) {
          if (resetSnapshot.data!) return const SizedBox.shrink();
          return innerContent;
        },
      );
    }

    return innerContent;
  }

  Widget _buildLayerContent() {
    Widget layerStack = Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      clipBehavior: widget.clipBehavior,
      children: widget.layers.map((layerItem) {
        return _buildLayerWidget(layerItem);
      }).toList(),
    );

    // Apply transform scale for sub-editors.
    if (widget.transformHelper.scale != 1.0) {
      layerStack = Transform.scale(
        scale: widget.transformHelper.scale,
        child: layerStack,
      );
    }

    // Build the gesture-wrapped layer content.
    // Override touchSlop to near-zero so the ScaleGestureRecognizer
    // accepts almost immediately — the layer follows the finger without
    // the default ~18px slop delay.
    Widget content = MediaQuery(
      data: MediaQuery.of(context).copyWith(
        gestureSettings: const DeviceGestureSettings(touchSlop: 1),
      ),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _activePointerCount++,
        onPointerUp: (_) {
          _activePointerCount--;
          _onAllPointersUp();
        },
        onPointerCancel: (_) {
          _activePointerCount--;
          _onAllPointersUp();
        },
        child: GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          child: Stack(
          children: [
            if (_cutOutsideImageArea)
              ClipPath(
                clipper: _ImageBoundsClipper(
                  imgRatio: _transformConfigs?.cropRect.size.aspectRatio ??
                      widget.transformHelper.mainImageSize.aspectRatio,
                  is90DegRotated: _transformConfigs?.is90DegRotated ?? false,
                  isOval: _transformConfigs?.isOvalCropper ??
                      widget.configs.cropRotateEditor.initialCropMode ==
                          CropMode.oval,
                ),
                child: layerStack,
              )
            else
              layerStack,
            if (_cutOutsideImageArea)
              IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    foregroundPainter: _buildCropPainter(),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
          ],
        ),
      ),
      ),
    );

    // Wrap with UI stream rebuild.
    final gestureContent = content;
    content = StreamBuilder(
      stream: _uiLayerCtrl.stream,
      builder: (context, snapshot) => gestureContent,
    );

    // Wrap with DeferredPointerHandler for desktop.
    if (_isMainEditorMode) {
      final streamContent = content;
      content = ValueListenableBuilder(
        valueListenable: _deferId,
        builder: (_, deferId, __) {
          return DeferredPointerHandler(
            id: deferId,
            selectedLayerId: _layerInteractionManager.selectedLayerId,
            child: streamContent,
          );
        },
      );
    }

    // Wrap with mouse cursor handling for desktop.
    if (_isMainEditorMode) {
      final deferContent = content;
      content = ExtendedRebuildMouseRegion(
        key: _mouseCursorsKey,
        onHover: isDesktop ? _handleMouseHover : null,
        child: deferContent,
      );
    }

    // Build the final stack with helper lines and remove area overlays.
    return Stack(
      children: [
        content,
        if (widget.enableHelperLines) _buildHelperLines(),
        if (widget.enableRemoveArea) _buildRemoveArea(),
      ],
    );
  }

  // ──────────── Layer Widget ────────────────────────────────────

  Widget _buildLayerWidget(Layer layer) {
    return LayerWidget(
      key: layer.key,
      layer: layer,
      configs: widget.configs,
      callbacks: widget.callbacks,
      layersService: _layersService,
      layerInteractionManager: _layerInteractionManager,
      editorBodySize: _editorBodySize,
      isInteractive: widget.isInteractive,
      editorScaleFactor: _editorScaleFactor,
      enableHero: widget.enableHero,
      enableMouseCursor:
          _isMainEditorMode ? !widget.isDragSelectionActive : true,
      onDuplicate: widget.onDuplicateLayer != null
          ? () => widget.onDuplicateLayer!(layer)
          : null,
      onContextMenuToggled: widget.onContextMenuToggled,
    );
  }

  // ──────────── Helper Lines ────────────────────────────────────

  Widget _buildHelperLines() {
    if (!_layerInteractionManager.showHelperLines) {
      return const SizedBox.shrink();
    }

    final helperLines = _helperLines;
    final strokeWidth = helperLines.style.strokeWidth;

    return RepaintBoundary(
      child: StreamBuilder(
        stream: _removeBtnCtrl.stream,
        builder: (_, __) {
          return StreamBuilder<void>(
            stream: _helperLineCtrl.stream,
            builder: (context, snapshot) {
              final scale = _editorScaleFactor;
              final offset = _editorScaleOffset;
              final screenSize = _editorSize;
              final editorBodySize = _editorBodySize;

              if (helperLines.isDisabledAtZoom && scale > 1) {
                return const SizedBox.shrink();
              }

              final isRemoval = _layerInteractionManager.hoverRemoveBtn;

              return Transform.translate(
                offset: offset,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (helperLines.showVerticalLine)
                      _buildHelperLine(
                        key: const ValueKey('Screen-Vertical-Guide-Line'),
                        width:
                            _layerInteractionManager.showVerticalHelperLine &&
                                    !isRemoval
                                ? strokeWidth
                                : 0,
                        height: screenSize.height * scale,
                        left: editorBodySize.width / 2 * scale,
                        top: 0,
                        color: helperLines.style.verticalColor,
                      ),
                    if (helperLines.showHorizontalLine)
                      _buildHelperLine(
                        key: const ValueKey('Screen-Horizontal-Guide-Line'),
                        width: screenSize.width * scale,
                        height:
                            _layerInteractionManager.showHorizontalHelperLine &&
                                    !isRemoval
                                ? strokeWidth
                                : 0,
                        left: 0,
                        top: editorBodySize.height / 2 * scale,
                        color: helperLines.style.horizontalColor,
                        margin: widget.configs.layerInteraction
                                .hideToolbarOnInteraction
                            ? EdgeInsets.only(
                                top: widget.appBarHeight,
                                bottom: widget.bottomBarHeight,
                              )
                            : null,
                      ),
                    if (helperLines.showRotateLine)
                      _buildRotateLine(
                          scale, screenSize.height * 2, strokeWidth),
                    if (helperLines.showLayerAlignLine)
                      ..._buildLayerAlignLines(scale, screenSize, strokeWidth),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildHelperLine({
    required double width,
    required double height,
    required double left,
    required double top,
    required Color color,
    Key? key,
    EdgeInsets? margin,
  }) {
    return Positioned(
      key: key,
      left: left,
      top: top,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: width,
        height: height,
        margin: margin,
        color: color,
      ),
    );
  }

  Widget _buildRotateLine(double scale, double height, double strokeWidth) {
    return Positioned(
      left: _layerInteractionManager.rotationHelperLineX * scale,
      top: _layerInteractionManager.rotationHelperLineY * scale,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Transform.rotate(
          angle: _layerInteractionManager.rotationHelperLineDeg,
          child: AnimatedContainer(
            key: const ValueKey('Rotation-Guide-Line'),
            duration: const Duration(milliseconds: 100),
            width: _layerInteractionManager.showRotationHelperLine &&
                    !_layerInteractionManager.hoverRemoveBtn
                ? strokeWidth
                : 0,
            height: height,
            color: _helperLines.style.rotateColor,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildLayerAlignLines(
      double scale, Size screenSize, double strokeWidth) {
    final editorCenter = _editorBodySize / 2;
    final halfStroke = strokeWidth / 2;

    final verticalOffset = (editorCenter.width +
            _layerInteractionManager.verticalGuideOffset.dx -
            halfStroke) *
        scale;

    final horizontalOffset = (editorCenter.height +
            _layerInteractionManager.horizontalGuideOffset.dy -
            halfStroke) *
        scale;

    final isRemoval = _layerInteractionManager.hoverRemoveBtn;
    final showHorizontal =
        _layerInteractionManager.isHorizontalGuideVisible && !isRemoval;
    final showVertical =
        _layerInteractionManager.isVerticalGuideVisible && !isRemoval;

    return [
      if (showHorizontal)
        _buildHelperLine(
          key: const ValueKey('Horizontal-Guide-Line'),
          width: screenSize.width * scale,
          height: strokeWidth,
          top: horizontalOffset,
          left: 0,
          color: _helperLines.style.layerAlignColor,
        ),
      if (showVertical)
        _buildHelperLine(
          key: const ValueKey('Vertical-Guide-Line'),
          width: strokeWidth,
          height: screenSize.height * scale,
          top: 0,
          left: verticalOffset,
          color: _helperLines.style.layerAlignColor,
        ),
    ];
  }

  // ──────────── Remove Area ─────────────────────────────────────

  Widget _buildRemoveArea() {
    return Positioned(
      key: _removeAreaKey,
      top: 0,
      left: 0,
      child: SafeArea(
        bottom: false,
        child: StreamBuilder(
          stream: _removeBtnCtrl.stream,
          builder: (_, __) => _buildRemoveWidget(),
        ),
      ),
    );
  }

  Widget _buildRemoveWidget() {
    final layerInteraction = widget.configs.layerInteraction;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      child: _isLayerBeingTransformed
          ? Container(
              key: UniqueKey(),
              height: kToolbarHeight,
              width: kToolbarHeight,
              decoration: BoxDecoration(
                color: _layerInteractionManager.hoverRemoveBtn
                    ? layerInteraction.style.removeAreaBackgroundActive
                    : layerInteraction.style.removeAreaBackgroundInactive,
                borderRadius:
                    const BorderRadius.only(bottomRight: Radius.circular(100)),
              ),
              padding: const EdgeInsets.only(right: 12, bottom: 7),
              child: Center(
                child: Icon(
                  widget.configs.mainEditor.icons.removeElementZone,
                  size: 28,
                ),
              ),
            )
          : SizedBox.shrink(key: UniqueKey()),
    );
  }

  // ──────────── Crop Painter ────────────────────────────────────

  CustomPainter _buildCropPainter() {
    final imgRatio = _transformConfigs?.cropRect.size.aspectRatio ??
        widget.transformHelper.mainImageSize.aspectRatio;
    final isRoundCropper = _transformConfigs?.isOvalCropper ??
        widget.configs.cropRotateEditor.initialCropMode == CropMode.oval;
    return CropLayerPainter(
      imgRatio: imgRatio,
      isRoundCropper: isRoundCropper,
      is90DegRotated: _transformConfigs?.is90DegRotated ?? false,
      backgroundColor: widget.overlayColor,
      opacity: 1.0,
    );
  }
}

/// Clips the layer stack to the image bounds based on the image aspect ratio.
///
/// Uses the same sizing logic as [CropLayerPainter] to compute the visible
/// image area within the available space.
class _ImageBoundsClipper extends CustomClipper<Path> {
  _ImageBoundsClipper({
    required this.imgRatio,
    required this.is90DegRotated,
    required this.isOval,
  });

  final double imgRatio;
  final bool is90DegRotated;
  final bool isOval;

  @override
  Path getClip(Size size) {
    if (imgRatio <= 0) return Path()..addRect(Offset.zero & size);

    final double ratio = is90DegRotated ? 1 / imgRatio : imgRatio;
    final Offset center = Offset(size.width / 2, size.height / 2);

    double w, h;
    if (size.aspectRatio > ratio) {
      h = size.height;
      w = size.height * ratio;
    } else {
      w = size.width;
      h = size.width / ratio;
    }

    final Rect imageRect = Rect.fromCenter(center: center, width: w, height: h);


    if (isOval) {
      return Path()..addOval(imageRect);
    }
    return Path()..addRect(imageRect);
  }

  @override
  bool shouldReclip(covariant _ImageBoundsClipper oldClipper) {
    return oldClipper.imgRatio != imgRatio ||
        oldClipper.is90DegRotated != is90DegRotated ||
        oldClipper.isOval != isOval;
  }
}
