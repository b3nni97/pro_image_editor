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
    this.removeAreaBuilder,
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

  /// Optional builder to fully override the drag-to-delete area (look and
  /// position). It receives the [removeAreaKey] (which the returned widget must
  /// carry so its bounds are hit-tested), this stack's interaction manager
  /// (for the hover state), a [rebuildStream] that ticks when the hover state
  /// changes, whether a layer is currently being transformed, and the visible
  /// (letterboxed) image rectangle within the body so the area can be kept
  /// inside the image. When `null` the built-in default area is used.
  final Widget Function(
    GlobalKey removeAreaKey,
    LayerInteractionManager layerInteractionManager,
    Stream<void> rebuildStream,
    bool isLayerBeingTransformed,
    Rect imageBounds,
  )? removeAreaBuilder;

  @override
  State<InteractiveLayerStack> createState() => _InteractiveLayerStackState();
}

class _InteractiveLayerStackState extends State<InteractiveLayerStack>
    with SingleTickerProviderStateMixin {
  late final LayerInteractionManager _layerInteractionManager;
  late final LayerInteractionService _layersService;
  late final StreamController<void> _uiLayerCtrl;
  late final StreamController<void> _helperLineCtrl;
  late final StreamController<void> _removeBtnCtrl;

  /// Mirrors whether any alignment guide is currently visible, used purely as
  /// the anchor's lifecycle clock: it is snapped to 1 while a guide shows and
  /// reversed to 0 when the guides hide. Its duration matches the per-line
  /// fade, so the anchor is released ([_guideAnchorLayerId]) exactly when the
  /// fade-out finishes — never a frame early (which would flash the guide
  /// above the just-manipulated layer) nor via a guessed timer.
  late final AnimationController _guideAnchorClock;

  final GlobalKey _removeAreaKey = GlobalKey();
  // Stable identity for the helper-line overlay so its animation state
  // survives being moved within the layer stack (beneath the active layer)
  // between rebuilds.
  final GlobalKey _helperLinesKey = GlobalKey();
  final _mouseCursorsKey = GlobalKey<ExtendedRebuildMouseRegionState>();
  final _deferId = ValueNotifier(generateUniqueId());

  Size _editorBodySize = Size.infinite;
  bool _isLayerBeingTransformed = false;

  /// Id of the layer the alignment guides are currently anchored to. The
  /// guides render just beneath this layer (which itself renders above every
  /// other layer) for the duration of a drag and its fade-out. This is
  /// deliberately decoupled from selection: selection is cleared the moment
  /// all fingers lift (see [_onAllPointersUp]), so relying on it would let the
  /// guides flash above the just-dragged layer while they fade out.
  ///
  /// It is released once the fade-out completes, driven by [_guideAnchorClock]
  /// (whose duration matches the line fade), not on a guessed timer.
  String? _guideAnchorLayerId;

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

  /// The pure interactive-viewer zoom factor (without [transformHelper.scale]).
  ///
  /// The helper lines are rendered *inside* the [ExtendedInteractiveViewer]
  /// (as siblings of the layer content), so the viewer already applies the
  /// zoom and pan to them. They must therefore be laid out in plain content
  /// coordinates — only this factor is used to keep their stroke width and
  /// length visually constant across zoom levels, not to position them.
  double get _viewerScaleFactor => _viewer?.scaleFactor ?? 1.0;

  /// Tracks the previous pointer count to detect 2→1 finger transitions.
  int _lastPointerCount = 0;

  /// When a 2→1 pointer drop is detected, records the focal point position.
  /// Movement is suppressed until the finger moves > 5px from this point.
  Offset? _pointerDropFocal;

  HelperLineConfigs get _helperLines => widget.configs.helperLines;

  @override
  void initState() {
    super.initState();
    _uiLayerCtrl = StreamController.broadcast();
    _helperLineCtrl = StreamController.broadcast();
    _removeBtnCtrl = StreamController.broadcast();

    // Matches the per-line fade duration in [_buildHelperLine].
    _guideAnchorClock = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..addStatusListener((status) {
        if (status == AnimationStatus.dismissed &&
            _guideAnchorLayerId != null) {
          setState(() => _guideAnchorLayerId = null);
        }
      });

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
    _guideAnchorClock.dispose();
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

    // Anchor the alignment guides to the layer being manipulated so it renders
    // above the guides (and every other layer) for the whole gesture. Prefer
    // [activeInteractionLayer] since it is set for every interaction path —
    // including the rotate/scale handle, which enters through a different
    // gesture than this scale detector.
    _guideAnchorLayerId = _layerInteractionManager.activeInteractionLayer?.id ??
        (_selectedLayers.isNotEmpty ? _selectedLayers.first.id : null);

    _layerInteractionManager.onScaleStart(
      details: details,
      selectedLayers: _selectedLayers,
    );

    setState(() {});
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (!_hasSelectedLayers) {
      _viewer?.onScaleUpdate(details);
      return;
    }

    // Keep the guide anchor in sync with the layer currently being
    // manipulated. This also covers the rotate/scale handle, whose gesture may
    // bypass [_onScaleStart] but still flows through here (see the
    // [rotateScaleLayerSizeHelper] branch below). setState so the layer stack
    // reorders immediately — otherwise the handle path rebuilds only the
    // guides (targeted), leaving the layer un-elevated beneath the rotate line
    // during the gesture and its fade-out. The guard makes this fire only once
    // per gesture (when the anchor first changes).
    final activeLayer = _layerInteractionManager.activeInteractionLayer;
    if (activeLayer != null && activeLayer.id != _guideAnchorLayerId) {
      setState(() => _guideAnchorLayerId = activeLayer.id);
    }

    final int pointerCount = details.pointerCount;

    bool beforeShowHorizontalHelperLine =
        _layerInteractionManager.showHorizontalHelperLine;
    bool beforeShowVerticalHelperLine =
        _layerInteractionManager.showVerticalHelperLine;
    bool beforeShowRotationHelperLine =
        _layerInteractionManager.showRotationHelperLineUi;

    void checkUpdateHelperLineUI() {
      if (beforeShowHorizontalHelperLine !=
              _layerInteractionManager.showHorizontalHelperLine ||
          beforeShowVerticalHelperLine !=
              _layerInteractionManager.showVerticalHelperLine ||
          beforeShowRotationHelperLine !=
              _layerInteractionManager.showRotationHelperLineUi) {
        _helperLineCtrl.add(null);
        // A guide appeared/disappeared → keep the anchor clock in sync so it is
        // "armed" (at 1) whenever a guide is on screen during the gesture.
        _syncGuideAnchorClock();
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

    // The number of fingers changed this frame (one added or lifted): the focal
    // point jumps, so the translation must skip this frame and resync.
    final bool pointerCountChanged = pointerCount != _lastPointerCount;

    // Detect 2→1 pointer transition (one finger lifted from pinch).
    // Use a distance-based dead zone to prevent accidental displacement:
    // movement is suppressed until the remaining finger moves > 5px
    // from where it was at the moment the second finger lifted.
    if (_lastPointerCount == 2 && pointerCount == 1) {
      _pointerDropFocal = details.localFocalPoint;
    }
    _lastPointerCount = pointerCount;

    // Skip movement until the remaining finger has moved beyond the dead zone
    // after lifting the second finger.
    if (pointerCount == 1 && _pointerDropFocal != null) {
      final dist = (details.localFocalPoint - _pointerDropFocal!).distance;
      if (dist < 5.0) {
        return;
      }
      // Dead zone cleared — allow movement from now on.
      _pointerDropFocal = null;
    }

    // Translation + position snapping. Runs for both single- and multi-touch,
    // so a layer can be dragged (and snap to the center / other layers) while
    // it is simultaneously being rotated or scaled with two fingers.
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
      isMultiPointer: pointerCount >= 2,
      resyncFocalOnly: pointerCountChanged,
    );

    // Scale + rotation (and rotation snap) — two fingers only.
    if (pointerCount == 2) {
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

    // The gesture is over and the manager has cleared the guide flags. Drive
    // the anchor clock: if a guide was visible it now fades out and the anchor
    // is released when the clock hits 0; otherwise it is released immediately.
    _syncGuideAnchorClock();

    setState(() {});
  }

  /// Whether any alignment guide is currently rendered visible. Hovering the
  /// remove area collapses every line to size 0, so nothing would animate on
  /// release — treat that as "not visible" so the anchor is dropped at once.
  bool get _anyGuideVisible =>
      !_layerInteractionManager.hoverRemoveBtn &&
      (_layerInteractionManager.showVerticalHelperLine ||
          _layerInteractionManager.showHorizontalHelperLine ||
          _layerInteractionManager.showRotationHelperLineUi ||
          _layerInteractionManager.isVerticalGuideVisible ||
          _layerInteractionManager.isHorizontalGuideVisible);

  /// Drives [_guideAnchorClock] from the current guide visibility so the anchor
  /// is released precisely when the fade-out finishes. Snaps the clock to 1
  /// while a guide is visible; once the gesture is over and no guide remains,
  /// reverses it (the [AnimationStatus.dismissed] listener then releases the
  /// anchor). While an interaction is still active the anchor is always kept.
  void _syncGuideAnchorClock() {
    if (_anyGuideVisible) {
      _guideAnchorClock.value = 1.0;
      return;
    }
    // No guide visible. Never release while an interaction is still running —
    // [activeInteractionLayer] also covers the rotate/scale handle, which may
    // not set [_isLayerBeingTransformed].
    if (_isLayerBeingTransformed ||
        _layerInteractionManager.activeInteractionLayer != null) {
      return;
    }
    if (_guideAnchorClock.value == 0.0) {
      // Nothing was showing, so nothing will fade — release immediately.
      if (_guideAnchorLayerId != null) {
        setState(() => _guideAnchorLayerId = null);
      }
    } else {
      // A guide is fading out; release the anchor when the clock reaches 0.
      _guideAnchorClock.reverse();
    }
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
    // Paint order (bottom → top): every other layer, then the alignment
    // guides, then the anchored (actively dragged) layer on top. This places
    // the guides above all other layers but below the layer being dragged, so
    // a dragged layer (e.g. text) is never covered by the guides — including
    // while they fade out after release (see [_guideAnchorLayerId]). Only the
    // paint order changes; the layer data order is untouched and each layer
    // keeps its state via its own key. When no layer is anchored the guides
    // are invisible (size 0) and simply sit on top. A stable GlobalKey keeps
    // the guides' animation state intact as they move between these positions.
    final layerChildren = <Widget>[];
    if (widget.enableHelperLines) {
      Widget? anchoredLayerWidget;
      for (final layer in widget.layers) {
        final layerWidget = _buildLayerWidget(layer);
        if (layer.id == _guideAnchorLayerId) {
          anchoredLayerWidget = layerWidget;
        } else {
          layerChildren.add(layerWidget);
        }
      }
      layerChildren.add(_buildHelperLines());
      if (anchoredLayerWidget != null) {
        layerChildren.add(anchoredLayerWidget);
      }
    } else {
      for (final layer in widget.layers) {
        layerChildren.add(_buildLayerWidget(layer));
      }
    }

    Widget layerStack = Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      clipBehavior: widget.clipBehavior,
      children: layerChildren,
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
                  clipper: _imageBoundsClipper(),
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

    // Build the final stack. Helper lines are *not* placed here; they are
    // injected inside the layer stack (see [_buildLayerContent]) directly
    // beneath the active layer, so a dragged layer renders on top of the
    // guides while all other layers stay below them. The remove area stays on
    // top so the drag-to-delete zone is always visible.
    return Stack(
      children: [
        content,
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

  /// Clipper that restricts a child to the letterboxed image area (the region
  /// actually covered by the image inside the body), so overlays don't paint
  /// over the surrounding black/white background.
  _ImageBoundsClipper _imageBoundsClipper() {
    return _ImageBoundsClipper(
      imgRatio: _transformConfigs?.cropRect.size.aspectRatio ??
          widget.transformHelper.mainImageSize.aspectRatio,
      is90DegRotated: _transformConfigs?.is90DegRotated ?? false,
      isOval: _transformConfigs?.isOvalCropper ??
          widget.configs.cropRotateEditor.initialCropMode == CropMode.oval,
    );
  }

  /// The rectangle of the visible (letterboxed) image within the editor body,
  /// in the same coordinate space the layer/remove-area stack is laid out in.
  /// Mirrors the region [_imageBoundsClipper] clips to.
  Rect _visibleImageRect() {
    final size = _editorBodySize;
    final imgRatio = _transformConfigs?.cropRect.size.aspectRatio ??
        widget.transformHelper.mainImageSize.aspectRatio;
    if (imgRatio <= 0 || size.isEmpty) return Offset.zero & size;

    final double ratio =
        (_transformConfigs?.is90DegRotated ?? false) ? 1 / imgRatio : imgRatio;
    final center = Offset(size.width / 2, size.height / 2);

    double w, h;
    if (size.aspectRatio > ratio) {
      h = size.height;
      w = size.height * ratio;
    } else {
      w = size.width;
      h = size.width / ratio;
    }
    return Rect.fromCenter(center: center, width: w, height: h);
  }

  Widget _buildHelperLines() {
    // Intentionally *not* gated by [showHelperLines]. Keeping the subtree
    // mounted lets the per-line AnimatedContainers shrink their thickness
    // back to 0 when a gesture ends, so the guides fade out symmetrically to
    // how they faded in. Tearing the subtree out on release would remove the
    // AnimatedContainers before that exit animation could play. While idle,
    // every line renders at size 0, so nothing is painted.
    final helperLines = _helperLines;
    final strokeWidth = helperLines.style.strokeWidth;

    return IgnorePointer(
      key: _helperLinesKey,
      child: RepaintBoundary(
        child: StreamBuilder(
          stream: _removeBtnCtrl.stream,
          builder: (_, __) {
            return StreamBuilder<void>(
              stream: _helperLineCtrl.stream,
              builder: (context, snapshot) {
                final scale = _viewerScaleFactor;
                final editorBodySize = _editorBodySize;

                if (helperLines.isDisabledAtZoom && scale > 1) {
                  return const SizedBox.shrink();
                }

                final isRemoval = _layerInteractionManager.hoverRemoveBtn;

                // The viewer already applies zoom+pan, so everything here is in
                // content coordinates. Stroke width and line length are divided
                // by the viewer scale so they stay visually constant; lines
                // are made several times the body size so they still reach the
                // edges when the view is zoomed out or panned.
                // Per-line thickness (falls back to the shared strokeWidth).
                final thinV =
                    (helperLines.style.verticalStrokeWidth ?? strokeWidth) /
                        scale;
                final thinH =
                    (helperLines.style.horizontalStrokeWidth ?? strokeWidth) /
                        scale;
                final spanHeight = editorBodySize.height / scale * 3;
                final spanWidth = editorBodySize.width / scale * 3;
                final centerX = editorBodySize.width / 2;
                final centerY = editorBodySize.height / 2;

                // Clip to the letterboxed image area so the guides never paint
                // over the black/white background around the image.
                return SizedBox(
                  width: editorBodySize.width,
                  height: editorBodySize.height,
                  child: ClipPath(
                    clipper: _imageBoundsClipper(),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (helperLines.showVerticalLine)
                          _buildHelperLine(
                            key: const ValueKey('Screen-Vertical-Guide-Line'),
                            width: _layerInteractionManager
                                        .showVerticalHelperLine &&
                                    !isRemoval
                                ? thinV
                                : 0,
                            height: spanHeight,
                            left: centerX - thinV / 2,
                            top: centerY - spanHeight / 2,
                            color: helperLines.style.verticalColor,
                            lineType: helperLines.style.verticalLineType,
                          ),
                        if (helperLines.showHorizontalLine)
                          _buildHelperLine(
                            key: const ValueKey('Screen-Horizontal-Guide-Line'),
                            width: spanWidth,
                            height: _layerInteractionManager
                                        .showHorizontalHelperLine &&
                                    !isRemoval
                                ? thinH
                                : 0,
                            left: centerX - spanWidth / 2,
                            top: centerY - thinH / 2,
                            color: helperLines.style.horizontalColor,
                            lineType: helperLines.style.horizontalLineType,
                          ),
                        if (helperLines.showRotateLine) _buildRotateLine(scale),
                        if (helperLines.showLayerAlignLine)
                          ..._buildLayerAlignLines(scale),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
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
    HelperLineType lineType = HelperLineType.solid,
  }) {
    final bool dashed = lineType == HelperLineType.dashed;
    return Positioned(
      key: key,
      left: left,
      top: top,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: width,
        height: height,
        margin: margin,
        // Solid lines paint via the container color; dashed lines are drawn by
        // a painter that fills the (animated) box, so the fade still works.
        color: dashed ? null : color,
        child: dashed
            ? CustomPaint(
                painter: _DashedLinePainter(
                  color: color,
                  pattern: _kDashedGuidePattern,
                ),
                child: const SizedBox.expand(),
              )
            : null,
      ),
    );
  }

  Widget _buildRotateLine(double scale) {
    final strokeWidth =
        _helperLines.style.rotateStrokeWidth ?? _helperLines.style.strokeWidth;
    // Content-space position; the viewer applies the zoom+pan. Stroke and
    // length are scale-compensated to stay visually constant. The base shape
    // is a *horizontal* bar so that at 0° rotation the guide runs along the
    // object's horizontal axis (a "level" line), then rotates with the
    // object's snapped angle. Length uses the longest body side so the line
    // spans the viewport at any rotation.
    final thin = strokeWidth / scale;
    final length = _editorBodySize.longestSide / scale * 3;
    final bool dashed =
        _helperLines.style.rotateLineType == HelperLineType.dashed;
    final color = _helperLines.style.rotateColor;
    return Positioned(
      left: _layerInteractionManager.rotationHelperLineX,
      top: _layerInteractionManager.rotationHelperLineY,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Transform.rotate(
          angle: _layerInteractionManager.rotationHelperLineDeg,
          child: AnimatedContainer(
            key: const ValueKey('Rotation-Guide-Line'),
            duration: const Duration(milliseconds: 100),
            width: length,
            height: _layerInteractionManager.showRotationHelperLineUi &&
                    !_layerInteractionManager.hoverRemoveBtn
                ? thin
                : 0,
            color: dashed ? null : color,
            child: dashed
                ? CustomPaint(
                    painter: _DashedLinePainter(
                      color: color,
                      pattern: _kDashedGuidePattern,
                    ),
                    child: const SizedBox.expand(),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildLayerAlignLines(double scale) {
    final editorCenter = _editorBodySize / 2;
    // Content-space positions; the viewer applies zoom+pan. Stroke and length
    // are scale-compensated to stay visually constant across zoom levels.
    final strokeWidth = _helperLines.style.layerAlignStrokeWidth ??
        _helperLines.style.strokeWidth;
    final thin = strokeWidth / scale;
    final halfStroke = thin / 2;
    final spanHeight = _editorBodySize.height / scale * 3;
    final spanWidth = _editorBodySize.width / scale * 3;

    final verticalOffset = editorCenter.width +
        _layerInteractionManager.verticalGuideOffset.dx -
        halfStroke;

    final horizontalOffset = editorCenter.height +
        _layerInteractionManager.horizontalGuideOffset.dy -
        halfStroke;

    final isRemoval = _layerInteractionManager.hoverRemoveBtn;
    final showHorizontal =
        _layerInteractionManager.isHorizontalGuideVisible && !isRemoval;
    final showVertical =
        _layerInteractionManager.isVerticalGuideVisible && !isRemoval;

    // Always mounted; thickness is driven by the visibility flag so the lines
    // grow in and shrink out via their AnimatedContainer, matching the center
    // guides instead of popping. While inactive the size is 0 (invisible) and
    // the last offset is retained for a clean fade-out.
    return [
      _buildHelperLine(
        key: const ValueKey('Horizontal-Guide-Line'),
        width: spanWidth,
        height: showHorizontal ? thin : 0,
        top: horizontalOffset,
        left: editorCenter.width - spanWidth / 2,
        color: _helperLines.style.layerAlignColor,
        lineType: _helperLines.style.layerAlignLineType,
      ),
      _buildHelperLine(
        key: const ValueKey('Vertical-Guide-Line'),
        width: showVertical ? thin : 0,
        height: spanHeight,
        top: editorCenter.height - spanHeight / 2,
        left: verticalOffset,
        color: _helperLines.style.layerAlignColor,
        lineType: _helperLines.style.layerAlignLineType,
      ),
    ];
  }

  // ──────────── Remove Area ─────────────────────────────────────

  Widget _buildRemoveArea() {
    // A host-provided builder fully overrides look and position. It must attach
    // [_removeAreaKey] to its widget so the hover hit-test can find its bounds.
    final builder = widget.removeAreaBuilder;
    final Widget built = builder != null
        ? builder(
            _removeAreaKey,
            _layerInteractionManager,
            _removeBtnCtrl.stream,
            _isLayerBeingTransformed,
            _visibleImageRect(),
          )
        : Positioned(
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

    return _pinRemoveAreaToViewport(built);
  }

  /// Keeps the drag-to-delete area fixed in screen space at the editor's
  /// un-zoomed base view. The area lives inside the interactive viewer (with
  /// the layers), so without this it would zoom and pan away when the user
  /// zooms into the image. We cancel the viewer's current transform and
  /// re-apply its *base fit* transform, so the area stays at exactly the same
  /// on-screen spot (e.g. bottom of the image) regardless of zoom/pan.
  ///
  /// We deliberately use [initialMatrix4] (the base/reset fit), not
  /// [startMatrix4]: the latter is the shared zoom the editor may *open* with
  /// (e.g. after zooming in a previous sub-editor), which would otherwise pin
  /// the area to that already-zoomed view and push it off screen.
  Widget _pinRemoveAreaToViewport(Widget child) {
    final viewer = _viewer;
    final ctrl = viewer?.transformationController;
    if (viewer == null || ctrl == null) return child;

    final Matrix4 initial =
        viewer.widget.initialMatrix4 ?? Matrix4.identity();

    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        Matrix4 counter;
        try {
          counter = Matrix4.inverted(ctrl.value)..multiply(initial);
        } catch (_) {
          // Non-invertible matrix (degenerate) → skip compensation.
          counter = Matrix4.identity();
        }
        return Transform(
          transform: counter,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: _editorBodySize.width,
            height: _editorBodySize.height,
            child: Stack(clipBehavior: Clip.none, children: [child]),
          ),
        );
      },
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

/// The standard dash pattern (dash/gap lengths in logical pixels) used for
/// [HelperLineType.dashed] helper lines.
const List<double> _kDashedGuidePattern = [6.0, 4.0];

/// Paints a dashed helper line filling its box. The line runs along the longer
/// side of [size]; the shorter side is the (animated) thickness, so the fade-in
/// still works. [pattern] is alternating dash/gap lengths in logical pixels.
class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter({required this.color, required this.pattern});

  final Color color;
  final List<double> pattern;

  @override
  void paint(Canvas canvas, Size size) {
    final bool horizontal = size.width >= size.height;
    final double lineLength = horizontal ? size.width : size.height;
    final double thickness = horizontal ? size.height : size.width;
    if (lineLength <= 0 || thickness <= 0 || pattern.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness;
    final double cross = thickness / 2;

    double pos = 0;
    int i = 0;
    while (pos < lineLength) {
      final double seg = pattern[i % pattern.length];
      // Even indices are dashes, odd indices are gaps.
      if (i.isEven && seg > 0) {
        final double end = (pos + seg).clamp(0.0, lineLength);
        if (horizontal) {
          canvas.drawLine(Offset(pos, cross), Offset(end, cross), paint);
        } else {
          canvas.drawLine(Offset(cross, pos), Offset(cross, end), paint);
        }
      }
      pos += seg;
      i++;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) {
    if (oldDelegate.color != color) return true;
    if (oldDelegate.pattern.length != pattern.length) return true;
    for (var i = 0; i < pattern.length; i++) {
      if (oldDelegate.pattern[i] != pattern[i]) return true;
    }
    return false;
  }
}
