// Dart imports:
import 'dart:async';
import 'dart:math';

// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import '/core/models/editor_callbacks/main_editor/helper_lines/helper_lines_callbacks.dart';
import '/core/models/editor_configs/pro_image_editor_configs.dart';
import '/core/models/history/last_layer_interaction_position.dart';
import '/core/models/layers/layer.dart';
import '/shared/utils/debounce.dart';
import '/shared/utils/unique_id_generator.dart';

/// A helper class responsible for managing layer interactions in the editor.
///
/// The `LayerInteractionManager` class provides methods for handling various
/// interactions with layers in an image editing environment, including
/// scaling, rotating, flipping, and zooming. It also manages the display of
/// helper lines and provides haptic feedback when interacting with these lines
/// to enhance the user experience.
class LayerInteractionManager {
  /// Creates an instance of [LayerInteractionManager].
  ///
  /// - [helperLinesCallbacks]: An optional instance of [HelperLinesCallbacks]
  ///   to handle helper line hit events.
  LayerInteractionManager({
    required this.helperLinesCallbacks,
    required this.configs,
    this.onSelectedLayerChanged,
    required this.onSelectedLayersChanged,
  });

  /// An optional instance of [HelperLinesCallbacks] that defines callback
  ///  functions for handling helper line interactions.
  final HelperLinesCallbacks? helperLinesCallbacks;

  /// The configuration settings for the Pro Image Editor.
  ///
  /// This object contains various customizable options and parameters
  /// that define the behavior and appearance of the image editor.
  final ProImageEditorConfigs configs;

  /// Callback function to be called when the selected layer changes.
  final ValueChanged<String>? onSelectedLayerChanged;

  /// Callback function to be called when the selected layer changes.
  final ValueChanged<Set<String>>? onSelectedLayersChanged;

  /// Debounce for scaling actions in the editor.
  late Debounce scaleDebounce;

  /// Y-coordinate of the rotation helper line.
  double rotationHelperLineY = 0;

  /// X-coordinate of the rotation helper line.
  double rotationHelperLineX = 0;

  /// Rotation angle of the rotation helper line.
  double rotationHelperLineDeg = 0;

  /// A list that stores the layers selected at the start of a scaling
  /// operation.
  /// This is used to keep track of the initial state of the selected layers
  /// before any scaling transformations are applied.
  List<Layer> selectedLayersScaleStart = [];

  /// The base scale factor from the layer;
  final Map<String, double> _baseScaleFactor = {};

  /// The base angle factor from the layer;
  final Map<String, double> _baseAngleFactor = {};

  /// Initial rotation angle when snapping started.
  final Map<String, double> _snapStartRotation = {};

  /// Last recorded rotation angle during snapping.
  final Map<String, double> _snapLastRotation = {};

  /// The gesture's detail.rotation at the moment snap was entered.
  /// Used to compute how far the user has rotated since snapping.
  final Map<String, double> _snapDetailRotation = {};

  /// Tracks the "raw" (unsnapped) layer offset during a drag.
  /// Deltas are always applied to this value so that snap overrides in
  /// helper lines or alignment guides do not accumulate drift.
  final Map<String, Offset> _rawLayerOffsets = {};

  /// The snapped layer offset on each axis while a center snap is active.
  /// Used at gesture end to re-apply the snap if a tiny finger-lift jitter
  /// nudged the layer just off the line it had snapped to.
  final Map<String, double> _snapHoldX = {};
  final Map<String, double> _snapHoldY = {};

  /// X-coordinate where snapping started.
  double snapStartPosX = 0;

  /// Y-coordinate where snapping started.
  double snapStartPosY = 0;

  /// Flag indicating if vertical helper lines should be displayed.
  bool showVerticalHelperLine = false;

  /// Flag indicating if horizontal helper lines should be displayed.
  bool showHorizontalHelperLine = false;

  /// Flag indicating that the rotation snap is currently *locked* to a snap
  /// angle. This drives the actual snapping behaviour and is intentionally
  /// independent of whether the guide line is shown.
  bool showRotationHelperLine = false;

  /// Whether the rotation guide *line* should be painted.
  ///
  /// Decoupled from [showRotationHelperLine] (the snap lock): the rotation
  /// still snaps silently, but the line only appears once the user has shown
  /// real rotation intent (see [HelperLineConfigs.rotateLineMinIntentDeg]).
  /// This keeps the line from flashing during a pure scaling gesture without
  /// weakening the snap itself.
  bool showRotationHelperLineUi = false;

  /// Whether to show the vertical alignment line for the active layer.
  bool isVerticalGuideVisible = false;

  /// Whether to show the horizontal alignment line for the active layer.
  bool isHorizontalGuideVisible = false;

  /// Offset of the horizontal alignment line relative to the editor center.
  Offset horizontalGuideOffset = Offset.zero;

  /// Offset of the vertical alignment line relative to the editor center.
  Offset verticalGuideOffset = Offset.zero;

  /// Flag indicating if rotation helper lines have started.
  bool _rotationStartedHelper = false;


  /// Flag indicating if helper lines should be displayed.
  bool showHelperLines = false;

  /// Flag indicating if the remove button is hovered.
  bool hoverRemoveBtn = false;

  /// Enables or disables hit detection.
  /// When `true`, allows detecting user interactions with the painted layer.
  bool enabledHitDetection = true;

  /// Flag indicating if the scaling tool is active.
  bool _activeScale = false;

  /// Whether a 2-finger scale/rotate gesture is currently active.
  /// Used by handleTapUp to avoid clearing the selection mid-pinch.
  bool get isScaling => _activeScale;

  /// Tracks whether any layer has been transformed (moved, scaled, rotated)
  /// during the current editing session.
  bool layerWasTransformed = false;

  /// Checks if there are any selected layers.
  ///
  /// Returns `true` if the list of selected layer IDs is not empty,
  /// indicating that at least one layer is selected. Otherwise, returns
  /// `false`.
  bool get hasSelectedLayers => selectedLayerIds.isNotEmpty;

  double _getLayerBaseScale(String layerId) {
    return _baseScaleFactor[layerId] ?? 1;
  }

  double _getLayerBaseAngle(String layerId) {
    return _baseAngleFactor[layerId] ?? 0;
  }

  double _getLayerSnapStartRotation(String layerId) {
    return _snapStartRotation[layerId] ?? 0;
  }

  double _getLayerSnapLastRotation(String layerId) {
    return _snapLastRotation[layerId] ?? 0;
  }

  /// The set of currently selected layer IDs (for multi-select support).
  final Set<String> selectedLayerIds = <String>{};

