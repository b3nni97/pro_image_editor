// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:heroine/heroine.dart';

// Project imports:
import 'package:pro_image_editor/pro_image_editor.dart';

import '../mock/mock_image.dart';

/// Reproduces the stages setup (embedded tune editor + pushed filter editor)
/// and verifies that creating a NEW text layer flies home with a heroine
/// flight when the text editor closes — both over the embedded tune editor
/// and over the pushed filter editor.
void main() {
  const configs = ProImageEditorConfigs(
    progressIndicatorConfigs: ProgressIndicatorConfigs(
      widgets: ProgressIndicatorWidgets(
        circularProgressIndicator: SizedBox.shrink(),
      ),
    ),
    imageGeneration: ImageGenerationConfigs(
      enableIsolateGeneration: false,
      enableBackgroundGeneration: false,
    ),
    layerInteraction: LayerInteractionConfigs(
      selectable: LayerInteractionSelectable.disabled,
    ),
    mainEditor: MainEditorConfigs(initialSubEditor: SubEditorMode.tune),
    tuneEditor: TuneEditorConfigs(enableInteractiveLayers: true),
    filterEditor: FilterEditorConfigs(enableInteractiveLayers: true),
  );

  Future<ProImageEditorState> pumpEditor(WidgetTester tester) async {
    final editorKey = GlobalKey<ProImageEditorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [HeroineController()],
        home: ProImageEditor.memory(
          mockMemoryImage,
          key: editorKey,
          configs: configs,
          callbacks: ProImageEditorCallbacks(
            onImageEditingComplete: (bytes) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return editorKey.currentState!;
  }

  Future<bool> addTextAndDetectFlight(
    WidgetTester tester,
    ProImageEditorState editor,
  ) async {
    editor.openTextEditor();
    await tester.pumpAndSettle();
    expect(find.byType(TextEditor), findsOneWidget);

    await tester.enterText(find.byType(EditableText).first, 'FlyHome');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('TextEditorDoneButton')));

    // Watch the closing transition frame by frame: the flight must engage
    // for the new layer's tag.
    bool engaged = false;
    for (int i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final layers = editor.activeLayers;
      if (layers.isNotEmpty && HeroineController.isTagInFlight(layers.last.id)) {
        engaged = true;
        break;
      }
    }
    await tester.pumpAndSettle();
    return engaged;
  }

  testWidgets('new text over the EMBEDDED tune editor engages a hero flight',
      (tester) async {
    final editor = await pumpEditor(tester);

    final engaged = await addTextAndDetectFlight(tester, editor);
    expect(engaged, isTrue,
        reason: 'closing text editor over embedded tune must fly the layer');
  });

  testWidgets('new text over the PUSHED filter editor engages a hero flight',
      (tester) async {
    final editor = await pumpEditor(tester);

    editor.openFilterEditor();
    await tester.pumpAndSettle();
    expect(find.byType(FilterEditor), findsOneWidget);

    final engaged = await addTextAndDetectFlight(tester, editor);
    expect(engaged, isTrue,
        reason: 'closing text editor over pushed filter must fly the layer');
  });
}
