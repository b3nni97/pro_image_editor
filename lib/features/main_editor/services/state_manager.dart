import 'dart:ui' show Offset, Rect;

import '/core/models/editor_image.dart';
import '/core/models/history/state_history.dart';
import '/core/models/layers/layer.dart';
import '/core/models/multi_threading/thread_capture_model.dart';
import '/features/filter_editor/constants/identity_matrix_constant.dart';
import '/features/filter_editor/types/filter_matrix.dart';
import '/features/tune_editor/models/tune_adjustment_matrix.dart';
import '../../crop_rotate_editor/models/transform_configs.dart';

/// A class for managing the state and history of image editing changes.
///
/// Every history entry is a complete, immutable snapshot of the editor state
/// (layers, filters, tune adjustments, blur, transform). Entries own deep
/// copies of their layers, so later mutations of the live working state can
/// never retroactively change committed history.
class StateManager {
  /// Creates an instance of [StateManager].
  StateManager({
    required this.onStateHistoryChange,
    required this.activeBackgroundImage,
    required this.copyLayers,
  });

  /// Optional callbacks for additional editor actions.
  final Function()? onStateHistoryChange;

  /// Creates deep copies of layers so history entries stay isolated from the
  /// live working state. Copies preserve layer ids and GlobalKeys.
  final List<Layer> Function(List<Layer> layers) copyLayers;

  /// Position in the state history.
  int _historyPointer = 0;

  /// A getter that returns the current position of the history pointer.
  /// The history pointer indicates the current index in the image editor's
  /// state history.
  int get historyPointer => _historyPointer;

  /// A setter for updating the history pointer.
  /// The history pointer must remain within the valid range of `_stateHistory`.
  /// Throws an `ArgumentError` if the provided value is out of range.
  ///
  /// - [value]: The new history pointer index.
  /// - Throws: `ArgumentError` if `value < 0` or `value >=
  /// _stateHistory.length`.
  set historyPointer(int value) {
    if (value < 0 || value >= _stateHistory.length) {
      throw ArgumentError('History pointer out of range');
    }
    _historyPointer = value;
  }

  /// A list that stores the history of changes made in the image editor.
  /// Each entry in the list is of type `EditorStateHistory`, representing a
  /// snapshot of the editor's state at a particular point in time.
  List<EditorStateHistory> _stateHistory = [];

  /// A getter that returns the list of historical editor states.
  /// This list provides a record of changes applied to the image, allowing
  /// for undo/redo functionality.
  List<EditorStateHistory> get stateHistory => _stateHistory;

  final Map<int, EditorImage> _backgroundImages = {};

  /// The currently active background image in the editor.
  EditorImage? activeBackgroundImage;

  /// Updates the background images in the editor's history.
  ///
  /// Replaces the background image at the current history pointer with
  /// [oldImage], and sets the next history entry to [newImage]. Also updates
  /// the [activeBackgroundImage] to [newImage].
  ///
  /// Parameters:
  /// - [oldImage]: The previous background image to store at the current
  /// history pointer.
  /// - [newImage]: The new background image to store at the next history
  /// pointer.
  void updateBackgroundImages({
    required EditorImage oldImage,
    required EditorImage newImage,
  }) {
    _backgroundImages[historyPointer - 1] ??= oldImage.copyWith();
    _backgroundImages[historyPointer] = newImage.copyWith();
    activeBackgroundImage = newImage.copyWith();
    for (var item in screenshots) {
      item.broken = true;
    }
  }

  /// A setter for updating the state history list.
  /// When a new list of editor states is assigned, it triggers
  /// `_updateActiveItems()` to refresh any dependent components based on the
  /// updated history.
  ///
  /// - [value]: A list of `EditorStateHistory` representing the updated state
  /// history.
  set stateHistory(List<EditorStateHistory> value) {
    _stateHistory = value;
    updateActiveItems();
  }

  /// Updates the active items in the editor state based on the current
  /// history pointer.
  ///
  /// Every history entry is a full snapshot, so the active state is read
  /// directly from the entry at the current pointer. The active layers become
  /// a fresh working copy so gestures can mutate them without touching the
  /// committed history entry.
  void updateActiveItems() {
    _refreshActiveFromEntry();
  }