  /// Returns the currently selected layer ID.
  ///
  /// If multiple layers are selected, this returns the **last one inserted**.
  /// Returns an empty string if no layer is selected.
  String get selectedLayerId =>
      selectedLayerIds.isNotEmpty ? selectedLayerIds.first : '';

  /// Sets the [selectedLayerIds] to a single [id], replacing any existing
  /// selection.
  ///
  /// This is useful when only single selection is needed.
  set selectedLayerId(String id) {
    selectedLayerIds
      ..clear()
      ..add(id);
    _notifySelectionChanged();
  }

  /// Add a layer to the selection set.
  void addSelectedLayer(String id) {
    selectedLayerIds.add(id);
    _notifySelectionChanged();
  }

  /// Adds multiple layer IDs to the set of selected layers.
  ///
  /// This method takes a set of layer IDs and adds each ID to the
  /// `selectedLayerIds` collection. After updating the selection,
  /// it triggers a notification to indicate that the selection has changed.
  ///
  /// [value] A set of layer IDs to be added to the selection.
  void addMultipleSelectedLayers(Set<String> value) {
    for (final id in value) {
      selectedLayerIds.add(id);
    }
    _notifySelectionChanged();
  }

  /// Remove a layer from the selection set.
  void removeSelectedLayer(String id) {
    selectedLayerIds.remove(id);
    _notifySelectionChanged();
  }

  /// Removes multiple layers from the selection based on the provided set
  /// of layer IDs.
  ///
  /// This method iterates through the given set of layer IDs and removes each
  /// one from the `selectedLayerIds` collection. After the removal process,
  /// it triggers a notification to indicate that the selection has changed.
  ///
  /// [value] A set of layer IDs to be removed from the selection.
  void removeMultipleSelectedLayers(Set<String> value) {
    for (final id in value) {
      selectedLayerIds.remove(id);
    }
    _notifySelectionChanged();
  }

  /// Clear all selected layers.
  void clearSelectedLayers() {
    selectedLayerIds.clear();
    _notifySelectionChanged();
  }

  /// Set selected layers to a specific set.
  void setSelectedLayers(Iterable<String> ids) {
    selectedLayerIds
      ..clear()
      ..addAll(ids);
    _notifySelectionChanged();
  }

  /// Notifies selection change callbacks, both single and multi-select.
  void _notifySelectionChanged() {
    onSelectedLayerChanged?.call(selectedLayerId);
    onSelectedLayersChanged?.call(selectedLayerIds);
  }

  /// Groups the currently selected layers by assigning them a common groupId.
  ///
  /// This method creates a group from all currently selected layers by giving
  /// them the same unique groupId. After grouping, whenever any layer in the
  /// group is selected, all layers in the group will be automatically selected.
  ///
  /// [activeLayers] The list of all active layers in the editor.
  /// [onHistoryChanged] Callback to trigger when the layer history
  /// needs to be updated.
  ///
  /// Returns the groupId that was assigned to the layers, or null
  /// if no layers were selected.
  String? groupSelectedLayers(
    List<Layer> activeLayers,
    Function(List<Layer> layers) onHistoryChanged,
  ) {
    if (selectedLayerIds.isEmpty) return null;

    // Generate a unique group ID
    final groupId = generateUniqueId();

    // Create a copy of the layers list for history
    final updatedLayers = <Layer>[];
    for (final layer in activeLayers) {
      final layerCopy = _copyLayer(layer);
      if (selectedLayerIds.contains(layer.id)) {
        // Assign the new groupId to selected layers
        layerCopy.groupId = groupId;
      }
      updatedLayers.add(layerCopy);
    }

    // Update history with the modified layers
    onHistoryChanged(updatedLayers);

    return groupId;
  }

  /// Ungroups the specified layer by removing its groupId.
  ///
  /// This method removes the groupId from the specified layer and all other
  /// layers that share the same groupId, effectively breaking the group.
  ///
  /// [layer] The layer to ungroup.
  /// [activeLayers] The list of all active layers in the editor.
  /// [onHistoryChanged] Callback to trigger when the layer history
  /// needs to be updated.
  ///
  /// Returns true if any layers were ungrouped, false otherwise.
  bool ungroupLayer(
    Layer layer,
    List<Layer> activeLayers,
    Function(List<Layer> layers) onHistoryChanged,
  ) {
    if (layer.groupId == null) return false;

    final groupIdToRemove = layer.groupId!;

    // Create a copy of the layers list for history
    final updatedLayers = <Layer>[];
    bool hasChanges = false;

    for (final currentLayer in activeLayers) {
      final layerCopy = _copyLayer(currentLayer);
      if (currentLayer.groupId == groupIdToRemove) {
        // Remove the groupId from layers in the group
        layerCopy.groupId = null;
        hasChanges = true;
      }
      updatedLayers.add(layerCopy);
    }

    if (hasChanges) {
      // Update history with the modified layers
      onHistoryChanged(updatedLayers);
    }

    return hasChanges;
  }

  /// Creates a copy of a layer with all its properties.
  Layer _copyLayer(Layer originalLayer) {
    // Copy layer-specific properties based on layer type
    if (originalLayer is TextLayer) {
      return TextLayer(
        id: originalLayer.id,
        text: originalLayer.text,
        textStyle: originalLayer.textStyle,
        colorMode: originalLayer.colorMode,
        color: originalLayer.color,
        background: originalLayer.background,
        align: originalLayer.align,
        fontScale: originalLayer.fontScale,
        customSecondaryColor: originalLayer.customSecondaryColor,
        maxTextWidth: originalLayer.maxTextWidth,
        hit: originalLayer.hit,
        key: originalLayer.key,
        interaction: originalLayer.interaction,
        offset: originalLayer.offset,
        rotation: originalLayer.rotation,
        scale: originalLayer.scale,
        flipX: originalLayer.flipX,
        flipY: originalLayer.flipY,
        meta: originalLayer.meta,
        boxConstraints: originalLayer.boxConstraints,
      )..groupId = originalLayer.groupId;
    } else if (originalLayer is EmojiLayer) {
      return EmojiLayer(
        id: originalLayer.id,
        emoji: originalLayer.emoji,
        key: originalLayer.key,
        interaction: originalLayer.interaction,
        offset: originalLayer.offset,
        rotation: originalLayer.rotation,
        scale: originalLayer.scale,
        flipX: originalLayer.flipX,
        flipY: originalLayer.flipY,
        meta: originalLayer.meta,
        boxConstraints: originalLayer.boxConstraints,
      )..groupId = originalLayer.groupId;
    } else if (originalLayer is PaintLayer) {
      return PaintLayer(
        id: originalLayer.id,
        item: originalLayer.item,
        rawSize: originalLayer.rawSize,
        opacity: originalLayer.opacity,
        key: originalLayer.key,
        interaction: originalLayer.interaction,
        offset: originalLayer.offset,
        rotation: originalLayer.rotation,
        scale: originalLayer.scale,
        flipX: originalLayer.flipX,
        flipY: originalLayer.flipY,
        meta: originalLayer.meta,
        boxConstraints: originalLayer.boxConstraints,
      )..groupId = originalLayer.groupId;
    } else if (originalLayer is WidgetLayer) {
      return WidgetLayer(
        id: originalLayer.id,
        widget: originalLayer.widget,
        exportConfigs: originalLayer.exportConfigs,
        key: originalLayer.key,
        interaction: originalLayer.interaction,
        offset: originalLayer.offset,
        rotation: originalLayer.rotation,
        scale: originalLayer.scale,
        flipX: originalLayer.flipX,
        flipY: originalLayer.flipY,
        meta: originalLayer.meta,
        boxConstraints: originalLayer.boxConstraints,
      )..groupId = originalLayer.groupId;
    }

    // Fallback for base Layer type
    return Layer(
      id: originalLayer.id,
      key: originalLayer.key,
      interaction: originalLayer.interaction,
      offset: originalLayer.offset,
      rotation: originalLayer.rotation,
      scale: originalLayer.scale,
      flipX: originalLayer.flipX,
      flipY: originalLayer.flipY,
      meta: originalLayer.meta,
      boxConstraints: originalLayer.boxConstraints,
      groupId: originalLayer.groupId,
    );
  }

