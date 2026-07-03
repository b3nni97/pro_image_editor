// Flutter imports:
import 'package:flutter/foundation.dart';

import '/core/models/layers/layer.dart';

/// Cross-route channel that carries the *edited* content of a layer into its
/// canvas hero during a closing edit flight.
///
/// When an existing layer is edited, the layer on the canvas keeps its old
/// content until the closing hero flight finishes (so it stays hidden behind
/// the hero placeholder and never flashes). The edited layer is published here
/// so the shuttle can fly the *new* content into place and the canvas hero can
/// derive the correct end rect from it.
///
/// Keyed by layer id (not stored on the [Layer] instance) because sub-editors
/// render *copies* of the layers — the object that handles the edit and the
/// object the shuttle renders are different instances with the same id. The
/// override is never serialized and must be cleared once the real layer is
/// swapped back in.
class HeroFlightOverrides {
  HeroFlightOverrides._();

  /// The shared instance used by editors (writers) and layer widgets (readers).
  static final HeroFlightOverrides instance = HeroFlightOverrides._();

  final Map<String, Layer> _overrides = {};

  /// Bumped whenever an override is set or cleared so layer widgets rebuild and
  /// pick up the change *before* the hero flight measures its end rect
  /// (otherwise a longer/shorter edit flies to the stale size).
  final ValueNotifier<int> tick = ValueNotifier(0);

  /// Returns the override layer for [id], or `null` if none is active.
  Layer? operator [](String id) => _overrides[id];

  /// Publishes [layer] as the override for [id] and notifies listeners.
  void set(String id, Layer layer) {
    _overrides[id] = layer;
    tick.value++;
  }

  /// Removes the override for [id] and notifies listeners. No-op if absent.
  void clear(String id) {
    if (_overrides.remove(id) != null) {
      tick.value++;
    }
  }

  final Set<String> _pendingFlightIds = {};

  /// Whether the layer [id] is the destination of an *imminent* hero flight.
  ///
  /// Used by the new-text flow: the real layer is swapped onto the canvas
  /// *before* the closing pop so the flight can measure a content-ful
  /// destination — but the flight only engages (and hides the destination)
  /// one frame later. While marked, the layer widget keeps the content
  /// invisible (opacity 0, layout preserved for the measurement) so the text
  /// doesn't show up at the target before the flight covers it.
  bool isFlightPending(String id) => _pendingFlightIds.contains(id);

  /// Marks [id] as the destination of an imminent hero flight.
  void markPendingFlight(String id) {
    if (_pendingFlightIds.add(id)) tick.value++;
  }

  /// Clears the pending-flight mark for [id].
  void clearPendingFlight(String id) {
    if (_pendingFlightIds.remove(id)) tick.value++;
  }
}
