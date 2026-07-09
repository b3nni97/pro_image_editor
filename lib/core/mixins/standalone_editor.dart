// Dart imports:
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:heroine/heroine.dart';

import '/core/mixins/converted_callbacks.dart';
import '/core/models/complete_parameters.dart';
import '/features/filter_editor/types/filter_matrix.dart';
import '/features/tune_editor/models/tune_adjustment_matrix.dart';
import '/shared/controllers/video_controller.dart';
import '/shared/factories/editor_factory.dart';
import '/shared/factories/editor_mapper.dart';
import '/shared/services/content_recorder/controllers/content_recorder_controller.dart';
import '/shared/utils/decode_image.dart';
import '/shared/utils/transparent_image_generator_utils.dart';
import '/shared/widgets/overlays/loading_dialog/loading_dialog.dart';
import '../models/editor_callbacks/pro_image_editor_callbacks.dart';
import '../models/editor_configs/pro_image_editor_configs.dart';
import '../models/editor_image.dart';
import '../models/init_configs/editor_init_configs.dart';
import '../models/layers/layer.dart';
import '../models/multi_threading/thread_capture_model.dart';
import 'converted_configs.dart';

/// A mixin providing access to standalone editor configurations and image.
mixin StandaloneEditor<T extends EditorInitConfigs> {
  /// Returns the initialization configurations for the editor.
  T get initConfigs;

  /// Returns the editor image
  EditorImage? get editorImage;

  /// Returns the video controller
  ProVideoController? get videoController;
}