  /// Helper variable for scaling during rotation of a layer.
  double? rotateScaleLayerScaleHelper;

  /// Helper variable for storing the size of a layer during rotation and
  /// scaling operations.
  Size? rotateScaleLayerSizeHelper;

  /// Represents the layer being interacted with during a
  /// scale or rotate gesture.
  ///
  /// This is set when the user drags the scale/rotate button from the
  /// selection overlay.
  Layer? activeInteractionLayer;

  /// Last recorded X-axis position for layers.
  LayerLastPosition lastPositionX = LayerLastPosition.center;

  /// Last recorded Y-axis position for layers.
  LayerLastPosition lastPositionY = LayerLastPosition.center;

  Offset? _rotateScaleButtonStartPosition;
  final _horizontalSnapHelper = _LayerAlignGuideHelper();
  final _verticalSnapHelper = _LayerAlignGuideHelper();

  /// Configuration settings for displaying and managing helper lines within
  /// the editor.
  HelperLineConfigs get helperLineConfigs => configs.helperLines;

  /// Resets the state of the layer interaction manager by:
  ///
  /// - Setting `_rotateScaleButtonStartPosition` to `null`.
  /// - Setting `_rotationStartedHelper` to `false`.
  /// - Enabling the display of helper lines by setting `showHelperLines` to
  /// `true`.
  void reset() {
    _rotateScaleButtonStartPosition = null;
    _rotationStartedHelper = false;
    showHelperLines = true;
  }

  Offset _getFractionalLayerOffset(Layer layer) {
    if (layer.isTextLayer) {
      return configs.textEditor.layerFractionalOffset;
    } else if (layer.isEmojiLayer) {
      return configs.emojiEditor.layerFractionalOffset;
    } else if (layer.isWidgetLayer) {
      return configs.stickerEditor.layerFractionalOffset;
    } else if (layer.isPaintLayer) {
      return configs.paintEditor.layerFractionalOffset;
    }
    return const Offset(-0.5, -0.5);
  }

  /// Determines if layers are selectable based on the configuration and device
  /// type.
  bool layersAreSelectable(ProImageEditorConfigs configs) {
    if (configs.layerInteraction.selectable ==
        LayerInteractionSelectable.auto) {
      return isDesktop;
    }
    return configs.layerInteraction.selectable ==
        LayerInteractionSelectable.enabled;
  }

  /// Calculates scaling and rotation based on user interactions.
  void calculateInteractiveButtonScaleRotate({
    required double editorScaleFactor,
    required Offset editorScaleOffset,
    required ProImageEditorConfigs configs,
    required ScaleUpdateDetails details,
    required List<Layer> selectedLayers,
    required Size editorSize,
    required LayerInteractionStyle layerTheme,
  }) {
    /// Calculates the rotation angle (in radians) for a button moved to a
    /// new position.
    /// [oldPosition] is the initial button position,
    /// [newPosition] is the final button position.
    double calculateRotation(Offset oldPosition, Offset newPosition) {
      // Calculate the vectors from the origin to the old and new positions
      Offset oldVector = oldPosition;
      Offset newVector = newPosition;

      // Get the angle of each vector relative to the x-axis
      double oldAngle = atan2(oldVector.dy, oldVector.dx);
      double newAngle = atan2(newVector.dy, newVector.dx);

      // Calculate the rotation angle
      double rotation = newAngle - oldAngle;

      // Normalize the rotation angle to be between -pi and pi
      if (rotation > pi) rotation -= 2 * pi;
      if (rotation < -pi) rotation += 2 * pi;

      return rotation; // In radians
    }

    /// Calculates the scale factor based on the movement of a button.
    /// [oldPosition] is the initial button position,
    /// [newPosition] is the final button position.
    double calculateScale(
      Offset oldPosition,
      Offset newPosition,
    ) {
      // Calculate distances from the origin to the old and new positions
      double oldDistance = (oldPosition).distance;
      double newDistance = (newPosition).distance;

      // Calculate the scale factor
      if (oldDistance == 0 || newDistance == 0) {
        return 1;
      }

      return newDistance / oldDistance;
    }

    for (Layer layer in selectedLayers) {
      /// Optionally, this could be extended to allow multiple layers to be
      /// transformed using a single layer interaction button.
      if (activeInteractionLayer?.id != layer.id) continue;

      Offset layerOffset = layer.offset;

      Offset realTouchPosition =
          (details.localFocalPoint - editorScaleOffset) / editorScaleFactor;

      Offset touchPositionFromLayerCenter =
          realTouchPosition - editorSize.center(Offset.zero) - layerOffset;

      if (layer.flipX) {
        touchPositionFromLayerCenter = Offset(
          -touchPositionFromLayerCenter.dx,
          touchPositionFromLayerCenter.dy,
        );
      }
      if (layer.flipY) {
        touchPositionFromLayerCenter = Offset(
          touchPositionFromLayerCenter.dx,
          -touchPositionFromLayerCenter.dy,
        );
      }

      _rotateScaleButtonStartPosition ??= touchPositionFromLayerCenter;

      if (layer.interaction.enableScale) {
        layer.scale = _getLayerBaseScale(layer.id) *
            calculateScale(
              _rotateScaleButtonStartPosition!,
              touchPositionFromLayerCenter,
            );
        _setMinMaxScaleFactor(configs, layer);
      }

      if (layer.interaction.enableRotate) {
        layer.rotation = _getLayerBaseAngle(layer.id) +
            calculateRotation(
              _rotateScaleButtonStartPosition!,
              touchPositionFromLayerCenter,
            );

        checkRotationLine(
          layer: layer,
          editorSize: editorSize,
          editorScaleFactor: editorScaleFactor,
        );
      }
    }
  }

