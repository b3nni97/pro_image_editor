// Flutter imports:
import 'package:flutter/widgets.dart';

// Project imports:
import '/core/enums/editor_mode.dart';
import '/features/blur_editor/blur_editor.dart';
import '/features/crop_rotate_editor/crop_rotate_editor.dart';
import '/features/emoji_editor/emoji_editor.dart';
import '/features/filter_editor/filter_editor.dart';
import '/features/paint_editor/paint_editor.dart';
import '/features/text_editor/text_editor.dart';
import '/features/tune_editor/tune_editor.dart';

/// Mixin which contains all global keys for the main-editor
mixin MainEditorGlobalKeys {
  /// A GlobalKey for the Paint Editor, used to access and control the state
  /// of the paint editor.
  late GlobalKey<PaintEditorState> paintEditor = GlobalKey<PaintEditorState>();

  /// A GlobalKey for the Text Editor, used to access and control the state of
  /// the text editor.
  late GlobalKey<TextEditorState> textEditor = GlobalKey<TextEditorState>();

  /// A GlobalKey for the Crop and Rotate Editor, used to access and control
  /// the state of the crop and rotate editor.
  late GlobalKey<CropRotateEditorState> cropRotateEditor =
      GlobalKey<CropRotateEditorState>();

  /// A GlobalKey for the Filter Editor, used to access and control the state
  /// of the filter editor.
  late GlobalKey<FilterEditorState> filterEditor =
      GlobalKey<FilterEditorState>();

  /// A GlobalKey for the Tune Editor, used to access and control the state of
  /// the tune editor.
  late GlobalKey<TuneEditorState> tuneEditor = GlobalKey<TuneEditorState>();

  /// A GlobalKey for the Blur Editor, used to access and control the state of
  /// the blur editor.
  late GlobalKey<BlurEditorState> blurEditor = GlobalKey<BlurEditorState>();

  /// A GlobalKey for the Emoji Editor, used to access and control the state of
  /// the emoji editor.
  late GlobalKey<EmojiEditorState> emojiEditor = GlobalKey<EmojiEditorState>();

  /// Re-initializes all GlobalKeys. Useful when rapidly switching between
  /// subeditors via `pushReplacement` to avoid "Duplicate GlobalKey" errors.
  /// This also ensures the `CropRotateEditor` shows its fake hero before its
  /// key is lost, allowing the outgoing hero animation to play.
  ///
  /// When [preserve] is set, the corresponding editor's key is kept intact.
  /// This is used for embedded sub-editors whose key must not be reset
  /// because they remain in the widget tree permanently.
  void resetGlobalKeys({SubEditorMode? preserve}) {
    paintEditor = GlobalKey<PaintEditorState>();
    textEditor = GlobalKey<TextEditorState>();
    cropRotateEditor = GlobalKey<CropRotateEditorState>();
    if (preserve != SubEditorMode.filter) {
      filterEditor = GlobalKey<FilterEditorState>();
    }
    if (preserve != SubEditorMode.tune) {
      tuneEditor = GlobalKey<TuneEditorState>();
    }
    if (preserve != SubEditorMode.blur) {
      blurEditor = GlobalKey<BlurEditorState>();
    }
    emojiEditor = GlobalKey<EmojiEditorState>();
  }
}


