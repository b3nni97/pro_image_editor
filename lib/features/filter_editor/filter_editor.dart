// Dart imports:
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '/core/models/history/editor_history_scope.dart';

import '/shared/widgets/smart_hero.dart';

import '../../core/mixins/editor_callbacks_mixin.dart';
import '../../shared/widgets/extended/interactive_viewer/extended_interactive_viewer.dart';
import '/core/constants/image_constants.dart';
import '/core/mixins/converted_callbacks.dart';
import '/core/mixins/converted_configs.dart';
import '/core/mixins/standalone_editor.dart';
import '/core/models/transform_helper.dart';
import '/core/utils/size_utils.dart';
import '/features/filter_editor/widgets/filter_editor_appbar.dart';
import '/pro_image_editor.dart';
import '/shared/services/content_recorder/widgets/content_recorder.dart';
import '/shared/utils/file_constructor_utils.dart';
import '/shared/widgets/layer/layer_stack.dart';
import '/shared/widgets/layer/interactive_layer_stack.dart';
import '/shared/widgets/transform/transformed_content_generator.dart';
import 'constants/identity_matrix_constant.dart';
import 'utils/lerp_color_matrix_utils.dart';

export 'types/filter_matrix.dart';
export 'utils/filter_generator/filter_addons.dart';
export 'utils/filter_generator/filter_model.dart';
export 'utils/filter_generator/filter_presets.dart';
export 'widgets/filter_editor_item_list.dart';
export 'widgets/filtered_widget.dart';

