import 'package:flutter/widgets.dart';

/// A singleton class to manage gesture propagation in the app.
///
/// Use [GestureManager.instance] to access the singleton.
class GestureManager {
  GestureManager._();

  /// The single instance of [GestureManager].
  static final GestureManager instance = GestureManager._();

  bool _isBlocked = false;

  /// Returns `true` if gesture propagation is currently blocked.
  bool get isBlocked => _isBlocked;

  /// Temporarily blocks pointer events from reaching widgets below in the
  /// image editor.
  ///
  /// Resets automatically in the next frame.
  void stopPropagation() {
    _isBlocked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isBlocked = false;
    });
  }

  final Map<int, DateTime> _layerPointers = {};

  /// Marks the pointer with the given id as having gone down on a layer
  /// widget.
  ///
  /// Layer widgets handle their taps through raw [Listener]s instead of
  /// gesture recognizers, so surrounding tap detectors (e.g. the
  /// "show original" preview) cannot rely on the gesture arena to know a
  /// tap was aimed at a layer — they check [wasPointerOnLayer] instead.
  void markPointerOnLayer(int pointer) {
    final now = DateTime.now();
    // Prune stale entries so the map stays bounded even when no consumer
    // ever checks the marked pointers.
    _layerPointers.removeWhere(
      (_, time) => now.difference(time) > const Duration(seconds: 10),
    );
    _layerPointers[pointer] = now;
  }

  /// Whether the pointer with the given id went down on a layer widget
  /// (see [markPointerOnLayer]).
  bool wasPointerOnLayer(int pointer) => _layerPointers.containsKey(pointer);
}
