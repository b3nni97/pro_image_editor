// Project imports:
import '/features/crop_rotate_editor/crop_rotate_editor.dart';
import '/shared/widgets/reactive_widgets/reactive_custom_appbar.dart';
import '/shared/widgets/reactive_widgets/reactive_custom_widget.dart';
import 'utils/custom_widgets_standalone_editor.dart';
import 'utils/custom_widgets_typedef.dart';

/// A custom widget for editing crop and rotate effects in an image editor.
///
/// This widget extends the standalone editor for the crop and rotate editor
/// state, providing a customizable interface for applying and adjusting crop
/// and rotate transformations.
class CropRotateEditorWidgets
    extends CustomWidgetsStandaloneEditor<CropRotateEditorState> {
  /// Creates a [CropRotateEditorWidgets] widget.
  ///
  /// This widget allows customization of the app bar, bottom bar, body items,
  /// and additional widgets specific to crop and rotate functionality,
  /// enabling a flexible design tailored to specific needs.
  ///
  /// Example:
  /// ```
  /// CropRotateEditorWidgets(
  ///   appBar: myAppBar,
  ///   bottomBar: myBottomBar,
  ///   bodyItems: myBodyItems,
  /// )
  /// ```
  const CropRotateEditorWidgets({
    super.appBar,
    super.bottomBar,
    super.bodyItems,
    super.wrapBody,
    this.aspectRatioOptions,
    this.slider,
    this.cropCornerWidget,
  });

  /// A widget for selecting aspect ratio options in the crop editor.
  ///
  /// This widget allows users to select different aspect ratio options for the
  /// crop editor.
  ///
  /// - [editorState] - The current state of the editor.
  /// - [rebuildStream] - A [Stream] that triggers the widget to rebuild.
  /// - [aspectRatio] - The aspect ratio to be set.
  /// - [originalAspectRatio] - The original aspect ratio.
  ///
  /// Returns a [ReactiveWidget] that provides options for crop editor
  /// aspect ratios.
  final CropEditorAspectRatioOptions<CropRotateEditorState>? aspectRatioOptions;

  /// A custom slider widget for the straighten tool in the crop editor.
  ///
  /// This widget allows users to adjust the straighten angle using a slider.
  ///
  /// {@macro customSliderWidget}
  final CustomSlider<CropRotateEditorState>? slider;

  /// A widget builder for displaying a custom widget at the top-right corner
  /// of the crop rect area.
  ///
  /// This is useful for showing contextual indicators like a lock icon when
  /// the aspect ratio is fixed, similar to the iOS Photos crop editor.
  ///
  /// The builder receives the editor state and a rebuild stream, so the widget
  /// can react to state changes (e.g., aspect ratio changes).
  ///
  /// **Example:**
  /// ```dart
  /// cropCornerWidget: (editorState, rebuildStream) {
  ///   return StreamBuilder(
  ///     stream: rebuildStream,
  ///     builder: (context, _) {
  ///       final bool isLocked = editorState.aspectRatio > 0;
  ///       return Icon(
  ///         isLocked ? Icons.lock : Icons.lock_open,
  ///         color: Colors.white,
  ///         size: 20,
  ///       );
  ///     },
  ///   );
  /// },
  /// ```
  final CropCornerWidgetBuilder<CropRotateEditorState>? cropCornerWidget;

  @override
  CropRotateEditorWidgets copyWith({
    ReactiveAppbar? Function(
            CropRotateEditorState editorState, Stream<void> rebuildStream)?
        appBar,
    ReactiveWidget? Function(
            CropRotateEditorState editorState, Stream<void> rebuildStream)?
        bottomBar,
    CustomBodyItems<CropRotateEditorState>? bodyItems,
    CropEditorAspectRatioOptions<CropRotateEditorState>? aspectRatioOptions,
    CustomSlider<CropRotateEditorState>? slider,
    CropCornerWidgetBuilder<CropRotateEditorState>? cropCornerWidget,
  }) {
    return CropRotateEditorWidgets(
      appBar: appBar ?? this.appBar,
      bottomBar: bottomBar ?? this.bottomBar,
      bodyItems: bodyItems ?? this.bodyItems,
      aspectRatioOptions: aspectRatioOptions ?? this.aspectRatioOptions,
      slider: slider ?? this.slider,
      cropCornerWidget: cropCornerWidget ?? this.cropCornerWidget,
    );
  }
}