  /// Reads the active state from the entry at the current history pointer.
  ///
  /// [workingLayers] can supply the live layer list that should stay the
  /// active working state (used by [addHistory] so the mounted layer
  /// instances survive a commit without being swapped for copies). When
  /// omitted, a fresh copy of the entry's layers is created — required after
  /// undo/redo/import, where the entry is the only source of truth.
  void _refreshActiveFromEntry({List<Layer>? workingLayers}) {
    final entry = _stateHistory[_historyPointer];

    _activeFilters = entry.filters;
    _activeTuneAdjustments = entry.tuneAdjustments;
    activeLayers = workingLayers ?? copyLayers(entry.layers);
    _transformConfigs = entry.transformConfigs ?? TransformConfigs.empty();
    _activeBlur = entry.blur ?? 0.0;

    onStateHistoryChange?.call();

    if (_backgroundImages[historyPointer] != null) {
      activeBackgroundImage = _backgroundImages[historyPointer]!.copyWith();
    }
  }

  /// A list of active filters applied to the image.
  /// This stores instances of `FilterMatrix`, representing various filter
  /// adjustments.
  FilterMatrix _activeFilters = [];

  /// A getter that returns the list of currently applied filters.
  /// Use this to retrieve the active `FilterMatrix` configurations.
  FilterMatrix get activeFilters => _activeFilters;

  /// A list of active tune adjustments for the image, such as brightness,
  /// contrast, etc.
  /// Each element in the list is of type `TuneAdjustmentMatrix`, representing
  /// specific adjustment settings.
  List<TuneAdjustmentMatrix> _activeTuneAdjustments = [];

  /// A getter that returns the list of currently applied tune adjustments.
  /// This is used to access the active `TuneAdjustmentMatrix` configurations.
  List<TuneAdjustmentMatrix> get activeTuneAdjustments =>
      _activeTuneAdjustments;

  /// The current transformation configurations applied to the image,
  /// including rotation, scaling, or other transformations.
  /// `TransformConfigs.empty()` initializes the object with default values.
  TransformConfigs _transformConfigs = TransformConfigs.empty();

  /// A getter that returns the current transformation configuration.
  /// This can be used to retrieve details about active transformations on the
  /// image.
  TransformConfigs get transformConfigs => _transformConfigs;

  /// The current blur intensity applied to the image.
  /// The value is represented as a `double`, where `0.0` indicates no blur,
  /// and higher values correspond to increasing blur intensity.
  double _activeBlur = 0.0;

  /// A getter that returns the current blur value.
  /// This allows you to query the active blur level applied to the image.
  double get activeBlur => _activeBlur;

  /// Get the list of layers from the current image editor changes.
  List<Layer> activeLayers = [];

  /// Flag indicating if a hero screenshot is required.
  bool heroScreenshotRequired = false;

  /// List of captured screenshots for each state in the history.
  List<ThreadCaptureState> screenshots = [];

  /// Retrieves the currently active screenshot based on the position.
  ThreadCaptureState? get activeScreenshot {
    var historyPos = _historyPointer - 1;

    return screenshots.length > historyPos && historyPos >= 0
        ? screenshots[historyPos]
        : null;
  }

  /// Check if the active screenshot is broken.
  bool? get activeScreenshotIsBroken => activeScreenshot?.broken;

  /// Determines whether undo actions can be performed on the current state.
  bool get canUndo => _historyPointer > 0;

  /// Determines whether redo actions can be performed on the current state.
  bool get canRedo => _historyPointer < _stateHistory.length - 1;

  /// Clean forward changes in the history.
  ///
  /// This method removes any changes made after the current edit position in
  /// the history. It ensures that the state history and screenshots are
  /// consistent with the current position. This is useful when performing an
  /// undo operation, and new edits are made, effectively discarding the "redo"
  /// history.
  void _cleanForwardChanges() {
    if (_stateHistory.length > 1) {
      while (_historyPointer < _stateHistory.length - 1) {
        _stateHistory.removeLast();
      }
      while (_historyPointer < screenshots.length) {
        screenshots.removeLast();
      }
      _backgroundImages.removeWhere((index, _) => index > _historyPointer);
    }
    _historyPointer = _stateHistory.length - 1;
  }

  /// Set the history limit to manage the maximum number of stored states.
  ///
  /// This method sets a limit on the number of states that can be stored in
  /// the history.
  /// If the number of stored states exceeds this limit, the oldest states are
  /// removed to free up memory. This is crucial for preventing excessive
  /// memory usage, especially when each state includes large data such as
  /// screenshots.
  ///
  /// - `limit`: The maximum number of states to retain in the history. Must
  /// be 1 or greater.
  void setHistoryLimit(int limit, bool enableScreenshotLimit) {
    if (limit <= 0) {
      throw ArgumentError('The state history limit must be 1 or greater!');
    }
    while (_historyPointer > limit) {
      if (_historyPointer > 0) {
        _historyPointer--;
        _stateHistory.removeAt(0);
        if (enableScreenshotLimit) screenshots.removeAt(0);
      } else {
        _stateHistory.removeLast();
        if (enableScreenshotLimit) screenshots.removeLast();
      }
    }
  }

