/// Describes the kind of user action that created a history entry.
///
/// Attached to history entries when they are committed, so undo/redo can
/// report *what* is being reverted (e.g. to show a "UNDO CHANGE FILTER"
/// overlay).
enum HistoryActionType {
  /// A layer was added (see [HistoryAction.detail] for the layer kind,
  /// e.g. `text`, `emoji`, `paint`, `sticker`).
  addLayer,

  /// A layer was removed.
  removeLayer,

  /// A layer was moved, scaled or rotated.
  transformLayer,

  /// A layer changed its position in the stacking order.
  reorderLayer,

  /// A layer's content was edited (e.g. text changed).
  updateLayer,

  /// A tune adjustment changed (see [HistoryAction.detail] for the
  /// adjustment id, e.g. `brightness`, `exposure`, `highlights`).
  tune,

  /// A different filter was selected.
  filter,

  /// The opacity of the selected filter changed.
  filterOpacity,

  /// The blur factor changed.
  blur,

  /// A crop/rotate change was applied (see [HistoryAction.detail] for the
  /// specific operation when known, e.g. `rotate`, `straighten`,
  /// `perspectiveX`, `perspectiveY`, `flip`, `crop`, `zoom`).
  cropRotate,

  /// Paint content changed (local paint-editor history).
  paint,

  /// The background image was replaced.
  backgroundImage,
}

/// The kind of user action that created a history entry, with an optional
/// [detail] qualifier (tune adjustment id, layer kind, crop operation, ...).
class HistoryAction {
  /// Creates a [HistoryAction].
  const HistoryAction(this.type, {this.detail});

  /// The action category.
  final HistoryActionType type;

  /// Optional qualifier, e.g. the tune adjustment id (`brightness`),
  /// the layer kind (`text`), or the crop operation (`straighten`).
  final String? detail;

  @override
  String toString() =>
      'HistoryAction(${type.name}${detail != null ? ', $detail' : ''})';
}

/// Whether a history feedback event came from an undo or a redo.
enum HistoryFeedbackMode {
  /// The user reverted an action.
  undo,

  /// The user re-applied a previously reverted action.
  redo,
}

/// Emitted after every undo/redo so the host app can show feedback like
/// "UNDO CHANGE FILTER" (see `MainEditorCallbacks.onHistoryFeedback` and
/// `ProImageEditorState.historyFeedbackNotifier`).
class HistoryFeedback {
  /// Creates a [HistoryFeedback].
  HistoryFeedback({
    required this.mode,
    required this.action,
  }) : timestamp = DateTime.now();

  /// Whether this was an undo or a redo.
  final HistoryFeedbackMode mode;

  /// The action that was reverted (undo) or re-applied (redo). `null` when
  /// the entry has no tag (e.g. imported history).
  final HistoryAction? action;

  /// When the undo/redo happened. Lets overlay widgets restart their
  /// fade-out animation on every event.
  final DateTime timestamp;
}
