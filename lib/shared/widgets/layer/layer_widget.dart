// Dart imports:
import 'dart:async';
import 'dart:math';

// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' hide Layer;
import 'package:heroine/heroine.dart';

import '/core/constants/editor_various_constants.dart';
import '/core/mixins/converted_configs.dart';
import '/core/mixins/editor_configs_mixin.dart';
import '/core/models/editor_callbacks/pro_image_editor_callbacks.dart';
import '/core/models/editor_configs/pro_image_editor_configs.dart';
import '/core/models/layers/layer.dart';
import '/core/services/gesture_manager.dart';
import '/features/main_editor/services/layer_interaction_manager.dart';
import '/shared/widgets/layer/services/base_layer_interaction_service.dart';
import '/shared/widgets/layer/services/hero_flight_overrides.dart';
import '/features/paint_editor/enums/paint_editor_enum.dart';
import '/shared/widgets/layer/enums/layer_widget_type_enum.dart';
import '/shared/widgets/layer/services/layer_widget_context_menu.dart';
import '/shared/widgets/layer/widgets/layer_widget_censor_item.dart';
import '/shared/widgets/layer/widgets/layer_widget_emoji_item.dart';
import '/shared/widgets/layer/widgets/layer_widget_paint_item.dart';
import '/shared/widgets/layer/widgets/layer_widget_text_item.dart';
import 'interaction_helper/layer_interaction_helper_widget.dart';
import 'widgets/layer_widget_custom_item.dart';

/// A widget representing a layer within a design canvas.
class LayerWidget extends StatefulWidget with SimpleConfigsAccess {
  /// Creates a [LayerWidget] with the specified properties.
  const LayerWidget({
    super.key,
    required this.editorBodySize,
    required this.configs,
    required this.layer,
    this.layersService,
    this.layerInteractionManager,
    this.onContextMenuToggled,
    this.onDuplicate,
    this.isInteractive = false,
    this.enableMouseCursor = true,
    this.enableHero = true,
    this.editorScaleFactor = 1.0,
    this.callbacks = const ProImageEditorCallbacks(),
  });
  @override
  final ProImageEditorConfigs configs;

  @override
  final ProImageEditorCallbacks callbacks;

  /// Service for managing editor layers such as adding, removing, or
  /// updating them.
  final BaseLayerInteractionService? layersService;

  /// Handles user interactions with layers, like selecting or dragging them.
  final LayerInteractionManager? layerInteractionManager;

  /// The size of the editor's body area in logical pixels.
  final Size editorBodySize;

  /// Data for the layer.
  final Layer layer;

  /// Callback when the context menu open/close
  final Function(bool isOpen)? onContextMenuToggled;

  /// Callback triggered when a layer should be copied.
  final Function()? onDuplicate;

  /// Indicates whether the layer is interactive.
  final bool isInteractive;

  /// A flag indicating whether the mouse cursor should be enabled for this
  /// widget.
  final bool enableMouseCursor;

  /// Whether to wrap this layer in a [Hero] widget.
  ///
  /// Set to `false` when rendering a non-interactive duplicate of the layer
  /// stack (e.g. the sharp-restore overlay) to prevent [GlobalKey] conflicts.
  final bool enableHero;

  /// The combined scale factor of the interactive viewer and transform helper.
  /// Used to compute zoom-independent touch padding.
  final double editorScaleFactor;

  @override
  createState() => _LayerWidgetState();
}

