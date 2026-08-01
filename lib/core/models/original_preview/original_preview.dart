import 'package:flutter/foundation.dart';

/// Describes an active "show original" preview.
///
/// While an event is non-null on
/// `ProImageEditorState.originalPreviewNotifier`, the editor temporarily
/// renders the raw background image: filters, tune adjustments, blur and
/// layers are hidden. An applied crop/rotate transform stays visible, which
/// is why [isTransformed] is reported — hosts typically label the preview
/// "ORIGINAL" or "CROPPED ORIGINAL" based on it.
class OriginalPreviewEvent {
  /// Creates an [OriginalPreviewEvent].
  OriginalPreviewEvent({required this.isTransformed})
      : timestamp = DateTime.now();

  /// Whether the displayed image is visibly cropped/transformed compared to
  /// the raw original, i.e. the preview shows the *cropped* original rather
  /// than the untouched one. This includes a crop applied at initialization
  /// (aspect-ratio clamp, transform setup) — but not one that doesn't
  /// visibly change the image (e.g. a concretized identity transform).
  final bool isTransformed;

  /// When the preview was requested. A repeated tap while the preview is
  /// active emits a fresh event so overlays can restart their animation.
  final DateTime timestamp;
}

/// Grants sub-editors (tune/filter/blur) access to the main editor's
/// "show original" preview, so a tap inside an embedded or pushed sub-editor
/// triggers the same preview state that the main editor owns.
class OriginalPreviewScope {
  /// Creates an [OriginalPreviewScope].
  const OriginalPreviewScope({
    required this.listenable,
    required this.requestPreview,
  });

  /// The active preview event; `null` while no preview is shown.
  final ValueListenable<OriginalPreviewEvent?> listenable;

  /// Shows the original image for the configured duration
  /// (see `MainEditorConfigs.originalPreviewDuration`). Calling it again
  /// while active restarts the timer.
  final void Function() requestPreview;
}
