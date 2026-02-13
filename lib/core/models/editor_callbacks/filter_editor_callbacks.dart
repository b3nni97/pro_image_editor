// Flutter imports:
import 'package:flutter/widgets.dart';

// Project imports:
import '/features/filter_editor/utils/filter_generator/filter_model.dart';
import 'standalone_editor_callbacks.dart';

/// A class representing callbacks for the filter editor.
class FilterEditorCallbacks extends StandaloneEditorCallbacks {
  /// Creates a new instance of [FilterEditorCallbacks].
  const FilterEditorCallbacks({
    this.onFilterFactorChange,
    this.onFilterFactorChangeEnd,
    this.onFilterChanged,
    super.onInit,
    super.onAfterViewInit,
    super.onUpdateUI,
    super.onDone,
    super.onCloseEditor,
    this.onEditorZoomScaleStart,
    this.onEditorZoomScaleUpdate,
    this.onEditorZoomScaleEnd,
    this.onEditorZoomMatrix4Change,
  });

  /// A callback function that is triggered when the filter factor changes.
  ///
  /// The [ValueChanged<double>] parameter provides the new filter factor.
  final ValueChanged<double>? onFilterFactorChange;

  /// A callback function that is triggered when the filter factor change ends.
  ///
  /// The [ValueChanged<double>] parameter provides the final filter factor.
  final ValueChanged<double>? onFilterFactorChangeEnd;

  /// A callback function that is triggered when the filter is changed.
  ///
  /// The [ValueChanged<FilterModel>] parameter provides the new filter model.
  final ValueChanged<FilterModel>? onFilterChanged;

  /// Called when the user ends a pan or scale gesture on the widget.
  ///
  /// At the time this is called, the [TransformationController] will have
  /// already been updated to reflect the change caused by the interaction,
  /// though a pan may cause an inertia animation after this is called as well.
  ///
  /// {@template flutter.widgets.InteractiveViewer.onInteractionEnd}
  /// Will be called even if the interaction is disabled with [panEnabled] or
  /// [scaleEnabled] for both touch gestures and mouse interactions.
  ///
  /// A [GestureDetector] wrapping the InteractiveViewer will not respond to
  /// [GestureDetector.onScaleStart], [GestureDetector.onScaleUpdate], and
  /// [GestureDetector.onScaleEnd]. Use [onEditorZoomScaleStart],
  /// [onEditorZoomScaleUpdate], and [onEditorZoomScaleEnd] to respond to those
  /// gestures.
  /// {@endtemplate}
  ///
  /// See also:
  ///
  ///  * [onEditorZoomScaleStart], which handles the start of the same
  ///    interaction.
  ///  * [onEditorZoomScaleUpdate], which handles an update to the same
  ///    interaction.
  final GestureScaleEndCallback? onEditorZoomScaleEnd;

  /// Called when the user begins a pan or scale gesture on the editor.
  ///
  /// At the time this is called, the [TransformationController] will not have
  /// changed due to this interaction.
  ///
  /// {@macro flutter.widgets.InteractiveViewer.onInteractionEnd}
  ///
  /// The coordinates provided in the details' `focalPoint` and
  /// `localFocalPoint` are normal Flutter event coordinates, not
  /// InteractiveViewer scene coordinates. See
  /// [TransformationController.toScene] for how to convert these coordinates to
  /// scene coordinates relative to the child.
  ///
  /// See also:
  ///
  ///  * [onEditorZoomScaleUpdate], which handles an update to the same
  ///    interaction.
  ///  * [onEditorZoomScaleEnd], which handles the end of the same interaction.
  final GestureScaleStartCallback? onEditorZoomScaleStart;

  /// Called when the user updates a pan or scale gesture on the editor.
  ///
  /// At the time this is called, the [TransformationController] will have
  /// already been updated to reflect the change caused by the interaction, if
  /// the interaction caused the matrix to change.
  ///
  /// {@macro flutter.widgets.InteractiveViewer.onEditorZoomScaleEnd}
  ///
  /// The coordinates provided in the details' `focalPoint` and
  /// `localFocalPoint` are normal Flutter event coordinates, not
  /// InteractiveViewer scene coordinates. See
  /// [TransformationController.toScene] for how to convert these coordinates to
  /// scene coordinates relative to the child.
  ///
  /// See also:
  ///
  ///  * [onEditorZoomScaleStart], which handles the start of the same
  ///    interaction.
  ///  * [onEditorZoomScaleEnd], which handles the end of the same interaction.
  final GestureScaleUpdateCallback? onEditorZoomScaleUpdate;

  /// Called when the editor zoom matrix changes.
  final Function(Matrix4 value)? onEditorZoomMatrix4Change;

  /// Handles the filter factor change event.
  ///
  /// This method calls the [onFilterFactorChange] callback with the provided
  /// [newFactor] and then calls [handleUpdateUI].
  void handleFilterFactorChange(double newFactor) {
    onFilterFactorChange?.call(newFactor);
    handleUpdateUI();
  }

  /// Handles the filter factor change end event.
  ///
  /// This method calls the [onFilterFactorChangeEnd] callback with the
  /// provided [newFactor] and then calls [handleUpdateUI].
  void handleFilterFactorChangeEnd(double newFactor) {
    onFilterFactorChangeEnd?.call(newFactor);
    handleUpdateUI();
  }

  /// Handles the filter changed event.
  ///
  /// This method calls the [onFilterChanged] callback with the provided
  /// [filter] and then calls [handleUpdateUI].
  void handleFilterChanged(FilterModel filter) {
    onFilterChanged?.call(filter);
    handleUpdateUI();
  }

  /// Creates a copy with modified editor callbacks.
  FilterEditorCallbacks copyWith({
    ValueChanged<double>? onFilterFactorChange,
    ValueChanged<double>? onFilterFactorChangeEnd,
    ValueChanged<FilterModel>? onFilterChanged,
    Function()? onInit,
    Function()? onAfterViewInit,
    Function()? onUpdateUI,
    Function()? onDone,
    Function()? onCloseEditor,
    GestureScaleEndCallback? onEditorZoomScaleEnd,
    GestureScaleStartCallback? onEditorZoomScaleStart,
    GestureScaleUpdateCallback? onEditorZoomScaleUpdate,
    Function(Matrix4 value)? onEditorZoomMatrix4Change,
  }) {
    return FilterEditorCallbacks(
      onFilterFactorChange: onFilterFactorChange ?? this.onFilterFactorChange,
      onFilterFactorChangeEnd:
          onFilterFactorChangeEnd ?? this.onFilterFactorChangeEnd,
      onFilterChanged: onFilterChanged ?? this.onFilterChanged,
      onInit: onInit ?? this.onInit,
      onAfterViewInit: onAfterViewInit ?? this.onAfterViewInit,
      onUpdateUI: onUpdateUI ?? this.onUpdateUI,
      onDone: onDone ?? this.onDone,
      onCloseEditor: onCloseEditor ?? this.onCloseEditor,
      onEditorZoomScaleEnd: onEditorZoomScaleEnd ?? this.onEditorZoomScaleEnd,
      onEditorZoomScaleStart:
          onEditorZoomScaleStart ?? this.onEditorZoomScaleStart,
      onEditorZoomScaleUpdate:
          onEditorZoomScaleUpdate ?? this.onEditorZoomScaleUpdate,
      onEditorZoomMatrix4Change:
          onEditorZoomMatrix4Change ?? this.onEditorZoomMatrix4Change,
    );
  }
}
