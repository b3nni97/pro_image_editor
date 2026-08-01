import 'dart:math';

import 'package:flutter/widgets.dart';

import '/core/constants/editor_various_constants.dart';
import '/core/services/gesture_manager.dart';

/// Detects a plain tap on the image area and reports it via
/// [onImageAreaTap] — used to trigger the "show original" preview (see
/// `MainEditorConfigs.enableOriginalPreviewOnTap`).
///
/// Layer widgets handle their taps through raw [Listener]s instead of
/// gesture recognizers (see `LayerWidget`), so a plain [GestureDetector]
/// around the editor body would also fire for taps on layers. This detector
/// therefore implements its own tap detection with the same slop/time rules
/// as the layer widgets and skips:
///
/// - pointers that went down on a layer
///   (see [GestureManager.wasPointerOnLayer]),
/// - multi-touch gestures (pinch/zoom),
/// - drags (movement beyond [tapSlop]) and long presses.
class OriginalPreviewTapDetector extends StatefulWidget {
  /// Creates an [OriginalPreviewTapDetector].
  const OriginalPreviewTapDetector({
    super.key,
    required this.child,
    this.onImageAreaTap,
  });

  /// Called when the user taps the plain image area — not a layer and not
  /// as part of a multi-touch or drag gesture. `null` disables detection.
  final VoidCallback? onImageAreaTap;

  /// The editor content to observe.
  final Widget child;

  @override
  State<OriginalPreviewTapDetector> createState() =>
      _OriginalPreviewTapDetectorState();
}

class _OriginalPreviewTapDetectorState
    extends State<OriginalPreviewTapDetector> {
  PointerDownEvent? _downEvent;
  DateTime _downTimestamp = DateTime.now();
  int _activePointers = 0;
  bool _isMultiTouch = false;

  void _onPointerDown(PointerDownEvent event) {
    _activePointers++;
    if (_activePointers > 1) {
      _isMultiTouch = true;
      _downEvent = null;
      return;
    }
    _isMultiTouch = false;
    _downEvent = event;
    _downTimestamp = DateTime.now();
  }

  void _onPointerUp(PointerUpEvent event) {
    _activePointers = max(0, _activePointers - 1);
    final down = _downEvent;
    if (_activePointers > 0) return;
    _downEvent = null;

    if (widget.onImageAreaTap == null || _isMultiTouch || down == null) return;
    if (event.pointer != down.pointer) return;
    if ((event.position - down.position).distance >= tapSlop) return;
    if (DateTime.now().difference(_downTimestamp).inMilliseconds >
        tapTimeElapsed) {
      return;
    }
    if (GestureManager.instance.isBlocked) return;
    if (GestureManager.instance.wasPointerOnLayer(event.pointer)) return;

    widget.onImageAreaTap!();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _activePointers = max(0, _activePointers - 1);
    _downEvent = null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onImageAreaTap == null) return widget.child;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: widget.child,
    );
  }
}