class _LayerWidgetState extends State<LayerWidget>
    with ImageEditorConvertedConfigs, SimpleConfigsAccessState {
  late LayerWidgetType _layerType;

  late final _layersService = widget.layersService;
  late final _layerInteractionManager = widget.layerInteractionManager;

  /// Indicates whether the layer is selected.
  bool get _isSelected =>
      _layerInteractionManager?.selectedLayerIds.contains(_layer.id) ?? false;

  /// Flag to control the display of a move cursor.
  final _showMoveCursor = ValueNotifier(false);
  final _lastHitState = ValueNotifier(false);

  late final _contextManager = LayerWidgetContextMenu(
    i18nLayerInteraction: i18n.layerInteraction,
    layerInteractionIcons: layerInteraction.icons,
    onContextMenuToggled: widget.onContextMenuToggled,
    onEditTap: () => _layersService?.handleEditTap(_layer),
    onRemoveTap: () => _layersService?.handleRemoveLayer(_layer),
  );

  late final Offset _fractionalOffset;

  /// Last computed pull vector toward the drag-to-delete area, retained so the
  /// "suck in" translate can animate back out after the layer leaves the zone
  /// (see [build]).
  Offset _removeAreaPull = Offset.zero;

  PointerEvent? _lastDownEvent;
  Offset? _lastLayerOffset;
  int? _temporaryLayerHash;

  DateTime _tapDownTimestamp = DateTime.now();
  Timer? _longPressTimer;
  final Duration _longPressThreshold = const Duration(milliseconds: 500);

  /// Returns the current layer being displayed.
  Layer get _layer => widget.layer;

  Size get _halfBodySize => widget.editorBodySize / 2;

  /// Calculates the horizontal offset for the layer.
  double get offsetX => _layer.offset.dx + _halfBodySize.width;

  /// Calculates the vertical offset for the layer.
  double get offsetY => _layer.offset.dy + _halfBodySize.height;

  bool get _enableVisibleOverlay =>
      _layerInteractionManager?.layersAreSelectable(widget.configs) ?? false;

  @override
  void initState() {
    super.initState();

    if (_layer.isTextLayer) {
      _layerType = LayerWidgetType.text;
      _fractionalOffset = configs.textEditor.layerFractionalOffset;
    } else if (_layer.isEmojiLayer) {
      _layerType = LayerWidgetType.emoji;
      _fractionalOffset = configs.emojiEditor.layerFractionalOffset;
    } else if (_layer.isWidgetLayer) {
      _layerType = LayerWidgetType.widget;
      _fractionalOffset = configs.stickerEditor.layerFractionalOffset;
    } else if (_layer.isPaintLayer) {
      var layer = _layer as PaintLayer;
      _layerType = layer.item.mode == PaintMode.blur ||
              layer.item.mode == PaintMode.pixelate
          ? LayerWidgetType.censor
          : LayerWidgetType.canvas;
      _fractionalOffset = configs.paintEditor.layerFractionalOffset;
    } else {
      _layerType = LayerWidgetType.unknown;
      _fractionalOffset = const Offset(-0.5, -0.5);
    }
  }

  @override
  void dispose() {
    _lastHitState.dispose();
    _showMoveCursor.dispose();
    _longPressTimer?.cancel();
    super.dispose();
  }

  /// Handles a secondary tap up event, typically for showing a context menu.
  void _onSecondaryTapUp(TapUpDetails details) {
    if (_isOutsideHitBox() || GestureManager.instance.isBlocked) return;

    _contextManager.open(
      context: context,
      details: details,
      enableEditButton:
          _layerType == LayerWidgetType.text && _layer.interaction.enableEdit,
      enableRemoveButton: true,
    );
  }

  /// Handles a pointer down event on the layer.
  void _onPointerDown(PointerDownEvent event) {
    if (GestureManager.instance.isBlocked) return;
    bool isLayerSelected = _isSelected;

    _lastDownEvent = event;
    _lastLayerOffset = _layer.offset;
    _temporaryLayerHash = _layer.hashCode;
    _tapDownTimestamp = DateTime.now();

    if (!widget.isInteractive && _isOutsideHitBox()) {
      return;
    }
    if (!isDesktop || event.buttons != kSecondaryMouseButton) {
      _layersService?.handleTapDown(_layer, event);
    }
    // Start long press detection
    _longPressTimer?.cancel();
    _longPressTimer = Timer(_longPressThreshold, () {
      if (_lastDownEvent == null ||
          _lastLayerOffset == null ||
          _temporaryLayerHash != _layer.hashCode) {
        return;
      }

      final offsetDistance = (_layer.offset - _lastLayerOffset!).distance;

      if (offsetDistance <= 0 && _layer.interaction.enableSelection) {
        _layersService?.handleLongPress(
          _layer,
          isSelected: isLayerSelected,
          areLayersSelectable: _enableVisibleOverlay,
        );
      }
    });
  }

  /// Handles a pointer up event on the layer.
  void _onPointerUp(PointerUpEvent event) {
    _longPressTimer?.cancel();
    if (GestureManager.instance.isBlocked) return;
    // Determine if this pointer-up constitutes a genuine tap (minimal
    // movement) vs. the end of a drag/pinch gesture. handleTapUp uses
    // this to decide whether to clear the selection on mobile.
    final bool isTap = _lastDownEvent != null &&
        (event.position - _lastDownEvent!.position).distance < tapSlop;
    _layersService?.handleTapUp(_layer, isTap: isTap);

    /// Important: To avoid gesture conflicts, we need to create our own
    /// onTap event using the Listener widget instead of GestureDetector.
    /// Below is a minimal example of how this can work. If anyone has
    /// issues with this, please open a new issue.

    // Cancel if down position is not set
    if (_lastDownEvent == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final interaction = _layer.interaction;
      final offsetDistance =
          (event.position - _lastDownEvent!.position).distance;
      final timeElapsed =
          DateTime.now().difference(_tapDownTimestamp).inMilliseconds;

      // Ignore if pointer moved too much (exceeds tap slop)
      if (offsetDistance >= tapSlop) return;

      // Ignore if tap took too long (not a quick tap)
      if (timeElapsed > tapTimeElapsed) return;

      // Fire onTap only if selection/edit is enabled and pointer is inside hit box
      final bool canSelect = interaction.enableSelection;
      final bool canEdit = interaction.enableEdit;
      final bool insideHitBox = widget.isInteractive || !_isOutsideHitBox();
      final bool isStylus = event.kind == PointerDeviceKind.stylus;
      final bool isTextLayer = _layerType == LayerWidgetType.text;

      if (!(canSelect || canEdit)) {
        return;
      }

      // For stylus on TEXT layers only, bypass hit box check since it has
      // precision issues with stylus input
      // For paint layers: always use hit box validation (no bypass)
      // to ensure taps on empty space inside shapes don't trigger edit.
      final bool stylusTextBypass = isStylus && isTextLayer;

      if (insideHitBox || stylusTextBypass) {
        _layersService?.handleLayerTap(_layer, _lastDownEvent!);
      }
    });
  }

  bool _isOutsideHitBox() {
    final bool hitOutsideCanvas = _isHitOutsideInCanvas();
    final bool hitOutsideText = _isHitOutsideInText();
    final bool isCensor = _layerType == LayerWidgetType.censor;
    final bool isSelected = _isSelected;

    return ((hitOutsideCanvas || hitOutsideText) && !isCensor) && !isSelected;
  }

  /// Checks if the hit is outside the canvas for certain types of layers.
  bool _isHitOutsideInCanvas() {
    return _layer.isPaintLayer && !(_layer as PaintLayer).item.hit;
  }

  /// Checks if the hit is outside the canvas for certain types of layers.
  bool _isHitOutsideInText() {
    return _layer.isTextLayer && !(_layer as TextLayer).hit;
  }

  /// Calculates the transformation matrix for the layer's rotation and flip.
  ///
  /// During a pinch gesture, the visual scale ratio (scale / gestureBaseScale)
  /// is applied here via the GPU, so the content doesn't need to re-render
  /// (no text re-layout every frame = no flickering).
  Matrix4 _calcTransformMatrix() {
    final matrix = Matrix4.identity()
      ..rotateX(_layer.flipY ? pi : 0)
      ..rotateY(_layer.flipX ? pi : 0)
      ..rotateZ(_layer.rotation);

    // During gesture: content stays at gestureBaseScale, the visual
    // difference is applied as a GPU transform.
    final base = _layer.gestureBaseScale;
    if (base != null && base > 0) {
      final visualScale = _layer.scale / base;
      matrix.scale(visualScale, visualScale);
    }

    return matrix;
  }

  void _onHoverEnter() {
    if (((!_layer.isPaintLayer || _layerType == LayerWidgetType.censor) &&
            !_layer.isTextLayer) ||
        _isSelected) {
      _showMoveCursor.value = true;
    }
  }

  void _onHoverLeave() {
    if (_layer.isPaintLayer) {
      (_layer as PaintLayer).item.hit = false;
    } else if (_layer.isTextLayer) {
      (_layer as TextLayer).hit = false;
    }
    _showMoveCursor.value = false;
    _lastHitState.value = false;
  }

  @override
  Widget build(BuildContext context) {
    Matrix4 transformMatrix = _calcTransformMatrix();

    // When the layer is interactive (sub-editor) but not selected, add
    // transparent padding so the touch target is larger and easier to hit.
    // Padding is zoom-compensated: divided by scaleFactor so it stays a
    // constant size on screen regardless of IV zoom level.
    final EdgeInsets overlayPadding;
    if (_isSelected) {
      overlayPadding = layerInteraction.style.overlayPadding;
    } else if (widget.isInteractive) {
      final compensated = 12.0 / widget.editorScaleFactor;
      overlayPadding = EdgeInsets.all(compensated);
    } else {
      overlayPadding = EdgeInsets.zero;
    }

    final Widget content = RepaintBoundary(child: _buildInteractionHandlers());

    final style = layerInteraction.style;
    final bool effectEnabled = !(style.removeAreaHoverScale == 1.0 &&
        style.removeAreaHoverOpacity == 1.0);
    final manager = _layerInteractionManager;
    final bool overRemoveArea = effectEnabled &&
        manager != null &&
        manager.hoverRemoveBtn &&
        (_isSelected || manager.activeInteractionLayer?.id == _layer.id);

    // Vector (content space) from this layer's centre to the delete-area centre
    // so a hovered layer is "pulled into" the zone as it shrinks/fades away.
    // Persisted so the pull also animates smoothly back out on release/exit,
    // where [removeAreaCenter] is already cleared.
    if (overRemoveArea && manager.removeAreaCenter != null) {
      _removeAreaPull = manager.removeAreaCenter! - Offset(offsetX, offsetY);
    }
    final Offset pull = _removeAreaPull;

    if (!effectEnabled) {
      return Positioned.fill(
        child: _TransformedLayerBox(
          layerOffset: Offset(offsetX, offsetY),
          fractionalOffset: _fractionalOffset,
          overlayPadding: overlayPadding,
          transform: transformMatrix,
          child: content,
        ),
      );
    }

    // Drive translate (via layerOffset, so rotation doesn't skew the pull),
    // scale and opacity off a single animated value so the "suck into the
    // delete zone" effect stays in sync in and out.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: overRemoveArea ? 1.0 : 0.0),
      duration: style.removeAreaHoverDuration,
      curve: style.removeAreaHoverCurve,
      child: content,
      builder: (context, t, animChild) {
        final double scale = 1.0 + (style.removeAreaHoverScale - 1.0) * t;
        final double opacity = 1.0 + (style.removeAreaHoverOpacity - 1.0) * t;
        return Positioned.fill(
          child: _TransformedLayerBox(
            layerOffset: Offset(offsetX, offsetY) + pull * t,
            fractionalOffset: _fractionalOffset,
            overlayPadding: overlayPadding,
            transform: transformMatrix,
            child: Transform.scale(
              scale: scale,
              child: Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: animChild,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _maybeBuildHero({required String tag, required Widget child}) {
    if (!widget.enableHero) {
      return child;
    }
    return Heroine(
      // Spring tuned to the sub-editor page transition — governs the
      // *closing* text-editor flight (heroine uses the destination hero's
      // motion), so flight and route fade end together. Matches the
      // editor-side heroine in TextEditorInput.
      motion: CupertinoMotion.smooth(
        duration: mainEditorConfigs.style.subEditorPage.transitionDuration,
        snapToEnd: true,
      ),
      // When switching between sub-editors, the destination editor applies
      // its canvas transform (e.g. the sub-editor preview scale) only after
      // its first layout — a one-shot measurement targets the unscaled
      // (too large) rect and the layer visibly snaps at the flight end.
      // Tracking re-measures the target every frame and redirects the
      // spring once the destination transform settled.
      continuouslyTrackTarget: true,
      // Layers always fly above the (heroine-based) image hero — see
      // SmartHero, which uses the default z-index of 0.
      zIndex: 10,
      // Scale-don't-relayout shuttle for layer<->layer flights (editor
      // switches). The default FadeShuttleBuilder lays the content out INTO
      // the flight box, but the canvas renders layers under the sub-editor
      // preview transform — the overlay lacks that ancestor scale, so the
      // text would paint ~1/scale too large for the whole flight and snap
      // back at landing.
      flightShuttleBuilder: const _LayerFittedShuttleBuilder(),
      // Don't pin the hidden layer to the size captured at flight start
      // (heroine's default placeholder): while the text editor is open the
      // layer renders the *edited* content via HeroFlightOverrides, and the
      // closing flight must measure THAT size — with the pinned stale size,
      // longer/shorter edits landed shifted sideways and snapped into place
      // at the flight end. Opacity (NOT Offstage, which collapses to zero
      // size) keeps the child laid out at its current natural size while
      // invisible. Layout changes are safe here: the layer is center-anchored
      // and positioned independently of its siblings.
      placeholderBuilder: (context, heroSize, child) => IgnorePointer(
        child: Opacity(opacity: 0, child: child),
      ),
      // In-tree, this layer is clipped by its ancestors (interactive-viewer
      // viewport, host app canvas card, ...), but the flight overlay renders
      // above everything unclipped — a layer poking over such an edge would
      // pop fully visible the moment the flight starts. Passing the
      // effective ancestor clip lets heroine clip the shuttle identically
      // (interpolated open towards the unclipped editor side).
      flightClipBounds: _resolveAncestorClipBounds,
      tag: tag,
      child: child,
    );
  }

  /// The nearest ancestor clip above this layer (usually the image-bounds
  /// ClipPath around the layer stack), in global coordinates — i.e. the
  /// canvas region this layer belongs to. Returns null when nothing clips
  /// (flight stays unclipped).
  ///
  /// Deliberately *not* intersected with outer clips (interactive-viewer
  /// viewport, host app card, ...): the canvas rect is exactly what the
  /// accompanying canvas hero flies between during editor switches, and
  /// heroine interpolates the flight mask between both sides' rects to
  /// track that motion. Clamping at the viewport would break this under
  /// zoom, where the canvas extends beyond the screen — the screen edge
  /// crops the overlay naturally anyway. The clip contributes its *actual*
  /// geometry (via its clipper), approximated by its bounding rect — not
  /// just the clip widget's box, which can be much larger (e.g. the
  /// image-bounds clipper cuts the letterboxed image area out of the
  /// full-body layer stack). Mapping through the clip's transform to
  /// global keeps it correct under the interactive viewer's zoom/pan.
  Rect? _resolveAncestorClipBounds() {
    if (!mounted) return null;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return null;

    RenderObject? node = renderObject.parent;
    while (node != null) {
      if (node is RenderBox && node.hasSize) {
        final size = node.size;
        final Rect? localClip = switch (node) {
              final RenderClipRect n => n.clipper?.getClip(size),
              final RenderClipRRect n => n.clipper?.getClip(size).outerRect,
              final RenderClipOval n => n.clipper?.getClip(size),
              final RenderClipPath n => n.clipper?.getClip(size).getBounds(),
              _ => null,
            } ??
            (node is RenderClipRect ||
                    node is RenderClipRRect ||
                    node is RenderClipOval ||
                    node is RenderClipPath
                ? Offset.zero & size
                : null);
        if (localClip != null) {
          return MatrixUtils.transformRect(
            node.getTransformTo(null),
            localClip,
          );
        }
      }
      node = node.parent;
    }
    return null;
  }

  /// Latched once the pending flight for this layer has actually started, so
  /// the content stays visible through the landing and after the flight ends
  /// (see [_buildFlightPendingGuard]).
  bool _pendingFlightStarted = false;

  /// Keeps the content invisible while this layer is the destination of an
  /// *imminent* hero flight that hasn't engaged yet.
  ///
  /// The new-text flow swaps the real layer onto the canvas one frame before
  /// the closing flight starts (the flight needs a content-ful destination to
  /// measure) — without this guard the text is visible at the target for that
  /// frame while the editor still shows the same text. Opacity (not
  /// Visibility) so the layout is preserved for the flight measurement.
  Widget _buildFlightPendingGuard({required Widget child}) {
    final overrides = HeroFlightOverrides.instance;
    if (!overrides.isFlightPending(_layer.id)) {
      _pendingFlightStarted = false;
      return child;
    }
    if (HeroineController.isTagInFlight(_layer.id)) {
      _pendingFlightStarted = true;
    }
    if (_pendingFlightStarted) return child;
    return Opacity(opacity: 0, child: child);
  }

  Widget _buildInteractionHandlers() {
    var interaction = _layer.interaction;
    return LayerInteractionHelperWidget(
      layer: _layer,
      configs: configs,
      callbacks: callbacks,
      selected: _isSelected,
      onEditLayer: () => _layersService?.handleEditTap(_layer),
      forceIgnoreGestures:
          !(interaction.enableSelection || interaction.enableEdit),
      isInteractive: widget.isInteractive,
      enableVisibleOverlay: _enableVisibleOverlay,
      onScaleRotateDown: (details) => _layersService?.handleScaleRotateDown(
          context.size ?? Size.zero, _layer),
      onScaleRotateUp: (_) => _layersService?.handleScaleRotateUp(),
      onRemoveLayer: () => _layersService?.handleRemoveLayer(_layer),
      onDuplicate: widget.onDuplicate,
      onGroupLayers: _layersService?.handleGroupLayers,
      onUngroupLayers: () => _layersService?.handleUngroupLayers(_layer),
      child: _buildCursor(
        child: ValueListenableBuilder(
            valueListenable: _lastHitState,
            builder: (_, __, ___) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onSecondaryTapUp: isDesktop ? _onSecondaryTapUp : null,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _onPointerDown,
                  onPointerUp: _onPointerUp,
                  child: Padding(
                    padding: _isSelected
                        ? layerInteraction.style.overlayPadding
                        : (widget.isInteractive
                            ? EdgeInsets.all(12.0 / widget.editorScaleFactor)
                            : EdgeInsets.zero),
                    child: KeyedSubtree(
                      key: widget.enableHero ? _layer.keyInternalSize : null,
                      child: _maybeBuildHero(
                        tag: _layer.id,
                        // Rebuild the hero child when a flight override is
                        // set/cleared so the hero measures the *new* size for
                        // its end rect (prevents a sideways shift when the
                        // edited text changed length).
                        child: ValueListenableBuilder<int>(
                          valueListenable: HeroFlightOverrides.instance.tick,
                          builder: (_, __, ___) => _buildFlightPendingGuard(
                            child: _buildContent(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
      ),
    );
  }

  Widget _buildCursor({required Widget child}) {
    return ValueListenableBuilder(
        valueListenable: _showMoveCursor,
        builder: (_, showCursor, __) {
          return MouseRegion(
            hitTestBehavior: HitTestBehavior.translucent,
            cursor: showCursor &&
                    _layer.interaction.enableMove &&
                    widget.enableMouseCursor
                ? layerInteraction.style.hoverCursor
                : MouseCursor.defer,
            onEnter: (event) => _onHoverEnter(),
            onExit: (event) => _onHoverLeave(),
            child: child,
          );
        });
  }

  /// Builds the content widget based on the type of layer being displayed.
  Widget _buildContent() {
    Widget? content;
    switch (_layerType) {
      case LayerWidgetType.emoji:
        content = LayerWidgetEmojiItem(
          layer: _layer as EmojiLayer,
          emojiEditorConfigs: emojiEditorConfigs,
          textEditorConfigs: textEditorConfigs,
          designMode: designMode,
        );
      case LayerWidgetType.text:
        // While a closing edit flight is active, render the edited content
        // (override, keyed by id) so this layer already has the *new* size —
        // the hero captures the correct end rect (no left/right shift) and no
        // old text flashes after the flight while the (copied) layer re-syncs.
        final textOverride = HeroFlightOverrides.instance[_layer.id];
        content = LayerWidgetTextItem(
          layer: textOverride is TextLayer ? textOverride : _layer as TextLayer,
          textEditorConfigs: textEditorConfigs,
          showMoveCursor: _showMoveCursor,
          onHitChanged: (state) {
            _lastHitState.value = state;
          },
        );
      case LayerWidgetType.widget:
        content = LayerWidgetCustomItem(
          layer: _layer as WidgetLayer,
          stickerEditorConfigs: stickerEditorConfigs,
        );
      case LayerWidgetType.canvas:
        content = LayerWidgetPaintItem(
          layer: _layer as PaintLayer,
          isSelected: _isSelected,
          enableHitDetection:
              _layerInteractionManager?.enabledHitDetection ?? false,
          onHitChanged: (state) {
            _lastHitState.value = state;
          },
          paintEditorConfigs: widget.configs.paintEditor,
        );
      case LayerWidgetType.censor:
        content = LayerWidgetCensorItem(
          layer: _layer as PaintLayer,
          censorConfigs: paintEditorConfigs.censorConfigs,
        );
      default:
        return const SizedBox.shrink();
    }

    if (_layer.boxConstraints != null) {
      content = ConstrainedBox(
        constraints: _layer.boxConstraints!,
        child: content,
      );
    }

    return content;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    _layer.debugFillProperties(properties);
  }
}

/// Combines layer positioning and rotation into a single render object.
///
/// Unlike the previous `CustomSingleChildLayout` + `Transform` approach,
/// this widget fills its parent for hit-testing (`size = constraints.biggest`)
/// and applies position + rotation as a single paint/hit-test transform.
/// This ensures rotated content remains hittable even when the rotated bounds
/// extend beyond the unrotated layout rectangle.
class _TransformedLayerBox extends SingleChildRenderObjectWidget {
  const _TransformedLayerBox({
    required this.layerOffset,
    required this.fractionalOffset,
    required this.overlayPadding,
    required this.transform,
    required Widget child,
  }) : super(child: child);

  /// The layer's anchor position in the editor coordinate space.
  final Offset layerOffset;

  /// The fractional anchor offset (e.g. (-0.5, -0.5) for center).
  final Offset fractionalOffset;

  /// Touch-padding added around the content.
  final EdgeInsets overlayPadding;

  /// Rotation / flip matrix (no translation component).
  final Matrix4 transform;

  @override
  _RenderTransformedLayerBox createRenderObject(BuildContext context) {
    return _RenderTransformedLayerBox(
      layerOffset: layerOffset,
      fractionalOffset: fractionalOffset,
      overlayPadding: overlayPadding,
      transform: transform,
    );
  }

  @override
  void updateRenderObject(
      BuildContext context, _RenderTransformedLayerBox renderObject) {
    renderObject
      ..layerOffset = layerOffset
      ..fractionalOffset = fractionalOffset
      ..overlayPadding = overlayPadding
      ..transform = transform;
  }
}

class _RenderTransformedLayerBox extends RenderProxyBox {
  _RenderTransformedLayerBox({
    required Offset layerOffset,
    required Offset fractionalOffset,
    required EdgeInsets overlayPadding,
    required Matrix4 transform,
  })  : _layerOffset = layerOffset,
        _fractionalOffset = fractionalOffset,
        _overlayPadding = overlayPadding,
        _transform = transform;

  // ---- Properties with dirty-tracking ----

  Offset _layerOffset;
  set layerOffset(Offset value) {
    if (_layerOffset == value) return;
    _layerOffset = value;
    markNeedsPaint();
  }

  Offset _fractionalOffset;
  set fractionalOffset(Offset value) {
    if (_fractionalOffset == value) return;
    _fractionalOffset = value;
    markNeedsPaint();
  }

  EdgeInsets _overlayPadding;
  set overlayPadding(EdgeInsets value) {
    if (_overlayPadding == value) return;
    _overlayPadding = value;
    markNeedsPaint();
  }

  Matrix4 _transform;
  set transform(Matrix4 value) {
    if (_transform == value) return;
    _transform = value;
    markNeedsPaint();
  }

  // ---- Layout ----

  @override
  void performLayout() {
    assert(child != null);
    // Child is unconstrained so it sizes to its natural content.
    child!.layout(const BoxConstraints(), parentUsesSize: true);
    // This box fills the parent so size.contains() always passes for
    // valid touch positions, fixing hit-testing for rotated content.
    size = constraints.biggest;
  }

  // ---- Positioning helpers (mirrors old _LayerPositionDelegate logic) ----

  /// Computes the child's top-left position from the layer offset,
  /// fractional anchor, and overlay padding.
  Offset _childPosition() {
    final cs = child!.size;
    return Offset(
      _layerOffset.dx +
          _fractionalOffset.dx * cs.width -
          _overlayPadding.horizontal * (_fractionalOffset.dx + 0.5),
      _layerOffset.dy +
          _fractionalOffset.dy * cs.height -
          _overlayPadding.vertical * (_fractionalOffset.dy + 0.5),
    );
  }

  /// Builds the combined translation + rotation matrix.
  ///
  /// Steps: translate to child center → apply rotation/flip → translate back.
  Matrix4 _effectiveTransform() {
    final pos = _childPosition();
    final halfW = child!.size.width / 2;
    final halfH = child!.size.height / 2;
    return Matrix4.identity()
      ..translateByDouble(pos.dx + halfW, pos.dy + halfH, 0.0, 1.0)
      ..multiply(_transform)
      ..translateByDouble(-halfW, -halfH, 0.0, 1.0);
  }

  // ---- Hit testing ----

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return result.addWithPaintTransform(
      transform: _effectiveTransform(),
      position: position,
      hitTest: (BoxHitTestResult result, Offset? position) {
        return child!.hitTest(result, position: position!);
      },
    );
  }

  // ---- Coordinate mapping ----

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_effectiveTransform());
  }

  // ---- Painting ----

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    final effectiveTransform = _effectiveTransform();
    context.pushTransform(
      needsCompositing,
      offset,
      effectiveTransform,
      (PaintingContext context, Offset offset) {
        context.paintChild(child!, offset);
      },
    );
  }
}

/// Shuttle for layer<->layer heroine flights (sub-editor switches): renders
/// both hero contents at their natural (unconstrained) layout size and
/// scales them into the animated flight box via [FittedBox] — matching how
/// the canvas renders layers (laid out unconstrained, scaled by ancestor
/// transforms). The default [FadeShuttleBuilder] would lay the content out
/// INTO the flight box instead, painting text without the canvas' preview
/// scale (too large) for the whole flight.
///
/// For flights where the *other* endpoint is not a layer (text-editor
/// open/close), it delegates to the other hero's shuttle builder so those
/// flights keep their specialized rendering.
class _LayerFittedShuttleBuilder extends HeroineShuttleBuilder {
  const _LayerFittedShuttleBuilder();

  @override
  List<Object?> get props => [];

  @override
  Widget call(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    // Delegate text-editor flights to the editor-side builder (heroine
    // prefers the destination hero's builder, which on closing flights is
    // this one — without delegation the editor side would lose its
    // specialized max-width layout environment).
    final otherBuilder =
        switch (fromHeroContext.mounted ? fromHeroContext.widget : null) {
      final Heroine heroine
          when heroine.flightShuttleBuilder != null &&
              heroine.flightShuttleBuilder is! _LayerFittedShuttleBuilder =>
        heroine.flightShuttleBuilder,
      _ => null,
    };
    if (otherBuilder != null) {
      return otherBuilder(
        flightContext,
        animation,
        flightDirection,
        fromHeroContext,
        toHeroContext,
      );
    }

    Widget side(BuildContext heroContext) {
      if (!heroContext.mounted) return const SizedBox.shrink();
      // BoxFit.fill, not contain: both endpoints render the same layer, so
      // the flight box normally keeps the child's aspect ratio and fill ==
      // contain. But the very first flight frame can measure the source with
      // a transient 1-frame layout wobble (route push), making the box aspect
      // slightly off — contain then lets the *smaller* dimension win and the
      // whole visible text pops to the target size for that frame (a visible
      // jump when arriving at the crop editor), while fill only distorts the
      // glyphs imperceptibly for that frame. The image hero's shuttle uses
      // fill for the same reason and is smooth.
      return FittedBox(
        fit: BoxFit.fill,
        clipBehavior: Clip.none,
        child: InheritedTheme.captureAll(
          heroContext,
          (heroContext.widget as Heroine).child,
        ),
      );
    }

    // Both endpoints are copies of the SAME layer, so render only one side —
    // no cross-fade. Drawing both (even briefly at full opacity) doubles the
    // glyphs' anti-aliased edges and blends two differently rasterized
    // scales, which reads as text flicker during zoomed editor switches.
    // Prefer the destination: its rendering is what the landing hands off
    // to; the mounted check per frame covers an endpoint dying mid-flight.
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return side(toHeroContext.mounted ? toHeroContext : fromHeroContext);
      },
    );
  }
}
