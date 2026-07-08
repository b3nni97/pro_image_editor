// Flutter imports:
import 'package:flutter/widgets.dart';
import '/core/models/layers/layer.dart';

import '/features/main_editor/services/layer_interaction_manager.dart';
import '/shared/widgets/layer/models/layer_item_interaction.dart';
import '/shared/widgets/reactive_widgets/reactive_custom_widget.dart';

/// {@template removeLayerArea}
/// A function that returns a [Widget] used as a remove area in the
/// editor interface. It provides access to the [removeAreaKey] for
/// positioning or targeting the remove area, the [editor] state for
/// managing editor-related actions, and a [rebuildStream] to handle
/// updates for interactive elements.
///
/// The [removeAreaKey] parameter is a [GlobalKey] that points to the
/// specific area where elements should be removed or targeted. The
/// `layerInteractionManager` parameter exposes the active interaction state —
/// most importantly `hoverRemoveBtn` — of whichever editor currently hosts the
/// layers (main editor *or* a sub-editor). The [rebuildStream] stream enables
/// dynamic rebuilding of the widget.
///
/// The `imageBounds` parameter is the rectangle of the visible (letterboxed)
/// image within the editor body — use it to keep the remove area inside the
/// image rather than in the surrounding background. Its coordinate space is
/// the same one a [Positioned] returned by this builder is laid out in.
///
/// The same builder is reused by the main editor and by the sub-editors that
/// show layers (Filter, Tune, Blur), so it must not depend on a main-editor
/// state — it is intentionally driven by the [LayerInteractionManager].
///
/// **Example Usage:**
/// ```dart
/// removeLayerArea: (removeAreaKey, manager, rebuildStream,
///     isLayerBeingTransformed, imageBounds) {
///   return Positioned(
///     key: removeAreaKey,
///     left: imageBounds.left,
///     top: imageBounds.bottom - 96, // keep it inside the visible image
///     width: imageBounds.width,
///     height: 96,
///     child: StreamBuilder(
///       stream: rebuildStream,
///       builder: (context, snapshot) {
///         final hover = manager.hoverRemoveBtn;
///         return Center(
///           child: AnimatedScale(
///             scale: isLayerBeingTransformed ? 1 : 0,
///             duration: const Duration(milliseconds: 160),
///             child: Container(
///               padding: const EdgeInsets.all(16),
///               decoration: BoxDecoration(
///                 color: hover ? Colors.red : Colors.black54,
///                 shape: BoxShape.circle,
///               ),
///               child: const Icon(Icons.delete, color: Colors.white),
///             ),
///           ),
///         );
///       },
///     ),
///   );
/// },
/// ```
/// {@endtemplate}
typedef RemoveLayerArea = Widget Function(
  GlobalKey removeAreaKey,
  LayerInteractionManager layerInteractionManager,
  Stream<void> rebuildStream,
  bool isLayerBeingTransformed,
  Rect imageBounds,
);

/// A typedef for creating a [ReactiveWidget] that manages crop editor
/// aspect ratio options.
///
/// - [T] - The type representing the editor state.
/// - [editorState] - The current state of the editor.
/// - [rebuildStream] - A [Stream] that triggers the widget to rebuild.
/// - [aspectRatio] - The aspect ratio to be set.
/// - [originalAspectRatio] - The original aspect ratio.
///
/// Returns a [ReactiveWidget] that provides options for crop editor
/// aspect ratios.
typedef CropEditorAspectRatioOptions<T> = ReactiveWidget Function(
  T editorState,
  Stream<void> rebuildStream,
  double aspectRatio,
  double originalAspectRatio,
);

/// A typedef for creating a [ReactiveWidget] that includes a custom
/// color picker.
///
/// - [T] - The type representing the editor state.
///
/// {@template colorPickerWidget}
/// - [editorState] - The current state of the editor.
/// - [rebuildStream] - A [Stream] that triggers the widget to rebuild.
/// - [currentColor] - The currently selected color.
/// - [setColor] - A function to update the selected color.
///
/// Returns an optional [ReactiveWidget] that provides a custom color
/// picker.
///
/// **Example:**
/// ```dart
/// colorPicker: (editor, rebuildStream, currentColor, setColor) =>
///    ReactiveWidget(
///      stream: rebuildStream,
///      builder: (_) => BarColorPicker(
///        configs: editor.configs,
///        length: 200,
///        horizontal: false,
///        initialColor: currentColor,
///        colorListener: (int value) {
///          setColor(Color(value));
///        },
///      ),
/// ),
/// ```
/// {@endtemplate}
typedef CustomColorPicker<T> = ReactiveWidget? Function(
  T editorState,
  Stream<void> rebuildStream,
  Color currentColor,
  void Function(Color color) setColor,
);

/// A typedef for creating a [ReactiveWidget] that includes a custom
/// slider.
///
/// - [T] - The type representing the editor state.
///
/// {@template customSliderWidget}
/// - [editorState] - The current state of the editor.
/// - [rebuildStream] - A [Stream] that triggers the widget to rebuild.
/// - [value] - The current value of the slider.
/// - [onChanged] - A function to handle changes to the slider's value.
/// - [onChangeEnd] - A function to handle the end of slider value changes.
///
/// Returns a [ReactiveWidget] that provides a custom slider.
///
/// **Example:**
/// ```dart
/// slider: (editorState, rebuildStream, value, onChanged, onChangeEnd) {
///   return ReactiveWidget(
///     stream: rebuildStream,
///     builder: (_) => Slider(
///       onChanged: onChanged,
///       onChangeEnd: onChangeEnd,
///       value: value,
///       activeColor: Colors.blue.shade200,
///     ),
///   );
/// },
/// ```
/// {@endtemplate}
typedef CustomSlider<T> = ReactiveWidget Function(
  T editorState,
  Stream<void> rebuildStream,
  double value,
  Function(double value) onChanged,
  Function(double value) onChangeEnd,
);

