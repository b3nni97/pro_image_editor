// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:pro_image_editor/shared/widgets/layer/layer_widget.dart';

import '../mock/mock_image.dart';

/// Reproduces the stages setup: the editor starts with an EMBEDDED tune
/// editor (`initialSubEditor: tune`), the user zooms the canvas, switches to
/// the PUSHED filter editor and immediately taps the text layer. The filter
/// editor's background image must stay painted behind the (non-opaque)
/// text-editor route.
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
    // On the test VM (desktop) `auto` would make the first tap SELECT the
    // layer; on the phone taps edit directly. Force the mobile behavior.
    layerInteraction: LayerInteractionConfigs(
      selectable: LayerInteractionSelectable.disabled,
    ),
    mainEditor: MainEditorConfigs(
      initialSubEditor: SubEditorMode.tune,
      enableZoom: true,
    ),
    tuneEditor: TuneEditorConfigs(
      enableZoom: true,
      enableInteractiveLayers: true,
    ),
    filterEditor: FilterEditorConfigs(
      enableZoom: true,
      enableInteractiveLayers: true,
    ),
  );

  testWidgets(
      'filter background stays painted: zoomed embedded tune -> pushed '
      'filter -> tap text layer', (tester) async {
    final editorKey = GlobalKey<ProImageEditorState>();
    await tester.pumpWidget(
      MaterialApp(
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

    // Embedded tune editor is the visible body.
    expect(find.byType(TuneEditor), findsOneWidget);

    // Create the text layer through the text editor, like stages does via
    // its custom bottom bar.
    editorKey.currentState!.openTextEditor();
    await tester.pumpAndSettle();
    expect(find.byType(TextEditor), findsOneWidget,
        reason: 'text editor should open');
    await tester.enterText(find.byType(EditableText), 'HeroText');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('TextEditorDoneButton')));
    await tester.pumpAndSettle();
    expect(find.byType(TextEditor), findsNothing,
        reason: 'text editor should close after done');
    // The text is painted by a CustomPainter (no Text/RichText widget), so
    // assert on the LayerWidget itself. Default skipOffstage: true — the
    // layer must be onstage in the embedded tune editor.
    expect(find.byType(LayerWidget), findsWidgets,
        reason: 'text layer should be painted in the embedded tune editor');

    // Zoom the canvas (like pinch-zooming in stages). With an embedded
    // sub-editor, zoom is handled by the MAIN editor's interactive viewer.
    editorKey.currentState!.interactiveViewer.currentState!
        .zoomTo(scale: 2.5, offset: const Offset(-150, -150));
    await tester.pumpAndSettle();

    // Switch to the pushed filter editor.
    editorKey.currentState!.openFilterEditor();
    await tester.pumpAndSettle();
    expect(find.byType(FilterEditor), findsOneWidget);

    Finder filterBackground() => find.descendant(
          of: find.byType(FilterEditor),
          matching: find.byType(FilteredWidget),
        );
    expect(filterBackground(), findsWidgets);

    // Immediately tap the text layer inside the filter editor.
    final textInFilter = find.descendant(
      of: find.byType(FilterEditor),
      matching: find.byType(LayerWidget),
    );
    expect(textInFilter, findsOneWidget);
    await tester.tap(textInFilter, warnIfMissed: false);
    await tester.pumpAndSettle();

    // The text editor opened above the filter editor...
    expect(find.byType(TextEditor), findsOneWidget);

    // ...and the filter editor's background image is STILL mounted and
    // painted behind it. The default `skipOffstage: true` fails both when
    // the subtree was unmounted and when it was turned offstage.
    expect(find.byType(FilterEditor), findsOneWidget);
    expect(filterBackground(), findsWidgets);

    // Closing the text editor must land back in the (still open) filter
    // editor, with the edited text adopted into its layer copy.
    await tester.enterText(
      find
          .descendant(
            of: find.byType(TextEditor),
            matching: find.byType(EditableText),
          )
          .first,
      'HeroText edited',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('TextEditorDoneButton')));
    await tester.pumpAndSettle();

    expect(find.byType(TextEditor), findsNothing);
    expect(find.byType(FilterEditor), findsOneWidget);
    expect(filterBackground(), findsWidgets);
    expect(textInFilter, findsOneWidget);
  });
}
