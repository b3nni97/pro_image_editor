// ignore_for_file: deprecated_member_use_from_same_package
// TODO: Remove the deprecated values when releasing version 12.0.0.

import '/features/tune_editor/models/tune_adjustment_item.dart';
import '../custom_widgets/tune_editor_widgets.dart';
import '../icons/tune_editor_icons.dart';
import '../styles/tune_editor_style.dart';
import 'utils/base_sub_editor_configs.dart';
import 'utils/editor_safe_area.dart';
import 'utils/zoom_configs.dart';

export '../custom_widgets/tune_editor_widgets.dart';
export '../icons/tune_editor_icons.dart';
export '../styles/tune_editor_style.dart';

/// A configuration class for the Tune Editor.
///
/// This class defines various configurations such as enabling the editor,
/// showing layers, providing tune adjustment options, and defining the
/// editor's safe area.
class TuneEditorConfigs extends ZoomConfigs implements BaseSubEditorConfigs {
  /// Creates a [TuneEditorConfigs] instance with the specified parameters.
  ///
  /// - [enabled] determines whether the tune editor is enabled or not.
  /// - [showLayers] specifies if the layers are visible in the editor.
  /// - [tuneAdjustmentOptions] provides a list of available tune adjustment
  ///   options that the user can configure.
  /// - [safeArea] defines the safe area configuration for the editor interface.
  const TuneEditorConfigs({
    this.enableGesturePop = true,
    @Deprecated(
      'Use tools inside MainEditorConfigs instead, e.g. tools: '
      '[SubEditorMode.tune]',
    )
    super.enableZoom,
    super.enableDoubleTapZoom,
    super.doubleTapZoomFactor,
    super.doubleTapZoomDuration,
    super.doubleTapZoomCurve,
    super.viewportFitBuilder,
    this.enabled = true,
    this.showLayers = true,
    this.enableInteractiveLayers = false,
    this.resizeToAvoidBottomInset = false,
    this.tuneAdjustmentOptions,
    this.safeArea = const EditorSafeArea(),
    this.style = const TuneEditorStyle(),
    this.icons = const TuneEditorIcons(),
    this.widgets = const TuneEditorWidgets(),
  });

  /// {@macro enableGesturePop}
  @override
  final bool enableGesturePop;

  /// Indicates whether the tune editor is enabled.
  ///
  /// When this is `false`, the tune editor features will be disabled.
  @Deprecated(
    'Use tools inside MainEditorConfigs instead, e.g. tools: '
    '[SubEditorMode.tune]',
  )
  final bool enabled;

  /// Specifies whether the layers should be visible in the editor.
  ///
  /// If `true`, layers are displayed within the tune editor interface.
  final bool showLayers;

  /// Whether layers in the editor can be interacted with (moved, scaled,
  /// rotated, and edited).
  ///
  /// When `true`, the user can directly manipulate layers within the tune
  /// editor. When `false` (default), layers are displayed as a static preview.
  final bool enableInteractiveLayers;

  /// Whether the Scaffold should resize to avoid the bottom inset (keyboard).
  ///
  /// When set to `false` (default), the keyboard will overlay the editor
  /// content instead of resizing it.
  final bool resizeToAvoidBottomInset;

  /// Defines the safe area configuration for the editor.
  ///
  /// This determines padding or spacing around the editor UI elements.
  final EditorSafeArea safeArea;

  /// A list of tune adjustment options available in the tune editor.
  ///
  /// These options allow users to modify aspects like brightness, contrast,
  /// or other tune adjustments.
  final List<TuneAdjustmentItem>? tuneAdjustmentOptions;

  /// Style configuration for the tune editor.
  final TuneEditorStyle style;

  /// Icons used in the tune editor.
  final TuneEditorIcons icons;

  /// Widgets associated with the tune editor.
  final TuneEditorWidgets widgets;

  /// Creates a copy of this [TuneEditorConfigs] object with the given fields
  /// replaced with new values.
  ///
  /// The [copyWith] method allows you to create a new instance of
  /// [TuneEditorConfigs] with some properties updated while keeping the
  /// others unchanged.
  ///
  /// - [enabled] updates whether the tune editor is enabled.
  /// - [showLayers] updates the visibility of layers in the editor.
  /// - [safeArea] updates the safe area configuration.
  /// - [tuneAdjustmentOptions] updates the available tune adjustment options.
  TuneEditorConfigs copyWith({
    bool? enableGesturePop,
    bool? enabled,
    bool? showLayers,
    bool? enableInteractiveLayers,
    bool? resizeToAvoidBottomInset,
    EditorSafeArea? safeArea,
    List<TuneAdjustmentItem>? tuneAdjustmentOptions,
    TuneEditorStyle? style,
    TuneEditorIcons? icons,
    TuneEditorWidgets? widgets,
  }) {
    return TuneEditorConfigs(
      enableGesturePop: enableGesturePop ?? this.enableGesturePop,
      enabled: enabled ?? this.enabled,
      safeArea: safeArea ?? this.safeArea,
      showLayers: showLayers ?? this.showLayers,
      enableInteractiveLayers:
          enableInteractiveLayers ?? this.enableInteractiveLayers,
      resizeToAvoidBottomInset:
          resizeToAvoidBottomInset ?? this.resizeToAvoidBottomInset,
      tuneAdjustmentOptions:
          tuneAdjustmentOptions ?? this.tuneAdjustmentOptions,
      style: style ?? this.style,
      icons: icons ?? this.icons,
      widgets: widgets ?? this.widgets,
    );
  }
}
