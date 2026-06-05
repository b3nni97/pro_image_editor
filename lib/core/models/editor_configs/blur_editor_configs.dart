// ignore_for_file: deprecated_member_use_from_same_package
// TODO: Remove the deprecated values when releasing version 12.0.0.

import '../custom_widgets/blur_editor_widgets.dart';
import '../icons/blur_editor_icons.dart';
import '../styles/blur_editor_style.dart';
import 'utils/base_sub_editor_configs.dart';
import 'utils/editor_safe_area.dart';

export '../custom_widgets/blur_editor_widgets.dart';
export '../icons/blur_editor_icons.dart';
export '../styles/blur_editor_style.dart';

/// Configuration options for a blur editor.
///
/// `BlurEditorConfigs` allows you to define settings for a blur editor,
/// including whether the editor is enabled and a list of blur generators.
///
/// Example usage:
/// ```dart
/// BlurEditorConfigs(
///   enabled: true,
///   maxBlur: 5.0,
/// );
/// ```
class BlurEditorConfigs implements BaseSubEditorConfigs {
  /// Creates an instance of BlurEditorConfigs with optional settings.
  ///
  /// By default, the editor is enabled, and max blur is 5.0.
  const BlurEditorConfigs({
    this.enableGesturePop = true,
    @Deprecated(
      'Use tools inside MainEditorConfigs instead, e.g. tools: '
      '[SubEditorMode.blur]',
    )
    this.enabled = true,
    this.showLayers = true,
    this.enableInteractiveLayers = false,
    this.resizeToAvoidBottomInset = false,
    this.maxBlur = 5.0,
    this.safeArea = const EditorSafeArea(),
    this.style = const BlurEditorStyle(),
    this.icons = const BlurEditorIcons(),
    this.widgets = const BlurEditorWidgets(),
  }) : assert(maxBlur > 0, 'maxBlur must be positive');

  /// {@macro enableGesturePop}
  @override
  final bool enableGesturePop;

  /// Indicates whether the blur editor is enabled.
  @Deprecated(
    'Use tools inside MainEditorConfigs instead, e.g. tools: '
    '[SubEditorMode.blur]',
  )
  final bool enabled;

  /// Show also layers in the editor.
  final bool showLayers;

  /// Whether layers in the editor can be interacted with (moved, scaled,
  /// rotated, and edited).
  ///
  /// When `true`, the user can directly manipulate layers within the blur
  /// editor. When `false` (default), layers are displayed as a static preview.
  final bool enableInteractiveLayers;

  /// Whether the Scaffold should resize to avoid the bottom inset (keyboard).
  ///
  /// When set to `false` (default), the keyboard will overlay the editor
  /// content instead of resizing it.
  final bool resizeToAvoidBottomInset;

  /// Maximum blur value.
  final double maxBlur;

  /// Defines the safe area configuration for the editor.
  final EditorSafeArea safeArea;

  /// Style configuration for the blur editor.
  final BlurEditorStyle style;

  /// Icons used in the blur editor.
  final BlurEditorIcons icons;

  /// Widgets associated with the blur editor.
  final BlurEditorWidgets widgets;

  /// Creates a copy of this `BlurEditorConfigs` object with the given fields
  /// replaced with new values.
  ///
  /// The [copyWith] method allows you to create a new instance of
  /// [BlurEditorConfigs] with some properties updated while keeping the
  /// others unchanged.
  BlurEditorConfigs copyWith({
    bool? enableGesturePop,
    bool? enabled,
    bool? showLayers,
    bool? enableInteractiveLayers,
    bool? resizeToAvoidBottomInset,
    double? maxBlur,
    EditorSafeArea? safeArea,
    BlurEditorStyle? style,
    BlurEditorIcons? icons,
    BlurEditorWidgets? widgets,
  }) {
    return BlurEditorConfigs(
      enableGesturePop: enableGesturePop ?? this.enableGesturePop,
      safeArea: safeArea ?? this.safeArea,
      enabled: enabled ?? this.enabled,
      showLayers: showLayers ?? this.showLayers,
      enableInteractiveLayers:
          enableInteractiveLayers ?? this.enableInteractiveLayers,
      resizeToAvoidBottomInset:
          resizeToAvoidBottomInset ?? this.resizeToAvoidBottomInset,
      maxBlur: maxBlur ?? this.maxBlur,
      style: style ?? this.style,
      icons: icons ?? this.icons,
      widgets: widgets ?? this.widgets,
    );
  }
}
