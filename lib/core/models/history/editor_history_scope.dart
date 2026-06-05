import '/core/models/layers/layer.dart';
import '/features/filter_editor/types/filter_matrix.dart';
import '/features/tune_editor/models/tune_adjustment_matrix.dart';

/// Provides sub-editors with access to the main editor's global history
/// system (undo/redo).
///
/// When a sub-editor receives an [EditorHistoryScope], it uses the global
/// history instead of a local undo/redo stack. Every change (adjustment,
/// layer move, etc.) becomes an individual undo step in the shared history
/// that persists across editor switches.
class EditorHistoryScope {
  /// Creates an [EditorHistoryScope].
  const EditorHistoryScope({
    required this.addHistory,
    required this.undo,
    required this.redo,
    required this.canUndo,
    required this.canRedo,
    required this.getActiveLayers,
    required this.getActiveTuneAdjustments,
    required this.getActiveFilters,
    required this.getActiveBlur,
    required this.copyLayers,
  });

  /// Adds a new entry to the global history.
  ///
  /// Pass only the fields that changed. Unchanged fields are automatically
  /// filled from the current active state by the main editor.
  final void Function({
    List<Layer>? layers,
    FilterMatrix? filters,
    List<TuneAdjustmentMatrix>? tuneAdjustments,
    double? blur,
    bool blockCaptureScreenshot,
  }) addHistory;

  /// Triggers a global undo, reverting the last change.
  final void Function() undo;

  /// Triggers a global redo, re-applying the last undone change.
  final void Function() redo;

  /// Returns whether a global undo is available.
  final bool Function() canUndo;

  /// Returns whether a global redo is available.
  final bool Function() canRedo;

  /// Returns the current active layers from the global state.
  final List<Layer> Function() getActiveLayers;

  /// Returns the current active tune adjustments from the global state.
  final List<TuneAdjustmentMatrix> Function() getActiveTuneAdjustments;

  /// Returns the current active filters from the global state.
  final FilterMatrix Function() getActiveFilters;

  /// Returns the current active blur factor from the global state.
  final double Function() getActiveBlur;

  /// Creates a deep copy of the given layer list.
  final List<Layer> Function(List<Layer>) copyLayers;
}
