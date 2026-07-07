// Dart imports:
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:heroine/heroine.dart';

import '/core/models/history/editor_history_scope.dart';

import '/shared/widgets/smart_hero.dart';

import '../../shared/widgets/extended/interactive_viewer/extended_interactive_viewer.dart';
import '/core/mixins/converted_callbacks.dart';
import '/core/mixins/converted_configs.dart';
import '/core/mixins/standalone_editor.dart';
import '/core/models/transform_helper.dart';
import '/core/utils/size_utils.dart';
import '/features/tune_editor/widgets/tune_editor_bottombar.dart';
import '/pro_image_editor.dart';
import '/shared/services/content_recorder/widgets/content_recorder.dart';
import '/shared/utils/file_constructor_utils.dart';
import '/shared/widgets/layer/layer_stack.dart';
import '/shared/widgets/layer/interactive_layer_stack.dart';
import '/shared/widgets/transform/transformed_content_generator.dart';
import 'utils/tune_presets.dart';
import 'widgets/tune_editor_appbar.dart';

export 'models/tune_adjustment_item.dart';

/// The `TuneEditor` widget allows users to edit images with various
/// tune adjustment tools such as brightness, contrast, and saturation.
///
/// You can create a `TuneEditor` using one of the factory methods provided:
/// - `TuneEditor.file`: Loads an image from a file.
/// - `TuneEditor.asset`: Loads an image from an asset.
/// - `TuneEditor.network`: Loads an image from a network URL.
/// - `TuneEditor.memory`: Loads an image from memory as a `Uint8List`.
/// - `TuneEditor.autoSource`: Automatically selects the source based on
/// the provided parameters.
class TuneEditor extends StatefulWidget
    with StandaloneEditor<TuneEditorInitConfigs> {
  /// Constructs a `TuneEditor` widget.
  ///
  /// The [key] parameter is used to provide a key for the widget.
  /// The [editorImage] parameter specifies the image to be edited.
  /// The [initConfigs] parameter specifies the initialization configurations
  /// for the editor.
  const TuneEditor._({
    super.key,
    required this.initConfigs,
    this.editorImage,
    this.videoController,
  }) : assert(editorImage != null || videoController != null,
            'Either editorImage or videoController must be provided.');

  /// Constructs a `TuneEditor` widget with image data loaded from memory.
  factory TuneEditor.memory(
    Uint8List byteArray, {
    Key? key,
    required TuneEditorInitConfigs initConfigs,
  }) {
    return TuneEditor._(
      key: key,
      editorImage: EditorImage(byteArray: byteArray),
      initConfigs: initConfigs,
    );
  }

  /// Constructs a `TuneEditor` widget with an image loaded from a file.
  factory TuneEditor.file(
    dynamic file, {
    Key? key,
    required TuneEditorInitConfigs initConfigs,
  }) {
    return TuneEditor._(
      key: key,
      editorImage: EditorImage(file: ensureFileInstance(file)),
      initConfigs: initConfigs,
    );
  }

  /// Constructs a `TuneEditor` widget with an image loaded from an asset.
  factory TuneEditor.asset(
    String assetPath, {
    Key? key,
    required TuneEditorInitConfigs initConfigs,
  }) {
    return TuneEditor._(
      key: key,
      editorImage: EditorImage(assetPath: assetPath),
      initConfigs: initConfigs,
    );
  }

  /// Constructs a `TuneEditor` widget with an image loaded from a network
  /// URL.
  factory TuneEditor.network(
    String networkUrl, {
    Key? key,
    required TuneEditorInitConfigs initConfigs,
  }) {
    return TuneEditor._(
      key: key,
      editorImage: EditorImage(networkUrl: networkUrl),
      initConfigs: initConfigs,
    );
  }

  /// Constructs a `TuneEditor` widget with an image loaded automatically
  /// based on the provided source.
  ///
  /// Either [byteArray], [file], [networkUrl], or [assetPath] must be provided.
  factory TuneEditor.autoSource({
    Key? key,
    Uint8List? byteArray,
    dynamic file,
    String? assetPath,
    String? networkUrl,
    EditorImage? editorImage,
    ProVideoController? videoController,
    required TuneEditorInitConfigs initConfigs,
  }) {
    return TuneEditor._(
      key: key,
      editorImage: videoController != null
          ? null
          : editorImage ??
              EditorImage(
                byteArray: byteArray,
                file: file,
                networkUrl: networkUrl,
                assetPath: assetPath,
              ),
      videoController: videoController,
      initConfigs: initConfigs,
    );
  }

  /// Constructs a `TuneEditor` widget with an video player.
  factory TuneEditor.video(
    ProVideoController videoController, {
    Key? key,
    required TuneEditorInitConfigs initConfigs,
  }) {
    return TuneEditor._(
      key: key,
      videoController: videoController,
      initConfigs: initConfigs,
    );
  }

  @override
  final TuneEditorInitConfigs initConfigs;
  @override
  final EditorImage? editorImage;
  @override
  final ProVideoController? videoController;

  @override
  createState() => TuneEditorState();
}

