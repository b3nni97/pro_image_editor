// Project imports:
import 'package:flutter/widgets.dart';

import '/features/tune_editor/models/tune_adjustment_matrix.dart';
import 'standalone_editor_callbacks.dart';

/// A class representing callbacks for the tune editor.
class TuneEditorCallbacks extends StandaloneEditorCallbacks {
  /// Creates a new instance of [TuneEditorCallbacks].
  const TuneEditorCallbacks({
    this.onTuneFactorChange,
    this.onTuneFactorChangeEnd,
    this.onTuneChanged,
    super.onInit,
    super.onAfterViewInit,
    super.onUpdateUI,
    super.onDone,
    super.onRedo,
    super.onUndo,
    super.onCloseEditor,
    this.onEditorZoomScaleStart,
    this.onEditorZoomScaleUpdate,
    this.onEditorZoomScaleEnd,
    this.onEditorZoomMatrix4Change,
  });

  /// A callback function that is triggered when the tune factor changes.
  ///
  /// The [ValueChanged<double>] parameter provides the new tune factor.
  final ValueChanged<List<TuneAdjustmentMatrix>>? onTuneFactorChange;

  /// A callback function that is triggered when the tune factor change ends.
  ///
  /// The [ValueChanged<double>] parameter provides the final tune factor.
  final ValueChanged<List<TuneAdjustmentMatrix>>? onTuneFactorChangeEnd;

  /// A callback function that is triggered when the tune type is changed.
  ///
  /// The [ValueChanged<TuneAdjustmentType>] parameter provides the new tune
  /// type.
  final ValueChanged<String>? onTuneChanged;

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

  /// Handles the tune factor change event.
  ///
  /// This method calls the [onTuneFactorChange] callback with the provided
  /// [matrix] and then calls [handleUpdateUI].
  void handleTuneFactorChange(List<TuneAdjustmentMatrix> matrix) {
    onTuneFactorChange?.call(matrix);
    handleUpdateUI();
  }

  /// Handles the tune factor change end event.
  ///
  /// This method calls the [onTuneFactorChangeEnd] callback with the
  /// provided [matrix] and then calls [handleUpdateUI].
  void handleTuneFactorChangeEnd(List<TuneAdjustmentMatrix> matrix) {
    onTuneFactorChangeEnd?.call(matrix);
    handleUpdateUI();
  }

  /// Handles the tune changed event.
  ///
  /// This method calls the [onTuneChanged] callback with the provided
  /// [id] and then calls [handleUpdateUI].
  void handleTuneChanged(String id) {
    onTuneChanged?.call(id);
    handleUpdateUI();
  }

  /// Creates a copy with modified editor callbacks.
  TuneEditorCallbacks copyWith({
    ValueChanged<List<TuneAdjustmentMatrix>>? onTuneFactorChange,
    ValueChanged<List<TuneAdjustmentMatrix>>? onTuneFactorChangeEnd,
    ValueChanged<String>? onTuneChanged,
    Function()? onInit,
    Function()? onAfterViewInit,
    Function()? onUpdateUI,
    Function()? onDone,
    Function()? onRedo,
    Function()? onUndo,
    Function()? onCloseEditor,
    GestureScaleEndCallback? onEditorZoomScaleEnd,
    GestureScaleStartCallback? onEditorZoomScaleStart,
    GestureScaleUpdateCallback? onEditorZoomScaleUpdate,
    Function(Matrix4 value)? onEditorZoomMatrix4Change,
  }) {
    return TuneEditorCallbacks(
      onTuneFactorChange: onTuneFactorChange ?? this.onTuneFactorChange,
      onTuneFactorChangeEnd:
          onTuneFactorChangeEnd ?? this.onTuneFactorChangeEnd,
      onTuneChanged: onTuneChanged ?? this.onTuneChanged,
      onInit: onInit ?? this.onInit,
      onAfterViewInit: onAfterViewInit ?? this.onAfterViewInit,
      onUpdateUI: onUpdateUI ?? this.onUpdateUI,
      onDone: onDone ?? this.onDone,
      onRedo: onRedo ?? this.onRedo,
      onUndo: onUndo ?? this.onUndo,
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
