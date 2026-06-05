import 'package:flutter/material.dart';

import '/core/models/layers/layer.dart';

/// An abstract base interface for layer interaction services.
///
/// [LayerInteractionService] implements this interface. [LayerWidget]
/// implement this interface so that [LayerWidget] can work with either one.
abstract class BaseLayerInteractionService {
  /// Handles edit interaction for different layer types.
  void handleEditTap(Layer layer);

  /// Handles tap events on a layer to manage selection or editing.
  void handleLayerTap(Layer layer, PointerEvent event);

  /// Handles the tap-up event on a layer and updates the UI.
  ///
  /// [isTap] indicates whether the pointer-up was a genuine tap (minimal
  /// finger movement) vs. the end of a drag/pinch gesture.
  void handleTapUp(Layer layer, {bool isTap = false});

  /// Handles the tap-down event on a layer to begin selection or interaction.
  void handleTapDown(Layer layer, PointerDownEvent event);

  /// Called when scale or rotate interaction starts.
  void handleScaleRotateDown(Size layerOriginalSize, Layer layer);

  /// Called when scale or rotate interaction ends.
  void handleScaleRotateUp();

  /// Removes the given layer from the canvas and updates the UI.
  void handleRemoveLayer(Layer layer);

  /// Handles grouping of currently selected layers.
  void handleGroupLayers();

  /// Handles ungrouping of the specified layer.
  void handleUngroupLayers(Layer layer);

  /// Handles long-press gesture to trigger multi-layer selection.
  void handleLongPress(
    Layer layer, {
    bool areLayersSelectable = false,
    bool isSelected = false,
  });
}
