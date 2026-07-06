// Flutter imports:
import 'package:flutter/material.dart';

import '/core/models/history/editor_history_scope.dart';
import '/features/filter_editor/types/filter_matrix.dart';
import '/features/tune_editor/models/tune_adjustment_matrix.dart';
import '../editor_callbacks/pro_image_editor_callbacks.dart';
import '../editor_configs/pro_image_editor_configs.dart';
import '../layers/layer.dart';

/// Configuration class for initializing the image editor.
///
/// This class holds various configurations needed to initialize the image
/// editor.
abstract class EditorInitConfigs {
  /// Creates a new instance of [EditorInitConfigs].
  ///
  /// The [theme] parameter specifies the theme data for the editor.
  /// The [configs] parameter specifies the configuration options for the image
  /// editor.
  /// The [callbacks] parameter specifies the callback options for the image
  /// editor.
  /// The [mainImageSize] parameter specifies the size of the image with layers
  /// applied.
  /// The [mainBodySize] parameter specifies the size of the body with layers
  /// applied.
  /// The [appliedFilters] parameter specifies the list of applied filters.
  /// The [appliedBlurFactor] parameter specifies the applied blur factor.
  /// The [transformConfigs] parameter specifies the transformation
  /// configurations for the editor.
  /// The [layers] parameter specifies the layers in the editor.
  const EditorInitConfigs({
    required this.theme,
    this.configs = const ProImageEditorConfigs(),
    this.callbacks = const ProImageEditorCallbacks(),
    this.mainImageSize,
    this.mainBodySize,
    this.transformConfigs,
    this.appliedFilters = const [],
    this.appliedTuneAdjustments = const [],
    this.appliedBlurFactor = 0,
    this.layers,
    this.convertToUint8List = false,
    this.enableCloseButton = true,
    this.historyScope,
    this.onLayerTransformChanged,
    this.onTextLayerTap,
  });

  /// Determines whether the close button is displayed on the widget.
  final bool enableCloseButton;

  /// The configuration options for the image editor.
  final ProImageEditorConfigs configs;

  /// The callbacks for the image editor.
  final ProImageEditorCallbacks callbacks;

  /// The size of the image in the main editor.
  final Size? mainImageSize;

  /// The size of the body with layers applied.
  final Size? mainBodySize;

  /// The list of applied filters.
  final FilterMatrix appliedFilters;

  /// The list of applied tune adjustments.
  final List<TuneAdjustmentMatrix> appliedTuneAdjustments;

  /// The applied blur factor.
  final double appliedBlurFactor;

  /// The transformation configurations for the editor.
  final TransformConfigs? transformConfigs;

  /// The theme data for the editor.
  final ThemeData theme;

  /// The layers in the editor.
  final List<Layer>? layers;

  /// Determines whether to return the image as a Uint8List when closing the
  /// editor.
  final bool convertToUint8List;

  /// Optional scope providing access to the main editor's global history.
  ///
  /// When provided, the sub-editor writes every change directly to the
  /// global undo/redo history instead of maintaining a local undo stack.
  /// This enables unified undo/redo across all editors.
  final EditorHistoryScope? historyScope;

  /// Callback triggered whenever layers are transformed (moved, scaled,
  /// or rotated) in the interactive layer stack.
  ///
  /// The main editor hooks into this to sync the sub-editor's layer
  /// positions back to [activeLayers], keeping the backgroundOverride's
  /// Hero rects up-to-date.
  final void Function(List<Layer> layers)? onLayerTransformChanged;

  /// Callback triggered when a text layer is tapped for editing within a
  /// sub-editor's interactive layer stack. The main editor typically passes
  /// its text-editor opening method here.
  final void Function(TextLayer layer)? onTextLayerTap;
}