/// A mixin providing access to standalone editor configurations and image
/// within a state.
mixin StandaloneEditorState<T extends StatefulWidget,
        I extends EditorInitConfigs>
    on State<T>, ImageEditorConvertedConfigs, ImageEditorConvertedCallbacks {
  /// Returns the initialization configurations for the editor.
  I get initConfigs => (widget as StandaloneEditor<I>).initConfigs;

  /// The background image which is used in the video editor.
  EditorImage? videoBackgroundImage;

  /// Returns the image being edited.
  EditorImage? get editorImage =>
      videoBackgroundImage ?? (widget as StandaloneEditor<I>).editorImage;

  /// Returns the controller to edit the video.
  ProVideoController? get videoController =>
      (widget as StandaloneEditor<I>).videoController;

  @override
  ProImageEditorConfigs get configs => initConfigs.configs;

  @override
  ProImageEditorCallbacks get callbacks => initConfigs.callbacks;

  /// Helper stream to rebuild widgets.
  @protected
  late final StreamController<void> rebuildController;

  /// Returns the theme data for the editor.
  ThemeData get theme => initConfigs.theme;

  /// Returns the initial transformation configurations for the editor.
  /// If [_transformConfigsOverride] is set (via [updateAppliedState]), uses
  /// that instead of the original initConfigs value.
  TransformConfigs? get initialTransformConfigs =>
      _transformConfigsOverride ?? initConfigs.transformConfigs;
  TransformConfigs? _transformConfigsOverride;

  /// Returns the layers in the editor.
  List<Layer>? get layers => initConfigs.layers;

  /// The editor's mutable copies of the main editor's layers, rendered by
  /// the interactive layer stack when interactive layers are enabled for
  /// this sub-editor.
  late final List<Layer> mutableLayers = List<Layer>.from(layers ?? []);

  /// Whether [mutableLayers] were changed by user interaction since the
  /// last sync from the main editor.
  bool layersModified = false;

  /// Ids of layers the user drag-deleted inside this sub-editor. Remembered so
  /// a re-sync from the main editor's (still-stale) list doesn't bring them
  /// back before this editor commits its state (see [syncLayersWhenIdle],
  /// [removeLayerFromSubEditor]).
  final Set<String> locallyRemovedLayerIds = {};

  /// Removes [layer] (matched by id) from this editor's working copy in
  /// response to a drag-to-delete gesture.
  ///
  /// Matches by id (not identity) to stay robust regardless of which copy the
  /// interactive layer stack hands back, and remembers the id so a subsequent
  /// re-sync from the main editor's still-stale list doesn't resurrect it (see
  /// [syncLayersWhenIdle]).
  void removeLayerFromSubEditor(Layer layer) {
    locallyRemovedLayerIds.add(layer.id);
    layersModified = true;
    // The interactive layer stack may have already removed it by identity; only
    // touch the list (and rebuild) if the copy is still present.
    final removed = mutableLayers.indexWhere((l) => l.id == layer.id);
    if (removed < 0) return;
    if (mounted) {
      setState(() => mutableLayers.removeAt(removed));
    } else {
      mutableLayers.removeAt(removed);
    }
  }

  /// Guards against scheduling multiple deferred layer syncs
  /// (see [syncLayersWhenIdle]).
  bool _layerSyncScheduled = false;

  /// Replaces [mutableLayers] with the widget's layer list — but never while
  /// one of the current layers is mid hero-flight.
  ///
  /// Call this from `didUpdateWidget` when interactive layers are enabled,
  /// so the copies follow the main editor's list (e.g. after adding a text
  /// layer or switching sub-editors).
  ///
  /// The main editor passes *fresh copies* (new [Layer.key] GlobalKeys) on
  /// every rebuild, so the swap remounts the LayerWidgets. Doing that during
  /// a flight destroys the heroine that owns the flight's motion controller
  /// and cuts the landing animation short (visible snap when the text editor
  /// closes). Defer the sync until the flight is over instead.
  ///
  /// A mid-gesture re-sync can swap out the instance being dragged, so
  /// drag-to-delete removals are reconciled by id (see
  /// [removeLayerFromSubEditor] / [locallyRemovedLayerIds]) rather than by
  /// identity, and this method filters those ids out below.
  void syncLayersWhenIdle({bool deferred = false}) {
    if (!mounted) return;
    if (mutableLayers.any((l) => HeroineController.isTagInFlight(l.id))) {
      if (_layerSyncScheduled) return;
      _layerSyncScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _layerSyncScheduled = false;
        syncLayersWhenIdle(deferred: true);
      });
      return;
    }
    // Preserve widget identity across the swap: carry the previous copies'
    // GlobalKeys over to the incoming copies (matched by id). Otherwise every
    // sync remounts the LayerWidgets, which resets the Heroine state — e.g.
    // the "hidden while its editor is open" flight status of an edited text
    // layer, making it briefly visible at the target before the close flight.
    final incoming = List<Layer>.from(layers ?? []);
    // Once the main editor has dropped a drag-deleted layer from its own list
    // (on commit), stop tracking its id — otherwise a same-id layer that undo
    // legitimately restores would be filtered out below forever.
    locallyRemovedLayerIds.removeWhere(
      (id) => !incoming.any((l) => l.id == id),
    );
    // Drop layers the user drag-deleted here. The main editor's list (the
    // source of [layers]) is only reconciled on commit, so until then a
    // re-sync would otherwise resurrect them.
    incoming.removeWhere((l) => locallyRemovedLayerIds.contains(l.id));
    for (final layer in incoming) {
      final i = mutableLayers.indexWhere((l) => l.id == layer.id);
      if (i >= 0) {
        layer
          ..key = mutableLayers[i].key
          ..keyInternalSize = mutableLayers[i].keyInternalSize;
      }
    }
    mutableLayers
      ..clear()
      ..addAll(incoming);
    // Keep the "modified" flag set while a drag-delete is still pending so
    // [exportLayers] reports the change on commit even though the sync
    // otherwise resets it.
    layersModified = locallyRemovedLayerIds.isNotEmpty;
    // The immediate path runs during didUpdateWidget, where a rebuild
    // follows anyway; the deferred path needs its own.
    if (deferred) setState(() {});
  }

  /// Applies edited layer content from the main editor to this editor's
  /// copy (matched by id), preserving the copy's own GlobalKeys so the
  /// mounted LayerWidget updates in place.
  ///
  /// Pushed sub-editors never receive a didUpdateWidget-driven re-sync
  /// (their layer list is captured once at push), so content edits — e.g.
  /// a text change made through the text editor — are handed over here.
  void adoptLayerUpdate(Layer updated) {
    final i = mutableLayers.indexWhere((l) => l.id == updated.id);
    if (i < 0 || !mounted) return;
    updated
      ..key = mutableLayers[i].key
      ..keyInternalSize = mutableLayers[i].keyInternalSize;
    setState(() => mutableLayers[i] = updated);
  }

  /// Removes this editor's copy of the layer with [id] — the counterpart of
  /// [adoptLayerUpdate] for layers the main editor deleted.
  void adoptLayerRemoval(String id) {
    final i = mutableLayers.indexWhere((l) => l.id == id);
    if (i < 0 || !mounted) return;
    setState(() => mutableLayers.removeAt(i));
  }

  /// Returns the applied blur factor.
  /// If [_appliedBlurOverride] is set (via [updateAppliedState]), uses that
  /// instead of the original initConfigs value.
  double get appliedBlurFactor =>
      _appliedBlurOverride ?? initConfigs.appliedBlurFactor;
  double? _appliedBlurOverride;

  /// Returns the applied filters.
  /// If [_appliedFiltersOverride] is set (via [updateAppliedState]), uses that
  /// instead of the original initConfigs value.
  FilterMatrix get appliedFilters =>
      _appliedFiltersOverride ?? initConfigs.appliedFilters;
  FilterMatrix? _appliedFiltersOverride;

  /// Returns the applied tune adjustments.
  /// If [_appliedTuneOverride] is set (via [updateAppliedState]), uses that
  /// instead of the original initConfigs value.
  List<TuneAdjustmentMatrix> get appliedTuneAdjustments =>
      _appliedTuneOverride ?? initConfigs.appliedTuneAdjustments;
  List<TuneAdjustmentMatrix>? _appliedTuneOverride;

  /// Updates the applied state overrides for this sub-editor.
  ///
  /// Called by the main editor after a global undo/redo to push the
  /// reverted state to the active sub-editor, ensuring its preview
  /// reflects the correct applied filters, tune adjustments, and blur.
  void updateAppliedState({
    required FilterMatrix filters,
    required List<TuneAdjustmentMatrix> tuneAdjustments,
    required double blur,
    TransformConfigs? transformConfigs,
  }) {
    _appliedFiltersOverride = filters;
    _appliedTuneOverride = tuneAdjustments;
    _appliedBlurOverride = blur;
    _transformConfigsOverride = transformConfigs;
  }

  /// Returns the body size with layers.
  Size? get mainBodySize => initConfigs.mainBodySize;

  /// Returns the image size with layers.
  Size? get mainImageSize => initConfigs.mainImageSize;

  /// The information data from the image.
  ImageInfos? imageInfos;

  /// Represents the dimensions of the body.
  Size editorBodySize = Size.infinite;

  /// Manages the capturing a screenshot of the image.
  late ContentRecorderController screenshotCtrl;

  /// Indicates it create a screenshot or not.
  bool isGenerationActive = false;

  /// Indicates if the video editor is used
  bool get isVideoEditor => videoController != null;

  /// The position in the history of screenshots. This is used to track the
  /// current position in the list of screenshots.
  int screenshotHistoryPosition = 0;

  /// A list of captured screenshots. Each element in the list represents the
  /// state of a screenshot captured by the isolate.
  final List<ThreadCaptureState> screenshotHistory = [];

  Uint8List? _transparentImageBytes;

  /// Sets the image information data.
  ///
  /// This method decodes image information based on the current editor state
  /// and configuration, ensuring accurate metadata extraction.
  Future<void> setImageInfos({
    TransformConfigs? activeHistory,
    bool? forceUpdate,
  }) async {
    if (imageInfos == null || forceUpdate == true) {
      imageInfos = (await decodeImageInfos(
        bytes: await (editorImage?.safeByteArray(context) ??
            _createTransparentImage()),
        screenSize: editorBodySize,
        configs: activeHistory,
      ));
    }
  }

  /// This function is for internal use only and is marked as protected.
  /// Please use the `done()` method instead.
  @protected
  void doneEditing({
    dynamic returnValue,
    EditorImage? editorImage,
    Function? onCloseWithValue,
    Function(Uint8List?)? onSetFakeHero,
    required double blur,
    required List<List<double>> matrixFilterList,
    required List<List<double>> matrixTuneAdjustmentsList,
    required TransformConfigs? transform,
  }) async {
    if (isGenerationActive) return;

    if (initConfigs.convertToUint8List) {
      initConfigs.callbacks.onImageEditingStarted?.call();

      isGenerationActive = true;
      LoadingDialog.instance.show(
        context,
        configs: configs,
        theme: theme,
        message: i18n.doneLoadingMsg,
      );

      /// Ensure the image infos are read
      if (imageInfos == null) await setImageInfos();
      if (!mounted) {
        LoadingDialog.instance.hide();
        return;
      }

      /// Capture the final screenshot
      bool screenshotIsCaptured = screenshotHistoryPosition > 0 &&
          screenshotHistoryPosition <= screenshotHistory.length;
      Uint8List? bytes = await screenshotCtrl.captureFinalScreenshot(
        imageInfos: imageInfos!,
        backgroundScreenshot: screenshotIsCaptured
            ? screenshotHistory[screenshotHistoryPosition - 1]
            : null,
        originalImageBytes: screenshotHistoryPosition > 0
            ? null
            : await editorImage!.safeByteArray(context),
      );

      isGenerationActive = false;

      var imageBytes = bytes ?? Uint8List.fromList([]);

      /// Return final image that the user can handle it but still with the
      /// active loading dialog
      await initConfigs.callbacks.onImageEditingComplete?.call(imageBytes);

      /// Return complete parameters if requested
      if (initConfigs.callbacks.onCompleteWithParameters != null) {
        final isTransformed = transform?.isNotEmpty ?? false;

        var decodedImage = await decodeImageFromList(imageBytes);
        Size originalImageSize = Size(
          decodedImage.width.toDouble(),
          decodedImage.height.toDouble(),
        );
        Size? outputSize = transform?.getCropSize(originalImageSize);
        Offset? outputOffset = transform?.getCropStartOffset(originalImageSize);

        await initConfigs.callbacks.onCompleteWithParameters?.call(
          CompleteParameters(
            blur: blur,
            matrixFilterList: matrixFilterList,
            matrixTuneAdjustmentsList: matrixTuneAdjustmentsList,
            cropWidth: isTransformed ? outputSize!.width.round() : null,
            cropHeight: isTransformed ? outputSize!.height.round() : null,
            cropX: isTransformed ? outputOffset!.dx.round() : null,
            cropY: isTransformed ? outputOffset!.dy.round() : null,
            flipX: transform?.flipX ?? false,
            flipY: transform?.flipY ?? false,
            rotateTurns: transform?.angleToTurns() ?? 0,
            startTime: null,
            endTime: null,
            image: imageBytes,
            isTransformed: isTransformed,
            layers: layers ?? [],
          ),
        );
      }

      /// Precache the image for the case the user require the hero animation
      if (onSetFakeHero != null) {
        if (bytes != null && mounted) {
          await precacheImage(MemoryImage(bytes), context);
        }
        onSetFakeHero.call(bytes);
      }

      /// Hide the loading dialog
      LoadingDialog.instance.hide();

      initConfigs.callbacks.onCloseEditor?.call(editorMode);
    } else {
      if (onCloseWithValue == null) {
        Navigator.pop(context, returnValue);
      } else {
        onCloseWithValue.call();
      }
    }
  }

  /// Closes the editor without applying changes.
  void close() {
    if (initConfigs.callbacks.onCloseEditor == null) {
      Navigator.pop(context);
    } else {
      initConfigs.callbacks.onCloseEditor?.call(editorMode);
    }

    EditorFactory.getEditor(editorMode).handleCloseEditor();
  }

  /// Returns the editor mode based on the init config type.
  EditorMode get editorMode {
    return EditorMapper.getEditorModeFromConfigs(initConfigs);
  }

  /// Takes a screenshot of the current editor state.
  ///
  /// This method captures a screenshot of the current editor state, storing
  /// it in the screenshot history for potential future use.
  @protected
  void takeScreenshot() async {
    if (!initConfigs.convertToUint8List) return;

    await setImageInfos();

    screenshotHistory.removeRange(
      screenshotHistoryPosition,
      screenshotHistory.length,
    );

    screenshotHistoryPosition++;

    await screenshotCtrl.capture(
      imageInfos: imageInfos!,
      screenshots: screenshotHistory,
    );
  }

  @override
  @mustCallSuper
  void initState() {
    super.initState();
    screenshotCtrl = ContentRecorderController(
      configs: configs.imageGeneration,
      isVideoEditor: isVideoEditor,
      ignoreGeneration: !initConfigs.convertToUint8List,
    );
    rebuildController = StreamController.broadcast();
  }

  @override
  @mustCallSuper
  void dispose() {
    screenshotCtrl.destroy();
    rebuildController.close();
    super.dispose();
  }

  Future<Uint8List> _createTransparentImage() async {
    if (_transparentImageBytes != null) return _transparentImageBytes!;

    _transparentImageBytes =
        await createTransparentImage(videoController!.initialResolution);
    return _transparentImageBytes!;
  }
}