  /// Adds a new entry to the history of image editor changes and updates the
  /// history pointer.
  ///
  /// The entry stores deep copies of [history]'s layers, so the committed
  /// snapshot stays isolated from the live working state. When the new state
  /// is visually identical to the entry at the current pointer, no entry is
  /// added (unless [force] is `true`) — this keeps every undo step a visible
  /// change. Forward (redo) history is only discarded when an entry is
  /// actually added.
  ///
  /// - [history]: An `EditorStateHistory` object representing the new editor
  /// state to be added.
  /// - [historyLimit]: An optional parameter that sets a limit on the size of
  /// the history list.
  ///   Defaults to 1000. If the history exceeds this limit, older entries are
  /// removed.
  /// - [force]: Adds the entry even when it equals the current state. Needed
  /// by the image-generation pipeline, which uses `canUndo` to decide whether
  /// a screenshot-based result must be produced.
  ///
  /// Returns `true` when an entry was added, `false` when the change was
  /// skipped as a no-op.
  bool addHistory(
    EditorStateHistory history, {
    int historyLimit = 1000,
    bool enableScreenshotLimit = true,
    bool force = false,
  }) {
    final entry = history.copyWith(layers: copyLayers(history.layers));

    if (!force &&
        _stateHistory.isNotEmpty &&
        isVisuallyEqual(entry, _stateHistory[_historyPointer])) {
      return false;
    }

    _cleanForwardChanges();
    _stateHistory.add(entry);
    historyPointer = _stateHistory.length - 1;
    setHistoryLimit(historyLimit, enableScreenshotLimit);
    _refreshActiveFromEntry(workingLayers: history.layers);
    return true;
  }

  /// Redoes the last undone change, moving the history pointer forward by one
  /// step.
  /// If there is no forward change available, this operation will throw an
  /// error due to out-of-bounds access handled by the `historyPointer` setter.
  void redo() {
    historyPointer = _historyPointer + 1;
    updateActiveItems();
  }

  /// Undoes the last change by moving the history pointer back by one step.
  /// This reverts the editor to the previous state.
  /// If there is no previous state available, this operation will throw an
  /// error due to out-of-bounds access handled by the `historyPointer` setter.
  void undo() {
    historyPointer = _historyPointer - 1;
    updateActiveItems();
  }

  /// Locks or unlocks all layers based on the provided parameters.
  ///
  /// This method iterates through either the active layers or the entire state
  /// history and toggles the lock state of each layer's interaction.
  ///
  /// Parameters:
  /// - `enableInteraction` (required): A boolean value indicating whether to
  ///   lock (`false`) or unlock (`true`) the layers.
  /// - `onlyCurrentHistory` (required): A boolean value indicating whether to
  ///   apply the lock/unlock operation only to the current history (`true`)
  ///   or to all state history (`false`).
  ///
  /// If `onlyCurrentHistory` is `true`, the method will only affect the
  /// active layers.
  /// If `onlyCurrentHistory` is `false`, the method will iterate through all
  /// layers in the state history and apply the lock/unlock operation.
  void updateLayerInteraction({
    required bool enableInteraction,
    required bool onlyCurrentHistory,
  }) {
    if (onlyCurrentHistory) {
      for (Layer layer in activeLayers) {
        layer.interaction.toggleAll(enableInteraction);
      }
    } else {
      for (var history in stateHistory) {
        for (var layer in history.layers) {
          layer.interaction.toggleAll(enableInteraction);
        }
      }
    }
  }

  /// Whether two history entries represent the same visual editor state.
  ///
  /// Used to skip no-op history commits: an undo step between two visually
  /// equal entries would be invisible to the user. Tune adjustments with a
  /// value of `0` are treated as absent, and `null`/empty transforms compare
  /// equal.
  bool isVisuallyEqual(EditorStateHistory a, EditorStateHistory b) {
    return (a.blur ?? 0.0) == (b.blur ?? 0.0) &&
        _transformsEqual(a.transformConfigs, b.transformConfigs) &&
        _filtersEqual(a.filters, b.filters) &&
        _tuneEqual(a.tuneAdjustments, b.tuneAdjustments) &&
        _layerListsEqual(a.layers, b.layers);
  }

  bool _transformsEqual(TransformConfigs? a, TransformConfigs? b) {
    final configsA = a ?? TransformConfigs.empty();
    final configsB = b ?? TransformConfigs.empty();
    if (_isNeutralTransform(configsA) && _isNeutralTransform(configsB)) {
      return true;
    }
    return configsA == configsB;
  }

