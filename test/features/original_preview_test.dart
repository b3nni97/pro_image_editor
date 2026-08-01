import 'dart:math';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:pro_image_editor/shared/widgets/layer/layer_widget.dart';

import '../mock/mock_image.dart';

/// Regression tests for the tap-to-peek "show original" preview
/// (`MainEditorConfigs.enableOriginalPreviewOnTap`).
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
    mainEditor: MainEditorConfigs(
      enableOriginalPreviewOnTap: true,
    ),
  );

  /// A visually effective (non-identity) grayscale color matrix.
  const List<double> grayscaleMatrix = [
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ];

  Future<ProImageEditorState> pumpEditor(
    WidgetTester tester, {
    Function(OriginalPreviewEvent? event)? onOriginalPreviewChanged,
  }) async {
    final editorKey = GlobalKey<ProImageEditorState>();
    await tester.pumpWidget(
      MaterialApp(
        home: ProImageEditor.memory(
          mockMemoryImage,
          key: editorKey,
          configs: configs,
          callbacks: ProImageEditorCallbacks(
            onImageEditingComplete: (bytes) async {},
            mainEditorCallbacks: MainEditorCallbacks(
              onOriginalPreviewChanged: onOriginalPreviewChanged,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return editorKey.currentState!;
  }

  testWidgets('does nothing while the state has no visible edits',
      (tester) async {
    final editor = await pumpEditor(tester);

    editor.showOriginalPreview();
    expect(editor.originalPreviewNotifier.value, isNull,
        reason: 'without edits there is no original to peek at');
  });

  testWidgets('shows the original and auto-hides after the duration',
      (tester) async {
    final events = <OriginalPreviewEvent?>[];
    final editor = await pumpEditor(
      tester,
      onOriginalPreviewChanged: events.add,
    );

    editor.addHistory(
      filters: [grayscaleMatrix],
      action: const HistoryAction(HistoryActionType.filter),
    );
    await tester.pump();

    editor.showOriginalPreview();
    expect(editor.isOriginalPreviewActive, isTrue);
    expect(editor.originalPreviewNotifier.value!.isTransformed, isFalse,
        reason: 'no crop/rotate transform is applied');
    expect(events, hasLength(1));

    // The preview ends on its own after `originalPreviewDuration`.
    await tester.pump(
      configs.mainEditor.originalPreviewDuration +
          const Duration(milliseconds: 100),
    );
    expect(editor.isOriginalPreviewActive, isFalse);
    expect(events, hasLength(2));
    expect(events.last, isNull);
  });

  testWidgets('reports a cropped original when a transform is applied',
      (tester) async {
    final editor = await pumpEditor(tester);

    editor.addHistory(
      transformConfigs: TransformConfigs.empty().copyWith(angle: pi / 2),
      action: const HistoryAction(HistoryActionType.cropRotate),
    );
    await tester.pump();

    editor.showOriginalPreview();
    expect(editor.originalPreviewNotifier.value!.isTransformed, isTrue);

    editor.hideOriginalPreview();
    expect(editor.isOriginalPreviewActive, isFalse);
  });

  Future<ProImageEditorState> pumpEditorWithBaselineTransform(
    WidgetTester tester,
    TransformConfigs baselineTransform,
  ) async {
    final editorKey = GlobalKey<ProImageEditorState>();
    await tester.pumpWidget(
      MaterialApp(
        home: ProImageEditor.memory(
          mockMemoryImage,
          key: editorKey,
          configs: configs.copyWith(
            mainEditor: configs.mainEditor.copyWith(
              transformSetup: MainEditorTransformSetup(
                transformConfigs: baselineTransform,
              ),
            ),
          ),
          callbacks: ProImageEditorCallbacks(
            onImageEditingComplete: (bytes) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return editorKey.currentState!;
  }

  testWidgets(
      'an effective baseline crop (e.g. aspect-ratio clamp) counts as cropped',
      (tester) async {
    // A real crop (half of the image) as the editor's initial state — the
    // same situation an effective aspect-ratio clamp produces.
    final editor = await pumpEditorWithBaselineTransform(
      tester,
      TransformConfigs.empty().copyWith(
        cropRect: const Rect.fromLTWH(0, 0, 100, 100),
        originalSize: const Size(100, 200),
        cropEditorScreenRatio: 1,
      ),
    );

    expect(editor.stateManager.hasVisibleChanges, isTrue,
        reason: 'the image is visibly cropped compared to the raw original');

    editor.showOriginalPreview();
    expect(editor.originalPreviewNotifier.value!.isTransformed, isTrue,
        reason: 'the displayed original is the cropped original');
    editor.hideOriginalPreview();
  });

  testWidgets('a no-op baseline transform still counts as untouched original',
      (tester) async {
    // A concretized transform whose crop covers the full image (with the
    // float noise a no-op aspect-ratio clamp produces) — visually identical
    // to "no crop".
    final editor = await pumpEditorWithBaselineTransform(
      tester,
      TransformConfigs.empty().copyWith(
        cropRect: const Rect.fromLTWH(1e-13, 0, 100, 200),
        originalSize: const Size(100, 200),
        cropEditorScreenRatio: 1,
      ),
    );

    expect(editor.stateManager.hasVisibleChanges, isFalse,
        reason: 'the transform does not visibly change the image');

    editor.addHistory(
      filters: [grayscaleMatrix],
      action: const HistoryAction(HistoryActionType.filter),
    );
    await tester.pump();

    editor.showOriginalPreview();
    expect(editor.originalPreviewNotifier.value!.isTransformed, isFalse,
        reason: 'nothing is cropped, so the label is "ORIGINAL"');
    editor.hideOriginalPreview();
  });

  testWidgets('a tap on the image area triggers the preview', (tester) async {
    final editor = await pumpEditor(tester);

    editor.addHistory(
      filters: [grayscaleMatrix],
      action: const HistoryAction(HistoryActionType.filter),
    );
    await tester.pump();

    await tester.tapAt(tester.getCenter(find.byType(ProImageEditor)));
    await tester.pump();
    expect(editor.isOriginalPreviewActive, isTrue);

    await tester.pump(
      configs.mainEditor.originalPreviewDuration +
          const Duration(milliseconds: 100),
    );
    expect(editor.isOriginalPreviewActive, isFalse);
  });

  testWidgets('a tap on a layer does not trigger the preview', (tester) async {
    final editor = await pumpEditor(tester);

    // Add a text layer (sits at the image center).
    editor.openTextEditor();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, 'Peek');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('TextEditorDoneButton')));
    await tester.pumpAndSettle();

    // A tap on the plain image area (away from the layer) triggers the
    // preview...
    await tester.tapAt(const Offset(100, 100));
    await tester.pump();
    expect(editor.isOriginalPreviewActive, isTrue);
    await tester.pump(
      configs.mainEditor.originalPreviewDuration +
          const Duration(milliseconds: 100),
    );
    expect(editor.isOriginalPreviewActive, isFalse);

    // ...but a tap on the layer itself must not — it belongs to the layer
    // (e.g. opens the text editor), not to the peek gesture.
    await tester.tap(find.byType(LayerWidget).first, warnIfMissed: false);
    await tester.pump();
    expect(editor.isOriginalPreviewActive, isFalse,
        reason: 'taps on layers are layer interactions, not peek taps');
    await tester.pumpAndSettle();
  });

  testWidgets('a tap inside an embedded tune editor triggers the preview',
      (tester) async {
    final editorKey = GlobalKey<ProImageEditorState>();
    await tester.pumpWidget(
      MaterialApp(
        home: ProImageEditor.memory(
          mockMemoryImage,
          key: editorKey,
          configs: configs.copyWith(
            mainEditor: configs.mainEditor.copyWith(
              initialSubEditor: SubEditorMode.tune,
            ),
            tuneEditor: const TuneEditorConfigs(
              enableInteractiveLayers: true,
            ),
          ),
          callbacks: ProImageEditorCallbacks(
            onImageEditingComplete: (bytes) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final editor = editorKey.currentState!;

    editor.addHistory(
      filters: [grayscaleMatrix],
      action: const HistoryAction(HistoryActionType.filter),
    );
    await tester.pump();

    await tester.tapAt(tester.getCenter(find.byType(ProImageEditor)));
    await tester.pump();
    expect(editor.isOriginalPreviewActive, isTrue,
        reason: 'the embedded sub-editor forwards the tap to the '
            'main editor preview scope');

    await tester.pump(
      configs.mainEditor.originalPreviewDuration +
          const Duration(milliseconds: 100),
    );
    expect(editor.isOriginalPreviewActive, isFalse);
  });

  testWidgets('committing a change or undoing hides an active preview',
      (tester) async {
    final editor = await pumpEditor(tester);

    editor.addHistory(
      filters: [grayscaleMatrix],
      action: const HistoryAction(HistoryActionType.filter),
    );
    await tester.pump();

    editor.showOriginalPreview();
    expect(editor.isOriginalPreviewActive, isTrue);

    editor.addHistory(
      blur: 2,
      action: const HistoryAction(HistoryActionType.blur),
    );
    expect(editor.isOriginalPreviewActive, isFalse,
        reason: 'a committed change ends the preview');

    editor.showOriginalPreview();
    expect(editor.isOriginalPreviewActive, isTrue);

    editor.undoAction();
    await tester.pump();
    expect(editor.isOriginalPreviewActive, isFalse,
        reason: 'undo ends the preview');
  });
}