  /// Calculates movement of a layer based on user interactions, considering
  /// various conditions such as hit areas and screen boundaries.
  void calculateMovement({
    required double editorScaleFactor,
    required BuildContext context,
    required ScaleUpdateDetails detail,
    required List<Layer> selectedLayers,
    required List<Layer> layerList,
    required GlobalKey removeAreaKey,
    required Function(bool value) onHoveredRemoveChanged,
    required StreamController<void> helperLineCtrl,
  }) {
    if (_activeScale) {
      // Skip just this one frame to avoid the focal-point jump when
      // transitioning from 2-finger scale to 1-finger drag. Then sync
      // the focal point and clear the flag so subsequent frames work
      // immediately (no 100ms debounce lag).
      _activeScale = false;
      _lastLocalFocalPoint = detail.localFocalPoint;
      return;
    }

    _checkLayerHoverRemoveArea(
      detail: detail,
      onHoveredRemoveChanged: onHoveredRemoveChanged,
      removeAreaKey: removeAreaKey,
    );

    bool hasMultiSelection = selectedLayers.length > 1;
    if (!layerWasTransformed) {
      layerWasTransformed = selectedLayers.isNotEmpty;
    }
    // Compute content-space delta from localFocalPoint differences.
    // The GestureDetector sits inside the InteractiveViewer's Transform,
    // so localFocalPoint is already in content coordinates — no scale
    // division needed.
    final lastLocal = _lastLocalFocalPoint ?? detail.localFocalPoint;
    final contentDelta = detail.localFocalPoint - lastLocal;
    _lastLocalFocalPoint = detail.localFocalPoint;

    // Compute smoothed drag speed once per frame (outside the layer loop).
    final dragSpeed = contentDelta.distance;
    _smoothedDragSpeed = _smoothedDragSpeed * 0.7 + dragSpeed * 0.3;
    final bool isFastDrag = _smoothedDragSpeed > 1.0;

    for (Layer layer in selectedLayers) {
      if (!layer.interaction.enableMove) continue;

      Offset fractionalOffset = _getFractionalLayerOffset(layer);


      // Apply delta to the raw (unsnapped) offset so that snap overrides
      // from helper lines / alignment guides never accumulate drift.
      final rawOffset = _rawLayerOffsets[layer.id] ?? layer.offset;
      final newRawOffset = Offset(
        rawOffset.dx + contentDelta.dx,
        rawOffset.dy + contentDelta.dy,
      );
      _rawLayerOffsets[layer.id] = newRawOffset;
      layer.offset = newRawOffset;

      if (hasMultiSelection ||
          (editorScaleFactor > 1 && helperLineConfigs.isDisabledAtZoom)) {
        continue;
      }

      // Skip snap logic when dragging fast.
      if (isFastDrag) {
        showVerticalHelperLine = false;
        showHorizontalHelperLine = false;
        // Still compute position-relative-to-center and update
        // lastPositionX/Y so that when the drag slows down, the snap
        // logic has up-to-date state (prevents stale state from causing
        // a false "crossed center" detection and teleportation).
        final Offset layerCenterOffsetFast =
            layer.computeOffsetFromCenterFraction(fractionalOffset);
        lastPositionX = layerCenterOffsetFast.dx <= 0
            ? LayerLastPosition.left
            : LayerLastPosition.right;
        lastPositionY = layerCenterOffsetFast.dy <= 0
            ? LayerLastPosition.top
            : LayerLastPosition.bottom;
        continue;
      }

      final Offset localPointFromCenter =
          layer.computeLocalCenterOffset(fractionalOffset);
      final Offset layerCenterOffset =
          layer.computeOffsetFromCenterFraction(fractionalOffset);

      final releaseThreshold = helperLineConfigs.releaseThreshold;
      bool hasLineHit = false;
      double posX = layerCenterOffset.dx;
      double posY = layerCenterOffset.dy;

      bool hitAreaX =
          detail.focalPoint.dx >= snapStartPosX - releaseThreshold &&
              detail.focalPoint.dx <= snapStartPosX + releaseThreshold;
      bool hitAreaY =
          detail.focalPoint.dy >= snapStartPosY - releaseThreshold &&
              detail.focalPoint.dy <= snapStartPosY + releaseThreshold;

      // Proximity check: only snap when the layer is within 8 content
      // units of center. This prevents teleporting from far away.
      const double snapProximity = 8.0;
      bool helperGoNearLineLeft =
          posX >= 0 && posX < snapProximity &&
              lastPositionX == LayerLastPosition.left;
      bool helperGoNearLineRight =
          posX <= 0 && posX > -snapProximity &&
              lastPositionX == LayerLastPosition.right;
      bool helperGoNearLineTop =
          posY >= 0 && posY < snapProximity &&
              lastPositionY == LayerLastPosition.top;
      bool helperGoNearLineBottom =
          posY <= 0 && posY > -snapProximity &&
              lastPositionY == LayerLastPosition.bottom;

      /// Calc vertical helper line
      if (helperLineConfigs.showVerticalLine) {
        if ((!showVerticalHelperLine &&
                (helperGoNearLineLeft || helperGoNearLineRight)) ||
            (showVerticalHelperLine && hitAreaX)) {
          if (!showVerticalHelperLine) {
            hasLineHit = true;
            snapStartPosX = detail.focalPoint.dx;
          }
          showVerticalHelperLine = true;
          final snapX = -localPointFromCenter.dx;
          layer.offset = Offset(snapX, layer.offset.dy);
          // Sync raw offset to snap position so releasing the snap
          // doesn't cause a jump.
          _rawLayerOffsets[layer.id] = layer.offset;
          _snapHoldX[layer.id] = snapX;
          lastPositionX = LayerLastPosition.center;
        } else {
          showVerticalHelperLine = false;
          lastPositionX =
              posX <= 0 ? LayerLastPosition.left : LayerLastPosition.right;
        }
      }

      if (helperLineConfigs.showHorizontalLine) {
        /// Calc horizontal helper line
        if ((!showHorizontalHelperLine &&
                (helperGoNearLineTop || helperGoNearLineBottom)) ||
            (showHorizontalHelperLine && hitAreaY)) {
          if (!showHorizontalHelperLine) {
            hasLineHit = true;
            snapStartPosY = detail.focalPoint.dy;
          }
          showHorizontalHelperLine = true;
          final snapY = -localPointFromCenter.dy;
          layer.offset = Offset(layer.offset.dx, snapY);
          // Sync raw offset to snap position so releasing the snap
          // doesn't cause a jump.
          _rawLayerOffsets[layer.id] = layer.offset;
          _snapHoldY[layer.id] = snapY;
          lastPositionY = LayerLastPosition.center;
        } else {
          showHorizontalHelperLine = false;
          lastPositionY =
              posY <= 0 ? LayerLastPosition.top : LayerLastPosition.bottom;
        }
      }

      _updateAlignmentGuides(
        detail: detail,
        layerList: layerList,
        activeLayer: layer,
        helperLineCtrl: helperLineCtrl,
        editorScaleFactor: editorScaleFactor,
        fractionalOffset: fractionalOffset,
      );

      if (hasLineHit) {
        if (showHorizontalHelperLine) {
          helperLinesCallbacks?.handleHorizontalLineHit();
        }
        if (showVerticalHelperLine) {
          helperLinesCallbacks?.handleVerticalLineHit();
        }
      }


    }
  }

