// Project imports:
import 'package:flutter/widgets.dart';

import 'editor_init_configs.dart';

/// Configuration class for initializing the blur editor.
///
/// This class extends [EditorInitConfigs] and adds parameters for the image
/// size and whether to return the image as a Uint8List when closing the editor.
class BlurEditorInitConfigs extends EditorInitConfigs {
  /// Creates a new instance of [BlurEditorInitConfigs].
  ///
  /// The [theme] parameter specifies the theme data for the editor.
  /// The [imageSize] parameter specifies the size of the image.
  /// The [convertToUint8List] parameter determines whether to return the image
  /// as a Uint8List when closing the editor.
  /// The other parameters are inherited from [EditorInitConfigs].
  const BlurEditorInitConfigs({
    super.configs,
    super.transformConfigs,
    super.layers,
    super.callbacks,
    super.mainImageSize,
    super.mainBodySize,
    super.appliedFilters,
    super.appliedTuneAdjustments,
    super.appliedBlurFactor,
    super.convertToUint8List,
    super.historyScope,
    super.onLayerTransformChanged,
    this.backgroundImageOverride,
    required super.theme,
  });

  /// An optional widget that overrides the default background image.
  ///
  /// Used when the main editor directly embeds this sub-editor,
  /// allowing the main editor to control the hero and crop animations.
  /// When null, the sub-editor uses its own background rendering.
  final Widget? backgroundImageOverride;
}