  /// Whether the transform is visually equivalent to "no transform": no
  /// rotation, flip, zoom, perspective or offset, and a crop rect covering
  /// the full image.
  ///
  /// An untouched crop editor exports a "concretized" transform (real
  /// cropRect/originalSize instead of the `empty()` placeholders) that must
  /// compare equal to [TransformConfigs.empty] to keep no-op crop sessions
  /// out of the history.
  bool _isNeutralTransform(TransformConfigs t) {
    if (t.isEmpty) return true;

    final originalRatio =
        t.originalSize.isFinite ? t.originalSize.aspectRatio : double.nan;
    final coversFullImage = t.cropRect == Rect.largest ||
        (t.cropRect.left == 0 &&
            t.cropRect.top == 0 &&
            originalRatio.isFinite &&
            (t.cropRect.size.aspectRatio - originalRatio).abs() < 0.001);

    return t.angle == 0 &&
        t.straightenAngle == 0 &&
        t.perspectiveX == 0 &&
        t.perspectiveY == 0 &&
        !t.flipX &&
        !t.flipY &&
        t.scaleUser == 1 &&
        t.offset == Offset.zero &&
        coversFullImage;
  }

  bool _filtersEqual(FilterMatrix a, FilterMatrix b) {
    // Identity matrices are visually absent: a filter editor without a
    // selection exports a single identity matrix instead of an empty list.
    final effectiveA = a.where((m) => !_isIdentityColorMatrix(m)).toList();
    final effectiveB = b.where((m) => !_isIdentityColorMatrix(m)).toList();

    if (effectiveA.length != effectiveB.length) return false;
    for (var i = 0; i < effectiveA.length; i++) {
      if (effectiveA[i].length != effectiveB[i].length) return false;
      for (var j = 0; j < effectiveA[i].length; j++) {
        if (effectiveA[i][j] != effectiveB[i][j]) return false;
      }
    }
    return true;
  }

  bool _isIdentityColorMatrix(List<double> matrix) {
    if (matrix.length != identityMatrix.length) return false;
    for (var i = 0; i < matrix.length; i++) {
      if (matrix[i] != identityMatrix[i]) return false;
    }
    return true;
  }

  bool _tuneEqual(
    List<TuneAdjustmentMatrix> a,
    List<TuneAdjustmentMatrix> b,
  ) {
    // Zero-value adjustments are visually absent: the tune editor initializes
    // every adjustment to 0 even when nothing was changed.
    final mapA = {
      for (var item in a)
        if (item.value != 0.0) item.id: item.value,
    };
    final mapB = {
      for (var item in b)
        if (item.value != 0.0) item.id: item.value,
    };
    if (mapA.length != mapB.length) return false;
    for (var entry in mapA.entries) {
      if (mapB[entry.key] != entry.value) return false;
    }
    return true;
  }

  bool _layerListsEqual(List<Layer> a, List<Layer> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_layersEqual(a[i], b[i])) return false;
    }
    return true;
  }

  /// Compares the visually relevant content of two layers. Interaction flags,
  /// meta data and layout caches are ignored because they don't change what
  /// the user sees on the canvas.
  bool _layersEqual(Layer a, Layer b) {
    if (a.runtimeType != b.runtimeType) return false;
    if (a.id != b.id ||
        a.offset != b.offset ||
        a.rotation != b.rotation ||
        a.scale != b.scale ||
        a.flipX != b.flipX ||
        a.flipY != b.flipY ||
        a.groupId != b.groupId) {
      return false;
    }

    if (a is TextLayer && b is TextLayer) {
      return a.text == b.text &&
          a.color == b.color &&
          a.background == b.background &&
          a.colorMode == b.colorMode &&
          a.align == b.align &&
          a.fontScale == b.fontScale &&
          a.textStyle == b.textStyle &&
          a.maxTextWidth == b.maxTextWidth &&
          a.customSecondaryColor == b.customSecondaryColor;
    }
    if (a is EmojiLayer && b is EmojiLayer) {
      return a.emoji == b.emoji;
    }
    if (a is PaintLayer && b is PaintLayer) {
      return a.opacity == b.opacity &&
          _mapsDeepEqual(a.item.toMap(), b.item.toMap());
    }
    if (a is WidgetLayer && b is WidgetLayer) {
      return a.width == b.width && identical(a.widget, b.widget);
    }
    return true;
  }

  bool _mapsDeepEqual(Map<dynamic, dynamic> a, Map<dynamic, dynamic> b) {
    if (a.length != b.length) return false;
    for (var entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (!_valuesDeepEqual(entry.value, b[entry.key])) return false;
    }
    return true;
  }

  bool _valuesDeepEqual(dynamic a, dynamic b) {
    if (a is Map && b is Map) return _mapsDeepEqual(a, b);
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_valuesDeepEqual(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

}