  void _checkLayerHoverRemoveArea({
    required ScaleUpdateDetails detail,
    required GlobalKey removeAreaKey,
    required Function(bool value) onHoveredRemoveChanged,
  }) {
    RenderBox? box =
        removeAreaKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null) {
      Offset position = box.localToGlobal(Offset.zero);
      bool hit = Rect.fromLTWH(
        position.dx,
        position.dy,
        box.size.width,
        box.size.height,
      ).contains(detail.focalPoint);
      if (hoverRemoveBtn != hit) {
        hoverRemoveBtn = hit;
        onHoveredRemoveChanged.call(hoverRemoveBtn);
      }
    }
  }

  /// Calculates scaling and rotation of a layer based on user interactions.
  void calculateScaleRotate({
    required ProImageEditorConfigs configs,
    required ScaleUpdateDetails detail,
    required List<Layer> selectedLayers,
    required Size editorSize,
    required double editorScaleFactor,
    required EdgeInsets screenPaddingHelper,
  }) {
    _activeScale = true;
    bool enableMobilePinchScale =
        configs.layerInteraction.enableMobilePinchScale;
    bool enableMobilePinchRotate =
        configs.layerInteraction.enableMobilePinchRotate;

    if (enableMobilePinchScale || enableMobilePinchRotate) {
      if (!layerWasTransformed) {
        layerWasTransformed = selectedLayers.isNotEmpty;
      }
      for (Layer layer in selectedLayers) {
        // Lazy-init base factors: when a 2-finger pinch starts mid-gesture
        // (the ScaleStart already fired with 1 finger and onScaleEnd cleared
        // the maps), we need to capture the current scale/rotation as base.
        // Compensate for detail.scale/rotation which are relative to the
        // original ScaleStart, not to when the 2nd finger was added.
        final bool lazyInitScale = !_baseScaleFactor.containsKey(layer.id);
        _baseScaleFactor.putIfAbsent(
          layer.id,
          () => detail.scale != 0 ? layer.scale / detail.scale : layer.scale,
        );
        final bool lazyInitAngle = !_baseAngleFactor.containsKey(layer.id);
        _baseAngleFactor.putIfAbsent(
          layer.id,
          () => layer.rotation - detail.rotation,
        );

        if (layer.interaction.enableScale && enableMobilePinchScale) {
          // Freeze text content at pre-gesture scale (set once).
          // The visual difference is applied via Transform on the GPU.
          layer.gestureBaseScale ??= layer.scale;
          layer.scale = _getLayerBaseScale(layer.id) * detail.scale;
          _setMinMaxScaleFactor(configs, layer);
        }
        if (layer.interaction.enableRotate && enableMobilePinchRotate) {
          // Track rotation speed in degrees/second (frame-rate independent).
          final now = DateTime.now();
          final dtMs = now.difference(_lastRotationTimestamp).inMilliseconds;
          final dtSec = dtMs > 0 ? dtMs / 1000.0 : 1.0 / 60.0; // fallback
          final rotationDeltaDeg =
              (detail.rotation - _lastDetailRotation).abs() * 180 / pi;
          // Clamp instant speed: values > 100°/s are either glitch
          // spikes (360° wrapping) or legitimately fast rotation.
          // Capping prevents EMA poisoning while still allowing
          // the EMA to decay when the user slows down.
          final instantSpeed =
              (rotationDeltaDeg / dtSec).clamp(0.0, 100.0);
          _lastDetailRotation = detail.rotation;
          _lastRotationTimestamp = now;
          _smoothedRotationSpeed =
              _smoothedRotationSpeed * 0.5 + instantSpeed * 0.5;

          // Compute the unsnapped ("real") rotation from finger position.
          layer.rotation = _getLayerBaseAngle(layer.id) + detail.rotation;

          // ── Rotation snap ──
          final bool canSnap = selectedLayers.length <= 1 &&
              helperLineConfigs.showRotateLine &&
              !(editorScaleFactor > 1 && helperLineConfigs.isDisabledAtZoom);

          // Whether the user has rotated enough within this gesture to *show*
          // the guide line. This gates only the line, not the snap itself —
          // detail.rotation is the rotation accumulated since gesture start,
          // so a pure scaling gesture (≈0° net) keeps the line hidden while
          // the object still snaps silently.
          final gestureRotationDeg = detail.rotation.abs() * 180 / pi;
          final hasRotationIntent =
              gestureRotationDeg >= helperLineConfigs.rotateLineMinIntentDeg;

          if (canSnap) {
            const breakFreeDeg = 10.0; // how far to rotate to escape lock

            if (showRotationHelperLine) {
              // ── LOCKED: hold at snap angle, check break-free ──
              final lockDetail =
                  _snapDetailRotation[layer.id] ?? detail.rotation;
              final escapeDeg =
                  (detail.rotation - lockDetail).abs() * 180 / pi;

              if (escapeDeg > breakFreeDeg) {
                // Break free: correct base so rotation continues
                // smoothly from the snap angle (no visual jump).
                showRotationHelperLine = false;
                showRotationHelperLineUi = false;
                _smoothedRotationSpeed = 0.0;
                _baseAngleFactor[layer.id] =
                    rotationHelperLineDeg - detail.rotation;
                layer.rotation =
                    _getLayerBaseAngle(layer.id) + detail.rotation;
              } else {
                // Stay locked at snap angle.
                layer.rotation = rotationHelperLineDeg;
                showRotationHelperLineUi = hasRotationIntent;
              }
            } else {
              // ── NOT LOCKED: check if rotation crossed a snap angle ──
              final deg = layer.rotation * 180 / pi;
              var prevDeg = _getLayerSnapLastRotation(layer.id);

              // Normalize prevDeg to within ±180° of deg so crossing
              // detection works even when raw rotation wraps by 360°.
              while ((prevDeg - deg) > 180) {
                prevDeg -= 360;
              }
              while ((prevDeg - deg) < -180) {
                prevDeg += 360;
              }

              // Find nearest snap angle to current position.
              final nearestSnapDeg = (deg / 45.0).round() * 45.0;

              // Pure crossing detection: did the rotation pass through
              // a snap angle between previous and current frame?
              // No proximity fallback needed — crossing detection catches
              // every slow pass-through. After break-free, rotation moves
              // AWAY from snap so crossing can't fire (no infinite loop).
              final speedDegPerSec = _smoothedRotationSpeed;
              const snapSpeedThreshold = 60.0; // °/sec: skip snap if fast

              final crossedSnap =
                  speedDegPerSec < snapSpeedThreshold &&
                  ((prevDeg < nearestSnapDeg && deg >= nearestSnapDeg) ||
                   (prevDeg > nearestSnapDeg && deg <= nearestSnapDeg));


              if (crossedSnap) {
                // Rotation naturally passed through snap angle → LOCK.
                // The snap always engages; the line only shows with intent.
                final snapRad = nearestSnapDeg / 180 * pi;
                showRotationHelperLine = true;
                showRotationHelperLineUi = hasRotationIntent;
                rotationHelperLineDeg = snapRad;
                _snapDetailRotation[layer.id] = detail.rotation;
                _baseAngleFactor[layer.id] = snapRad - detail.rotation;
                layer.rotation = snapRad;

                helperLinesCallbacks?.handleRotateLineHit();

                // Update helper line position.
                final frac = _getFractionalLayerOffset(layer);
                layer.computeLocalCenterOffset(frac);
                final center =
                    layer.computeOffsetFromCenterFraction(frac);
                rotationHelperLineX = center.dx + editorSize.width / 2;
                rotationHelperLineY = center.dy + editorSize.height / 2;
              }

              // Track previous rotation for crossing detection.
              _snapLastRotation[layer.id] = deg;
            }
          } else {
            showRotationHelperLine = false;
            showRotationHelperLineUi = false;
          }
        }
      }
    }

    // _activeScale is cleared by calculateMovement on the first
    // 1-pointer frame after scaling (single-frame skip, no debounce).
  }

  /// Checks the rotation line based on user interactions, adjusting rotation
  /// accordingly.
  void checkRotationLine({
    required Layer layer,
    required Size editorSize,
    required double editorScaleFactor,
  }) {
    if (!helperLineConfigs.showRotateLine ||
        (editorScaleFactor > 1 && helperLineConfigs.isDisabledAtZoom)) {
      return;
    }

    double hitSpanX = helperLineConfigs.releaseThreshold / 2;
    double deg = layer.rotation * 180 / pi;
    // How far is the current rotation from the nearest multiple of 45°.
    double degHit = deg % 45;
    if (degHit < 0) degHit += 45; // Normalize negative rotations to [0, 45)

    bool hitAreaBelow = degHit <= hitSpanX;
    bool hitAreaAfter = degHit >= 45 - hitSpanX;
    bool hitArea = hitAreaBelow || hitAreaAfter;

    double lastRotation = _getLayerSnapLastRotation(layer.id);

    // Rotation applied within this gesture (current angle minus the gesture's
    // base). Used only to decide whether the guide *line* is shown — the snap
    // itself always engages, so a scale-dominated handle drag with tiny
    // incidental rotation still snaps silently without flashing the line.
    final gestureRotationDeg =
        (layer.rotation - _getLayerBaseAngle(layer.id)).abs() * 180 / pi;
    final hasRotationIntent =
        gestureRotationDeg >= helperLineConfigs.rotateLineMinIntentDeg;

    if ((!showRotationHelperLine &&
            ((degHit > 0 && degHit <= hitSpanX && lastRotation < deg) ||
                (degHit < 45 &&
                    degHit >= 45 - hitSpanX &&
                    lastRotation > deg))) ||
        (showRotationHelperLine && hitArea)) {
      if (_rotationStartedHelper) {
        layer.rotation =
            (deg - (degHit > 45 - hitSpanX ? degHit - 45 : degHit)) / 180 * pi;
        rotationHelperLineDeg = layer.rotation;

        final Offset fractionalOffset = _getFractionalLayerOffset(layer);
        layer.computeLocalCenterOffset(fractionalOffset);
        final Offset layerCenterOffset =
            layer.computeOffsetFromCenterFraction(fractionalOffset);

        double posY = layerCenterOffset.dy;
        double posX = layerCenterOffset.dx;

        rotationHelperLineX = posX + editorSize.width / 2;
        rotationHelperLineY = posY + editorSize.height / 2;
        if (!showRotationHelperLine) {
          helperLinesCallbacks?.handleRotateLineHit();
        }
        showRotationHelperLine = true;
        showRotationHelperLineUi = hasRotationIntent;
      }
      _snapLastRotation[layer.id] = deg;
    } else {
      showRotationHelperLine = false;
      showRotationHelperLineUi = false;
      _rotationStartedHelper = true;
    }
  }

  /// Handles the initialization logic when a scaling gesture starts on a layer.
  /// The last localFocalPoint from the gesture, used to compute
  /// content-space deltas that correctly account for the InteractiveViewer
  /// transform.
  Offset? _lastLocalFocalPoint;

  /// Smoothed drag speed (EMA) used to skip snap logic during fast drags.
  double _smoothedDragSpeed = 0.0;

  /// Smoothed rotation speed in degrees/second (EMA), used to skip rotation
  /// snap during fast rotation. Frame-rate independent.
  double _smoothedRotationSpeed = 0.0;

  /// Last detail.rotation value for computing per-frame rotation delta.
  double _lastDetailRotation = 0.0;

  /// Timestamp of the last rotation speed sample for frame-rate independence.
  DateTime _lastRotationTimestamp = DateTime.now();


  void onScaleStart({
    required ScaleStartDetails details,
    required List<Layer> selectedLayers,
  }) {
    selectedLayersScaleStart = selectedLayers;
    snapStartPosX = details.focalPoint.dx;
    snapStartPosY = details.focalPoint.dy;
    _lastLocalFocalPoint = details.localFocalPoint;
    _smoothedDragSpeed = 0.0;
    _smoothedRotationSpeed = 0.0;
    _lastDetailRotation = 0.0;
    _lastRotationTimestamp = DateTime.now();


    _snapHoldX.clear();
    _snapHoldY.clear();

    for (Layer layer in selectedLayers) {
      _baseScaleFactor[layer.id] = layer.scale;
      _baseAngleFactor[layer.id] = layer.rotation;
      _snapStartRotation[layer.id] = layer.rotation * 180 / pi;
      _snapLastRotation[layer.id] = _getLayerSnapStartRotation(layer.id);
      _rawLayerOffsets[layer.id] = layer.offset;
      // Freeze content at current scale — the visual difference is applied
      // via Transform on the GPU so text doesn't re-layout every frame.
      layer.gestureBaseScale = layer.scale;
      reset();

      final fractionOffset = _getFractionalLayerOffset(layer);
      final centerOffset =
          layer.computeOffsetFromCenterFraction(fractionOffset);
      double posX = centerOffset.dx;
      double posY = centerOffset.dy;

      final releaseThreshold = helperLineConfigs.releaseThreshold;

      lastPositionY = posY <= -releaseThreshold
          ? LayerLastPosition.top
          : posY >= releaseThreshold
              ? LayerLastPosition.bottom
              : LayerLastPosition.center;
      lastPositionX = posX <= -releaseThreshold
          ? LayerLastPosition.left
          : posX >= releaseThreshold
              ? LayerLastPosition.right
              : LayerLastPosition.center;
    }
  }

  /// Handles cleanup and resets various flags and states after scaling
  /// interaction ends.
  void onScaleEnd() {
    // Re-apply an active center snap if the layer only drifted a tiny bit off
    // it (a finger-lift jitter). If the user genuinely dragged far away from
    // the snapped line, the difference is large and we leave it as-is.
    const double snapReleaseTolerance = 20.0;
    for (final layer in selectedLayersScaleStart) {
      final holdX = _snapHoldX[layer.id];
      if (holdX != null && (layer.offset.dx - holdX).abs() <= snapReleaseTolerance) {
        layer.offset = Offset(holdX, layer.offset.dy);
      }
      final holdY = _snapHoldY[layer.id];
      if (holdY != null && (layer.offset.dy - holdY).abs() <= snapReleaseTolerance) {
        layer.offset = Offset(layer.offset.dx, holdY);
      }
    }

    // Clear gesture-mode rendering → content re-renders sharply at final
    // scale/position.
    for (final layer in selectedLayersScaleStart) {
      layer.gestureBaseScale = null;
    }

    _activeScale = false;
    _baseScaleFactor.clear();
    _baseAngleFactor.clear();
    _snapStartRotation.clear();
    _snapLastRotation.clear();
    _snapDetailRotation.clear();
    _rawLayerOffsets.clear();
    _snapHoldX.clear();
    _snapHoldY.clear();
    _lastLocalFocalPoint = null;
    _smoothedDragSpeed = 0.0;
    _smoothedRotationSpeed = 0.0;
    _lastDetailRotation = 0.0;

    selectedLayersScaleStart.clear();
    enabledHitDetection = true;
    layerWasTransformed = false;
    showHorizontalHelperLine = false;
    showVerticalHelperLine = false;
    showRotationHelperLine = false;
    showRotationHelperLineUi = false;
    isVerticalGuideVisible = false;
    isHorizontalGuideVisible = false;
    showHelperLines = false;
    hoverRemoveBtn = false;
  }

  /// Rotate a layer.
  ///
  /// This method rotates a layer based on various factors, including flip and
  /// angle.
  void rotateLayer({
    required Layer layer,
    required bool beforeIsFlipX,
    required double newImgW,
    required double newImgH,
    required double rotationScale,
    required double rotationRadian,
    required double rotationAngle,
  }) {
    if (beforeIsFlipX) {
      layer.rotation -= rotationRadian;
    } else {
      layer.rotation += rotationRadian;
    }

    if (rotationAngle == 90) {
      layer
        ..scale /= rotationScale
        ..offset = Offset(
          newImgW - layer.offset.dy / rotationScale,
          layer.offset.dx / rotationScale,
        );
    } else if (rotationAngle == 180) {
      layer.offset = Offset(
        newImgW - layer.offset.dx,
        newImgH - layer.offset.dy,
      );
    } else if (rotationAngle == 270) {
      layer
        ..scale /= rotationScale
        ..offset = Offset(
          layer.offset.dy / rotationScale,
          newImgH - layer.offset.dx / rotationScale,
        );
    }
  }

  /// Handles zooming of a layer.
  ///
  /// This method calculates the zooming of a layer based on the specified
  /// parameters.
  /// It checks if the layer should be zoomed and performs the necessary
  /// transformations.
  ///
  /// Returns `true` if the layer was zoomed, otherwise `false`.
  bool zoomedLayer({
    required Layer layer,
    required double scale,
    required double scaleX,
    required double oldFullH,
    required double oldFullW,
    required double pixelRatio,
    required Rect cropRect,
    required bool isHalfPi,
  }) {
    var paddingTop = cropRect.top / pixelRatio;
    var paddingLeft = cropRect.left / pixelRatio;
    var paddingRight = oldFullW - cropRect.right;
    var paddingBottom = oldFullH - cropRect.bottom;

    // important to check with < 1 and >-1 cuz crop-editor has rounding bugs
    if (paddingTop > 0.1 ||
        paddingTop < -0.1 ||
        paddingLeft > 0.1 ||
        paddingLeft < -0.1 ||
        paddingRight > 0.1 ||
        paddingRight < -0.1 ||
        paddingBottom > 0.1 ||
        paddingBottom < -0.1) {
      var initialIconX = (layer.offset.dx - paddingLeft) * scaleX;
      var initialIconY = (layer.offset.dy - paddingTop) * scaleX;
      layer
        ..offset = Offset(
          initialIconX,
          initialIconY,
        )
        ..scale *= scale;
      return true;
    }
    return false;
  }

  /// Flip a layer horizontally or vertically.
  ///
  /// This method flips a layer either horizontally or vertically based on the
  /// specified parameters.
  void flipLayer({
    required Layer layer,
    required bool flipX,
    required bool flipY,
    required bool isHalfPi,
    required double imageWidth,
    required double imageHeight,
  }) {
    if (flipY) {
      if (isHalfPi) {
        layer.flipY = !layer.flipY;
      } else {
        layer.flipX = !layer.flipX;
      }
      layer.offset = Offset(
        imageWidth - layer.offset.dx,
        layer.offset.dy,
      );
    }
    if (flipX) {
      layer
        ..flipX = !layer.flipX
        ..offset = Offset(
          layer.offset.dx,
          imageHeight - layer.offset.dy,
        );
    }
  }

  void _setMinMaxScaleFactor(ProImageEditorConfigs configs, Layer layer) {
    double minScale = 1;
    double maxScale = 1;
    if (layer is PaintLayer) {
      minScale = configs.paintEditor.minScale;
      maxScale = configs.paintEditor.maxScale;
    } else if (layer is TextLayer) {
      minScale = configs.textEditor.minScale;
      maxScale = configs.textEditor.maxScale;
    } else if (layer is EmojiLayer) {
      minScale = configs.emojiEditor.minScale;
      maxScale = configs.emojiEditor.maxScale;
    } else if (layer is WidgetLayer) {
      minScale = configs.stickerEditor.minScale;
      maxScale = configs.stickerEditor.maxScale;
    }
    layer.scale = layer.scale.clamp(minScale, maxScale);
  }

  void _updateAlignmentGuides({
    required List<Layer> layerList,
    required Layer activeLayer,
    required ScaleUpdateDetails detail,
    required StreamController<void> helperLineCtrl,
    required double editorScaleFactor,
    required Offset fractionalOffset,
  }) {
    if (!helperLineConfigs.showLayerAlignLine) return;

    final snapThreshold = 3.0 / editorScaleFactor;
    final releaseThreshold = helperLineConfigs.releaseThreshold;

    final wasHorizontalGuideVisible = isHorizontalGuideVisible;
    final wasVerticalGuideVisible = isVerticalGuideVisible;

    // Reset guide visibility
    isHorizontalGuideVisible = false;
    isVerticalGuideVisible = false;

    Offset? horizontalOffset;
    Offset? verticalOffset;

    final Offset localPointFromCenter =
        activeLayer.computeLocalCenterOffset(fractionalOffset);
    final Offset layerCenterOffset =
        activeLayer.computeOffsetFromCenterFraction(fractionalOffset);

    List<Offset> uniqueDxOffsets = [];
    List<Offset> uniqueDyOffsets = [];
    final seenDx = <double>{};
    final seenDy = <double>{};

    bool isSimilar(Set<double> seen, double value, double threshold) {
      return seen.any((v) => (v - value).abs() < threshold);
    }

    for (final layer in layerList) {
      if (layer == activeLayer) continue;
      final centerOffset = layer.computeOffsetFromCenterFraction(
        _getFractionalLayerOffset(layer),
      );

      final dx = centerOffset.dx;
      final dy = centerOffset.dy;

      if (!isSimilar(seenDx, dx, snapThreshold)) {
        seenDx.add(dx);
        uniqueDxOffsets.add(centerOffset);
      }

      if (!isSimilar(seenDy, dy, snapThreshold)) {
        seenDy.add(dy);
        uniqueDyOffsets.add(centerOffset);
      }
    }

    for (final layerOffset in uniqueDxOffsets) {
      if (verticalOffset != null) break;

      final dx = (layerOffset.dx - layerCenterOffset.dx).abs();

      // Vertical snapping (dx axis)
      if (dx <= snapThreshold &&
          _verticalSnapHelper.maybeSnap(
            focal: detail.focalPoint.dx,
            focalDelta: detail.focalPointDelta.dx,
            offset: layerOffset,
            threshold: snapThreshold,
            releaseThreshold: releaseThreshold,
            positiveDirection: LayerLastPosition.left,
            negativeDirection: LayerLastPosition.right,
          )) {
        verticalOffset = layerOffset;
      }
    }

    for (final layerOffset in uniqueDyOffsets) {
      if (horizontalOffset != null) break;

      final dy = (layerOffset.dy - layerCenterOffset.dy).abs();

      // Horizontal snapping (dy axis)
      if (dy <= snapThreshold &&
          _horizontalSnapHelper.maybeSnap(
            focal: detail.focalPoint.dy,
            focalDelta: detail.focalPointDelta.dy,
            offset: layerOffset,
            threshold: snapThreshold,
            releaseThreshold: releaseThreshold,
            positiveDirection: LayerLastPosition.top,
            negativeDirection: LayerLastPosition.bottom,
          )) {
        horizontalOffset = layerOffset;
      }
    }

    // Handle vertical snapping
    if (verticalOffset != null) {
      verticalGuideOffset = verticalOffset;
      isVerticalGuideVisible = true;

      activeLayer.offset = Offset(
          verticalOffset.dx - localPointFromCenter.dx, activeLayer.offset.dy);
    }

    // Handle horizontal snapping
    if (horizontalOffset != null) {
      horizontalGuideOffset = horizontalOffset;
      isHorizontalGuideVisible = true;

      activeLayer.offset = Offset(
          activeLayer.offset.dx, horizontalOffset.dy - localPointFromCenter.dy);
    }

    // Notify UI only if something changed
    final hasChanged = isHorizontalGuideVisible != wasHorizontalGuideVisible ||
        isVerticalGuideVisible != wasVerticalGuideVisible;

    if (hasChanged) {
      helperLineCtrl.add(null);

      if ((isHorizontalGuideVisible && !wasHorizontalGuideVisible) ||
          (isVerticalGuideVisible && !wasVerticalGuideVisible)) {
        helperLinesCallbacks?.handleLayerAlignLineHit();
      }
    }
  }
}

class _LayerAlignGuideHelper {
  LayerLastPosition _lastSnapPosition = LayerLastPosition.center;
  Offset _lastSnapOffset = Offset.infinite;
  double? _lastSnapFocal;

  /// Returns true if snapping should occur, otherwise false
  bool maybeSnap({
    required double focal,
    required double focalDelta,
    required Offset offset,
    required double threshold,
    required double releaseThreshold,
    required LayerLastPosition positiveDirection,
    required LayerLastPosition negativeDirection,
  }) {
    final diff = (_lastSnapFocal ?? focal) - focal;

    if (_lastSnapFocal == null || diff.abs() < releaseThreshold) {
      final newPosition =
          focalDelta > 0 ? positiveDirection : negativeDirection;

      if (newPosition != _lastSnapPosition || _lastSnapOffset != offset) {
        _lastSnapFocal ??= focal;
        _lastSnapOffset = offset;
        _lastSnapPosition = LayerLastPosition.center;
        return true;
      }
    } else if (diff.abs() > releaseThreshold) {
      _lastSnapPosition =
          focal > _lastSnapFocal! ? positiveDirection : negativeDirection;
      _lastSnapFocal = null;
    }

    return false;
  }
}
