import 'package:flutter/material.dart';

import '/core/models/editor_configs/pro_image_editor_configs.dart';
import '/core/models/layers/layer.dart';
import '/core/services/keyboard_service.dart';
import '/core/services/mouse_service.dart';
import '/features/main_editor/services/layer_interaction_manager.dart';
import 'base_layer_interaction_service.dart';

/// A unified layer interaction service that handles selection, editing,
/// grouping, multi-selection, and gesture-handling for layers.
///
/// Used by both the main editor and sub-editors. The full feature set
/// (multi-selection, grouping, keyboard shortcuts, history) is available
/// everywhere. Context-specific behavior (e.g. how layers are removed,
/// how history is tracked) is injected via optional callbacks.
class LayerInteractionService implements BaseLayerInteractionService {
  /// Creates a [LayerInteractionService].
  LayerInteractionService({
    required this.configs,
    required this.layerInteraction,
    required this.onUpdateState,
    MouseService? mouseService,
    this.onTextLayerTap,
    this.onPaintLayerEdit,
    this.onLayerRemoved,
    this.onCheckInteractiveViewer,
    this.getActiveLayers,
    this.getIsLayerBeingTransformed,
    this.getEnableMultiSelectMode,
    this.onAddHistory,
    this.onLayerTapDownCallback,
    this.onLayerTapUpCallback,
    this.onEditSticker,
    this.onUIUpdate,
    this.getIsMounted,
  }) : _mouseService = mouseService;

  // ──────────────────── Required dependencies ────────────────────

  /// Configuration settings for the editor.
  final ProImageEditorConfigs configs;

  /// Handles interactions such as selecting and editing layers.
  final LayerInteractionManager layerInteraction;

  /// Triggers a UI state update (e.g. `setState`).
  final VoidCallback onUpdateState;

  // ──────────────────── Optional callbacks ────────────────────

  /// Called when a text layer is tapped for editing.
  final void Function(TextLayer layer)? onTextLayerTap;

  /// Called when a paint layer is tapped for editing.
  final void Function(PaintLayer layer)? onPaintLayerEdit;

  /// Called when a layer should be removed.
  final void Function(Layer layer)? onLayerRemoved;

  /// Called to enable/disable the InteractiveViewer.
  final VoidCallback? onCheckInteractiveViewer;

  /// Returns the currently active layers (needed for grouping).
  final List<Layer> Function()? getActiveLayers;

  /// Returns whether a layer is currently being transformed.
  final bool Function()? getIsLayerBeingTransformed;

  /// Returns whether multi-select mode is enabled externally.
  final bool Function()? getEnableMultiSelectMode;

  /// Called to add a history entry (for undo/redo).
  final void Function(List<Layer> layers)? onAddHistory;

  /// Called when a layer receives a tap-down event.
  final void Function(Layer layer)? onLayerTapDownCallback;

  /// Called when a layer receives a tap-up event.
  final void Function(Layer layer)? onLayerTapUpCallback;

  /// Called when a sticker/widget layer is tapped for editing.
  final void Function(Layer layer)? onEditSticker;

  /// Called for additional UI updates (e.g. stream notifications).
  final VoidCallback? onUIUpdate;

  /// Returns whether the widget is still mounted.
  final bool Function()? getIsMounted;

  // ──────────────────── Internal state ────────────────────

  final _keyboard = KeyboardService();
  MouseService? _mouseService;

  /// The mouse service for pointer event handling.
  @protected
  MouseService get mouseService => _mouseService!;

  /// Initializes the mouse service. Must be called after construction
  /// if no [MouseService] was passed to the constructor.
  void init() {
    _mouseService ??= MouseService(
      configs: configs,
      interactionManager: layerInteraction,
    );
  }

  /// Returns whether the widget is still mounted.
  bool get mounted => getIsMounted?.call() ?? true;

  @protected
  LayerInteractionConfigs get layerInteractionConfigs =>
      configs.layerInteraction;

