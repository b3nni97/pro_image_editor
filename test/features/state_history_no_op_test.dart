// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:pro_image_editor/pro_image_editor.dart';

import '../mock/mock_image.dart';

/// Regression tests for the full-snapshot history model: every history entry
/// must represent a visible change. Switching between sub-editors without
/// editing anything, or touching controls without changing values, must not
/// create undo steps.
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
    tuneEditor: TuneEditorConfigs(enableInteractiveLayers: true),
    filterEditor: FilterEditorConfigs(enableInteractiveLayers: true),
    blurEditor: BlurEditorConfigs(enableInteractiveLayers: true),
  );

  Future<ProImageEditorState> pumpEditor(WidgetTester tester) async {
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
    return editorKey.currentState!;
  }

  Future<void> addTextLayer(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(EditableText).first, text);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('TextEditorDoneButton')));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'switching between sub-editors without changes adds no history entries',
      (tester) async {
    final editor = await pumpEditor(tester);

    editor.openTextEditor();
    await tester.pumpAndSettle();
    await addTextLayer(tester, 'History');

    expect(editor.stateManager.historyPointer, 1,
        reason: 'adding a text layer is exactly one undo step');
    final entriesAfterText = editor.stateManager.stateHistory.length;

    // Tune -> Filter -> Blur -> Tune, without touching anything.
    editor.openTuneEditor();
    await tester.pumpAndSettle();
    editor.openFilterEditor();
    await tester.pumpAndSettle();
    editor.openBlurEditor();
    await tester.pumpAndSettle();
    editor.openTuneEditor();
    await tester.pumpAndSettle();

    expect(editor.stateManager.historyPointer, 1,
        reason: 'switching editors without changes must not move the pointer');
    expect(editor.stateManager.stateHistory.length, entriesAfterText,
        reason: 'switching editors without changes must not add entries');
  });

  testWidgets(
      'tune slider interaction without a value change adds no history entry',
      (tester) async {
    final editor = await pumpEditor(tester);

    editor.openTuneEditor();
    await tester.pumpAndSettle();

    final tuneState = editor.tuneEditor.currentState!;

    // Touch and release the slider without changing the value.
    tuneState
      ..onChangedStart(0)
      ..onChangedEnd(0);
    await tester.pumpAndSettle();

    expect(editor.stateManager.historyPointer, 0,
        reason: 'a no-op slider touch must not create an undo step');

    // A real adjustment is exactly one undo step.
    tuneState
      ..onChangedStart(0)
      ..onChanged(0.4)
      ..onChangedEnd(0.4);
    await tester.pumpAndSettle();

    expect(editor.stateManager.historyPointer, 1,
        reason: 'a completed slider drag is exactly one undo step');

    // Undoing it makes the adjustment visually disappear — both in the
    // global state and in the open tune editor's own working values (which
    // drive its sliders and preview).
    editor.undoAction();
    await tester.pumpAndSettle();
    final activeValues = editor.stateManager.activeTuneAdjustments
        .where((item) => item.value != 0);
    expect(activeValues, isEmpty,
        reason: 'undo must revert the tune adjustment');
    final editorValues =
        tuneState.tuneAdjustmentMatrix.where((item) => item.value != 0);
    expect(editorValues, isEmpty,
        reason: 'the open tune editor must sync its working values on undo');

    // Redo restores the adjustment in both places.
    editor.redoAction();
    await tester.pumpAndSettle();
    expect(
      editor.stateManager.activeTuneAdjustments
          .where((item) => item.value != 0),
      isNotEmpty,
      reason: 'redo must re-apply the tune adjustment',
    );
    expect(
      tuneState.tuneAdjustmentMatrix.where((item) => item.value != 0),
      isNotEmpty,
      reason: 'the open tune editor must sync its working values on redo',
    );
  });

  testWidgets(
      'undo with a filter editor pushed over an embedded tune editor does '
      'not duplicate layer GlobalKeys', (tester) async {
    // Reproduces the stages setup: two sub-editor layer stacks are mounted
    // at the same time (embedded tune below, pushed filter on top). The
    // post-undo sync must give each editor copies with its own keys.
    const stackedConfigs = ProImageEditorConfigs(
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

    final editorKey = GlobalKey<ProImageEditorState>();
    await tester.pumpWidget(
      MaterialApp(
        home: ProImageEditor.memory(
          mockMemoryImage,
          key: editorKey,
          configs: stackedConfigs,
          callbacks: ProImageEditorCallbacks(
            onImageEditingComplete: (bytes) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final editor = editorKey.currentState!;

    editor.openTextEditor();
    await tester.pumpAndSettle();
    await addTextLayer(tester, 'Stacked');
    expect(editor.stateManager.historyPointer, 1);

    editor.openFilterEditor();
    await tester.pumpAndSettle();

    // Undo the text layer while both layer stacks are mounted. Before the
    // fix this crashed with "Duplicate GlobalKey detected in widget tree".
    editor.undoAction();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(editor.stateManager.historyPointer, 0);
    expect(editor.activeLayers, isEmpty,
        reason: 'undo must remove the text layer');

    // Redo restores it without key conflicts either.
    editor.redoAction();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(editor.activeLayers.length, 1);
  });

  testWidgets(
      'filter selection and opacity change are separate undo steps '
      '(opacity -> full opacity -> original)', (tester) async {
    final editor = await pumpEditor(tester);

    editor.openFilterEditor();
    await tester.pumpAndSettle();
    final filterState = editor.filterEditor.currentState!;

    // Scrolling through the list passes over filters without settling —
    // those must NOT become undo steps.
    filterState.setFilter(PresetFilters.aden);
    await tester.pump(const Duration(milliseconds: 200));
    filterState.setFilter(PresetFilters.addictiveRed);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(editor.stateManager.historyPointer, 1,
        reason: 'only the settled filter is one undo step, '
            'not every filter passed while scrolling');

    // Settling on another filter is another step.
    filterState.setFilter(PresetFilters.amaro);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(editor.stateManager.historyPointer, 2,
        reason: 'each settled selection is its own undo step');

    // Changing the opacity commits at drag end as a separate step.
    filterState.onChanged(0.3);
    filterState.onChangedEnd(0.3);
    await tester.pumpAndSettle();
    expect(editor.stateManager.historyPointer, 3,
        reason: 'an opacity change is its own undo step');

    // Undo 1: back to the selected filter at full opacity.
    editor.undoAction();
    await tester.pumpAndSettle();
    expect(filterState.selectedFilter.name, PresetFilters.amaro.name);
    expect(filterState.filterOpacity, closeTo(1.0, 0.01),
        reason: 'first undo restores the full-opacity filter');

    // Undo 2: back to the previously selected filter.
    editor.undoAction();
    await tester.pumpAndSettle();
    expect(filterState.selectedFilter.name, PresetFilters.addictiveRed.name,
        reason: 'second undo restores the previous filter');

    // Undo 3: back to the original (no filter).
    editor.undoAction();
    await tester.pumpAndSettle();
    expect(editor.stateManager.activeFilters, isEmpty,
        reason: 'third undo restores the original image');
    expect(filterState.selectedFilter.name, PresetFilters.none.name);
  });

  testWidgets('undo/redo emit history feedback describing the action',
      (tester) async {
    final editor = await pumpEditor(tester);
    final feedbacks = <HistoryFeedback>[];
    editor.historyFeedbackNotifier.addListener(() {
      feedbacks.add(editor.historyFeedbackNotifier.value!);
    });

    editor.openTuneEditor();
    await tester.pumpAndSettle();
    editor.tuneEditor.currentState!
      ..onChangedStart(0)
      ..onChanged(0.4)
      ..onChangedEnd(0.4);
    await tester.pumpAndSettle();

    editor.undoAction();
    await tester.pumpAndSettle();
    expect(feedbacks, hasLength(1));
    expect(feedbacks.last.mode, HistoryFeedbackMode.undo);
    expect(feedbacks.last.action?.type, HistoryActionType.tune);
    expect(feedbacks.last.action?.detail, 'brightness',
        reason: 'the tune feedback carries the adjustment id');

    editor.redoAction();
    await tester.pumpAndSettle();
    expect(feedbacks, hasLength(2));
    expect(feedbacks.last.mode, HistoryFeedbackMode.redo);
    expect(feedbacks.last.action?.type, HistoryActionType.tune);
  });

  testWidgets('re-committing an identical filter state adds no history entry',
      (tester) async {
    final editor = await pumpEditor(tester);

    // Opening and leaving the filter editor without selecting a filter
    // exports a single identity matrix, which is visually "no filter".
    editor.openFilterEditor();
    await tester.pumpAndSettle();
    editor.openTuneEditor();
    await tester.pumpAndSettle();

    expect(editor.stateManager.historyPointer, 0,
        reason: 'an identity filter export must not create an undo step');
  });
}
