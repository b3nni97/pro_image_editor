// Project imports:
import 'package:flutter/widgets.dart';

import '/core/models/layers/layer.dart';
import 'editor_init_configs.dart';

/// Configuration class for initializing the tune editor.
///
/// This class extends [EditorInitConfigs] and adds a parameter to determine
/// whether to return the image as a Uint8List when closing the editor.
class TuneEditorInitConfigs extends EditorInitConfigs {
  /// Creates a new instance of [TuneEditorInitConfigs].
  ///
  /// The [theme] parameter specifies the theme data for the editor.
  /// The [convertToUint8List] parameter determines whether to return the image
  /// as a Uint8List when closing the editor.
  /// The other parameters are inherited from [EditorInitConfigs].
  const TuneEditorInitConfigs({
    super.transformConfigs,
    super.configs,
    super.callbacks,
    super.mainImageSize,
    super.mainBodySize,
    super.layers,
    super.appliedFilters,
    super.appliedTuneAdjustments,
    super.appliedBlurFactor,
    super.convertToUint8List,
    super.historyScope,
    this.backgroundImageOverride,
    this.onTextLayerTap,
    required super.theme,
  });

  /// An optional widget that overrides the default background image.
  ///
  /// Used when the main editor directly embeds this sub-editor,
  /// allowing the main editor to control the hero and crop animations.
  /// When null, the sub-editor uses its own background rendering.
  final Widget? backgroundImageOverride;

  /// Callback triggered when a text layer is tapped for editing within
  /// the interactive layer stack. The main editor typically passes its
  /// [openTextEditor] method here.
  final void Function(TextLayer layer)? onTextLayerTap;
}