  List<Layer> get _activeLayers => getActiveLayers?.call() ?? const [];

  bool _helperIsPointerDownSelected = false;
  bool _isScaleInteractionActive = false;
  bool _helperEnforceMultiSelect = false;
  bool _helperMouseDownMultiSelect = false;
  Set<String> _temporarySelectedIds = {};

  /// Whether multi-selection mode is active (keyboard, external toggle,
  /// or mouse action).
  bool get _enableMultiSelect =>
      (getEnableMultiSelectMode?.call() ?? false) ||
      mouseService.validateMultiSelectAction() ||
      ((_keyboard.isCtrlPressed || _keyboard.isShiftPressed) &&
          layerInteractionConfigs.enableKeyboardMultiSelection);

  // ──────────────────── Interface implementation ────────────────────

  @override
  void handleEditTap(Layer layer) {
    if (layer.isTextLayer) {
      onTextLayerTap?.call(layer as TextLayer);
    } else if (layer.isPaintLayer) {
      onPaintLayerEdit?.call(layer as PaintLayer);
    } else if (layer.isWidgetLayer) {
      onEditSticker?.call(layer);
    }
  }

  @override
  void handleLayerTap(Layer layer, PointerEvent event) {
    final bool layersAreSelectable =
        layerInteraction.layersAreSelectable(configs);

    if (mouseService.validatePanAction(event: event) && layersAreSelectable) {
      return;
    }

    if (layer.interaction.enableSelection && layersAreSelectable) {
      final selectedIds = layerInteraction.selectedLayerIds;
      final isAlreadySelected =
          selectedIds.contains(layer.id) && !_helperIsPointerDownSelected;

      if (!_enableMultiSelect && !_helperMouseDownMultiSelect) {
        layerInteraction.clearSelectedLayers();
        _deselectGroup(layer);
        if (!isAlreadySelected) {
          layerInteraction.addSelectedLayer(layer.id);
          _selectGroup(layer);
        }
      } else {
        if (isAlreadySelected) {
          layerInteraction.removeSelectedLayer(layer.id);
          _deselectGroup(layer);
        } else {
          layerInteraction.addSelectedLayer(layer.id);
          _selectGroup(layer);
        }
      }

      onCheckInteractiveViewer?.call();
    } else if (layer.interaction.enableEdit) {
      if (layer.isTextLayer && configs.textEditor.enableEdit) {
        onTextLayerTap?.call(layer as TextLayer);
      } else if (layer.isPaintLayer && configs.paintEditor.enableEdit) {
        onPaintLayerEdit?.call(layer as PaintLayer);
      }
    }

    _helperMouseDownMultiSelect = false;
  }

  @override
  void handleTapUp(Layer layer, {bool isTap = false}) {
    if (_helperEnforceMultiSelect) {
      _helperEnforceMultiSelect = false;
      return;
    }

    // Note: deselection on mobile is handled by _onAllPointersUp in
    // InteractiveLayerStack (pointer-count tracking). We must NOT deselect
    // here because handleTapUp fires for each individual finger-up —
    // including mid-pinch transitions (2→1 fingers) — which would
    // prematurely break active scale gestures.
    if (_isScaleInteractionActive) return;
    if (layerInteraction.hoverRemoveBtn) {
      onLayerRemoved?.call(layer);
    }

    onUIUpdate?.call();
    _validateClearLayer();
    onCheckInteractiveViewer?.call();
    onLayerTapUpCallback?.call(layer);

    onUpdateState();
  }