/// A typedef for a function that creates a [ReactiveWidget] for a tap
/// interaction.
///
/// The function takes the following parameters:
///
/// * [rebuildStream]: A stream that triggers the widget to rebuild.
/// * [onTap]: A callback function that is invoked when the widget is tapped.
/// * [toggleTooltipVisibility]: A function that toggles the visibility of a
/// tooltip based on the boolean value passed.
/// * [rotation]: A double value representing the current rotation of the
/// widget.
///
/// Returns a nullable [ReactiveWidget].
typedef LayerInteractionTapButton = ReactiveWidget? Function(
  Stream<void> rebuildStream,
  Function() onTap,
  double rotation,
);

/// A typedef for a function that creates a [ReactiveWidget] for scale
/// and rotate interactions.
///
/// The function takes the following parameters:
///
/// * [rebuildStream]: A stream that triggers the widget to rebuild.
/// * [onScaleRotateDown]: A callback function that is invoked when the
/// scale/rotate action starts (on pointer down event).
/// * [onScaleRotateUp]: A callback function that is invoked when the
/// scale/rotate action ends (on pointer up event).
/// * [toggleTooltipVisibility]: A function that toggles the visibility of a
/// tooltip based on the boolean value passed.
/// * [rotation]: A double value representing the current rotation of the
/// widget.
///
/// Returns a nullable [ReactiveWidget].
typedef LayerInteractionScaleRotateButton = ReactiveWidget? Function(
  Stream<void> rebuildStream,
  Function(PointerDownEvent) onScaleRotateDown,
  Function(PointerUpEvent) onScaleRotateUp,
  double rotation,
);

/// A typedef for a function that builds a reactive widget for a layer item.
///
/// This function receives a stream of rebuild signals, the layer data,
/// and the interactions available for the layer item.
/// It is responsible for building a reactive widget that responds to
/// changes in the rebuild stream and updates accordingly.
typedef LayerInteractionItem = ReactiveWidget Function(
  Stream<void> rebuildStream,
  Layer layer,
  LayerItemInteractions interactions,
);

/// Signature for building a reactive overlay widget for a given layer.
///
/// [rebuildStream] triggers rebuilds when events are emitted.
/// [info] contains layout details of the overlay child.
/// [layer] is the current layer to render.
/// [interactions] provides callbacks for interacting with the layer.
typedef LayerOverlayBuilder = ReactiveWidget Function(
  Stream<void> rebuildStream,
  OverlayChildLayoutInfo info,
  Layer layer,
  LayerItemInteractions interactions,
);

/// A typedef for a function that builds a widget for the layer border.
///
/// This function receives the layer widget and the layer data as
/// parameters. It is responsible for building a widget that
/// represents the border around the layer.
typedef LayerInteractionBorder = Widget Function(
    Widget layerWidget, Layer layerData);

/// {@template customBodyItem}
/// Add custom widgets at a specific position inside the body, which will not
/// be recorded in the final image. This is useful for interaction buttons or
/// dynamic overlays that should not appear in the exported image.
///
/// **Example:**
/// ```dart
/// bodyItems: (editor, rebuildStream) => [
///   ReactiveWidget(
///     stream: rebuildStream,
///     builder: (_) => Container(
///       width: 100,
///       height: 100,
///       color: Colors.blue,
///     ),
///   ),
/// ],
/// ```
/// {@endtemplate}

/// {@template customBodyItemRecorded}
/// Add custom widgets that will be recorded in the final image generation,
/// making it ideal for frames or other static decorations that should appear
/// in the exported image.
///
/// **Example:**
/// ```dart
/// bodyItemsRecorded: (editor, rebuildStream) => [
///   ReactiveWidget(
///     stream: rebuildStream,
///     builder: (_) => Container(
///       width: 300,
///       height: 300,
///       decoration: BoxDecoration(
///         border: Border.all(color: Colors.black, width: 4),
///       ),
///     ),
///   ),
/// ],
/// ```
/// {@endtemplate}

/// A function that returns a list of [ReactiveWidget]s, allowing
/// customization of body items based on the [editor] state and a
/// [rebuildStream] to trigger updates.
///
/// The [editor] parameter provides access to the current editor state,
/// enabling customization based on the editor's properties. The
/// [rebuildStream] stream allows dynamic updates to the widgets.
///
/// **Example Usage:**
/// ```dart
/// CustomBodyItems<ProImageEditorState> customItems = (editor, rebuildStream)
/// => [
///   ReactiveWidget(
///     stream: rebuildStream,
///     builder: (_) => Container(
///       width: 100,
///       height: 100,
///       color: Colors.red,
///     ),
///   ),
/// ];
/// ```
typedef CustomBodyItems<T> = List<ReactiveWidget> Function(
  T editor,
  Stream<void> rebuildStream,
);

/// A function that builds a [Widget] to display at a corner of the crop rect.
///
/// The widget receives the [editorState] for access to crop rect, aspect ratio,
/// and other editor properties, along with a [rebuildStream] to react to
/// changes.
///
/// **Example Usage:**
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
typedef CropCornerWidgetBuilder<T> = Widget Function(
  T editorState,
  Stream<void> rebuildStream,
);