/// The `FilterEditor` widget allows users to editing images with filters
///
/// You can create a `FilterEditor` using one of the factory methods provided:
/// - `FilterEditor.file`: Loads an image from a file.
/// - `FilterEditor.asset`: Loads an image from an asset.
/// - `FilterEditor.network`: Loads an image from a network URL.
/// - `FilterEditor.memory`: Loads an image from memory as a `Uint8List`.
/// - `FilterEditor.autoSource`: Automatically selects the source based on
/// provided parameters.
class FilterEditor extends StatefulWidget
    with StandaloneEditor<FilterEditorInitConfigs> {
  /// Constructs a `FilterEditor` widget.
  ///
  /// The [key] parameter is used to provide a key for the widget.
  /// The [editorImage] parameter specifies the image to be edited.
  /// The [initConfigs] parameter specifies the initialization configurations
  /// for the editor.
  const FilterEditor._({
    super.key,
    required this.initConfigs,
    this.editorImage,
    this.videoController,
  }) : assert(editorImage != null || videoController != null,
            'Either editorImage or videoController must be provided.');

  /// Constructs a `FilterEditor` widget with image data loaded from memory.
  factory FilterEditor.memory(
    Uint8List byteArray, {
    Key? key,
    required FilterEditorInitConfigs initConfigs,
  }) {
    return FilterEditor._(
      key: key,
      editorImage: EditorImage(byteArray: byteArray),
      initConfigs: initConfigs,
    );
  }

  /// Constructs a `FilterEditor` widget with an image loaded from a file.
  factory FilterEditor.file(
    dynamic file, {
    Key? key,
    required FilterEditorInitConfigs initConfigs,
  }) {
    return FilterEditor._(
      key: key,
      editorImage: EditorImage(file: ensureFileInstance(file)),
      initConfigs: initConfigs,
    );
  }

  /// Constructs a `FilterEditor` widget with an image loaded from an asset.
  factory FilterEditor.asset(
    String assetPath, {
    Key? key,
    required FilterEditorInitConfigs initConfigs,
  }) {
    return FilterEditor._(
      key: key,
      editorImage: EditorImage(assetPath: assetPath),
      initConfigs: initConfigs,
    );
  }

  /// Constructs a `FilterEditor` widget with an image loaded from a network
  /// URL.
  factory FilterEditor.network(
    String networkUrl, {
    Key? key,
    required FilterEditorInitConfigs initConfigs,
  }) {
    return FilterEditor._(
      key: key,
      editorImage: EditorImage(networkUrl: networkUrl),
      initConfigs: initConfigs,
    );
  }

  /// Constructs a `FilterEditor` widget with an image loaded automatically
  /// based on the provided source.
  ///
  /// Either [byteArray], [file], [networkUrl], or [assetPath] must be provided.
  factory FilterEditor.autoSource({
    Key? key,
    Uint8List? byteArray,
    dynamic file,
    String? assetPath,
    String? networkUrl,
    EditorImage? editorImage,
    ProVideoController? videoController,
    required FilterEditorInitConfigs initConfigs,
  }) {
    return FilterEditor._(
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

  /// Constructs a `FilterEditor` widget with an video player.
  factory FilterEditor.video(
    ProVideoController videoController, {
    Key? key,
    required FilterEditorInitConfigs initConfigs,
  }) {
    return FilterEditor._(
      key: key,
      videoController: videoController,
      initConfigs: initConfigs,
    );
  }

  @override
  final FilterEditorInitConfigs initConfigs;
  @override
  final EditorImage? editorImage;
  @override
  final ProVideoController? videoController;

  @override
  createState() => FilterEditorState();
}

/// The state class for the `FilterEditor` widget.
class FilterEditorState extends State<FilterEditor>
    with
        ImageEditorConvertedConfigs,
        ImageEditorConvertedCallbacks,
        StandaloneEditorState<FilterEditor, FilterEditorInitConfigs> {
  /// A key for managing the interactive viewer state.
  final GlobalKey<ExtendedInteractiveViewerState> interactiveViewerKey =
      GlobalKey();

  /// Update the image with the applied filter and the slider value.
  late final StreamController<void> _uiFilterStream;

  /// The ui filter stream to rebuild depending widgets.
  StreamController<void> get uiFilterStream => _uiFilterStream;

  /// The selected filter.
  FilterModel get selectedFilter => _selectedFilter;
  FilterModel _selectedFilter = PresetFilters.none;
  set selectedFilter(FilterModel filter) {
    setFilter(filter);
  }

  /// The opacity of the selected filter, ranging
  /// from 0 (fully transparent) to 1 (fully opaque).
  double get filterOpacity => _filterOpacity;
  double _filterOpacity = 1;
  set filterOpacity(double value) {
    setFilterOpacity(value);
  }

  /// A notifier for the last changed filter.
  ValueNotifier<FilterModel> lastChangedFilterNotifier =
      ValueNotifier(PresetFilters.none);

  /// The opacity of the last changed filter.
  double lastChangedFilterOpacity = 1;

  /// Stores the opacity value per filter (keyed by filter name) so that
  /// switching between filters preserves each filter's individual opacity.
  final Map<String, double> _filterOpacityMap = {};

  /// Undo stack: stores committed (filter, opacity) states.
  final List<_FilterHistoryEntry> _undoStack = [];

  /// Redo stack: stores forward (filter, opacity) states.
  final List<_FilterHistoryEntry> _redoStack = [];

  /// Timer used to commit a filter selection after a delay.
  /// Prevents intermediate filters from polluting the undo stack when the
  /// user scrolls quickly through the filter list.
  Timer? _commitTimer;

  /// The last filter state that was committed to the undo stack.
  /// Used to track the "before" state when committing a new change.
  late _FilterHistoryEntry _lastCommitted = _FilterHistoryEntry(
    filter: _selectedFilter,
    opacity: _filterOpacity,
  );

  /// A version counter that increments on every undo/redo action.
  /// Use this in widget keys to force slider rebuilds when undo/redo
  /// changes opacity without changing the selected filter.
  int historyVersion = 0;

  /// Shortcut to the global history scope from init configs.
  EditorHistoryScope? get _historyScope => initConfigs.historyScope;

  /// Whether global history is active.
  bool get _useGlobalHistory => _historyScope != null;

  /// Whether undo actions can be performed.
  bool get canUndo {
    if (_useGlobalHistory) return _historyScope!.canUndo();
    return _filterOpacity < 1.0 ||
        _undoStack.isNotEmpty ||
        _lastCommitted.filter != _selectedFilter;
  }

  /// Whether redo actions can be performed.
  bool get canRedo {
    if (_useGlobalHistory) return _historyScope!.canRedo();
    return _redoStack.isNotEmpty;
  }

  /// Mutable copy of the layers list for interactive editing.
  late final List<Layer> _mutableLayers;

  /// Whether the layers have been modified during this editing session.
  bool _layersModified = false;

  /// Exports the current layers if they were modified.
  List<Layer>? exportLayers() {
    if (_layersModified) return _mutableLayers;
    return null;
  }

  /// Undoes the last filter change.
  ///
  /// When global history is active, delegates to the main editor's undo.
  /// Otherwise, uses the local two-level undo behavior.
  void undo() {
    if (_useGlobalHistory) {
      if (_historyScope!.canUndo()) {
        _historyScope!.undo();
        _syncFromGlobalState();
      }
      return;
    }

    // Commit any pending filter change first
    commitPendingChange();

    if (_filterOpacity < 1.0) {
      // Level 1: Reset opacity to 1.0, push current state to redo
      _redoStack.add(_FilterHistoryEntry(
        filter: _selectedFilter,
        opacity: _filterOpacity,
      ));
      _filterOpacity = 1.0;
      _filterOpacityMap[_selectedFilter.name] = 1.0;
      _lastCommitted = _FilterHistoryEntry(
        filter: _selectedFilter,
        opacity: 1.0,
      );
      historyVersion++;
      _uiFilterStream.add(null);
      setState(() {});
    } else if (_undoStack.isNotEmpty) {
      // Level 2: Jump to previous filter
      _redoStack.add(_FilterHistoryEntry(
        filter: _selectedFilter,
        opacity: _filterOpacity,
      ));
      final previous = _undoStack.removeLast();
      _selectedFilter = previous.filter;
      _filterOpacity = previous.opacity;
      _filterOpacityMap[_selectedFilter.name] = _filterOpacity;
      _lastCommitted = _FilterHistoryEntry(
        filter: _selectedFilter,
        opacity: _filterOpacity,
      );
      historyVersion++;
      _uiFilterStream.add(null);
      setState(() {});
    }
  }

  /// Redoes the last undone filter change.
  ///
  /// When global history is active, delegates to the main editor's redo.
  void redo() {
    if (_useGlobalHistory) {
      if (_historyScope!.canRedo()) {
        _historyScope!.redo();
        _syncFromGlobalState();
      }
      return;
    }

    if (_redoStack.isNotEmpty) {
      _undoStack.add(_FilterHistoryEntry(
        filter: _selectedFilter,
        opacity: _filterOpacity,
      ));
      final next = _redoStack.removeLast();
      _selectedFilter = next.filter;
      _filterOpacity = next.opacity;
      _filterOpacityMap[_selectedFilter.name] = _filterOpacity;
      _lastCommitted = _FilterHistoryEntry(
        filter: _selectedFilter,
        opacity: _filterOpacity,
      );
      historyVersion++;
      _uiFilterStream.add(null);
      setState(() {});
    }
  }

  /// Synchronizes the local state from the global history after undo/redo.
  void _syncFromGlobalState() {
    // Restore filter state from global history
    final activeFilters = _historyScope!.getActiveFilters();
    final filterList =
        filterEditorConfigs.filterList ?? presetFiltersList;
    if (activeFilters.isNotEmpty &&
        !listEquals(activeFilters.first, identityMatrix)) {
      // Try to find which filter matches
      for (var filter in filterList) {
        if (filter.filters.isNotEmpty &&
            listEquals(filter.filters.first, activeFilters.first)) {
          _selectedFilter = filter;
          _filterOpacity = 1.0;
          break;
        }
      }
    } else {
      _selectedFilter = PresetFilters.none;
      _filterOpacity = 1.0;
    }
    _mutableLayers
      ..clear()
      ..addAll(_historyScope!.getActiveLayers());
    historyVersion++;
    _uiFilterStream.add(null);
    setState(() {});
  }

  /// Commits any pending filter change.
  ///
  /// When global history is active, writes directly to the global history.
  /// Otherwise, uses the local undo stack.
  void commitPendingChange() {
    _commitTimer?.cancel();
    if (_lastCommitted.filter != _selectedFilter) {
      if (_useGlobalHistory) {
        // Global history: save current filter state
        _historyScope!.addHistory(
          filters: _getActiveFilters(),
          layers: _historyScope!.copyLayers(_mutableLayers),
          blockCaptureScreenshot: true,
        );
      } else {
        _undoStack.add(_FilterHistoryEntry(
          filter: _lastCommitted.filter,
          opacity: _lastCommitted.opacity,
        ));
        _redoStack.clear();
      }
      _lastCommitted = _FilterHistoryEntry(
        filter: _selectedFilter,
        opacity: _filterOpacity,
      );
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _mutableLayers = List<Layer>.from(layers ?? []);
    _uiFilterStream = StreamController.broadcast();
    _uiFilterStream.stream.listen((_) => rebuildController.add(null));

    final isMultiSelectionDisabled = !filterEditorConfigs.enableMultiSelection;
    if (isMultiSelectionDisabled &&
        appliedFilters.isNotEmpty &&
        !listEquals(appliedFilters.first, identityMatrix)) {
      _initializeFilterFromApplied();
    }

    filterEditorCallbacks?.onInit?.call();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      filterEditorCallbacks?.onAfterViewInit?.call();
    });
  }

  @override
  void dispose() {
    _commitTimer?.cancel();
    _uiFilterStream.close();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FilterEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (filterEditorConfigs.enableInteractiveLayers) {
      final newLayers = layers ?? [];
      _mutableLayers
        ..clear()
        ..addAll(newLayers);
      _layersModified = false;
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
    commitPendingChange();
    doneEditing(
      editorImage: widget.editorImage,
      returnValue: _getActiveFilters(),
      blur: appliedBlurFactor,
      matrixFilterList: _getActiveFilters(),
      matrixTuneAdjustmentsList:
          appliedTuneAdjustments.map((item) => item.matrix).toList(),
      transform: initialTransformConfigs,
    );
    filterEditorCallbacks?.handleDone();
  }

  /// Exports the current filter matrix state.
  FilterMatrix exportStateHistory() {
    return _getActiveFilters();
  }

  FilterMatrix _getActiveFilters() {
    if (!filterEditorConfigs.enableMultiSelection) {
      if (selectedFilter.filters.isEmpty) {
        return [
          [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0]
        ];
      }
    }

    return [
      if (filterEditorConfigs.enableMultiSelection) ...appliedFilters,
      ...selectedFilter.filters.map(
        (matrix) => lerpColorMatrix(identityMatrix, matrix, filterOpacity),
      ),
    ];
  }

  /// Initializes the selected filter from previously applied filters.
  ///
  /// Searches through the available filter list to find a filter whose matrix
  /// matches the first applied filter. If found, sets it as the selected
  /// filter.
  ///
  /// Because the exported filter matrix may have been lerped with an opacity
  /// value (via [lerpColorMatrix]), both an exact match and a fuzzy
  /// reverse-lerp match are attempted.
  void _initializeFilterFromApplied() {
    final filterList = filterEditorConfigs.filterList ?? presetFiltersList;
    final firstApplied = appliedFilters.first;

    // Pass 1: Exact match (opacity was 1.0)
    for (final filter in filterList) {
      if (filter.filters.isNotEmpty &&
          listEquals(filter.filters.first, firstApplied)) {
        _setFilterInternal(filter);
        return;
      }
    }

    // Pass 2: Fuzzy match — the applied matrix might be
    // lerp(identity, rawFilter, opacity) with opacity < 1.0.
    // Try to reverse-engineer the opacity and verify the match.
    for (final filter in filterList) {
      if (filter.filters.isEmpty) continue;
      final raw = filter.filters.first;
      final opacity = _inferOpacityFromLerp(firstApplied, raw);
      if (opacity != null) {
        _setFilterInternal(filter);
        _filterOpacity = opacity;
        _filterOpacityMap[filter.name] = opacity;
        _lastCommitted = _FilterHistoryEntry(
          filter: _selectedFilter,
          opacity: _filterOpacity,
        );
        return;
      }
    }

    _setFilterInternal(
        FilterModel(name: 'Not-Found', filters: [firstApplied]));
  }

  /// Tries to derive the opacity `t` such that
  /// `lerp(identity, raw, t) ≈ applied` for all 20 matrix elements.
  ///
  /// Returns `t` if a consistent opacity is found, or `null` otherwise.
  double? _inferOpacityFromLerp(
      List<double> applied, List<double> raw) {
    if (applied.length != 20 || raw.length != 20) return null;

    const identity = [
      1.0, 0, 0, 0, 0, //
      0, 1.0, 0, 0, 0, //
      0, 0, 1.0, 0, 0, //
      0, 0, 0, 1.0, 0, //
    ];

    double? inferredT;
    const eps = 1e-6;

    for (int i = 0; i < 20; i++) {
      final identVal = identity[i];
      final rawVal = raw[i];
      final span = rawVal - identVal;
      if (span.abs() < eps) {
        // identity[i] ≈ raw[i], so applied[i] should also ≈ identity[i]
        if ((applied[i] - identVal).abs() > 0.01) return null;
        continue;
      }
      final t = (applied[i] - identVal) / span;
      if (t < -eps || t > 1.0 + eps) return null;
      if (inferredT == null) {
        inferredT = t;
      } else if ((t - inferredT).abs() > 0.01) {
        return null; // inconsistent opacity across elements
      }
    }
    // Reject near-zero opacity: t ≈ 0 means the applied matrix is
    // essentially the identity (no filter), which shouldn't match.
    final result = inferredT?.clamp(0.0, 1.0);
    if (result == null || result < 0.01) return null;
    return result;
  }



  /// Set the current filter.
  ///
  /// Automatically restores the previously saved opacity for this filter
  /// (defaults to 1.0 if no opacity was saved).
  ///
  /// The filter change is not immediately committed to the undo stack.
  /// Instead, a 1-second timer is started. If the user scrolls quickly
  /// through filters, only the final "settled" filter will be committed.
  void setFilter(FilterModel filter) {
    if (_selectedFilter == filter) return;

    _commitTimer?.cancel();
    _selectedFilter = filter;
    _filterOpacity = _filterOpacityMap[filter.name] ?? 1.0;
    _uiFilterStream.add(null);

    // Commit after 1 second of being settled on this filter
    _commitTimer = Timer(const Duration(seconds: 1), commitPendingChange);
  }

  /// Internal filter setter that doesn't start a commit timer.
  /// Used during initialization.
  void _setFilterInternal(FilterModel filter) {
    _selectedFilter = filter;
    _filterOpacity = _filterOpacityMap[filter.name] ?? 1.0;
    _lastCommitted = _FilterHistoryEntry(
      filter: _selectedFilter,
      opacity: _filterOpacity,
    );
    _uiFilterStream.add(null);
  }

  /// Set the current filter opacity.
  void setFilterOpacity(double value) {
    _filterOpacity = value.clamp(0, 1);
    _filterOpacityMap[selectedFilter.name] = _filterOpacity;
    _uiFilterStream.add(null);
    lastChangedFilterNotifier.value = selectedFilter;
    lastChangedFilterOpacity = filterOpacity;
    filterEditorCallbacks?.handleFilterFactorChange(value);
  }

  /// Called when the opacity slider interaction starts.
  /// Commits any pending filter change before the opacity modification.
  void onChangedStart(double value) {
    commitPendingChange();
  }

  /// Handles changes in the filter factor value.
  void onChanged(double value) {
    setFilterOpacity(value);
  }

  /// Handles the end of changes in the filter factor value.
  void onChangedEnd(double value) {
    filterEditorCallbacks?.handleFilterFactorChangeEnd(value);
    setState(() {});
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
        canPop: filterEditorConfigs.enableGesturePop,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: filterEditorConfigs.style.uiOverlayStyle,
          child: SafeArea(
            top: filterEditorConfigs.safeArea.top,
            bottom: filterEditorConfigs.safeArea.bottom,
            left: filterEditorConfigs.safeArea.left,
            right: filterEditorConfigs.safeArea.right,
            child: RecordInvisibleWidget(
              controller: screenshotCtrl,
              child: Scaffold(
                resizeToAvoidBottomInset:
                    filterEditorConfigs.resizeToAvoidBottomInset,
                backgroundColor:
                    filterEditorConfigs.style.background?.call(context) ??
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

  /// Builds the app bar for the filter editor.
  PreferredSizeWidget? _buildAppBar() {
    if (filterEditorConfigs.widgets.appBar != null) {
      return filterEditorConfigs.widgets.appBar!
          .call(this, rebuildController.stream);
    }
    return FilterEditorAppBar(
      filterEditorConfigs: filterEditorConfigs,
      i18n: i18n.filterEditor,
      close: close,
      done: done,
    );
  }

  /// Builds the main content area of the editor.
  Widget _buildBody() {
    return LayoutBuilder(builder: (context, constraints) {
      editorBodySize = constraints.biggest;
      final mainConfigs = configs.filterEditor;

      Widget content = initConfigs.backgroundImageOverride ??
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
              onInteractionStart: (details) {
                callbacks.filterEditorCallbacks?.onEditorZoomScaleStart
                    ?.call(details);
              },
              onInteractionUpdate: (details) {
                callbacks.filterEditorCallbacks?.onEditorZoomScaleUpdate
                    ?.call(details);
              },
              onInteractionEnd: (details) {
                callbacks.filterEditorCallbacks?.onEditorZoomScaleEnd
                    ?.call(details);
              },
              onMatrix4Change: (value) {
                callbacks.filterEditorCallbacks?.onEditorZoomMatrix4Change
                    ?.call(value);
              },
              child: Stack(
                alignment: Alignment.center,
                fit: StackFit.expand,
                children: [
                  if (initConfigs.convertToUint8List && isVideoEditor)
                    _buildBackground(),
                  ContentRecorder(
                    controller: screenshotCtrl,
                    child: Stack(
                      alignment: Alignment.center,
                      fit: StackFit.expand,
                      children: [
                        if (!initConfigs.convertToUint8List || !isVideoEditor)
                          _buildBackground(),
                        if (filterEditorConfigs.showLayers && layers != null)
                          filterEditorConfigs.enableInteractiveLayers
                              ? InteractiveLayerStack(
                                  configs: configs,
                                  callbacks: callbacks,
                                  layers: _mutableLayers,
                                  editorBodySize: editorBodySize,
                                  transformHelper: TransformHelper(
                                    mainBodySize: getValidSizeOrDefault(
                                        mainBodySize, editorBodySize),
                                    mainImageSize: getValidSizeOrDefault(
                                        mainImageSize, editorBodySize),
                                    editorBodySize: editorBodySize,
                                    transformConfigs: initialTransformConfigs,
                                  ),
                                  clipBehavior: Clip.none,
                                  overlayColor: filterEditorConfigs
                                          .style.background
                                          ?.call(context) ??
                                      kImageEditorBackground,
                                  onLayersChanged: () {
                                    _layersModified = true;
                                  },
                                  onBeforeLayerChange: _useGlobalHistory
                                      ? () {
                                          _historyScope!.addHistory(
                                            filters:
                                                _getActiveFilters(),
                                            layers: _historyScope!
                                                .copyLayers(_mutableLayers),
                                            blockCaptureScreenshot: true,
                                          );
                                        }
                                      : null,
                                )
                              : LayerStack(
                                  transformHelper: TransformHelper(
                                    mainBodySize: getValidSizeOrDefault(
                                        mainBodySize, editorBodySize),
                                    mainImageSize: getValidSizeOrDefault(
                                        mainImageSize, editorBodySize),
                                    editorBodySize: editorBodySize,
                                    transformConfigs: initialTransformConfigs,
                                  ),
                                  configs: configs,
                                  layers: layers!,
                                  clipBehavior: Clip.none,
                                  overlayColor: filterEditorConfigs
                                          .style.background
                                          ?.call(context) ??
                                      kImageEditorBackground,
                                ),
                        if (filterEditorConfigs.widgets.bodyItemsRecorded !=
                            null)
                          ...filterEditorConfigs.widgets.bodyItemsRecorded!(
                              this, rebuildController.stream)
                      ],
                    ),
                  ),
                ],
              ),
            );
          });

      if (filterEditorConfigs.widgets.wrapBody != null) {
        content = filterEditorConfigs.widgets.wrapBody!(this, content);
      }

      return Stack(
        alignment: Alignment.center,
        fit: StackFit.expand,
        children: [
          content,
          if (filterEditorConfigs.widgets.bodyItems != null)
            ...filterEditorConfigs.widgets.bodyItems!(
                this, rebuildController.stream),
        ],
      );
    });
  }

  Widget _buildBackground() {
    return SmartHero(
      tag: heroTag,
      child: StreamBuilder(
        stream: _uiFilterStream.stream,
        builder: (context, snapshot) {
          return TransformedContentGenerator(
            isVideoPlayer: videoController != null,
            configs: configs,
            transformConfigs:
                initialTransformConfigs ?? TransformConfigs.empty(),
            child: FilteredWidget(
              width:
                  getValidSizeOrDefault(mainImageSize, editorBodySize).width,
              height:
                  getValidSizeOrDefault(mainImageSize, editorBodySize).height,
              configs: configs,
              image: editorImage,
              videoPlayer: videoController?.videoPlayer,
              blankSize: initConfigs.mainImageSize,
              filters: _getActiveFilters(),
              tuneAdjustments: appliedTuneAdjustments,
              blurFactor: appliedBlurFactor,
            ),
          );
        },
      ),
    );
  }

  /// Builds the Filter Editor Item List
  Widget buildFilterEditorItemList() {
    return StatefulBuilder(builder: (context, setStateFilterList) {
      return FilterEditorItemList(
        editorState: this,
        mainBodySize: getValidSizeOrDefault(mainBodySize, editorBodySize),
        mainImageSize: getValidSizeOrDefault(mainImageSize, editorBodySize),
        editorImage: editorImage,
        image: editorImage != null
            ? null
            : widget.videoController!.thumbnails?.isNotEmpty == true
                ? Image(
                    image: widget.videoController!.thumbnails!.first,
                  )
                : Image.memory(kImageEditorTransparentBytes),
        activeFilters: appliedFilters,
        blurFactor: appliedBlurFactor,
        configs: configs,
        transformConfigs: initialTransformConfigs,
        selectedFilter: selectedFilter.filters,
        previewImageSize: const Size(52, 52),
        onSelectFilter: (filter) {
          setFilter(filter);
          setStateFilterList(() {});
          filterEditorCallbacks?.handleFilterChanged(filter);
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            takeScreenshot();
          });
        },
        lastChangedFilterNotifier: lastChangedFilterNotifier,
      );
    });
  }

  /// Builds the bottom navigation bar with filter options.
  Widget? _buildBottomNavBar() {
    if (filterEditorConfigs.widgets.bottomBar != null) {
      return filterEditorConfigs.widgets.bottomBar!
          .call(this, rebuildController.stream);
    }

    return SafeArea(
      child: Container(
        color: filterEditorConfigs.style.background?.call(context) ??
            kImageEditorBackground,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: RepaintBoundary(
                child: StreamBuilder(
                    stream: _uiFilterStream.stream,
                    builder: (context, snapshot) {
                      return SizedBox(
                        height: 40,
                        child: selectedFilter == PresetFilters.none
                            ? null
                            : filterEditorConfigs.widgets.slider?.call(
                                  this,
                                  rebuildController.stream,
                                  filterOpacity,
                                  onChanged,
                                  onChangedEnd,
                                ) ??
                                Slider(
                                  min: 0,
                                  max: 1,
                                  divisions: 100,
                                  value: filterOpacity,
                                  onChangeStart: onChangedStart,
                                  onChanged: onChanged,
                                  onChangeEnd: onChangedEnd,
                                ),
                      );
                    }),
              ),
            ),
            StatefulBuilder(builder: (context, setStateFilterList) {
              return FilterEditorItemList(
                editorState: this,
                mainBodySize:
                    getValidSizeOrDefault(mainBodySize, editorBodySize),
                mainImageSize:
                    getValidSizeOrDefault(mainImageSize, editorBodySize),
                editorImage: editorImage,
                image: editorImage != null
                    ? null
                    : widget.videoController!.thumbnails?.isNotEmpty == true
                        ? Image(
                            image: widget.videoController!.thumbnails!.first,
                          )
                        : Image.memory(kImageEditorTransparentBytes),
                activeFilters: filterEditorConfigs.enableMultiSelection
                    ? appliedFilters
                    : null,
                blurFactor: appliedBlurFactor,
                configs: configs,
                transformConfigs: initialTransformConfigs,
                selectedFilter: selectedFilter.filters,
                onSelectFilter: (filter) {
                  setFilter(filter);
                  setStateFilterList(() {});
                  filterEditorCallbacks?.handleFilterChanged(filter);
                  WidgetsBinding.instance.addPostFrameCallback((_) async {
                    takeScreenshot();
                  });
                },
                lastChangedFilterNotifier: lastChangedFilterNotifier,
              );
            }),
            // buildFilterEditorItemList(),
          ],
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<FilterEditorInitConfigs>(
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
      ..add(DiagnosticsProperty<FilterModel>(
        'selectedFilter',
        _selectedFilter,
      ))
      ..add(DoubleProperty(
        'filterOpacity',
        _filterOpacity,
      ))
      ..add(IterableProperty<TuneAdjustmentMatrix>(
        'appliedTuneAdjustments',
        appliedTuneAdjustments,
      ))
      ..add(DoubleProperty(
        'appliedBlurFactor',
        appliedBlurFactor,
      ))
      ..add(IterableProperty<List<double>>(
        'appliedFilters',
        filterEditorConfigs.enableMultiSelection ? appliedFilters : [],
      ));
  }
}

/// Internal helper class to store a filter + opacity pair for undo/redo.
class _FilterHistoryEntry {
  _FilterHistoryEntry({
    required this.filter,
    required this.opacity,
  });

  final FilterModel filter;
  final double opacity;
}