  @override
  void handleTapDown(Layer layer, PointerDownEvent event) {

    if (_isScaleInteractionActive ||
        (getIsLayerBeingTransformed?.call() ?? false) ||
        (mouseService.validatePanAction(event: event) && isDesktop)) {

      return;
    }

    mouseService.onPointerDown(event);
    layerInteraction.activeInteractionLayer = layer;

    final selectedIds = layerInteraction.selectedLayerIds;
    _temporarySelectedIds = {...selectedIds};
    _helperIsPointerDownSelected = false;
    _helperMouseDownMultiSelect =
        mouseService.validateMultiSelectAction(event: event);

    if (layer.interaction.enableSelection) {
      bool isAlreadySelected = selectedIds.contains(layer.id);


      if (!isAlreadySelected && (selectedIds.isEmpty || _enableMultiSelect)) {
        _helperIsPointerDownSelected = true;
        layerInteraction.addSelectedLayer(layer.id);

      } else if (!isAlreadySelected && !_enableMultiSelect) {
        _helperIsPointerDownSelected = true;
        layerInteraction
          ..clearSelectedLayers()
          ..addSelectedLayer(layer.id);

      }
      _selectGroup(layer);
    }

    onCheckInteractiveViewer?.call();
    onLayerTapDownCallback?.call(layer);
  }

  @override
  void handleScaleRotateDown(Size layerOriginalSize, Layer layer) {
    _isScaleInteractionActive = true;
    layerInteraction
      ..activeInteractionLayer = layer
      ..rotateScaleLayerSizeHelper = layerOriginalSize
      ..rotateScaleLayerScaleHelper = layer.scale;
    onCheckInteractiveViewer?.call();
  }

  @override
  void handleScaleRotateUp() {
    _isScaleInteractionActive = false;
    layerInteraction
      ..rotateScaleLayerSizeHelper = null
      ..rotateScaleLayerScaleHelper = null;
    _validateClearLayer();
    onCheckInteractiveViewer?.call();
    onUpdateState();
  }

  @override
  void handleRemoveLayer(Layer layer) {
    onLayerRemoved?.call(layer);
  }

  @override
  void handleGroupLayers() {
    if (getActiveLayers == null) return;
    final groupId = layerInteraction.groupSelectedLayers(
      _activeLayers,
      (updatedLayers) {
        onAddHistory?.call(updatedLayers);
      },
    );

    if (groupId != null) {
      onUpdateState();
    }
  }

  @override
  void handleUngroupLayers(Layer layer) {
    if (getActiveLayers == null) return;
    final wasUngrouped = layerInteraction.ungroupLayer(
      layer,
      _activeLayers,
      (updatedLayers) {
        onAddHistory?.call(updatedLayers);
      },
    );

    if (wasUngrouped) {
      onUpdateState();
    }
  }

  @override
  void handleLongPress(
    Layer layer, {
    bool areLayersSelectable = false,
    bool isSelected = false,
  }) {
    if (!areLayersSelectable ||
        !layerInteractionConfigs.enableLongPressMultiSelection ||
        mouseService.validatePanAction()) {
      return;
    }

    _helperEnforceMultiSelect = true;
    final newIds = {..._temporarySelectedIds, layer.id};
    if (isSelected) newIds.remove(layer.id);
    layerInteraction.setSelectedLayers(newIds);
    onUpdateState();
  }

  // ──────────────────── Private helpers ────────────────────

  void _validateClearLayer() {
    if (!layerInteractionConfigs.keepSelectionOnInteraction) {
      layerInteraction.clearSelectedLayers();
    }
  }

  void _selectGroup(Layer layer) {
    if (layer.groupId == null) return;
    Set<String> groupIds = _activeLayers
        .where(
            (l) => l.groupId == layer.groupId && l.interaction.enableSelection)
        .map((l) => l.id)
        .toSet();

    if (_enableMultiSelect) {
      layerInteraction.addMultipleSelectedLayers(groupIds);
    } else {
      layerInteraction.setSelectedLayers(groupIds);
    }
  }

  void _deselectGroup(Layer layer) {
    if (layer.groupId == null) return;
    Set<String> groupIds = _activeLayers
        .where((l) => l.groupId == layer.groupId)
        .map((l) => l.id)
        .toSet();

    if (_enableMultiSelect) {
      layerInteraction.removeMultipleSelectedLayers(groupIds);
    } else {
      layerInteraction.clearSelectedLayers();
    }
  }
}