/// The state class for the `TuneEditor` widget.
class TuneEditorState extends State<TuneEditor>
    with
        ImageEditorConvertedConfigs,
        ImageEditorConvertedCallbacks,
        StandaloneEditorState<TuneEditor, TuneEditorInitConfigs> {
  /// A key for managing the interactive viewer state.
  final GlobalKey<ExtendedInteractiveViewerState> interactiveViewerKey =
      GlobalKey();

  /// A stream controller used to manage UI updates.
  ///
  /// This stream is used to broadcast events when the UI needs to be rebuilt.
  late final StreamController<void> uiStream;

  /// A scroll controller for the bottom bar in the tune editor.
  ///
  /// This controller manages the scrolling behavior of the bottom bar.
  final bottomBarScrollCtrl = ScrollController();

  /// A list of tune adjustment items available in the editor.
  ///
  /// Each item represents an adjustable parameter such as brightness or
  /// contrast.
  List<TuneAdjustmentItem> tuneAdjustmentList = [];

  /// A list of matrices representing the adjustments applied to the image.
  ///
  /// Each matrix corresponds to a specific tune adjustment and stores the
  /// current value and its transformation matrix.
  List<TuneAdjustmentMatrix> tuneAdjustmentMatrix = [];

  /// The index of the currently selected tune adjustment item.
  ///
  /// This index represents the adjustment item that is currently being modified
  /// by the user.
  int selectedIndex = 0;

  /// Shortcut to the global history scope from init configs.
  EditorHistoryScope? get _historyScope => initConfigs.historyScope;

  /// Whether global history is active.
  bool get _useGlobalHistory => _historyScope != null;

  /// A stack used to keep track of previous states for undo functionality.
  ///
  /// Only used when [_useGlobalHistory] is false (standalone mode).
  List<List<TuneAdjustmentMatrix>> _undoStack = [];

  /// A stack used to keep track of states for redo functionality.
  ///
  /// Only used when [_useGlobalHistory] is false (standalone mode).
  List<List<TuneAdjustmentMatrix>> _redoStack = [];

  /// Determines whether undo can be performed on the current state.
  bool get canUndo =>
      _useGlobalHistory ? _historyScope!.canUndo() : _undoStack.isNotEmpty;

  /// Determines whether redo can be performed on the current state.
  bool get canRedo =>
      _useGlobalHistory ? _historyScope!.canRedo() : _redoStack.isNotEmpty;

  /// The redo stack, exposed for the main editor to preserve redo entries
  /// when switching between sub-editors.
  List<List<TuneAdjustmentMatrix>> get redoStack => _redoStack;

  /// Exports the current layers if they were modified.
  ///
  /// Returns `null` if no layer modifications were made.
  List<Layer>? exportLayers() {
    if (layersModified) return mutableLayers;
    return null;
  }

  /// A version counter that increments on every undo/redo.
  /// Use this in widget keys to force slider recreation after undo/redo.
  int historyVersion = 0;

  @override
  void initState() {
    super.initState();
    uiStream = StreamController.broadcast();
    uiStream.stream.listen((_) => rebuildController.add(null));

    var items = tuneEditorConfigs.tuneAdjustmentOptions ??
        tunePresets(
          icons: tuneEditorConfigs.icons,
          i18n: i18n.tuneEditor,
        );
    tuneAdjustmentList = items.map((item) {
      return item.copyWith(
        value: tuneAdjustmentMatrix
            .firstWhere((el) => el.id == item.id,
                orElse: () => TuneAdjustmentMatrix(
                      id: 'id',
                      value: 0,
                      matrix: [],
                    ))
            .value,
      );
    }).toList();

    for (final item in items) {
      int i = appliedTuneAdjustments.indexWhere((el) => el.id == item.id);
      tuneAdjustmentMatrix.add(
        i >= 0 ? appliedTuneAdjustments[i] : item.toMatrixItem(),
      );
    }

    tuneEditorCallbacks?.onInit?.call();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      tuneEditorCallbacks?.onAfterViewInit?.call();
    });
  }

  @override
  void dispose() {
    bottomBarScrollCtrl.dispose();
    uiStream.close();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TuneEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync mutable layers when the main editor rebuilds us with a new list
    // (e.g. after adding a text layer or switching sub-editors).
    if (tuneEditorConfigs.enableInteractiveLayers) {
      syncLayersWhenIdle();
    }
  }

  @override
  void setState(void Function() fn) {
    rebuildController.add(null);
    super.setState(fn);
  }

  /// Handles the "Done" action, either by applying changes or closing the
  /// editor.
  void done() async {
    doneEditing(
      editorImage: editorImage,
      returnValue: tuneAdjustmentMatrix,
      blur: appliedBlurFactor,
      matrixFilterList: appliedFilters,
      matrixTuneAdjustmentsList:
          tuneAdjustmentMatrix.map((item) => item.matrix).toList(),
      transform: initialTransformConfigs,
    );
    tuneEditorCallbacks?.handleDone();
  }

  /// Exports the current tune adjustment state.
  List<TuneAdjustmentMatrix> exportStateHistory() {
    return tuneAdjustmentMatrix;
  }

  /// Resets the tune editor state, clearing undo and redo stacks.
  void reset() {
    _undoStack = [];
    _redoStack = [];
    _setMatrixList();
    setState(() {});
  }

  /// Redoes the last undone action.
  ///
  /// When global history is active, delegates to the main editor's redo.
  /// Otherwise, uses the local redo stack.
  void redo() {
    if (_useGlobalHistory) {
      if (_historyScope!.canRedo()) {
        _historyScope!.redo();
        _syncFromGlobalState();
        tuneEditorCallbacks?.handleRedo();
      }
      return;
    }

    if (_redoStack.isNotEmpty) {
      /// Save current state to undo stack
      _undoStack.add(tuneAdjustmentMatrix.map((e) => e.copy()).toList());

      /// Restore the last state from redo stack
      tuneAdjustmentMatrix = _redoStack.removeLast();

      tuneEditorCallbacks?.handleRedo();

      historyVersion++;
      uiStream.add(null);
      setState(() {});
    }
  }

  /// Undoes the last action.
  ///
  /// When global history is active, delegates to the main editor's undo.
  /// Otherwise, uses the local undo stack.
  void undo() {
    if (_useGlobalHistory) {
      if (_historyScope!.canUndo()) {
        _historyScope!.undo();
        _syncFromGlobalState();
        tuneEditorCallbacks?.handleUndo();
      }
      return;
    }

    if (_undoStack.isNotEmpty) {
      /// Save current state to redo stack
      _redoStack.add(tuneAdjustmentMatrix.map((e) => e.copy()).toList());

      /// Restore the last state from undo stack
      tuneAdjustmentMatrix = _undoStack.removeLast();

      tuneEditorCallbacks?.handleUndo();

      historyVersion++;
      uiStream.add(null);
      setState(() {});
    }
  }

  /// Synchronizes the local state from the global history after undo/redo.
  void _syncFromGlobalState() {
    tuneAdjustmentMatrix =
        _historyScope!.getActiveTuneAdjustments().map((e) => e.copy()).toList();
    mutableLayers
      ..clear()
      ..addAll(_historyScope!.getActiveLayers());
    historyVersion++;
    uiStream.add(null);
    setState(() {});
  }

  /// Initializes the adjustment matrix with default values.
  void _setMatrixList() {
    tuneAdjustmentMatrix = tuneAdjustmentList
        .map(
          (item) => TuneAdjustmentMatrix(
            id: item.id,
            value: 0,
            matrix: item.toMatrix(0),
          ),
        )
        .toList();
  }

  /// Handles changes in the tune factor value.
  void onChanged(double value) {
    var selectedItem = tuneAdjustmentList[selectedIndex];

    int index =
        tuneAdjustmentMatrix.indexWhere((item) => item.id == selectedItem.id);

    var item = TuneAdjustmentMatrix(
      id: selectedItem.id,
      value: value,
      matrix: selectedItem.toMatrix(value),
    );
    if (index >= 0) {
      tuneAdjustmentMatrix[index] = item;
    } else {
      tuneAdjustmentMatrix.add(item);
    }

    /// Important that the hash-code update
    tuneAdjustmentMatrix = [...tuneAdjustmentMatrix];

    uiStream.add(null);
    tuneEditorCallbacks?.handleTuneFactorChange(tuneAdjustmentMatrix);
  }

  /// Saves the current state before making changes.
  ///
  /// When global history is active, adds a history entry to the main editor.
  /// Otherwise, saves to the local undo stack.
  void onChangedStart(double value) {
    if (_useGlobalHistory) {
      // Global history: save current tune state as a history entry.
      // The addHistory call captures the full state snapshot.
      _historyScope!.addHistory(
        tuneAdjustments: tuneAdjustmentMatrix.map((e) => e.copy()).toList(),
        layers: _historyScope!.copyLayers(mutableLayers),
        blockCaptureScreenshot: true,
      );
      return;
    }

    // Local undo stack
    _undoStack.add(
      tuneAdjustmentMatrix.map((e) => e.copy()).toList(),
    );
    _redoStack.clear();
  }

  /// Handles the end of changes in the tune factor value.
  void onChangedEnd(double value) {
    setState(() {});

    tuneEditorCallbacks?.handleTuneFactorChangeEnd(tuneAdjustmentMatrix);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      takeScreenshot();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: theme.copyWith(
          tooltipTheme: theme.tooltipTheme.copyWith(preferBelow: true)),
      child: ExtendedPopScope(
        canPop: tuneEditorConfigs.enableGesturePop,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: tuneEditorConfigs.style.uiOverlayStyle,
          child: SafeArea(
            top: tuneEditorConfigs.safeArea.top,
            bottom: tuneEditorConfigs.safeArea.bottom,
            left: tuneEditorConfigs.safeArea.left,
            right: tuneEditorConfigs.safeArea.right,
            child: RecordInvisibleWidget(
              controller: screenshotCtrl,
              child: Scaffold(
                resizeToAvoidBottomInset:
                    tuneEditorConfigs.resizeToAvoidBottomInset,
                backgroundColor:
                    tuneEditorConfigs.style.background?.call(context) ??
                        kImageEditorBackground,
                appBar: _buildAppBar(),
                body: _buildBody(),
                bottomNavigationBar: _buildBottomNavBar(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Builds the app bar for the tune editor.
  PreferredSizeWidget? _buildAppBar() {
    if (tuneEditorConfigs.widgets.appBar != null) {
      return tuneEditorConfigs.widgets.appBar!
          .call(this, rebuildController.stream);
    }
    return TuneEditorAppbar(
      tuneEditorConfigs: tuneEditorConfigs,
      i18n: i18n.tuneEditor,
      canRedo: canRedo,
      canUndo: canUndo,
      onClose: close,
      onDone: done,
      onRedo: redo,
      onUndo: undo,
    );
  }

  /// Builds the main content area of the editor.
  Widget _buildBody() {
    return LayoutBuilder(builder: (context, constraints) {
      editorBodySize = constraints.biggest;
      final mainConfigs = configs.tuneEditor;

      Widget content =
          // When backgroundImageOverride is provided, use it directly
          // instead of the sub-editor's own ExtendedInteractiveViewer +
          // background. The override already contains the main editor's
          // interactive viewer, hero animation, and image rendering.
          initConfigs.backgroundImageOverride ??
              Builder(builder: (context) {
                final double? effectiveAspectRatio =
                    initialTransformConfigs != null &&
                            initialTransformConfigs!.isNotEmpty
                        ? initialTransformConfigs!.cropRect.size.aspectRatio
                        : (mainImageSize != null && mainImageSize != Size.zero
                            ? mainImageSize!.aspectRatio
                            : null);

                final fit = mainConfigs.viewportFitBuilder
                        ?.call(effectiveAspectRatio) ??
                    const ViewportFitResult();

                // Auto-compute contentInset from the effective aspect
                // ratio so the pan boundaries correctly account for
                // FittedBox letterboxing after a crop change.
                final EdgeInsets effectiveContentInset =
                    ViewportFitResult.computeContentInset(
                  aspectRatio: effectiveAspectRatio,
                  viewportSize: editorBodySize,
                );

                return ExtendedInteractiveViewer(
                  key: interactiveViewerKey,
                  zoomConfigs: mainConfigs,
                  boundaryMargin: fit.boundaryMargin,
                  contentInset: effectiveContentInset,
                  minScale: fit.editorMinScale,
                  maxScale: fit.editorMaxScale,
                  initialMatrix4: fit.initialTransform,
                  startMatrix4: initConfigs.initialZoomMatrix,
                  onInteractionStart: (details) {
                    callbacks.tuneEditorCallbacks?.onEditorZoomScaleStart
                        ?.call(details);
                  },
                  onInteractionUpdate: (details) {
                    callbacks.tuneEditorCallbacks?.onEditorZoomScaleUpdate
                        ?.call(details);
                  },
                  onInteractionEnd: (details) {
                    callbacks.tuneEditorCallbacks?.onEditorZoomScaleEnd
                        ?.call(details);
                  },
                  onMatrix4Change: (value) {
                    callbacks.tuneEditorCallbacks?.onEditorZoomMatrix4Change
                        ?.call(value);
                  },
                  child: Stack(
                    children: [
                      if (initConfigs.convertToUint8List && isVideoEditor)
                        _buildBackground(),
                      ContentRecorder(
                        controller: screenshotCtrl,
                        child: Stack(
                          alignment: Alignment.center,
                          fit: StackFit.expand,
                          children: [
                            if (!initConfigs.convertToUint8List ||
                                !isVideoEditor)
                              _buildBackground(),
                            if (tuneEditorConfigs.showLayers && layers != null)
                              _buildLayers(),
                            if (tuneEditorConfigs.widgets.bodyItemsRecorded !=
                                null)
                              ...tuneEditorConfigs.widgets.bodyItemsRecorded!(
                                  this, rebuildController.stream),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              });

      if (tuneEditorConfigs.widgets.wrapBody != null) {
        content = tuneEditorConfigs.widgets.wrapBody!(this, content);
      }

      return Stack(
        alignment: Alignment.center,
        fit: StackFit.expand,
        children: [
          content,
          if (tuneEditorConfigs.widgets.bodyItems != null)
            ...tuneEditorConfigs.widgets.bodyItems!(
                this, rebuildController.stream),
        ],
      );
    });
  }

  Widget _buildBackground() {
    final Widget hero = SmartHero(
      tag: heroTag,
      // Match the sub-editor screen transition: same duration, same spring
      // as the layer/text heroines.
      motion: CupertinoMotion.smooth(
        duration: mainEditorConfigs.style.subEditorPage.transitionDuration,
        snapToEnd: true,
      ),
      child: StreamBuilder(
        stream: uiStream.stream,
        builder: (context, snapshot) {
          return TransformedContentGenerator(
            isVideoPlayer: videoController != null,
            configs: configs,
            transformConfigs:
                initialTransformConfigs ?? TransformConfigs.empty(),
            child: FilteredWidget(
              width: getValidSizeOrDefault(mainImageSize, editorBodySize).width,
              height:
                  getValidSizeOrDefault(mainImageSize, editorBodySize).height,
              configs: configs,
              image: editorImage,
              videoPlayer: videoController?.videoPlayer,
              blankSize: initConfigs.mainImageSize,
              filters: appliedFilters,
              tuneAdjustments: tuneAdjustmentMatrix,
              blurFactor: appliedBlurFactor,
            ),
          );
        },
      ),
    );

    // Bound the hero tightly to the visible content (same aspect math as
    // the crop editor's fake hero) instead of the full body: heroine
    // interpolates the two hero boxes, and a body-sized box with the image
    // letterboxed INSIDE doesn't frame the same object as the crop editor's
    // tight fake hero — the flight geometry (and its landing) can then
    // never match the rendered image on both ends.
    final double aspectRatio = initialTransformConfigs != null &&
            initialTransformConfigs!.isNotEmpty
        ? initialTransformConfigs!.cropRect.size.aspectRatio
        : getValidSizeOrDefault(mainImageSize, editorBodySize).aspectRatio;
    if (!aspectRatio.isFinite || aspectRatio <= 0) return hero;
    return Center(
      child: AspectRatio(aspectRatio: aspectRatio, child: hero),
    );
  }

  Widget _buildLayers() {
    if (tuneEditorConfigs.enableInteractiveLayers) {
      return InteractiveLayerStack(
        enableHero: true,
        configs: configs,
        callbacks: callbacks,
        layers: mutableLayers,
        editorBodySize: editorBodySize,
        interactiveViewerKey: interactiveViewerKey,
        transformHelper: TransformHelper(
          mainBodySize: getValidSizeOrDefault(mainBodySize, editorBodySize),
          mainImageSize: getValidSizeOrDefault(mainImageSize, editorBodySize),
          editorBodySize: editorBodySize,
          transformConfigs: initialTransformConfigs,
        ),
        clipBehavior: Clip.none,
        overlayColor: tuneEditorConfigs.style.background?.call(context) ??
            kImageEditorBackground,
        onTextLayerTap: initConfigs.onTextLayerTap,
        onLayersChanged: () {
          layersModified = true;
          initConfigs.onLayerTransformChanged?.call(mutableLayers);
        },
        onBeforeLayerChange: _useGlobalHistory
            ? () {
                _historyScope!.addHistory(
                  tuneAdjustments:
                      tuneAdjustmentMatrix.map((e) => e.copy()).toList(),
                  layers: _historyScope!.copyLayers(mutableLayers),
                  blockCaptureScreenshot: true,
                );
              }
            : null,
      );
    }

    return LayerStack(
      transformHelper: TransformHelper(
        mainBodySize: getValidSizeOrDefault(mainBodySize, editorBodySize),
        mainImageSize: getValidSizeOrDefault(mainImageSize, editorBodySize),
        editorBodySize: editorBodySize,
        transformConfigs: initialTransformConfigs,
      ),
      configs: configs,
      layers: layers!,
      clipBehavior: Clip.none,
      overlayColor: tuneEditorConfigs.style.background?.call(context) ??
          kImageEditorBackground,
    );
  }

  /// Builds the bottom navigation bar with tune options.
  Widget? _buildBottomNavBar() {
    if (tuneEditorConfigs.widgets.bottomBar != null) {
      return tuneEditorConfigs.widgets.bottomBar!
          .call(this, rebuildController.stream);
    }

    return TuneEditorBottombar(
      state: this,
      tuneEditorConfigs: tuneEditorConfigs,
      tuneAdjustmentList: tuneAdjustmentList,
      tuneAdjustmentMatrix: tuneAdjustmentMatrix,
      rebuildController: rebuildController,
      onChangedStart: onChangedStart,
      onChanged: onChanged,
      onChangedEnd: onChangedEnd,
      bottomBarScrollCtrl: bottomBarScrollCtrl,
      onSelect: (index) {
        setState(() {
          selectedIndex = index;
        });
      },
      selectedIndex: selectedIndex,
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<TuneEditorInitConfigs>(
        'initConfigs',
        widget.initConfigs,
      ))
      ..add(DiagnosticsProperty<EditorImage?>(
        'editorImage',
        widget.editorImage,
      ))
      ..add(DiagnosticsProperty<ProVideoController?>(
        'videoController',
        widget.videoController,
      ))
      ..add(IntProperty('selectedIndex', selectedIndex))
      ..add(IterableProperty<TuneAdjustmentItem>(
        'tuneAdjustmentList',
        tuneAdjustmentList,
      ))
      ..add(IterableProperty<TuneAdjustmentMatrix>(
        'tuneAdjustmentMatrix',
        tuneAdjustmentMatrix,
      ))
      ..add(FlagProperty(
        'canUndo',
        value: canUndo,
        ifTrue: 'can undo',
        ifFalse: 'cannot undo',
      ))
      ..add(FlagProperty(
        'canRedo',
        value: canRedo,
        ifTrue: 'can redo',
        ifFalse: 'cannot redo',
      ));
  }
}
