import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:heroine/heroine.dart';

import '/core/constants/editor_various_constants.dart';
import '/core/constants/image_constants.dart';
import '/core/models/history/editor_history_scope.dart';
import '/core/mixins/converted_configs.dart';
import '/core/mixins/editor_callbacks_mixin.dart';
import '/core/mixins/editor_configs_mixin.dart';
import '/core/mixins/standalone_editor.dart';
import '/core/models/init_configs/editor_init_configs.dart';
import '/core/models/styles/draggable_sheet_style.dart';
import '/core/services/gesture_manager.dart';
import '/core/services/mouse_service.dart';
import '/features/main_editor/widgets/main_editor_appbar.dart';
import '/features/main_editor/widgets/main_editor_background_image.dart';
import '/features/main_editor/widgets/main_editor_background_video.dart';
import '/features/main_editor/widgets/main_editor_bottombar.dart';

import '/shared/widgets/layer/interactive_layer_stack.dart';
import '/shared/widgets/layer/services/hero_flight_overrides.dart';

import '/pro_image_editor.dart';
import '/shared/mixins/editor_zoom.mixin.dart';
import '/shared/services/content_recorder/widgets/content_recorder.dart';
import '/shared/services/import_export/export_state_history.dart';

import '/shared/utils/file_constructor_utils.dart';
import '/shared/utils/transparent_image_generator_utils.dart';
import '/shared/widgets/adaptive_dialog.dart';
import '/shared/widgets/extended/interactive_viewer/extended_interactive_viewer.dart';
import '/shared/widgets/screen_resize_detector.dart';
import '../filter_editor/widgets/filter_generator.dart';
import '../paint_editor/models/paint_editor_response_model.dart';
import '../paint_editor/widgets/paint_editor_layer_editor.dart';
import 'controllers/main_editor_controllers.dart';
import 'mixins/main_editor_global_keys.dart';
import 'providers/image_infos_provider.dart';
import 'services/desktop_interaction_manager.dart';
import 'services/layer_copy_manager.dart';
import 'services/layer_drag_selection_service.dart';
import 'services/layer_interaction_manager.dart';
import 'services/main_editor_state_history_service.dart';
import 'services/sizes_manager.dart';
import 'widgets/main_editor_interactive_content.dart';

/// A widget for image editing using ProImageEditor.
///
/// `ProImageEditor` provides a versatile image editing widget for Flutter
/// applications.
/// It allows you to edit images from various sources like memory, files,
/// assets, or network URLs.
///
/// You can use one of the specific constructors, such as `memory`, `file`,
/// `asset`, or `network`,
/// to create an instance of this widget based on your image source.
/// Additionally, you can provide
/// custom configuration settings through the `configs` parameter.
///
/// Example usage:
///
/// ```dart
/// ProImageEditor.memory(Uint8List.fromList(imageBytes));
/// ProImageEditor.file(File('path/to/image.jpg'));
/// ProImageEditor.file('path/to/image.jpg');
/// ProImageEditor.asset('assets/images/image.png');
/// ProImageEditor.network('https://example.com/image.jpg');
/// ```
///
/// To handle image editing, you can use the callbacks provided by the
/// `EditorConfigs` instance
/// passed through the `configs` parameter.
///
/// See also:
/// - [ProImageEditorConfigs] for configuring image editing options.
/// - [ProImageEditorCallbacks] for callbacks.
class ProImageEditor extends StatefulWidget
    with SimpleConfigsAccess, SimpleCallbacksAccess {
  /// Creates a `ProImageEditor` widget for image editing.
  ///
  /// Use one of the specific constructors like `memory`, `file`, `asset`, or
  /// `network`
  /// to create an instance of this widget based on your image source.
  ///
  /// {@template mainEditorConfigs}
  /// ### Parameters
  /// - `key` *(optional)*: A [Key] used to uniquely identify the widget and
  ///   preserve its state during rebuilds.
  /// - `configs` *(optional)*: Defines customization options for the editor.
  ///   If omitted, default settings are applied.
  /// - `callbacks` *(required)*: Provides handlers for editor events and
  ///   user interactions.
  /// {@endtemplate}
  const ProImageEditor._({
    super.key,
    required this.callbacks,
    this.blankSize,
    this.editorImage,
    this.videoController,
    this.configs = const ProImageEditorConfigs(),
  }) : assert(
          editorImage != null || videoController != null || blankSize != null,
          'Either editorImage or videoController or blankSize must be '
          'provided.',
        );

  /// This constructor creates a `ProImageEditor` widget configured to edit an
  /// image loaded from the specified `byteArray`.
  ///
  ///
  /// {@macro mainEditorConfigs}
  /// - `byteArray` *(required)*: The image data as a `Uint8List`.
  ///
  /// Example usage:
  /// ```dart
  /// ProImageEditor.memory(
  ///   bytes,
  /// {@template mainEditorDemoTemplateCode}
  ///   configs: ProImageEditorConfigs(),
  ///   callbacks: ProImageEditorCallbacks(
  ///      onImageEditingComplete: (Uint8List bytes) async {
  ///        /*
  ///          `Your code to handle the edited image. Upload it to your server
  ///           as an example.
  ///
  ///           You can choose to use await, so that the load dialog remains
  ///           visible until your code is ready,
  ///           or no async, so that the load dialog closes immediately.
  ///        */
  ///        Navigator.pop(context);
  ///      },
  ///   ),
  /// {@endtemplate}
  /// )
  /// ```
  factory ProImageEditor.memory(
    Uint8List byteArray, {
    Key? key,
    required ProImageEditorCallbacks callbacks,
    ProImageEditorConfigs configs = const ProImageEditorConfigs(),
  }) {
    return ProImageEditor._(
      key: key,
      editorImage: EditorImage(byteArray: byteArray),
      configs: configs,
      callbacks: callbacks,
    );
  }

  /// This constructor creates a `ProImageEditor` widget configured to edit an
  /// image loaded from the specified `file`.
  ///
  /// {@macro mainEditorConfigs}
  /// - `file` *(required)*: The image data as a `File` or a `String` which is
  /// the path to the file.
  ///
  /// Example usage:
  /// ```dart
  /// ProImageEditor.file(
  ///   File(pathToMyFile),
  ///   {@macro mainEditorDemoTemplateCode}
  /// )
  /// ```
  factory ProImageEditor.file(
    dynamic file, {
    Key? key,
    ProImageEditorConfigs configs = const ProImageEditorConfigs(),
    required ProImageEditorCallbacks callbacks,
  }) {
    return ProImageEditor._(
      key: key,
      editorImage: EditorImage(file: ensureFileInstance(file)),
      configs: configs,
      callbacks: callbacks,
    );
  }

  /// This constructor creates a `ProImageEditor` widget configured to edit an
  /// image loaded from the specified `assetPath`.
  ///
  /// {@macro mainEditorConfigs}
  /// - `assetPath` *(required)*: The path to the image data in the local
  /// assets folder.
  ///
  /// Example usage:
  /// ```dart
  /// ProImageEditor.asset(
  ///   'assets/demo.png',
  ///   {@macro mainEditorDemoTemplateCode}
  /// )
  /// ```
  factory ProImageEditor.asset(
    String assetPath, {
    Key? key,
    ProImageEditorConfigs configs = const ProImageEditorConfigs(),
    required ProImageEditorCallbacks callbacks,
  }) {
    return ProImageEditor._(
      key: key,
      editorImage: EditorImage(assetPath: assetPath),
      configs: configs,
      callbacks: callbacks,
    );
  }

  /// This constructor creates a `ProImageEditor` widget configured to edit an
  /// image loaded from the specified `networkUrl`.
  ///
  /// {@macro mainEditorConfigs}
  /// - `networkUrl` *(required)*: The URL from which the image should be
  /// loaded.
  /// - `networkHeaders` *(optional)*: HTTP headers to include when fetching
  /// the image (e.g., for authentication).
  ///
  /// Example usage:
  /// ```dart
  /// ProImageEditor.network(
  ///   'https://example.com/image.jpg',
  ///   {@macro mainEditorDemoTemplateCode}
  /// )
  /// ```
  factory ProImageEditor.network(
    String networkUrl, {
    Key? key,
    Map<String, String>? networkHeaders,
    ProImageEditorConfigs configs = const ProImageEditorConfigs(),
    required ProImageEditorCallbacks callbacks,
  }) {
    return ProImageEditor._(
      key: key,
      editorImage: EditorImage(
        networkUrl: networkUrl,
        networkHeaders: networkHeaders,
      ),
      configs: configs,
      callbacks: callbacks,
    );
  }

  /// Creates a `ProImageEditor` instance by automatically determining the
  /// image source.
  ///
  /// This factory constructor intelligently selects the appropriate image
  /// loading method based on the provided parameters. It allows for seamless
  /// integration without requiring users to manually specify whether the image
  /// is from memory, a file, a network URL, or an asset.
  ///
  /// The selection is based on the first non-null parameter in the following
  /// order of priority:
  /// 1. `byteArray` (raw image data in memory)
  /// 2. `file` (local file system)
  /// 3. `networkUrl` (image from a remote URL)
  /// 4. `assetPath` (image stored as an app asset)
  ///
  /// Additionally, an `EditorImage` instance can be provided, which may contain
  /// any of the above sources, and will be processed in the same priority
  /// order.
  ///
  /// {@macro mainEditorConfigs}
  ///
  /// Example usage:
  /// ```dart
  /// ProImageEditor.autoSource(
  ///   byteArray: imageData,
  ///   callbacks: editorCallbacks,
  ///   configs: ProImageEditorConfigs(),
  /// )
  ///
  /// ProImageEditor.autoSource(
  ///   file: File('path/to/image.jpg'),
  ///   callbacks: editorCallbacks,
  /// )
  ///
  /// ProImageEditor.autoSource(
  ///   networkUrl: 'https://example.com/image.jpg',
  ///   callbacks: editorCallbacks,
  /// )
  ///
  /// ProImageEditor.autoSource(
  ///   assetPath: 'assets/images/sample.jpg',
  ///   callbacks: editorCallbacks,
  /// )
  ///
  /// ProImageEditor.autoSource(
  ///   editorImage: EditorImage(file: File('path/to/image.jpg')),
  ///   callbacks: editorCallbacks,
  /// )
  /// ```
  ///
  /// Throws an [ArgumentError] if no valid image source is provided.
  factory ProImageEditor.autoSource({
    Key? key,
    Uint8List? byteArray,
    dynamic file,
    String? assetPath,
    String? networkUrl,
    Map<String, String>? networkHeaders,
    EditorImage? editorImage,
    ProVideoController? videoController,
    ProImageEditorConfigs configs = const ProImageEditorConfigs(),
    required ProImageEditorCallbacks callbacks,
  }) {
    return ProImageEditor._(
      key: key,
      editorImage: editorImage ??
          EditorImage(
            byteArray: byteArray,
            file: file,
            networkUrl: networkUrl,
            networkHeaders: networkHeaders,
            assetPath: assetPath,
          ),
      videoController: videoController,
      configs: configs,
      callbacks: callbacks,
    );
  }

  /// Creates a blank ProImageEditor with the specified size.
  ///
  /// This constructor initializes a `ProImageEditor` with a blank canvas
  /// of the given [size].
  ///
  /// The [size] is also used to set the maximum output size for
  /// image generation in the editor configuration.
  ///
  /// {@macro mainEditorConfigs}
  ///
  /// Example usage:
  /// ```dart
  /// ProImageEditor.blank(
  ///   Size(1080, 1920),
  ///   {@macro mainEditorDemoTemplateCode}
  /// )
  /// ```
  factory ProImageEditor.blank(
    Size size, {
    Key? key,
    ProImageEditorConfigs configs = const ProImageEditorConfigs(),
    required ProImageEditorCallbacks callbacks,
  }) {
    return ProImageEditor._(
      key: key,
      blankSize: size,
      configs: configs.copyWith(
        imageGeneration: configs.imageGeneration.copyWith(maxOutputSize: size),
      ),
      callbacks: callbacks,
    );
  }

  /// This constructor creates a `ProImageEditor` widget configured to edit an
  /// video.
  ///
  /// {@macro mainEditorConfigs}
  /// - `videoController` *(required)*: The video-controller to control the
  /// video.
  ///
  /// Example usage:
  ///
  /// - [Example with video_player](https://github.com/hm21/pro_image_editor/blob/stable/example/lib/features/video_examples/pages/video_player_example.dart)
  /// - [Example with media_kit](https://github.com/hm21/pro_image_editor/blob/stable/example/lib/features/video_examples/pages/video_media_kit_example.dart)
  /// - [Example with chewie_player](https://github.com/hm21/pro_image_editor/blob/stable/example/lib/features/video_examples/pages/chewie_player_example.dart)
  /// - [Example with flick_video_player](https://github.com/hm21/pro_image_editor/blob/stable/example/lib/features/video_examples/pages/flick_video_player_example.dart)
  factory ProImageEditor.video(
    ProVideoController videoController, {
    Key? key,
    ProImageEditorConfigs configs = const ProImageEditorConfigs(),
    required ProImageEditorCallbacks callbacks,
  }) {
    return ProImageEditor._(
      key: key,
      videoController: videoController,
      configs: configs,
      callbacks: callbacks,
    );
  }

  @override
  final ProImageEditorConfigs configs;
  @override
  final ProImageEditorCallbacks callbacks;

  /// The image being edited in the editor.
  final EditorImage? editorImage;

  /// The controller for the video editor.
  final ProVideoController? videoController;

  /// The size of the blank canvas when no image/video is present.
  final Size? blankSize;

  @override
  State<ProImageEditor> createState() => ProImageEditorState();
}

/// State class for the ProImageEditor widget, handling configurations
/// and user interactions for image editing.
class ProImageEditorState extends State<ProImageEditor>
    with
        ImageEditorConvertedConfigs,
        SimpleConfigsAccessState,
        SimpleCallbacksAccessState,
        MainEditorGlobalKeys,
        EditorZoomMixin {
  final _bottomBarKey = GlobalKey();
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _backgroundImageColorFilterKey = GlobalKey<ColorFilterGeneratorState>();
  @override
  final interactiveViewer = GlobalKey<ExtendedInteractiveViewerState>();
  late final StreamController<void> _rebuildController;

  /// Helper class for managing sizes and layout calculations.
  late final SizesManager sizesManager;

  /// Manager class for handling desktop interactions in the image editor.
  late final DesktopInteractionManager _desktopInteractionManager;

  /// Manager class to copy layers.
  final LayerCopyManager _layerCopyManager = LayerCopyManager();

  /// Helper class for managing interactions with layers in the editor.
  late final LayerInteractionManager layerInteractionManager =
      LayerInteractionManager(
    onSelectedLayerChanged: mainEditorCallbacks?.onSelectedLayerChanged,
    onSelectedLayersChanged: mainEditorCallbacks?.onSelectedLayersChanged,
    helperLinesCallbacks: mainEditorCallbacks?.helperLines,
    configs: configs,
  );
  late final _mouseService = MouseService(
    configs: configs,
    interactionManager: layerInteractionManager,
  );

  /// Manager class for managing the state of the editor.
  late final StateManager stateManager = StateManager(
    activeBackgroundImage: widget.editorImage,
    onStateHistoryChange: () =>
        mainEditorCallbacks?.onStateHistoryChange?.call(stateManager, this),
  );

  /// Provides sub-editors with access to the global history system.
  late final EditorHistoryScope _editorHistoryScope = EditorHistoryScope(
    addHistory: ({
      List<Layer>? layers,
      FilterMatrix? filters,
      List<TuneAdjustmentMatrix>? tuneAdjustments,
      double? blur,
      bool blockCaptureScreenshot = false,
    }) {
      addHistory(
        layers: layers,
        filters: filters,
        tuneAdjustments: tuneAdjustments,
        blur: blur,
        blockCaptureScreenshot: blockCaptureScreenshot,
      );
    },
    undo: () {
      if (stateManager.canUndo) {
        layerInteractionManager.clearSelectedLayers();
        _checkInteractiveViewer();
        stateManager.undo();
        decodeImage();
      }
    },
    redo: () {
      if (stateManager.canRedo) {
        layerInteractionManager.clearSelectedLayers();
        _checkInteractiveViewer();
        stateManager.redo();
        decodeImage();
      }
    },
    canUndo: () => stateManager.canUndo,
    canRedo: () => stateManager.canRedo,
    getActiveLayers: () =>
        _layerCopyManager.copyLayerList(stateManager.activeLayers),
    getActiveTuneAdjustments: () => stateManager.activeTuneAdjustments,
    getActiveFilters: () => stateManager.activeFilters,
    getActiveBlur: () => stateManager.activeBlur,
    copyLayers: (layers) => _layerCopyManager.copyLayerList(layers),
  );
  late final _stateHistoryService = MainEditorStateHistoryService(
    sizesManager: sizesManager,
    stateManager: stateManager,
    controllers: _controllers,
    configs: configs,
    mainEditorCallbacks: mainEditorCallbacks,
    takeScreenshot: _takeScreenshot,
  );

  /// Controller instances for managing various aspects of the main editor.
  late final MainEditorControllers _controllers;

  late final _layerDragSelectionService = LayerDragSelectionService(
    layerInteractionManager: layerInteractionManager,
    activeLayers: () => activeLayers,
    bodySize: () => sizesManager.bodySize,
    configs: configs,
    onUpdateLayers: () => _controllers.uiLayerCtrl.add(null),
    interactiveViewer: () => interactiveViewer.currentState,
  );

  /// The current theme used by the image editor.
  late ThemeData _theme;

  /// Flag indicating if the editor has been initialized.
  bool _isInitialized = false;

  /// Whether the initial crop animation is currently playing.
  bool _isCropAnimating = false;

  /// Whether the background override for embedded sub-editors is still active.
  /// Starts true and switches to false after hero + crop animations complete.
  bool _isBackgroundOverrideActive = true;

  /// Flag indicating if the image needs decoding.
  bool _isImageNotDecoded = true;

  /// Flag to track if editing is completed.
  bool _isProcessingFinalImage = false;

  /// The pixel ratio of the device's screen.
  ImageInfos? _imageInfos;

  /// Indicates whether a sub-editor is currently open.
  bool isSubEditorOpen = false;

  /// Indicates whether a sub-editor is in the process of closing.
  bool isSubEditorClosing = false;

  /// Which sub-editor is currently open (from open until its close transition
  /// is fully dismissed).
  ///
  /// Used to keep Hero animations on the main-editor layers enabled for the
  /// *entire* TextEditor session — open, while open, and close. Enabling them
  /// only at the closing frame caused a one-frame flash where the destination
  /// layer painted at its final spot before the hero flight engaged.
  ///
  /// Scoped to the text editor on purpose: the tune/filter/blur/paint editors
  /// render their own copies of the (hero-tagged) layers via
  /// `backgroundImageOverride`, so enabling main-page heroes during *their*
  /// session would create duplicate-tag conflicts.
  SubEditor _activeSubEditor = SubEditor.unknown;

  /// Whether the open TextEditor route is stacked on top of another pushed
  /// sub-editor route (e.g. text tapped inside the filter editor). In that
  /// case the layer heroes of the editor BELOW (which renders its own
  /// hero-tagged copies) drive the flight, so the main editor's heroes must
  /// stay disabled to avoid duplicate-tag conflicts.
  bool _isTextOverSubEditor = false;

  /// Whether a dialog is currently open.
  bool _isDialogOpen = false;

  /// Whether a context menu is currently open.
  bool _isContextMenuOpen = false;

  /// Indicates whether the `onScaleUpdate` function can be triggered to
  /// interact with the layers.
  bool blockOnScaleUpdateFunction = false;

  /// Indicates whether the browser's context menu was enabled before any
  /// changes.
  bool _browserContextMenuBeforeEnabled = false;

  /// Indicates whether PopScope is disabled.
  bool isPopScopeDisabled = false;

  bool _isVideoPlayerReady = true;

  /// Whether a layer is currently being transformed
  /// (e.g., moved, scaled, or rotated).
  bool isLayerBeingTransformed = false;

  /// Returns `true` if one or more layers are currently selected.
  bool get hasSelectedLayers => layerInteractionManager.hasSelectedLayers;

  /// Returns the most recently selected layer, or `null` if no layer is
  /// selected.
  Layer? get selectedLayer => hasSelectedLayers
      ? () {
          final mostRecentSelectedLayerIndex = activeLayers.lastIndexWhere(
              (layer) =>
                  layerInteractionManager.selectedLayerIds.contains(layer.id));
          return mostRecentSelectedLayerIndex >= 0
              ? activeLayers[mostRecentSelectedLayerIndex]
              : null;
        }()
      : null;

  /// Returns a list of all currently selected layers.
  List<Layer> get selectedLayers => activeLayers
      .where(
        (layer) => layerInteractionManager.selectedLayerIds.contains(layer.id),
      )
      .toList();

  /// Get the list of layers from the current image editor changes.
  List<Layer> get activeLayers => stateManager.activeLayers;

  /// List to store the history of image editor changes.
  List<EditorStateHistory> get stateHistory => stateManager.stateHistory;

  /// Determines whether undo actions can be performed.
  ///
  /// Checks local sub-editors first (paint, cropRotate). For tune/filter/blur,
  /// the stateManager already includes their changes.
  bool get canUndo {
    if (_isSubEditorActive) {
      final subUndo = _activeLocalSubEditorCanUndo;
      if (subUndo != null && subUndo) return true;
    }
    return stateManager.canUndo;
  }

  /// Determines whether redo actions can be performed.
  bool get canRedo {
    if (_isSubEditorActive) {
      final subRedo = _activeLocalSubEditorCanRedo;
      if (subRedo != null && subRedo) return true;
    }
    return stateManager.canRedo;
  }

  /// Whether a sub-editor is currently active (either via page navigation
  /// or embedded via `initialSubEditor`).
  bool get _isSubEditorActive =>
      isSubEditorOpen || mainEditorConfigs.initialSubEditor != null;

  /// Returns the active LOCAL sub-editor's canUndo (only paint, cropRotate).
  /// Tune/Filter/Blur use global history so their canUndo is handled
  /// by stateManager.canUndo.
  bool? get _activeLocalSubEditorCanUndo {
    if (paintEditor.currentState != null) {
      return paintEditor.currentState!.canUndo;
    }
    if (cropRotateEditor.currentState != null) {
      return cropRotateEditor.currentState!.canUndo;
    }
    return null;
  }

  /// Returns the active LOCAL sub-editor's canRedo (only paint, cropRotate).
  bool? get _activeLocalSubEditorCanRedo {
    if (paintEditor.currentState != null) {
      return paintEditor.currentState!.canRedo;
    }
    if (cropRotateEditor.currentState != null) {
      return cropRotateEditor.currentState!.canRedo;
    }
    return null;
  }

  /// Indicates whether video editor is enabled.
  late final bool _isVideoEditor = widget.videoController != null;

  /// Determines whether multi-select mode is always enabled.
  ///
  /// If set to `true`, multi-select mode will be active without requiring
  /// the user to hold down CTRL/ SHIFT keys or long-press. This allows
  /// for easier selection of multiple items.
  bool get enableMultiSelectMode => _enableMultiSelectMode;
  bool _enableMultiSelectMode = false;
  set enableMultiSelectMode(bool value) {
    _enableMultiSelectMode = value;
    setState(() {});
  }

  /// Get the current background image.
  EditorImage? get editorImage => stateManager.activeBackgroundImage;

  /// A [Completer] used to track the completion of a page open operation.
  ///
  /// The completer is initialized and can be used to await the page open
  /// operation.
  Completer<bool> _pageOpenCompleter = Completer();

  /// A [Completer] used to track the completion of an image decoding operation.
  ///
  /// The completer is initialized and can be used to await the image
  /// decoding operation.
  final Completer<bool> _decodeImageCompleter = Completer();

  PointerEvent? _lastDownEvent;
  DateTime _tapDownTimestamp = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initializeVideoEditor();

    _rebuildController = StreamController.broadcast();
    _controllers = MainEditorControllers(configs, callbacks, _isVideoEditor);
    _desktopInteractionManager = DesktopInteractionManager(
      configs: configs,
      callbacks: callbacks,
      context: context,
      onUpdateUI: mainEditorCallbacks?.handleUpdateUI,
      setState: setState,
    );
    sizesManager = SizesManager(configs: configs, context: context);
    layerInteractionManager.scaleDebounce = Debounce(
      const Duration(milliseconds: 100),
    );

    /// For the case the user add transformConfigs we initialize the editor with
    /// this configurations and not the empty history
    if (mainEditorConfigs.transformSetup != null) {
      _initializeWithTransformations();
    } else {
      stateManager.addHistory(
        EditorStateHistory(
          transformConfigs: TransformConfigs.empty().copyWith(
            cropMode: cropRotateEditorConfigs.initialCropMode,
          ),
          blur: 0,
          layers: [],
          filters: [],
          tuneAdjustments: [],
        ),
      );
    }

    ServicesBinding.instance.keyboard.addHandler(_onKeyEvent);
    if (kIsWeb) {
      _browserContextMenuBeforeEnabled = BrowserContextMenu.enabled;
      BrowserContextMenu.disableContextMenu();
    }
    mainEditorCallbacks?.onInit?.call();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      mainEditorCallbacks?.onAfterViewInit?.call();
      _calcAppBarHeight();
    });
  }

  @override
  void dispose() {
    _prewarmedKeyboardConnection?.close();
    _rebuildController.close();
    _controllers.dispose();
    layerInteractionManager.scaleDebounce.dispose();
    SystemChrome.setSystemUIOverlayStyle(
      _theme.brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    );
    SystemChrome.restoreSystemUIOverlays();
    ServicesBinding.instance.keyboard.removeHandler(_onKeyEvent);
    if (kIsWeb && _browserContextMenuBeforeEnabled) {
      BrowserContextMenu.enableContextMenu();
    }
    super.dispose();
  }

  @override
  void setState(void Function() fn) {
    _rebuildController.add(null);
    super.setState(fn);
  }

  void _checkInteractiveViewer() {
    if (mainEditorConfigs.canZoomWhenLayerSelected) return;
    interactiveViewer.currentState?.setEnableInteraction(!hasSelectedLayers);
  }

  /// Handle keyboard events
  bool _onKeyEvent(KeyEvent event) {
    return _desktopInteractionManager.onKey(
      event,
      selectedLayers: selectedLayers,
      onEscape: () {
        if (!_isDialogOpen && !_isContextMenuOpen) {
          if (isSubEditorOpen) {
            if (!mainEditorConfigs.style.subEditorPage.barrierDismissible) {
              if (cropRotateEditor.currentState != null) {
                // Important to close the crop-editor like that cuz we need to
                // set the fake hero first
                cropRotateEditor.currentState!.close();
              } else {
                Navigator.pop(context);
              }
            }
          } else {
            closeEditor();
          }
        }
      },
      onUndoRedo: (undo) {
        if (_isDialogOpen || isSubEditorOpen) return;

        undo ? undoAction() : redoAction();
      },
    );
  }

  /// Adds a new state to the history with the given configuration and updates
  /// the state manager.
  ///
  /// This method is responsible for capturing the current state of the editor,
  /// including layers, transformations, filters, and blur settings. It then
  /// adds this state to the history, enabling undo and redo functionality.
  /// Additionally, it can take a screenshot if required.
  ///
  /// - [layers]: An optional list of layers to be included in the new state.
  /// - [newLayer]: An optional new layer to be added to the current layers.
  /// - [transformConfigs]: Optional transformation configurations for the new
  /// state.
  /// - [filters]: An optional list of filter states to be included in the new
  /// state.
  /// - [tuneAdjustments]: An optional list of tune adjustments states to be
  /// included in the new state.
  /// - [blur]: An optional blur state to be included in the new state.
  /// - [heroScreenshotRequired]: A flag indicating whether a hero screenshot
  /// is required.
  ///
  /// Example usage:
  /// ```dart
  /// addHistory(
  ///   layers: currentLayers,
  ///   newLayer: additionalLayer,
  ///   transformConfigs: currentTransformConfigs,
  ///   filters: currentFilters,
  ///   tuneAdjustments: currentTuneAdjustments
  ///   blur: currentBlurState,
  ///   heroScreenshotRequired: false,
  /// );
  /// ```
  void addHistory({
    List<Layer>? layers,
    Layer? newLayer,
    TransformConfigs? transformConfigs,
    FilterMatrix? filters,
    List<TuneAdjustmentMatrix>? tuneAdjustments,
    double? blur,
    bool heroScreenshotRequired = false,
    bool blockCaptureScreenshot = false,
  }) {
    List<Layer> activeLayerList = _layerCopyManager.copyLayerList(activeLayers);

    stateManager.addHistory(
      EditorStateHistory(
        transformConfigs: transformConfigs,
        blur: blur,
        layers: layers ??
            (newLayer != null
                ? [...activeLayerList, newLayer]
                : activeLayerList),
        filters: filters ?? [],
        tuneAdjustments: tuneAdjustments ?? [],
      ),
      historyLimit: stateHistoryConfigs.stateHistoryLimit,
      enableScreenshotLimit: imageGenerationConfigs.enableBackgroundGeneration,
    );
    if (!blockCaptureScreenshot) {
      if (!heroScreenshotRequired) {
        _takeScreenshot();
      } else {
        stateManager.heroScreenshotRequired = true;
      }
    } else {
      _controllers.screenshot.addEmptyScreenshot(
        screenshots: stateManager.screenshots,
      );
    }
    setState(() {});
  }

  /// Replaces a layer at the specified index with a new layer.
  ///
  /// This method updates the current layer at the given [index] in the list of
  /// active layers with the specified [layer]. It also resets the
  /// `selectedLayerId` in the `layerInteractionManager` to an empty string,
  /// effectively deselecting any currently selected layer. Additionally, it
  /// adds the updated list of layers to the history, enabling undo/redo
  /// functionality, and triggers a UI update by sending a null event to the
  /// UI layer controller.
  ///
  /// This is useful when you need to modify an existing layer while maintaining
  /// the rest of the layer order and history tracking.
  ///
  /// Parameters:
  /// - [index]: The index of the layer to be replaced. Must be within the
  ///   bounds of the current list of active layers.
  /// - [layer]: The new `Layer` instance that will replace the existing layer
  ///   at the specified index.
  ///
  /// Example usage:
  /// ```dart
  /// replaceLayer(index: 2, layer: newLayer);
  /// ```
  void replaceLayer({required int index, required Layer layer}) {
    layerInteractionManager.clearSelectedLayers();

    addHistory(
      layers: _layerCopyManager.copyLayerList(activeLayers)
        ..removeAt(index)
        ..insert(index, layer),
    );

    _controllers.uiLayerCtrl.add(null);
  }

  /// Returns the [ExtendedInteractiveViewer] that currently holds the live
  /// zoom/pan state.
  ///
  /// When a sub-editor is embedded (e.g. via
  /// [MainEditorConfigs.initialSubEditor]) and mounted, that sub-editor
  /// renders its own interactive viewer, so the
  /// zoom the user applied lives there — not in the main editor's viewer.
  /// In all other cases the main editor's viewer is the active one.
  ///
  /// When a sub-editor reuses the main editor's content via
  /// `backgroundImageOverride`, it does not build its own viewer, so its
  /// `interactiveViewerKey.currentState` is `null` and we correctly fall
  /// through to [interactiveViewer].
  ExtendedInteractiveViewerState? get _activeInteractiveViewer {
    return tuneEditor.currentState?.interactiveViewerKey.currentState ??
        filterEditor.currentState?.interactiveViewerKey.currentState ??
        interactiveViewer.currentState;
  }

  /// The viewer that holds the authoritative zoom state for editors that
  /// take part in zoom sharing (see [ZoomConfigs.enableShareZoomMatrix]):
  /// the embedded sub-editor's viewer when one is configured (falling back
  /// to the main viewer while the embedded editor still renders via
  /// `backgroundImageOverride`), otherwise the main editor's viewer.
  ///
  /// Pushed sub-editors with sharing enabled are seeded from this viewer's
  /// matrix and live-sync their zoom back into it, so switching between
  /// sub-editors keeps the current zoom instead of resetting it.
  ExtendedInteractiveViewerState? get _sharedZoomViewer {
    switch (mainEditorConfigs.initialSubEditor) {
      case SubEditorMode.tune:
        return tuneEditor.currentState?.interactiveViewerKey.currentState ??
            interactiveViewer.currentState;
      case SubEditorMode.filter:
        return filterEditor.currentState?.interactiveViewerKey.currentState ??
            interactiveViewer.currentState;
      default:
        return interactiveViewer.currentState;
    }
  }

  /// Adjusts [layer]'s offset and scale so that — when added while the active
  /// interactive viewer is zoomed/panned — it lands at the center of the
  /// *currently visible* area at the correct visual size, instead of the
  /// absolute image center.
  ///
  /// Reads the active viewer via [_activeInteractiveViewer] so it works both
  /// from the main editor and from an embedded sub-editor (TuneEditor,
  /// FilterEditor).
  void _applyViewerZoomCorrection(
    Layer layer, {
    bool autoCorrectZoomOffset = true,
    bool autoCorrectZoomScale = true,
  }) {
    final viewer = _activeInteractiveViewer;
    if (viewer == null) return;

    final scaleDelta = viewer.scaleFactor;

    if (autoCorrectZoomScale) {
      layer.scale /= scaleDelta;
    }
    if (autoCorrectZoomOffset) {
      final bodySize = sizesManager.bodySize;
      final bodyCenter = Offset(bodySize.width / 2, bodySize.height / 2);

      // Place the layer at the content currently under the *frame center* —
      // the screen position where the image center sits in the default (fit)
      // view. Computing this relative to the initial matrix makes it correct
      // regardless of letterboxing/insets:
      //  • un-zoomed → the image center (the layer maps through the same fit
      //    transform as the image, so offset stays 0),
      //  • zoomed/panned → the center of what's currently visible.
      // The previous absolute formula treated the fit transform itself as
      // "zoom", which pushed un-zoomed layers off the image center.
      final frameScreenPoint =
          MatrixUtils.transformPoint(viewer.initialMatrix4, bodyCenter);
      final contentPoint = MatrixUtils.transformPoint(
        Matrix4.inverted(viewer.transformMatrix4),
        frameScreenPoint,
      );
      layer.offset += contentPoint - bodyCenter;
    }
  }

  /// Add a new layer to the image editor.
  ///
  /// This method adds a new layer to the image editor and updates the editing
  /// state.
  void addLayer(
    Layer layer, {
    int removeLayerIndex = -1,
    bool blockSelectLayer = false,
    bool blockCaptureScreenshot = false,
    bool autoCorrectZoomOffset = true,
    bool autoCorrectZoomScale = true,
  }) {
    void correctOffset() {
      Offset fractionalOffset = const Offset(-0.5, -0.5);
      if (layer.isTextLayer) {
        fractionalOffset = textEditorConfigs.layerFractionalOffset;
      } else if (layer.isEmojiLayer) {
        fractionalOffset = emojiEditorConfigs.layerFractionalOffset;
      } else if (layer.isPaintLayer) {
        fractionalOffset = paintEditorConfigs.layerFractionalOffset;
      } else if (layer.isWidgetLayer) {
        fractionalOffset = stickerEditorConfigs.layerFractionalOffset;
      }

      if (fractionalOffset != const Offset(-0.5, -0.5)) {
        final overlayPadding = layerInteraction.style.overlayPadding;
        double dxCorrected = 0;
        double dyCorrected = 0;

        if (fractionalOffset.dx == 0) {
          dxCorrected = -overlayPadding.left;
        } else if (fractionalOffset.dx == 1) {
          dxCorrected = overlayPadding.right;
        }
        if (fractionalOffset.dy == 0) {
          dyCorrected = -overlayPadding.top;
        } else if (fractionalOffset.dy == 1) {
          dyCorrected = overlayPadding.bottom;
        }

        layer.offset += Offset(dxCorrected, dyCorrected);
      }
    }

    correctOffset();

    _applyViewerZoomCorrection(
      layer,
      autoCorrectZoomOffset: autoCorrectZoomOffset,
      autoCorrectZoomScale: autoCorrectZoomScale,
    );

    addHistory(newLayer: layer, blockCaptureScreenshot: blockCaptureScreenshot);

    if (removeLayerIndex >= 0) {
      activeLayers.removeAt(removeLayerIndex);
    }
    if (!blockSelectLayer && layer.interaction.enableSelection) {
      layerInteractionManager.addSelectedLayer(layer.id);
    }
    _checkInteractiveViewer();

    mainEditorCallbacks?.handleAddLayer(layer);
    setState(() {});
  }

  /// Remove a layer from the editor.
  ///
  /// This method removes a layer from the editor and updates the editing state.
  void removeLayer(Layer layer, {bool blockCaptureScreenshot = false}) {
    int layerPos = activeLayers.indexOf(layer);
    if (layerPos < 0) return;

    mainEditorCallbacks?.handleRemoveLayer(layer);

    var layers = _layerCopyManager.copyLayerList(activeLayers)
      ..removeAt(layerPos);

    addHistory(layers: layers, blockCaptureScreenshot: blockCaptureScreenshot);
    setState(() {});
  }

  /// Remove all layers from the editor.
  ///
  /// This method removes all layers from the editor and updates the editing
  /// state.
  void removeAllLayers() {
    addHistory(layers: []);
    setState(() {});
  }

  void _initializeVideoEditor() async {
    if (!_isVideoEditor) return;

    _isVideoPlayerReady = false;

    widget.videoController!.initialize(
      configsFunction: () => configs.videoEditor,
      callbacksFunction: () =>
          callbacks.videoEditorCallbacks ?? VideoEditorCallbacks(),
    );

    final resolution = widget.videoController!.initialResolution;
    stateManager.activeBackgroundImage = EditorImage(
      byteArray: await createTransparentImage(resolution),
    );
    _isVideoPlayerReady = true;

    if (!mounted) return;

    setState(() {});
    await decodeImage();
  }

  void _initializeWithTransformations() {
    var transformSetup = mainEditorConfigs.transformSetup!;

    /// Add the initial history
    stateManager.addHistory(
      EditorStateHistory(
        transformConfigs: transformSetup.transformConfigs,
        blur: 0,
        layers: [],
        filters: [],
        tuneAdjustments: [],
      ),
    );

    /// Set the decoded image infos for the case they are not empty
    if (transformSetup.imageInfos != null) {
      _imageInfos = transformSetup.imageInfos!;
      decodeImage(transformSetup.transformConfigs, transformSetup.imageInfos);
    }
  }

  /// Decode the image being edited.
  ///
  /// This method decodes the image if it hasn't been decoded yet and updates
  /// its properties.
  Future<void> decodeImage([
    TransformConfigs? transformConfigs,
    ImageInfos? imageInfos,
  ]) async {
    if (widget.blankSize != null) {
      final blankSize = widget.blankSize!;
      imageInfos ??= ImageInfos(
        rawSize: blankSize,
        renderedSize: blankSize,
        originalRenderedSize: blankSize,
        cropRectSize: blankSize,
        pixelRatio: blankSize.width / sizesManager.editorSize.width,
        isRotated: false,
      );
    }
    if (!_isVideoPlayerReady && _isVideoEditor) {
      var initSize = widget.videoController!.initialResolution;
      _imageInfos = ImageInfos(
        rawSize: initSize,
        renderedSize: initSize,
        originalRenderedSize: initSize,
        cropRectSize: initSize,
        pixelRatio: initSize.width / sizesManager.editorSize.width,
        isRotated: false,
      );

      sizesManager.originalImageSize ??= _imageInfos!.rawSize;
      sizesManager.decodedImageSize = _imageInfos!.renderedSize;

      bool shouldImportHistory =
          stateHistoryConfigs.initStateHistory != null && !_isInitialized;
      _isInitialized = true;
      _isImageNotDecoded = false;
      if (mounted) setState(() {});

      if (shouldImportHistory) {
        bool showLoadingDialog = i18n.importStateHistoryMsg.isNotEmpty;

        if (showLoadingDialog) {
          LoadingDialog.instance.show(
            context,
            theme: _theme,
            configs: configs,
            message: i18n.importStateHistoryMsg,
          );
        }
        await importStateHistory(stateHistoryConfigs.initStateHistory!);
        if (showLoadingDialog) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            LoadingDialog.instance.hide();
          });
        }
      }

      return;
    }

    bool shouldImportStateHistory =
        _isImageNotDecoded && stateHistoryConfigs.initStateHistory != null;
    _isImageNotDecoded = false;

    if (shouldImportStateHistory && i18n.importStateHistoryMsg.isNotEmpty) {
      LoadingDialog.instance.show(
        context,
        theme: _theme,
        configs: configs,
        message: i18n.importStateHistoryMsg,
      );
    }

    _imageInfos = imageInfos ??
        await decodeImageInfos(
          bytes: await editorImage!.safeByteArray(context),
          screenSize: Size(
            sizesManager.lastScreenSize.width,
            sizesManager.bodySize.height,
          ),
          configs: transformConfigs ?? stateManager.transformConfigs,
        );

    // Apply initial aspect ratio clamping
    if (_imageInfos != null &&
        !shouldImportStateHistory &&
        transformConfigs == null &&
        mainEditorConfigs.transformSetup == null) {
      final double actRatio = _imageInfos!.rawSize.aspectRatio;
      double? targetRatio;
      if (cropRotateEditorConfigs.initAspectRatio != null &&
          cropRotateEditorConfigs.initAspectRatio! > 0) {
        targetRatio = cropRotateEditorConfigs.initAspectRatio;
      } else if (cropRotateEditorConfigs.minAspectRatio != null &&
          actRatio < cropRotateEditorConfigs.minAspectRatio!) {
        targetRatio = cropRotateEditorConfigs.minAspectRatio;
      } else if (cropRotateEditorConfigs.maxAspectRatio != null &&
          actRatio > cropRotateEditorConfigs.maxAspectRatio!) {
        targetRatio = cropRotateEditorConfigs.maxAspectRatio;
      }
      if (targetRatio != null &&
          targetRatio > 0 &&
          stateManager.stateHistory.isNotEmpty) {
        final Size imgBaseSize = _imageInfos!.renderedSize;
        final double imgW = imgBaseSize.width;
        final double imgH = imgBaseSize.height;

        double newW = imgW;
        double newH = imgH;

        if (imgW / imgH > targetRatio) {
          newW = imgH * targetRatio;
        } else {
          newH = imgW / targetRatio;
        }

        double left = (imgW - newW) / 2;
        double top = (imgH - newH) / 2;

        Rect newCropRect = Rect.fromLTWH(left, top, newW, newH);

        stateManager.stateHistory.first.transformConfigs =
            (stateManager.stateHistory.first.transformConfigs ??
                    TransformConfigs.empty())
                .copyWith(
          cropRect: newCropRect,
          aspectRatio: (cropRotateEditorConfigs.initAspectRatio != null &&
                  cropRotateEditorConfigs.initAspectRatio! > 0)
              ? targetRatio
              : -1.0,
          originalSize: imgBaseSize,
          cropEditorScreenRatio: sizesManager.bodySize.aspectRatio,
        );
        stateManager.updateActiveItems();
        _imageInfos = _imageInfos!.copyWith(
          cropRectSize: newCropRect.size,
        );
      }
    }

    sizesManager.originalImageSize ??= _imageInfos!.rawSize;
    sizesManager.decodedImageSize = _imageInfos!.renderedSize;

    // Proactively mark the crop overlay as animating so the very first frame
    // rendered after initialization already hides it. This prevents a 1-frame
    // flicker where the dark crop overlay briefly appears before the
    // background image's crop animation starts.
    final tc = stateManager.transformConfigs;
    if (tc.isNotEmpty && !tc.originalSize.isInfinite) {
      final origSize = tc.originalSize;
      final fullRect = Rect.fromLTWH(0, 0, origSize.width, origSize.height);
      final cropRect = tc.cropRect;
      final needsCropAnim = (cropRect.left - fullRect.left).abs() >= 0.5 ||
          (cropRect.top - fullRect.top).abs() >= 0.5 ||
          (cropRect.width - fullRect.width).abs() >= 0.5 ||
          (cropRect.height - fullRect.height).abs() >= 0.5;
      if (needsCropAnim) {
        _isCropAnimating = true;
      }
    }

    _isInitialized = true;
    if (!_decodeImageCompleter.isCompleted) {
      _decodeImageCompleter.complete(true);
    }
    mainEditorCallbacks?.onImageDecoded?.call();

    if (shouldImportStateHistory) {
      await importStateHistory(stateHistoryConfigs.initStateHistory!);
      if (i18n.importStateHistoryMsg.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          LoadingDialog.instance.hide();
        });
      }
    }
    if (mounted) setState(() {});
    mainEditorCallbacks?.handleUpdateUI();
  }

  void _calcAppBarHeight() {
    double? renderedBottomBarHeight =
        _bottomBarKey.currentContext?.size?.height;
    if (renderedBottomBarHeight != null) {
      sizesManager
        ..bottomBarHeight = renderedBottomBarHeight
        ..appBarHeight = sizesManager.editorSize.height -
            sizesManager.bodySize.height -
            sizesManager.bottomBarHeight;
    }
  }

  /// Updates the background image in the editor.
  ///
  /// If [updateHistory] is `false`, marks all background-captured images that
  /// use the old-background image as "broken" so they will be recaptured with
  /// the new image, and set the active background image to [image].
  ///
  /// If [updateHistory] is `true`, updates the background images in the
  /// state manager, replaces the old image with [image], and adds the change
  /// to the history.
  ///
  /// After updating, decodes the new image asynchronously.
  ///
  /// [image]: The new background image to set.
  /// [updateHistory]: Whether to update the history with this change
  /// (default is `true`).
  Future<void> updateBackgroundImage(
    EditorImage image, {
    bool updateHistory = true,
  }) async {
    if (!updateHistory) {
      /// Mark all background-captured images that use the old background
      /// image as "broken" so the editor captures them again with the new
      /// image.
      for (var item in stateManager.screenshots) {
        item.broken = true;
      }
      stateManager.activeBackgroundImage = image;

      await decodeImage();
      _rebuildController.add(null);
    } else {
      addHistory();

      /// Ensure the screenshot is already added to the task list.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          stateManager.updateBackgroundImages(
            oldImage: editorImage ?? widget.editorImage!,
            newImage: image,
          );
          await decodeImage();
          _rebuildController.add(null);
        });
      });
    }
  }

  @override
  void resetZoom() {
    super.resetZoom();
    _controllers.cropLayerPainterCtrl.add(null);
  }

  /// Syncs layer transform properties (offset, rotation, scale, flip) from
  /// sub-editor copies back to [activeLayers].
  ///
  /// Sub-editors (TuneEditor, FilterEditor, BlurEditor) work on layer
  /// *copies*.  When a layer is moved/scaled/rotated in the sub-editor,
  /// [activeLayers] becomes stale.  Since the backgroundOverride (built
  /// from [activeLayers]) also renders Hero-tagged layers, both Hero
  /// instances must agree on position to avoid a "jumping" hero flight.
  void _syncLayerTransforms(List<Layer> subEditorLayers) {
    for (final subLayer in subEditorLayers) {
      final mainIdx = activeLayers.indexWhere((l) => l.id == subLayer.id);
      if (mainIdx >= 0) {
        final mainLayer = activeLayers[mainIdx];
        mainLayer
          ..offset = subLayer.offset
          ..rotation = subLayer.rotation
          ..scale = subLayer.scale
          ..flipX = subLayer.flipX
          ..flipY = subLayer.flipY;
      }
    }
  }

  /// Handles tap events on a text layer.
  ///
  /// This method opens a text editor for the specified text layer and updates
  /// the layer's properties
  /// based on the user's input.
  ///
  /// [layerData] - The text layer data to be edited.
  /// Throwaway IME connection that brings the keyboard up before the text
  /// editor opens and *holds it* through the whole hero flight (see
  /// [_prewarmKeyboard]).
  TextInputConnection? _prewarmedKeyboardConnection;

  /// The client behind [_prewarmedKeyboardConnection]. Typing during the
  /// flight flows through it into the editor's text controller (see
  /// [_KeyboardWarmupClient.targetController]).
  _KeyboardWarmupClient? _keyboardWarmupClient;

  /// Opens the software keyboard via a throwaway IME connection and waits a
  /// few frames so the expensive keyboard bring-up (~50-85ms UI-thread
  /// stall on iOS) happens *before* the text-editor route and its hero
  /// flight start. Frames only complete once the attach stall has cleared,
  /// so the frame waits reliably put the push on the clean side of it; with
  /// an already warm keyboard this adds just 2-3 imperceptible frames.
  ///
  /// The connection stays attached during the flight — switching IME clients
  /// mid-flight (even to an identically configured field) makes iOS rebuild
  /// the input view, which drops flight frames. The TextEditor's real field
  /// only takes over once the flight settled (`_handOffFocusWhenSettled`),
  /// which detaches this client seamlessly.
  ///
  /// [initialValue] seeds the IME editing state (text + caret) so the
  /// keyboard's shift/auto-capitalization state matches the edited text and
  /// typing during the flight edits the right value.
  ///
  /// The configuration mirrors the TextEditor's fields so the keyboard looks
  /// identical from the first frame (appearance, layout, suggestion bar).
  Future<void> _prewarmKeyboard({TextEditingValue? initialValue}) async {
    _prewarmedKeyboardConnection?.close();
    final client = _KeyboardWarmupClient(
      initialValue ?? TextEditingValue.empty,
    );
    _keyboardWarmupClient = client;
    _prewarmedKeyboardConnection = TextInput.attach(
      client,
      TextInputConfiguration(
        inputType: TextInputType.multiline,
        inputAction: TextInputAction.newline,
        textCapitalization: TextCapitalization.sentences,
        keyboardAppearance: _theme.brightness,
        autocorrect: textEditorConfigs.enableAutocorrect,
        smartDashesType: SmartDashesType.enabled,
        smartQuotesType: SmartQuotesType.enabled,
        enableSuggestions: textEditorConfigs.enableSuggestions,
      ),
    )
      ..setEditingState(client.currentTextEditingValue)
      ..show();
    for (var i = 0; i < 3 && mounted; i++) {
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  /// The currently open sub-editor state that works on its own layer
  /// copies, if any (pushed or embedded).
  StandaloneEditorState<StatefulWidget, EditorInitConfigs>?
      get _openSubEditorState {
    final states = <StandaloneEditorState<StatefulWidget, EditorInitConfigs>?>[
      filterEditor.currentState,
      tuneEditor.currentState,
      blurEditor.currentState,
    ];
    return states.firstWhere((state) => state != null, orElse: () => null);
  }

  void _onTextLayerTap(TextLayer layerData) async {
    final customCallback = mainEditorCallbacks?.onEditTextLayer;
    TextLayer? updatedLayer;

    if (customCallback != null) {
      updatedLayer = await customCallback(
          _layerCopyManager.copyLayer(layerData) as TextLayer);
    } else {
      // The tapped layer instance can be a *stale* sub-editor copy: after a
      // previous edit, the canvas shows the new content via the flight
      // override while the real layer swap (and the sub-editor's copy
      // re-sync) intentionally waits for the closing flight to finish.
      // Re-opening the editor within that window must show the freshest
      // content — the pending override first, then the main editor's layer,
      // and only then the tapped copy itself. Transforms stay live on the
      // tapped copy (they are synced continuously during drags), so only the
      // content source is resolved here.
      final mainLayerIndex =
          activeLayers.indexWhere((layer) => layer.id == layerData.id);
      final freshest = (HeroFlightOverrides.instance[layerData.id] ??
          (mainLayerIndex >= 0 ? activeLayers[mainLayerIndex] : null) ??
          layerData) as TextLayer;

      // Opening the keyboard blocks the UI thread ~50-85ms on iOS. Paying
      // that cost *before* the push — while the layer is still static —
      // keeps the hero flight gap-free (see _prewarmKeyboard docs).
      await _prewarmKeyboard(
        initialValue: TextEditingValue(
          text: freshest.text,
          selection: TextSelection.collapsed(offset: freshest.text.length),
        ),
      );
      if (!mounted) return;

      // The TextEditor renders at full size (scaleFactor=1.0) for editing
      // comfort. The Hero FittedBox shuttle handles the size transition.
      final pageFuture = openPage<TextLayer>(
        TextEditor(
          key: textEditor,
          layer: _layerCopyManager.copyLayer(freshest) as TextLayer,
          heroTag: layerData.id,
          configs: configs,
          theme: _theme,
          callbacks: callbacks,
          scaleFactor: 1.0,
          imageSize: sizesManager.decodedImageSize,
        ),
      );

      // The editor state exists after the route's first frame; from then on,
      // typing during the flight flows from the throwaway IME client into
      // the editor's controller — visible live in the flight shuttle — until
      // the real field takes the connection over after the flight settles.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _keyboardWarmupClient?.targetController =
            textEditor.currentState?.textCtrl;
      });

      updatedLayer = await pageFuture;

      // Stop forwarding before anything else: the editor (and its
      // controller) is being disposed with the popped route.
      _keyboardWarmupClient?.targetController = null;
      // No-op if the editor's real field already took the connection over;
      // hides the keyboard if the editor closed before the hand-off ran.
      _prewarmedKeyboardConnection?.close();
      _prewarmedKeyboardConnection = null;
    }

    if (!mounted || updatedLayer == null) return;

    // Bind the result to the *main* layer's keys: [layerData] can be a
    // pushed sub-editor's copy whose GlobalKeys belong to that editor's
    // (still mounted) layer stack and must not enter the main history.
    final mainLayerIdx =
        activeLayers.indexWhere((layer) => layer.id == layerData.id);
    final keySource =
        mainLayerIdx >= 0 ? activeLayers[mainLayerIdx] : layerData;

    updatedLayer
      ..id = layerData.id
      ..key = keySource.key
      ..keyInternalSize = keySource.keyInternalSize
      ..flipX = layerData.flipX
      ..flipY = layerData.flipY
      ..offset = layerData.offset
      ..scale = layerData.scale
      ..rotation = layerData.rotation
      ..boxConstraints = layerData.boxConstraints
      ..groupId = layerData.groupId
      ..interaction = layerData.interaction
      ..meta = layerData.meta;

    if (updatedLayer.text.isEmpty) {
      // The TextEditor published an override before popping; clear it since the
      // layer is being removed rather than swapped (otherwise it would leak).
      HeroFlightOverrides.instance.clear(layerData.id);
      // Remove the *main* instance — [layerData] can be a sub-editor copy
      // that [removeLayer]'s identity lookup wouldn't find.
      if (mainLayerIdx >= 0) removeLayer(activeLayers[mainLayerIdx]);
      _openSubEditorState?.adoptLayerRemoval(layerData.id);
      return;
    }

    // Show the *edited* content (keyed by id) so both the hero shuttle and the
    // rendered layer use the new text/size during the closing flight. (Usually
    // already set by the TextEditor before the pop; this keeps it in sync.)
    HeroFlightOverrides.instance.set(layerData.id, updatedLayer);

    // Wait for the pop route AND the heroine landing to finish before
    // swapping the real layer in — the swap remounts the layer's Heroine, and
    // doing that mid-landing cuts the closing animation short (visible snap).
    // The deadline is a safety net against a flight that never reports its
    // end.
    // `_activeSubEditor` stays [SubEditor.text] until the text route's pop
    // animation is fully dismissed — unlike [isSubEditorOpen], which stays
    // true for the whole session of a sub-editor the text editor may be
    // stacked on and would keep this loop spinning until the deadline.
    final flightDeadline = DateTime.now().add(const Duration(seconds: 3));
    while (mounted &&
        (_activeSubEditor == SubEditor.text ||
            HeroineController.isTagInFlight(layerData.id)) &&
        DateTime.now().isBefore(flightDeadline)) {
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted) return;

    final i = activeLayers.indexWhere((element) => element.id == layerData.id);
    replaceLayer(index: i, layer: updatedLayer);

    // Pushed sub-editors capture their layer copies once at push (no
    // didUpdateWidget re-sync), so hand the edited content to the open
    // editor's copy directly. The copy keeps that editor's own GlobalKeys.
    _openSubEditorState?.adoptLayerUpdate(
      _layerCopyManager.duplicateLayer(
        updatedLayer,
        offset: Offset.zero,
        enableCopyId: true,
        enableCopyKey: false,
      ),
    );

    // Keep the override a few frames after the swap so the (copied) layer in
    // the embedded editor re-syncs to the new content before we stop
    // overriding — otherwise the old text briefly reappears on handover.
    for (var frame = 0; frame < 3 && mounted; frame++) {
      await WidgetsBinding.instance.endOfFrame;
    }
    HeroFlightOverrides.instance.clear(layerData.id);
    if (mounted) setState(() {});
  }

  void _editPaintLayer(PaintLayer layer) async {
    if (layer.isPaintLayer && layer.item.isCensorArea) return;

    PaintLayer? result =
        await (callbacks.paintEditorCallbacks?.onEditLayer?.call(layer) ??
            showModalBottomSheet<PaintLayer>(
              context: context,
              backgroundColor:
                  paintEditorConfigs.style.editSheetBackgroundColor,
              showDragHandle: paintEditorConfigs.style.editSheetShowDragHandle,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (context) =>
                  paintEditorConfigs.widgets.editBottomSheet?.call(layer) ??
                  SafeArea(
                    child: PaintEditorLayerEditor(
                      layer: _layerCopyManager.duplicateLayer(layer,
                          offset: Offset.zero) as PaintLayer,
                      configs: configs,
                    ),
                  ),
            ));

    if (result == null) return;

    replaceLayer(index: getLayerStackIndex(layer), layer: result);
  }

  /// Initializes the key event listener by adding a handler to the keyboard
  /// service.
  void initKeyEventListener() {
    ServicesBinding.instance.keyboard.addHandler(_onKeyEvent);
  }

  /// Removes the key event listener by removing the handler from the keyboard
  /// service.
  void removeKeyEventListener() {
    ServicesBinding.instance.keyboard.removeHandler(_onKeyEvent);
  }

  void _selectLayerAfterHeroIsDone(String id) async {
    if (layerInteractionManager.layersAreSelectable(configs) &&
        layerInteraction.initialSelected) {
      if (isSubEditorOpen) await _pageOpenCompleter.future;
      layerInteractionManager.addSelectedLayer(id);
      _checkInteractiveViewer();
      _controllers.uiLayerCtrl.add(null);
    }
  }

  /// Open a new page on top of the current page.
  ///
  /// This method navigates to a new page using a fade transition animation.
  Future<T?> openPage<T>(
    Widget page, {
    /// Overrides [SubEditorPageStyle.transitionDuration] when set.
    Duration? duration,
  }) {
    layerInteractionManager.clearSelectedLayers();
    _checkInteractiveViewer();

    bool wasSubEditorOpen = isSubEditorOpen;
    isSubEditorOpen = true;

    SubEditor editorName = SubEditor.unknown;

    if (T is List<PaintLayer> || page is PaintEditor) {
      editorName = SubEditor.paint;
    } else if (T is TextLayer || page is TextEditor) {
      editorName = SubEditor.text;
    } else if (T is TransformConfigs || page is CropRotateEditor) {
      editorName = SubEditor.cropRotate;
    } else if (T is TuneAdjustmentMatrix || page is TuneEditor) {
      editorName = SubEditor.tune;
    } else if (T is FilterMatrix || page is FilterEditor) {
      editorName = SubEditor.filter;
    } else if (T is double || page is BlurEditor) {
      editorName = SubEditor.blur;
    } else if (page is EmojiEditor) {
      editorName = SubEditor.emoji;
    }

    // A TextEditor opened while another sub-editor route is active (e.g.
    // tapping a text layer inside the filter editor) must STACK on top of
    // that route instead of replacing it: pushReplacement unmounts the
    // editor below — visible as a black canvas behind the text editor,
    // because the main editor's background stays hidden while a sub-editor
    // is open — and silently discards that editor's un-committed result.
    final bool stackOnSubEditor =
        wasSubEditorOpen && editorName == SubEditor.text;
    final SubEditor previousSubEditor = _activeSubEditor;
    if (stackOnSubEditor) _isTextOverSubEditor = true;

    // Record which editor is open *before* the rebuild so the main-editor
    // layers build with the correct enableHero value from the first frame
    // (the TextEditor keeps layer heroes enabled for its whole session).
    _activeSubEditor = editorName;

    setState(() {});

    mainEditorCallbacks?.handleOpenSubEditor(editorName);

    if (!stackOnSubEditor) {
      if (wasSubEditorOpen && !_pageOpenCompleter.isCompleted) {
        _pageOpenCompleter.complete(true);
      }

      _pageOpenCompleter = Completer();
    }

    final subEditorStyle = mainEditorConfigs.style.subEditorPage;
    final effectiveDuration = duration ?? subEditorStyle.transitionDuration;
    var route = PageRouteBuilder<T?>(
      opaque: false,
      barrierColor: subEditorStyle.barrierColor,
      barrierDismissible: subEditorStyle.barrierDismissible,
      transitionDuration: effectiveDuration,
      reverseTransitionDuration: effectiveDuration,
      transitionsBuilder: subEditorStyle.transitionsBuilder ??
          (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
      pageBuilder: (context, animation, secondaryAnimation) {
        // Reset zoom of underlying sub-editors, normally once the new
        // editor fully covers them. This ensures they start at default
        // scale/translation when the user returns.
        //
        // Skipped for the TextEditor: its route is non-opaque and its
        // background is semi-transparent, so the zoomed editor stays
        // visible behind it. Resetting here would snap the image back to
        // scale 1 mid-overlay (a visible "jump") and discard the zoom the
        // user wants the new text placed at.
        //
        // Editors with enableShareZoomMatrix keep their zoom instead: the
        // opened editor is seeded with the shared zoom matrix and syncs it
        // back, so their covered state must survive. The crop-rotate editor
        // always resets everything.
        bool didHandleCoveredZoomReset = false;
        void resetCoveredEditorsZoom() {
          if (didHandleCoveredZoomReset || editorName == SubEditor.text) {
            return;
          }
          didHandleCoveredZoomReset = true;
          final isCropEditor = editorName == SubEditor.cropRotate;
          // Paint first: its reset() returns to the seeded zoom matrix and
          // its share callback writes that back into the shared viewer, so
          // the resets below must run afterwards to clear it again.
          if (isCropEditor || !paintEditorConfigs.enableShareZoomMatrix) {
            paintEditor.currentState?.resetZoom();
          }
          if (isCropEditor || !tuneEditorConfigs.enableShareZoomMatrix) {
            tuneEditor.currentState?.interactiveViewerKey.currentState
                ?.reset();
          }
          if (isCropEditor || !filterEditorConfigs.enableShareZoomMatrix) {
            filterEditor.currentState?.interactiveViewerKey.currentState
                ?.reset();
          }
          // With zoom sharing the main viewer may carry the shared zoom,
          // so it has to be cleared as well when the crop editor opens.
          // Without sharing it is left untouched to preserve the existing
          // behavior.
          if (isCropEditor && mainEditorConfigs.enableShareZoomMatrix) {
            interactiveViewer.currentState?.reset();
          }
        }

        void animationStatusListener(AnimationStatus status) {
          switch (status) {
            case AnimationStatus.completed:
              if (cropRotateEditor.currentState != null) {
                cropRotateEditor.currentState!.hideFakeHero();
              }
              resetCoveredEditorsZoom();
              break;
            case AnimationStatus.dismissed:
              setState(() {
                if (stackOnSubEditor) {
                  // The sub-editor below this route is still open; restore
                  // its bookkeeping instead of marking everything closed.
                  _isTextOverSubEditor = false;
                  isSubEditorClosing = false;
                  _activeSubEditor = previousSubEditor;
                  return;
                }
                isSubEditorOpen = false;
                isSubEditorClosing = false;
                _activeSubEditor = SubEditor.unknown;
                if (!_pageOpenCompleter.isCompleted) {
                  _pageOpenCompleter.complete(true);
                }

                if (stateManager.heroScreenshotRequired) {
                  stateManager.heroScreenshotRequired = false;
                  _takeScreenshot();
                }
              });

              animation.removeStatusListener(animationStatusListener);
              mainEditorCallbacks?.handleEndCloseSubEditor(editorName);
              break;
            case AnimationStatus.reverse:
              isSubEditorClosing = true;
              // When the route is popped before its opening animation ever
              // completed (fast editor switching), the completed-case reset
              // never ran — catch up now while the closing route still
              // mostly covers the editors below.
              resetCoveredEditorsZoom();
              // Hero stays enabled for the whole TextEditor session via
              // _activeSubEditor (set on open), so no per-frame toggle is
              // needed here — that toggle caused a one-frame flash of the
              // destination layer before the flight engaged.
              mainEditorCallbacks?.handleStartCloseSubEditor(editorName);

              break;
            case AnimationStatus.forward:
              break;
          }
        }

        animation.addStatusListener(animationStatusListener);

        if (!subEditorStyle.requireReposition) return page;

        return SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                top: subEditorStyle.positionTop,
                left: subEditorStyle.positionLeft,
                right: subEditorStyle.positionRight,
                bottom: subEditorStyle.positionBottom,
                child: Center(
                  child: Container(
                    width: subEditorStyle.enforceSizeFromMainEditor
                        ? sizesManager.editorSize.width
                        : null,
                    height: subEditorStyle.enforceSizeFromMainEditor
                        ? sizesManager.editorSize.height
                        : null,
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      borderRadius: subEditorStyle.borderRadius,
                    ),
                    child: page,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (mainEditorConfigs.enableSubEditorPage) {
      if (wasSubEditorOpen && !stackOnSubEditor) {
        return _navigatorKey.currentState!
            .pushReplacement<T?, dynamic>(route, result: null);
      }
      return _navigatorKey.currentState!.push<T?>(route);
    }
    if (wasSubEditorOpen && !stackOnSubEditor) {
      return Navigator.pushReplacement<T?, dynamic>(context, route,
          result: null);
    }
    return Navigator.push<T?>(
      context,
      route,
    );
  }

  /// Opens the paint editor.
  ///
  /// This method opens the paint editor and allows the user to draw on the
  /// current image.
  /// After closing the paint editor, any changes made are applied to the
  /// image's layers.
  void openPaintEditor() async {
    await _commitCurrentSubEditorState();
    var paintCallbacks =
        callbacks.paintEditorCallbacks ?? const PaintEditorCallbacks();
    var overridenPaintCallbacks = paintCallbacks.copyWith(
      onEditorZoomMatrix4Change: (value) {
        callbacks.paintEditorCallbacks?.onEditorZoomMatrix4Change?.call(value);
        if (paintEditorConfigs.enableShareZoomMatrix) {
          _sharedZoomViewer?.transformMatrix4 = value;
        }
      },
    );

    PaintEditorResponse? result = await openPage<PaintEditorResponse>(
      PaintEditor.autoSource(
        key: paintEditor,
        editorImage: widget.blankSize == null
            ? editorImage
            : EditorImage(byteArray: kImageEditorTransparentBytes),
        videoController: widget.videoController,
        initConfigs: PaintEditorInitConfigs(
          configs: configs,
          callbacks: callbacks.copyWith(
            paintEditorCallbacks: overridenPaintCallbacks,
          ),
          layers: _layerCopyManager.duplicateLayerList(
            activeLayers,
            offset: Offset.zero,
            enableCopyId: true,
          ),
          theme: _theme,
          mainImageSize: widget.blankSize ?? sizesManager.decodedImageSize,
          mainBodySize: sizesManager.bodySize,
          transformConfigs: stateManager.transformConfigs,
          appliedBlurFactor: stateManager.activeBlur,
          appliedFilters: stateManager.activeFilters,
          appliedTuneAdjustments: stateManager.activeTuneAdjustments,
          initialZoomMatrix: _sharedZoomViewer?.transformMatrix4,
        ),
      ),
      duration: const Duration(milliseconds: 150),
    );

    if (result == null) return;

    String lastLayerId = '';
    for (var i = 0; i < result.layers.length; i++) {
      final layer = result.layers[i];
      final oldIndex = activeLayers.indexWhere((el) => el.id == layer.id);

      final duplicatedLayer = _layerCopyManager.duplicateLayer(
        layer,
        offset: Offset.zero,
      );
      lastLayerId = duplicatedLayer.id;
      addLayer(
        duplicatedLayer,
        removeLayerIndex: oldIndex,
        blockSelectLayer: true,
        blockCaptureScreenshot: true,
        autoCorrectZoomOffset: false,
        autoCorrectZoomScale: false,
      );
    }
    for (Layer layer in result.removedLayers) {
      removeLayer(layer, blockCaptureScreenshot: true);
    }

    if (lastLayerId.isNotEmpty) {
      _selectLayerAfterHeroIsDone(lastLayerId);
    }

    _takeScreenshot(replaceLastScreenshot: true);
    setState(() {});
    mainEditorCallbacks?.handleUpdateUI();
  }

  /// Opens the text editor.
  ///
  /// This method opens the text editor, allowing the user to add or edit text
  /// layers on the image.
  void openTextEditor({
    /// Overrides [SubEditorPageStyle.transitionDuration] when set.
    Duration? duration,
  }) async {
    await _commitCurrentSubEditorState();
    final customCallback = mainEditorCallbacks?.onCreateTextLayer;
    TextLayer? layer;

    if (customCallback != null) {
      layer = await customCallback();
    } else {
      // ── Placeholder layer ──────────────────────────────────────
      // Insert an invisible placeholder so a Hero widget with a
      // matching tag exists on the main-editor page during *both*
      // the push and pop transitions of the text editor.
      final placeholder = TextLayer(
        text: '',
        color: const Color(0x00000000),
        background: const Color(0x00000000),
      );
      // Position the placeholder at the same zoom-corrected spot the final
      // text layer will occupy. This way the Hero flight — on both push and
      // pop — flies to/from the currently visible (zoomed) location instead
      // of the absolute image center.
      _applyViewerZoomCorrection(placeholder);
      activeLayers.add(placeholder);
      setState(() {});

      // Wait for the frame to fully render (build + layout + paint)
      // so the placeholder's Hero is discoverable by the Hero framework.
      await WidgetsBinding.instance.endOfFrame;

      layer = await openPage(
        TextEditor(
          key: textEditor,
          heroTag: placeholder.id,
          configs: configs,
          theme: _theme,
          callbacks: callbacks,
          scaleFactor: textEditorConfigs.enableMainEditorZoomFactor
              ? _activeInteractiveViewer?.scaleFactor ?? 1.0
              : 1.0,
          imageSize: sizesManager.decodedImageSize,
          // Keep the hero flight spring in sync with a per-call duration
          // override; both fall back to
          // SubEditorPageStyle.transitionDuration.
          heroFlightDuration: duration,
        ),
        duration: duration,
      );

      if (layer == null || !mounted) {
        // User cancelled – remove the placeholder.
        activeLayers.remove(placeholder);
        setState(() {});
        return;
      }

      // Reuse the placeholder's ID **and** keys so the LayerWidget's
      // Hero tag stays identical during the closing animation and the
      // pre-pop swap doesn't remount the layer subtree (a changed
      // keyInternalSize remounts the KeyedSubtree around the Heroine, which
      // kills the flight's motion controller mid-flight).
      layer
        ..id = placeholder.id
        ..key = placeholder.key
        ..keyInternalSize = placeholder.keyInternalSize;

      // Place the text at the center of the currently visible (zoomed)
      // area at the correct visual size. The placeholder/replace flow
      // bypasses [addLayer], so apply the same zoom correction here using
      // whichever viewer is currently active (main or embedded sub-editor).
      _applyViewerZoomCorrection(layer);

      // ── Swap in the real layer *before* the pop flight ─────────
      // Navigator.push resolves the moment pop() is called, i.e. right as
      // the reverse transition begins. We must put the real (visible) text
      // in place *now* so the closing Hero has a content-ful destination to
      // fly to — exactly like the edit-existing flow, where the original
      // layer stays on the page during the pop.
      //
      // Waiting until the pop finished (the previous behaviour) left the
      // transparent/empty placeholder as the Hero target for the whole
      // flight, so no animation was visible. Swapping now causes no content
      // flash because the placeholder was invisible to begin with.
      if (!mounted) return;

      // The swap makes the canvas layer render the real text one frame
      // before the closing flight engages and hides it — which showed the
      // text at the target while the editor still displayed the same text
      // ("two texts"). Mark the flight as pending so the LayerWidget keeps
      // the content invisible (layout preserved for the flight measurement)
      // until the flight has actually started.
      HeroFlightOverrides.instance.markPendingFlight(layer.id);

      // Replace in-place so the widget tree sees the same list index
      // and GlobalKey – this avoids destroying/recreating the Hero.
      final idx = activeLayers.indexOf(placeholder);
      if (idx >= 0) {
        activeLayers[idx] = layer;
      } else {
        activeLayers.add(layer);
      }

      addHistory(layers: activeLayers);
      _selectLayerAfterHeroIsDone(layer.id);

      setState(() {});
      mainEditorCallbacks?.handleUpdateUI();

      // Release the pending mark once the flight is over (deadline as a
      // safety net if the flight never engages, e.g. hero disabled).
      final pendingDeadline = DateTime.now().add(const Duration(seconds: 3));
      while (mounted &&
          (_activeSubEditor == SubEditor.text ||
              HeroineController.isTagInFlight(layer.id)) &&
          DateTime.now().isBefore(pendingDeadline)) {
        await WidgetsBinding.instance.endOfFrame;
      }
      HeroFlightOverrides.instance.clearPendingFlight(layer.id);
      return;
    }

    if (layer == null || !mounted) return;

    addLayer(layer, blockSelectLayer: true);
    _selectLayerAfterHeroIsDone(layer.id);

    setState(() {});
    mainEditorCallbacks?.handleUpdateUI();
  }

  /// Opens the crop rotate editor.
  ///
  /// This method opens the crop editor, allowing the user to crop and rotate
  /// the image.
  void openCropRotateEditor() async {
    if (!_isInitialized) await _decodeImageCompleter.future;
    await _commitCurrentSubEditorState();

    await openPage<TransformConfigs?>(
      CropRotateEditor.autoSource(
        key: cropRotateEditor,
        editorImage: widget.blankSize == null
            ? editorImage
            : EditorImage(byteArray: kImageEditorTransparentBytes),
        videoController: widget.videoController,
        initConfigs: CropRotateEditorInitConfigs(
          configs: configs,
          callbacks: callbacks,
          theme: _theme,
          // Use new GlobalKeys (enableCopyKey: false) so these copies
          // don't conflict with the embedded sub-editor's layers that
          // share the original keys and remain mounted underneath.
          layers: _layerCopyManager.duplicateLayerList(
            activeLayers,
            offset: Offset.zero,
            enableCopyKey: false,
            enableCopyId: true,
          ),
          transformConfigs: stateManager.transformConfigs,
          mainImageSize: widget.blankSize ?? sizesManager.decodedImageSize,
          mainBodySize: sizesManager.bodySize,
          enableFakeHero: true,
          appliedBlurFactor: stateManager.activeBlur,
          appliedFilters: stateManager.activeFilters,
          appliedTuneAdjustments: stateManager.activeTuneAdjustments,
          onDone: (transformConfigs, fitToScreenFactor, imageInfos) async {
            _imageInfos = null;
            unawaited(decodeImage(transformConfigs));
            addHistory(
              transformConfigs: transformConfigs,
              heroScreenshotRequired: true,
            );

            /// Important to reset the layer hero positions
            if (activeLayers.isNotEmpty) {
              _controllers.layerHeroResetCtrl.add(true);
              await Future.delayed(const Duration(milliseconds: 60));
              _controllers.layerHeroResetCtrl.add(false);
            }

            setState(() {});
          },
        ),
      ),
    ).then((transformConfigs) async {
      if (transformConfigs != null) {
        setState(() {});
        mainEditorCallbacks?.handleUpdateUI();
      }
    });
  }

  /// Opens the tune editor.
  ///
  /// This method opens the Tune Editor page, allowing the user to make tune
  /// adjustments (such as brightness, contrast, etc.) to the current image.
  ///
  /// If tune adjustments are made, they are added to the editor's history
  /// and the UI is updated accordingly. If the operation is canceled or no
  /// adjustments are made, the current state remains unchanged.
  void openTuneEditor({bool enableHero = true}) async {
    if (!mounted) return;
    await _commitCurrentSubEditorState();

    // If the embedded sub-editor is already tune, just close the overlay
    // route to return to it instead of pushing a duplicate.
    if (mainEditorConfigs.initialSubEditor == SubEditorMode.tune) {
      if (isSubEditorOpen) {
        Navigator.pop(context);
      }
      // Don't recreate tuneEditor GlobalKey — keep the TuneEditor state
      // alive so its layers remain visible during the route pop animation
      // instead of disappearing.
      setState(() {});
      return;
    }

    // When the tune editor takes part in zoom sharing, read the shared zoom
    // before the route is pushed and let the tune editor mirror its zoom
    // back into the shared viewer so the editor below shows the same zoom
    // when this route closes.
    final bool shareZoom = tuneEditorConfigs.enableShareZoomMatrix;
    final Matrix4? initialZoomMatrix =
        shareZoom ? _sharedZoomViewer?.transformMatrix4 : null;
    final effectiveCallbacks = !shareZoom
        ? callbacks
        : callbacks.copyWith(
            tuneEditorCallbacks:
                (callbacks.tuneEditorCallbacks ?? const TuneEditorCallbacks())
                    .copyWith(
              onEditorZoomMatrix4Change: (value) {
                callbacks.tuneEditorCallbacks?.onEditorZoomMatrix4Change
                    ?.call(value);
                _sharedZoomViewer?.transformMatrix4 = value;
              },
            ),
          );

    List<TuneAdjustmentMatrix>? tuneAdjustments = await openPage(
      HeroMode(
        enabled: enableHero,
        child: TuneEditor.autoSource(
          key: tuneEditor,
          editorImage: widget.blankSize == null
              ? editorImage
              : EditorImage(byteArray: kImageEditorTransparentBytes),
          videoController: widget.videoController,
          initConfigs: TuneEditorInitConfigs(
            theme: _theme,
            configs: configs,
            callbacks: effectiveCallbacks,
            initialZoomMatrix: initialZoomMatrix,
            transformConfigs: stateManager.transformConfigs,
            // Use new GlobalKeys (enableCopyKey: false) so these copies
            // don't conflict with the layer stack that keeps the original
            // keys mounted underneath the pushed route.
            layers: _layerCopyManager.duplicateLayerList(
              activeLayers,
              offset: Offset.zero,
              enableCopyKey: false,
              enableCopyId: true,
            ),
            mainImageSize: widget.blankSize ?? sizesManager.decodedImageSize,
            mainBodySize: sizesManager.bodySize,
            convertToUint8List: false,
            appliedBlurFactor: stateManager.activeBlur,
            appliedFilters: stateManager.activeFilters,
            appliedTuneAdjustments: stateManager.activeTuneAdjustments,
            onTextLayerTap: _onTextLayerTap,
            onLayerTransformChanged: _syncLayerTransforms,
            historyScope: _editorHistoryScope,
          ),
        ),
      ),
    );

    if (tuneAdjustments == null) return;

    addHistory(tuneAdjustments: tuneAdjustments, heroScreenshotRequired: true);

    setState(() {});
    mainEditorCallbacks?.handleUpdateUI();
  }

  /// Opens the filter editor.
  ///
  /// This method allows the user to apply filters to the current image and
  /// replaces the image
  /// with the filtered version if a filter is applied.
  ///
  /// The filter editor is opened as a page, and the resulting filtered image
  /// is received as a
  /// `Uint8List`. If no filter is applied or the operation is canceled, the
  /// original image is retained.
  void openFilterEditor() async {
    if (!mounted) return;
    await _commitCurrentSubEditorState();

    // If the embedded sub-editor is already filter, just close the overlay
    // route to return to it instead of pushing a duplicate.
    if (mainEditorConfigs.initialSubEditor == SubEditorMode.filter) {
      if (isSubEditorOpen) {
        Navigator.pop(context);
      }
      filterEditor = GlobalKey<FilterEditorState>();
      setState(() {});
      return;
    }

    // When the filter editor takes part in zoom sharing, read the shared
    // zoom before the route is pushed and let the filter editor mirror its
    // zoom back into the shared viewer so the editor below shows the same
    // zoom when this route closes.
    final bool shareZoom = filterEditorConfigs.enableShareZoomMatrix;
    final Matrix4? initialZoomMatrix =
        shareZoom ? _sharedZoomViewer?.transformMatrix4 : null;
    final effectiveCallbacks = !shareZoom
        ? callbacks
        : callbacks.copyWith(
            filterEditorCallbacks: (callbacks.filterEditorCallbacks ??
                    const FilterEditorCallbacks())
                .copyWith(
              onEditorZoomMatrix4Change: (value) {
                callbacks.filterEditorCallbacks?.onEditorZoomMatrix4Change
                    ?.call(value);
                _sharedZoomViewer?.transformMatrix4 = value;
              },
            ),
          );

    FilterMatrix? filters = await openPage(
      FilterEditor.autoSource(
        key: filterEditor,
        editorImage: widget.blankSize == null
            ? editorImage
            : EditorImage(byteArray: kImageEditorTransparentBytes),
        videoController: widget.videoController,
        initConfigs: FilterEditorInitConfigs(
          theme: _theme,
          configs: configs,
          callbacks: effectiveCallbacks,
          initialZoomMatrix: initialZoomMatrix,
          transformConfigs: stateManager.transformConfigs,
          // Use new GlobalKeys (enableCopyKey: false) so these copies
          // don't conflict with the layer stack that keeps the original
          // keys mounted underneath the pushed route.
          layers: _layerCopyManager.duplicateLayerList(
            activeLayers,
            offset: Offset.zero,
            enableCopyKey: false,
            enableCopyId: true,
          ),
          mainImageSize: widget.blankSize ?? sizesManager.decodedImageSize,
          mainBodySize: sizesManager.bodySize,
          convertToUint8List: false,
          appliedBlurFactor: stateManager.activeBlur,
          appliedFilters: stateManager.activeFilters,
          appliedTuneAdjustments: stateManager.activeTuneAdjustments,
          onTextLayerTap: _onTextLayerTap,
          onLayerTransformChanged: _syncLayerTransforms,
          historyScope: _editorHistoryScope,
        ),
      ),
    );

    if (filters == null) return;

    addHistory(filters: filters, heroScreenshotRequired: true);

    setState(() {});
    mainEditorCallbacks?.handleUpdateUI();
  }

  /// Opens the blur editor as a modal bottom sheet.
  void openBlurEditor() async {
    if (!mounted) return;
    await _commitCurrentSubEditorState();

    // If the embedded sub-editor is already blur, just close the overlay
    // route to return to it instead of pushing a duplicate.
    if (mainEditorConfigs.initialSubEditor == SubEditorMode.blur) {
      if (isSubEditorOpen) {
        Navigator.pop(context);
      }
      blurEditor = GlobalKey<BlurEditorState>();
      setState(() {});
      return;
    }

    double? blur = await openPage(
      BlurEditor.autoSource(
        key: blurEditor,
        editorImage: widget.blankSize == null
            ? editorImage
            : EditorImage(byteArray: kImageEditorTransparentBytes),
        videoController: widget.videoController,
        initConfigs: BlurEditorInitConfigs(
          theme: _theme,
          mainImageSize: widget.blankSize ?? sizesManager.decodedImageSize,
          mainBodySize: sizesManager.bodySize,
          // Use new GlobalKeys (enableCopyKey: false) so these copies
          // don't conflict with the layer stack that keeps the original
          // keys mounted underneath the pushed route.
          layers: _layerCopyManager.duplicateLayerList(
            activeLayers,
            offset: Offset.zero,
            enableCopyKey: false,
            enableCopyId: true,
          ),
          configs: configs,
          callbacks: callbacks,
          transformConfigs: stateManager.transformConfigs,
          convertToUint8List: false,
          appliedBlurFactor: stateManager.activeBlur,
          appliedFilters: stateManager.activeFilters,
          appliedTuneAdjustments: stateManager.activeTuneAdjustments,
          onTextLayerTap: _onTextLayerTap,
          onLayerTransformChanged: _syncLayerTransforms,
          historyScope: _editorHistoryScope,
        ),
      ),
    );

    if (blur == null) return;

    addHistory(blur: blur, heroScreenshotRequired: true);

    setState(() {});
    mainEditorCallbacks?.handleUpdateUI();
  }

  /// Opens the emoji editor.
  ///
  /// This method opens the emoji editor as a modal bottom sheet, allowing the
  /// user to add emoji
  /// layers to the current image. The selected emoji layer's properties, such
  /// as scale and offset,
  /// are adjusted before adding it to the image's layers.
  ///
  /// Keyboard event handlers are temporarily removed while the emoji editor is
  /// active and restored
  /// after its closure.
  void openEmojiEditor() async {
    await _commitCurrentSubEditorState();
    setState(() => layerInteractionManager.clearSelectedLayers());
    _checkInteractiveViewer();
    ServicesBinding.instance.keyboard.removeHandler(_onKeyEvent);
    final effectiveBoxConstraints = emojiEditorConfigs
        .style.editorBoxConstraintsBuilder
        ?.call(context, configs);

    DraggableSheetStyle sheetTheme =
        emojiEditorConfigs.style.themeDraggableSheet;
    bool useDraggableSheet = sheetTheme.maxChildSize != sheetTheme.minChildSize;
    EmojiLayer? layer = await showModalBottomSheet(
      context: context,
      backgroundColor: emojiEditorConfigs.style.backgroundColor,
      constraints: effectiveBoxConstraints,
      showDragHandle: emojiEditorConfigs.style.showDragHandle,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext context) => SafeArea(
        child: !useDraggableSheet
            ? ConstrainedBox(
                constraints: effectiveBoxConstraints ??
                    BoxConstraints(
                      maxHeight: 300 + MediaQuery.viewInsetsOf(context).bottom,
                    ),
                child: EmojiEditor(configs: configs),
              )
            : DraggableScrollableSheet(
                expand: sheetTheme.expand,
                initialChildSize: sheetTheme.initialChildSize,
                maxChildSize: sheetTheme.maxChildSize,
                minChildSize: sheetTheme.minChildSize,
                shouldCloseOnMinExtent: sheetTheme.shouldCloseOnMinExtent,
                snap: sheetTheme.snap,
                snapAnimationDuration: sheetTheme.snapAnimationDuration,
                snapSizes: sheetTheme.snapSizes,
                builder: (_, controller) {
                  return EmojiEditor(
                    configs: configs,
                    scrollController: controller,
                  );
                },
              ),
      ),
    );
    ServicesBinding.instance.keyboard.addHandler(_onKeyEvent);
    if (layer == null || !mounted) return;
    layer.scale = emojiEditorConfigs.initScale;

    addLayer(layer);

    setState(() {});
    mainEditorCallbacks?.handleUpdateUI();
  }

  /// Opens the sticker editor as a modal bottom sheet.
  void openStickerEditor() async {
    await _commitCurrentSubEditorState();
    setState(() => layerInteractionManager.selectedLayerId = '');
    _checkInteractiveViewer();
    ServicesBinding.instance.keyboard.removeHandler(_onKeyEvent);
    final effectiveBoxConstraints = stickerEditorConfigs
        .style.editorBoxConstraintsBuilder
        ?.call(context, configs);
    var sheetTheme = stickerEditorConfigs.style.draggableSheetStyle;
    WidgetLayer? layer = await showModalBottomSheet(
      context: context,
      backgroundColor: stickerEditorConfigs.style.bottomSheetBackgroundColor,
      constraints: effectiveBoxConstraints,
      showDragHandle: stickerEditorConfigs.style.showDragHandle,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SafeArea(
        child: DraggableScrollableSheet(
          expand: sheetTheme.expand,
          initialChildSize: sheetTheme.initialChildSize,
          maxChildSize: sheetTheme.maxChildSize,
          minChildSize: sheetTheme.minChildSize,
          shouldCloseOnMinExtent: sheetTheme.shouldCloseOnMinExtent,
          snap: sheetTheme.snap,
          snapAnimationDuration: sheetTheme.snapAnimationDuration,
          snapSizes: sheetTheme.snapSizes,
          builder: (_, controller) {
            return StickerEditor(
              configs: configs,
              scrollController: controller,
            );
          },
        ),
      ),
    );
    ServicesBinding.instance.keyboard.addHandler(_onKeyEvent);
    if (layer == null || !mounted) return;

    addLayer(layer);

    setState(() {});
    mainEditorCallbacks?.handleUpdateUI();
  }

  /// Moves a layer in the list to a new position.
  ///
  /// - `oldIndex` is the current index of the layer.
  /// - `newIndex` is the desired index to move the layer to.
  void moveLayerListPosition({required int oldIndex, required int newIndex}) {
    if (oldIndex == newIndex || oldIndex < 0 || newIndex < 0) return;

    final layers = _layerCopyManager.copyLayerList(activeLayers);

    if (oldIndex < layers.length && newIndex <= layers.length) {
      final item = layers.removeAt(oldIndex);

      // Insert directly at newIndex, no adjustment needed
      layers.insert(newIndex, item);

      addHistory(layers: layers);
      setState(() {});
    }
  }

  /// Moves the given layer one step forward in the stack.
  /// Does nothing if the layer is already at the top.
  void moveLayerForward(Layer layer) {
    int oldIndex = getLayerStackIndex(layer);
    if (oldIndex >= activeLayers.length - 1) return;
    moveLayerListPosition(oldIndex: oldIndex, newIndex: oldIndex + 1);
  }

  /// Moves the given layer one step backward in the stack.
  /// Does nothing if the layer is already at the bottom.
  void moveLayerBackward(Layer layer) {
    int oldIndex = getLayerStackIndex(layer);
    if (oldIndex <= 0) return;
    moveLayerListPosition(oldIndex: oldIndex, newIndex: oldIndex - 1);
  }

  /// Moves the given layer to the top of the stack.
  /// Does nothing if the layer is already at the top.
  void moveLayerToFront(Layer layer) {
    int oldIndex = getLayerStackIndex(layer);
    if (oldIndex == -1 || oldIndex == activeLayers.length - 1) return;
    moveLayerListPosition(
      oldIndex: oldIndex,
      newIndex: activeLayers.length - 1,
    );
  }

  /// Moves the given layer to the bottom of the stack.
  /// Does nothing if the layer is already at the bottom.
  void moveLayerToBack(Layer layer) {
    int oldIndex = getLayerStackIndex(layer);
    if (oldIndex <= 0) return;
    moveLayerListPosition(oldIndex: oldIndex, newIndex: 0);
  }

  /// Returns the index of the given layer in the active layer stack.
  /// Returns -1 if the layer is not found.
  int getLayerStackIndex(Layer layer) {
    return activeLayers.indexWhere((item) => item.id == layer.id);
  }

  /// Undo the last editing action.
  ///
  /// With global history, undo always goes through the stateManager.
  /// Sub-editors with [EditorHistoryScope] handle syncing their local state
  /// internally. For editors without historyScope (paint, cropRotate),
  /// the old delegation flow is preserved.
  void undoAction() {
    GestureManager.instance.stopPropagation();

    // Check for sub-editors that still use local undo (paint, cropRotate)
    if (_isSubEditorActive && _delegateUndoToLocalSubEditor()) {
      setState(() {});
      return;
    }

    // Global undo through stateManager
    if (stateManager.canUndo) {
      setState(() {
        layerInteractionManager.clearSelectedLayers();
        _checkInteractiveViewer();
        stateManager.undo();
        decodeImage();
      });
      mainEditorCallbacks?.handleUndo();
      _notifyActiveSubEditorRebuild();
    }
  }

  /// Redo the previously undone editing action.
  ///
  /// With global history, redo always goes through the stateManager.
  /// For editors without historyScope (paint, cropRotate),
  /// the old delegation flow is preserved.
  void redoAction() {
    // Check for sub-editors that still use local redo (paint, cropRotate)
    if (_isSubEditorActive && _delegateRedoToLocalSubEditor()) {
      setState(() {});
      return;
    }

    // Global redo through stateManager
    if (stateManager.canRedo) {
      setState(() {
        layerInteractionManager.clearSelectedLayers();
        _checkInteractiveViewer();
        stateManager.redo();
        decodeImage();
      });
      mainEditorCallbacks?.handleRedo();
      _notifyActiveSubEditorRebuild();
    }
  }

  /// Attempts to delegate undo to sub-editors that still use local undo
  /// (paint, cropRotate). Tune/Filter/Blur use global history.
  /// Returns true if the sub-editor handled the undo.
  bool _delegateUndoToLocalSubEditor() {
    if (paintEditor.currentState != null && paintEditor.currentState!.canUndo) {
      paintEditor.currentState!.undoAction();
      return true;
    }
    if (cropRotateEditor.currentState != null &&
        cropRotateEditor.currentState!.canUndo) {
      cropRotateEditor.currentState!.undoAction();
      return true;
    }
    return false;
  }

  /// Attempts to delegate redo to sub-editors that still use local redo
  /// (paint, cropRotate). Tune/Filter/Blur use global history.
  /// Returns true if the sub-editor handled the redo.
  bool _delegateRedoToLocalSubEditor() {
    if (paintEditor.currentState != null && paintEditor.currentState!.canRedo) {
      paintEditor.currentState!.redoAction();
      return true;
    }
    if (cropRotateEditor.currentState != null &&
        cropRotateEditor.currentState!.canRedo) {
      cropRotateEditor.currentState!.redoAction();
      return true;
    }
    return false;
  }

  /// Notifies the active sub-editor to rebuild its UI after a main editor
  /// undo/redo so that changes to applied filters, tune adjustments, blur,
  /// etc. are visually reflected in the sub-editor's preview.
  void _notifyActiveSubEditorRebuild() {
    if (tuneEditor.currentState != null) {
      tuneEditor.currentState!.updateAppliedState(
        filters: stateManager.activeFilters,
        tuneAdjustments: stateManager.activeTuneAdjustments,
        blur: stateManager.activeBlur,
        transformConfigs: stateManager.transformConfigs,
      );
      tuneEditor.currentState!.uiStream.add(null);
    }
    if (filterEditor.currentState != null) {
      filterEditor.currentState!.updateAppliedState(
        filters: stateManager.activeFilters,
        tuneAdjustments: stateManager.activeTuneAdjustments,
        blur: stateManager.activeBlur,
        transformConfigs: stateManager.transformConfigs,
      );
      filterEditor.currentState!.uiFilterStream.add(null);
    }
    if (blurEditor.currentState != null) {
      blurEditor.currentState!.updateAppliedState(
        filters: stateManager.activeFilters,
        tuneAdjustments: stateManager.activeTuneAdjustments,
        blur: stateManager.activeBlur,
        transformConfigs: stateManager.transformConfigs,
      );
      // BlurEditor doesn't have a dedicated UI stream; setState from main
      // editor's rebuild handles it.
    }
    if (cropRotateEditor.currentState != null) {
      cropRotateEditor.currentState!
          .applyExternalTransformConfigs(stateManager.transformConfigs);
    }
  }

  /// Takes a screenshot of the current editor state.
  ///
  /// This method is intended to be used for capturing the current state of the
  /// editor and saving it as an image.
  ///
  /// - If a subeditor is currently open, the method waits until it is fully
  ///   loaded.
  /// - The screenshot is taken in a post-frame callback to ensure the UI is
  ///   fully rendered.
  void _takeScreenshot({bool replaceLastScreenshot = false}) async {
    // Wait for the editor to be fully open, if it is currently opening
    if (isSubEditorOpen) await _pageOpenCompleter.future;

    if (replaceLastScreenshot) {
      stateManager.screenshots.removeLast();
    }

    // Capture the screenshot in a post-frame callback to ensure the UI is fully
    // rendered
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_imageInfos == null && mounted) await decodeImage();

      if (!mounted) return;

      await _controllers.screenshot.capture(
        imageInfos: _imageInfos!,
        screenshots: stateManager.screenshots,
      );
    });
  }

  /// Complete the editing process and return the edited image.
  ///
  /// This function is called when the user is done editing the image. If no
  /// changes have been made or if the image has no additional layers, it
  /// cancels the editing process and closes the editor. Otherwise, it captures
  /// the current state of the image, including any applied changes or layers,
  /// and returns it as a byte array.
  ///
  /// Before returning the edited image, a loading dialog is displayed to
  /// indicate that the operation is in progress.
  void doneEditing() async {
    mainEditorCallbacks?.handleDone();
    if (_isProcessingFinalImage) return;
    if (!stateManager.canUndo && activeLayers.isEmpty) {
      if (!imageGenerationConfigs.allowEmptyEditingCompletion) {
        return closeEditor();
      }
    }
    callbacks.onImageEditingStarted?.call();

    /// Hide every unnecessary element that Screenshot Controller will capture
    /// a correct image.
    setState(() {
      _isProcessingFinalImage = true;
      layerInteractionManager.clearSelectedLayers();
      _checkInteractiveViewer();
    });

    /// Ensure hero animations finished
    if (isSubEditorOpen) await _pageOpenCompleter.future;

    /// For the case the user add initial transformConfigs but there are no
    /// changes we need to ensure the editor will generate the image.
    if (mainEditorConfigs.transformSetup != null && !stateManager.canUndo) {
      addHistory();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      LoadingDialog.instance.show(
        context,
        theme: _theme,
        configs: configs,
        message: i18n.doneLoadingMsg,
      );

      if (callbacks.onThumbnailGenerated != null) {
        if (_imageInfos == null) await decodeImage();

        final results = await Future.wait([
          captureEditorImage(),
          _controllers.screenshot.getRawRenderedImage(
            imageInfos: _imageInfos!,
            useThumbnailSize: false,
          ),
        ]);

        await callbacks.onThumbnailGenerated!(
          results[0] as Uint8List,
          results[1] as ui.Image,
        );
      } else {
        Uint8List? bytes = await captureEditorImage();
        await onImageEditingComplete?.call(bytes);

        final transform = stateManager.transformConfigs;
        final isTransformed = transform.isNotEmpty;

        Size originalImageSize = _imageInfos!.rawSize;
        Size outputSize = transform.getCropSize(originalImageSize);
        Offset outputOffset = transform.getCropStartOffset(originalImageSize);

        await onCompleteWithParameters?.call(
          CompleteParameters(
            blur: stateManager.activeBlur,
            matrixFilterList: stateManager.activeFilters,
            matrixTuneAdjustmentsList: stateManager.activeTuneAdjustments
                .map((item) => item.matrix)
                .toList(),
            startTime: widget.videoController?.startTime,
            endTime: widget.videoController?.endTime,
            cropWidth: isTransformed ? outputSize.width.round() : null,
            cropHeight: isTransformed ? outputSize.height.round() : null,
            cropX: isTransformed ? outputOffset.dx.round() : null,
            cropY: isTransformed ? outputOffset.dy.round() : null,
            flipX: transform.is90DegRotated ? transform.flipY : transform.flipX,
            flipY: transform.is90DegRotated ? transform.flipX : transform.flipY,
            rotateTurns: transform.angleToTurns(),
            image: bytes,
            isTransformed: isTransformed,
            layers: activeLayers,
          ),
        );
      }

      LoadingDialog.instance.hide();

      onCloseEditor?.call(EditorMode.main);

      /// Allow users to continue editing if they didn't close the editor.
      setState(() => _isProcessingFinalImage = false);
    });
  }

  /// Adopts layer copies exported by a sub-editor into the main editor.
  ///
  /// Pushed sub-editors work on copies with their own GlobalKeys (see
  /// [openFilterEditor] and friends). Re-copies them and rebinds each copy
  /// to the live layer's keys (matched by id), so adopting them into
  /// history neither mounts the sub-editor's keys a second time while its
  /// route is still animating out, nor remounts the live LayerWidgets.
  List<Layer>? _adoptExportedLayers(List<Layer>? exported) {
    if (exported == null) return null;
    final adopted = _layerCopyManager.duplicateLayerList(
      exported,
      offset: Offset.zero,
      enableCopyId: true,
      enableCopyKey: false,
    );
    for (final layer in adopted) {
      final i = activeLayers.indexWhere((l) => l.id == layer.id);
      if (i >= 0) {
        layer
          ..key = activeLayers[i].key
          ..keyInternalSize = activeLayers[i].keyInternalSize;
      }
    }
    return adopted;
  }

  /// Extracts the state of the currently open subeditor (if any) and adds it
  /// to the history before switching to another subeditor. This ensures the
  /// newly opened subeditor receives the most up-to-date image state.
  Future<void> _commitCurrentSubEditorState() async {
    // Also commit when an embedded sub-editor is active
    // (initialSubEditor != null) because the embedded editor has no
    // navigation route, so isSubEditorOpen may be false.
    if (isSubEditorOpen || mainEditorConfigs.initialSubEditor != null) {
      if (cropRotateEditor.currentState != null) {
        await cropRotateEditor.currentState!.showFakeHero();
        // After skipAnimation the state might already be gone if the widget
        // was disposed during the pushReplacement, so guard with a null check.
        final cropState = cropRotateEditor.currentState;
        if (cropState != null) {
          final exported = cropState.exportStateHistory();
          final hasChanged = exported != stateManager.transformConfigs;
          if (hasChanged) {
            addHistory(transformConfigs: exported);
          }
        }
      } else if (filterEditor.currentState != null) {
        final exported = filterEditor.currentState!.exportStateHistory();
        final hasChanged = !listEquals(exported, stateManager.activeFilters);
        final exportedLayers = filterEditor.currentState!.exportLayers();
        if (hasChanged || exportedLayers != null) {
          addHistory(
            filters: hasChanged ? exported : null,
            layers: _adoptExportedLayers(exportedLayers),
          );
        }
      } else if (tuneEditor.currentState != null) {
        final tuneState = tuneEditor.currentState!;
        final exported = tuneState.exportStateHistory();
        // Filter out zero-value adjustments for comparison, because the tune
        // editor initializes all items to 0.0 even when the active state is [].
        final effectiveExported =
            exported.where((t) => t.value != 0.0).toList();
        final effectiveActive = stateManager.activeTuneAdjustments
            .where((t) => t.value != 0.0)
            .toList();
        final hasChanged = !listEquals(effectiveExported, effectiveActive);
        final exportedLayers = tuneState.exportLayers();
        if (hasChanged || exportedLayers != null) {
          addHistory(
            tuneAdjustments: hasChanged ? exported : null,
            layers: _adoptExportedLayers(exportedLayers),
          );
        }

        // Preserve redo entries as forward history so that redo survives
        // switching to another sub-editor.
        if (tuneState.canRedo) {
          final redoEntries = tuneState.redoStack;
          for (final redoState in redoEntries.reversed) {
            addHistory(
              tuneAdjustments: redoState,
              blockCaptureScreenshot: true,
            );
          }
          // Move pointer back so these become redo-able entries
          for (int i = 0; i < redoEntries.length; i++) {
            stateManager.undo();
          }
        }
      } else if (blurEditor.currentState != null) {
        final exported = blurEditor.currentState!.exportStateHistory();
        final hasChanged = exported != stateManager.activeBlur;
        final exportedLayers = blurEditor.currentState!.exportLayers();
        if (hasChanged || exportedLayers != null) {
          addHistory(
            blur: hasChanged ? exported : null,
            layers: _adoptExportedLayers(exportedLayers),
          );
        }
      } else if (paintEditor.currentState != null) {
        var res = paintEditor.currentState!.exportStateHistory();
        for (var layer in res.removedLayers) {
          removeLayer(layer, blockCaptureScreenshot: true);
        }
        for (var layer in res.layers) {
          final duplicatedLayer =
              _layerCopyManager.duplicateLayer(layer, offset: Offset.zero);
          final oldIndex = activeLayers.indexWhere((el) => el.id == layer.id);
          addLayer(duplicatedLayer,
              removeLayerIndex: oldIndex,
              blockSelectLayer: true,
              blockCaptureScreenshot: true,
              autoCorrectZoomOffset: false,
              autoCorrectZoomScale: false);
        }
      } else if (textEditor.currentState != null) {
        var layer = textEditor.currentState!.exportStateHistory();
        if (layer != null) addHistory(newLayer: layer);
      }
    }

    // Preserve the embedded sub-editor's GlobalKey so the LayoutBuilder
    // does not inflate a new widget tree during layout.
    resetGlobalKeys(preserve: mainEditorConfigs.initialSubEditor);
  }

  /// Captures the final editor image.
  ///
  /// This method generates the final image of the editor content, taking
  /// into account the pixel ratio for high-resolution images. If
  /// `generateOnlyImageBounds` is set in `imageGenerationConfigs`, it uses the
  /// base pixel ratio; otherwise, it uses the maximum of the base pixel ratio
  /// and the device's pixel ratio.
  ///
  /// Returns a [Uint8List] representing the final image.
  ///
  /// Returns an empty [Uint8List] if the screenshot capture fails.
  Future<Uint8List> captureEditorImage() async {
    if (isSubEditorOpen) {
      Navigator.pop(context);
      if (!_pageOpenCompleter.isCompleted) await _pageOpenCompleter.future;
      if (!mounted) return Uint8List.fromList([]);
    }

    if (_imageInfos == null) await decodeImage();

    if (!mounted) return Uint8List.fromList([]);

    bool hasChanges = stateManager.canUndo;
    bool useOriginalImage = !_isVideoEditor &&
        !hasChanges &&
        imageGenerationConfigs.enableUseOriginalBytes;

    if (!hasChanges && !imageGenerationConfigs.enableUseOriginalBytes) {
      addHistory();
    }

    return await _controllers.screenshot.captureFinalScreenshot(
          imageInfos: _imageInfos!,
          backgroundScreenshot:
              useOriginalImage ? null : stateManager.activeScreenshot,
          originalImageBytes: useOriginalImage
              ? await editorImage!.safeByteArray(context)
              : null,
        ) ??
        Uint8List.fromList([]);
  }

  /// Closes all active sub-editors within the main editor, including paint,
  /// text, crop/rotate, filter, tune, and emoji editors.
  /// This ensures that any open sub-editor is properly closed and the main
  /// editor returns to its default state.
  ///
  /// Returns a [Future] that completes when the sub-editor's route dismiss
  /// animation has finished and the widget has been fully removed from the
  /// tree. Await this before opening a new sub-editor to avoid duplicate
  /// GlobalKey errors.
  Future<void> closeSubEditor() async {
    if (!isSubEditorOpen) return;

    // Pop the route directly from the correct navigator to ensure the
    // route animation fires regardless of onCloseEditor callbacks.
    if (mainEditorConfigs.enableSubEditorPage) {
      _navigatorKey.currentState?.pop();
    } else {
      Navigator.of(context).pop();
    }

    // Wait for the route dismiss animation to complete so the old widget
    // is fully removed from the tree before a new editor can be opened.
    if (!_pageOpenCompleter.isCompleted) {
      await _pageOpenCompleter.future;
    }
  }

  /// Close the image editor.
  ///
  /// This function allows the user to close the image editor without saving
  /// any changes or edits.
  /// It navigates back to the previous screen or closes the modal editor.
  void closeEditor() {
    if (!stateManager.canUndo) {
      if (onCloseEditor == null) {
        Navigator.pop(context);
      } else {
        onCloseEditor!.call(EditorMode.main);
      }
    } else {
      closeWarning();
    }
  }

  /// Displays a warning dialog before closing the image editor.
  void closeWarning() async {
    if (isPopScopeDisabled) {
      Navigator.pop(context);
      return;
    }
    _isDialogOpen = true;

    bool close = false;

    if (!mounted) return;

    if (mainEditorConfigs.widgets.closeWarningDialog != null) {
      close = await mainEditorConfigs.widgets.closeWarningDialog!(this);
    } else {
      await showAdaptiveDialog(
        context: context,
        builder: (BuildContext context) => Theme(
          data: _theme,
          child: AdaptiveDialog(
            designMode: designMode,
            brightness: _theme.brightness,
            style: configs.dialogConfigs.style.adaptiveDialog,
            title: Text(i18n.various.closeEditorWarningTitle),
            content: Text(i18n.various.closeEditorWarningMessage),
            actions: <AdaptiveDialogAction>[
              AdaptiveDialogAction(
                designMode: designMode,
                onPressed: () => Navigator.pop(context, 'Cancel'),
                child: Text(i18n.various.closeEditorWarningCancelBtn),
              ),
              AdaptiveDialogAction(
                designMode: designMode,
                onPressed: () {
                  close = true;
                  Navigator.pop(context, 'OK');
                },
                child: Text(i18n.various.closeEditorWarningConfirmBtn),
              ),
            ],
          ),
        ),
      );
    }

    if (close) {
      if (onCloseEditor == null) {
        if (mounted) Navigator.pop(context);
      } else {
        onCloseEditor!.call(EditorMode.main);
      }
    }

    _isDialogOpen = false;
  }

  /// Imports state history and performs necessary recalculations.
  ///
  /// If [ImportStateHistory.configs.recalculateSizeAndPosition] is `true`, it
  /// recalculates the position and size of layers.
  /// It adjusts the scale and offset of each layer based on the image size and
  /// the editor's dimensions.
  ///
  /// If [ImportStateHistory.configs.mergeMode] is
  /// [ImportEditorMergeMode.replace], it replaces the current state history
  /// with the imported one.
  /// Otherwise, it merges the imported state history with the current one
  /// based on the merge mode.
  ///
  /// After importing, it updates the UI by calling [setState()] and the
  /// optional [onUpdateUI] callback.
  Future<void> importStateHistory(ImportStateHistory import) async {
    mainEditorCallbacks?.onImportHistoryStart?.call(this, import);

    await _stateHistoryService.importStateHistory(
      import,
      context,
      () => setState(() {}),
    );
    await decodeImage();

    mainEditorCallbacks?.onImportHistoryEnd?.call(this, import);
  }

  /// Exports the current state history.
  ///
  /// `configs` specifies the export configurations, such as whether to include
  /// filters or layers.
  ///
  /// Returns an [ExportStateHistory] object containing the exported state
  /// history, image state history, image size, edit position, and export
  /// configurations.
  Future<ExportStateHistory> exportStateHistory({
    ExportEditorConfigs configs = const ExportEditorConfigs(),
  }) async {
    if (_imageInfos == null) await decodeImage();
    if (_imageInfos == null) throw ArgumentError('Failed to decode the image');
    if (!mounted) throw ArgumentError('Context unmounted');

    return _stateHistoryService.exportStateHistory(
      imageInfos: _imageInfos!,
      configs: configs,
      context: context,
    );
  }

  /// Locks all layers in the editor.
  ///
  /// If [onlyCurrentHistory] is set to `true`, only the layers in the current
  /// history state will be locked.
  ///
  /// Parameters:
  /// - [onlyCurrentHistory]: A boolean value indicating whether to lock only
  ///   the layers in the current history state. Defaults to `false`.
  ///
  /// See also:
  /// - [unlockAllLayers] to unlock all layers.
  void lockAllLayers({bool onlyCurrentHistory = false}) {
    stateManager.updateLayerInteraction(
      enableInteraction: false,
      onlyCurrentHistory: onlyCurrentHistory,
    );
    clearLayerSelection();
  }

  /// Unlocks all layers in the editor.
  ///
  /// If [onlyCurrentHistory] is set to `true`, only the layers in the current
  /// history state will be unlocked.
  ///
  /// Parameters:
  /// - [onlyCurrentHistory]: A boolean value indicating whether to unlock only
  ///   the layers in the current history state. Defaults to `false`.
  ///
  /// See also:
  /// - [lockAllLayers] to lock all layers.
  void unlockAllLayers({bool onlyCurrentHistory = false}) {
    stateManager.updateLayerInteraction(
      enableInteraction: true,
      onlyCurrentHistory: onlyCurrentHistory,
    );
  }

  /// Clears the currently selected layer by:
  /// - Clearing the selected layer ID in the [layerInteractionManager]
  /// - Notifying listeners via [_controllers.uiLayerCtrl]
  void clearLayerSelection() {
    layerInteractionManager.clearSelectedLayers();
    _controllers.uiLayerCtrl.add(null);
  }

  /// Selects a layer by its index in [activeLayers].
  ///
  /// If the index is out of bounds, the selection is cleared and `null` is
  /// returned.
  /// Otherwise, the corresponding layer is marked as selected and listeners
  /// are notified.
  ///
  /// Returns the selected [Layer] or `null` if the index is invalid.
  Layer? selectLayerByIndex(int index, {bool enableMultiSelect = false}) {
    if (index < 0 || index >= activeLayers.length) {
      clearLayerSelection();
      return null;
    }

    var layer = activeLayers[index];

    return selectLayerById(layer.id, enableMultiSelect: enableMultiSelect);
  }

  /// Selects a layer by its unique [id].
  ///
  /// Internally uses [selectLayerByIndex] after finding the layer's index.
  ///
  /// Returns the selected [Layer] or `null` if the ID does not match any
  /// active layer.
  Layer? selectLayerById(String id, {bool enableMultiSelect = false}) {
    int index = activeLayers.indexWhere((layer) => layer.id == id);
    if (index == -1) return null;

    Layer? layer = activeLayers[index];

    // Check if the layer allows selection
    if (!layer.interaction.enableSelection) return null;

    if (!enableMultiSelect) layerInteractionManager.clearSelectedLayers();

    layerInteractionManager.addSelectedLayer(id);
    _controllers.uiLayerCtrl.add(null);
    return layer;
  }

  /// Selects all available layers.
  void selectAllLayers() {
    layerInteractionManager.setSelectedLayers(
      activeLayers
          .where((layer) => layer.interaction.enableSelection)
          .map((layer) => layer.id),
    );
    _controllers.uiLayerCtrl.add(null);
  }

  /// Deselects all currently selected layers.
  void unselectAllLayers() {
    layerInteractionManager.clearSelectedLayers();
    _controllers.uiLayerCtrl.add(null);
  }

  @override
  Widget build(BuildContext context) {
    _theme = configs.theme ??
        ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue.shade800,
            brightness: Brightness.dark,
          ),
        );

    return RecordInvisibleWidget(
      controller: _controllers.screenshot,
      child: ExtendedPopScope(
        canPop: (isPopScopeDisabled ||
                !stateManager.canUndo ||
                _isProcessingFinalImage) &&
            (!mainEditorConfigs.enableSubEditorPage || !isSubEditorOpen),
        onPopInvokedWithResult: (didPop, result) {
          if (mainEditorConfigs.enableSubEditorPage && isSubEditorOpen) {
            if (_navigatorKey.currentState?.canPop() == true) {
              _navigatorKey.currentState?.pop();
              return;
            }
          }
          if (!didPop &&
              !isPopScopeDisabled &&
              stateManager.canUndo &&
              !_isProcessingFinalImage) {
            closeWarning();
          }
          mainEditorCallbacks?.onPopInvoked?.call(didPop, result);
        },
        child: ImageInfosProvider(
          infos: _imageInfos,
          imageFitToWidth:
              _imageInfos?.renderedSize.width == sizesManager.bodySize.width,
          child: ScreenResizeDetector(
            ignoreSafeArea: false,
            onResizeUpdate: (event) {
              sizesManager
                ..recalculateLayerPosition(
                  history: stateManager.stateHistory,
                  resizeEvent: ResizeEvent(
                    oldContentSize: Size(
                      event.oldContentSize.width,
                      event.oldContentSize.height -
                          sizesManager.allToolbarHeight,
                    ),
                    newContentSize: Size(
                      event.newContentSize.width,
                      event.newContentSize.height -
                          sizesManager.allToolbarHeight,
                    ),
                  ),
                )
                ..lastScreenSize = event.newContentSize;
            },
            onResizeEnd: (event) async {
              await decodeImage();
            },
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: mainEditorConfigs.style.uiOverlayStyle,
              child: Theme(
                data: _theme,
                child: SafeArea(
                  top: mainEditorConfigs.safeArea.top,
                  bottom: mainEditorConfigs.safeArea.bottom,
                  left: mainEditorConfigs.safeArea.left,
                  right: mainEditorConfigs.safeArea.right,
                  // When initialSubEditor is set, the sub-editor is built
                  // OUTSIDE the LayoutBuilder (as a Stack sibling) to avoid
                  // creating new RenderRepaintBoundary render objects during
                  // _RenderLayoutBuilder.performLayout when GlobalKeys are
                  // reset. The LayoutBuilder only captures constraint sizes.
                  child: mainEditorConfigs.initialSubEditor != null
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            LayoutBuilder(
                              builder: (context, constraints) {
                                sizesManager.editorSize = constraints.biggest;
                                sizesManager.bodySize = constraints.biggest;
                                sizesManager.lastScreenSize =
                                    constraints.biggest;
                                return const SizedBox.shrink();
                              },
                            ),
                            _buildEmbeddedSubEditor(),
                          ],
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            sizesManager.editorSize = constraints.biggest;

                            var scaffold = Scaffold(
                              backgroundColor: mainEditorConfigs
                                      .style.background
                                      ?.call(context) ??
                                  kImageEditorBackground,
                              resizeToAvoidBottomInset:
                                  mainEditorConfigs.resizeToAvoidBottomInset,
                              appBar: _buildAppBar(),
                              body: _buildBody(),
                              bottomNavigationBar: _buildBottomNavBar(),
                            );

                            if (mainEditorConfigs.enableSubEditorPage) {
                              return Stack(
                                children: [
                                  scaffold,
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      ignoring: !isSubEditorOpen,
                                      child: Navigator(
                                        key: _navigatorKey,
                                        onGenerateRoute: (settings) =>
                                            PageRouteBuilder(
                                          opaque: false,
                                          pageBuilder: (context, _, __) =>
                                              const SizedBox.shrink(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }

                            return scaffold;
                          },
                        ),
                  // child: LayoutBuilder(builder: (context, constraints) {
                  //   sizesManager.editorSize = constraints.biggest;
                  //   return Scaffold(
                  //     backgroundColor:
                  //         mainEditorConfigs.style.background?.call(context) ??
                  //             kImageEditorBackground,
                  //     resizeToAvoidBottomInset: false,
                  //     appBar: _buildAppBar(),
                  //     body: _buildBody(),
                  //     bottomNavigationBar: _buildBottomNavBar(),
                  //   );
                  // }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget? _buildAppBar() {
    if (mainEditorConfigs.widgets.appBar != null) {
      return mainEditorConfigs.widgets.appBar!.call(
        this,
        _rebuildController.stream,
      );
    }

    return hasSelectedLayers &&
            configs.layerInteraction.hideToolbarOnInteraction
        ? null
        : MainEditorAppBar(
            i18n: i18n,
            configs: configs,
            closeEditor: closeEditor,
            undoAction: undoAction,
            redoAction: redoAction,
            doneEditing: doneEditing,
            isInitialized: _isInitialized,
            stateManager: stateManager,
          );
  }

  Widget _buildBody() {
    return LayoutBuilder(builder: (context, constraints) {
      sizesManager.bodySize = constraints.biggest;
      return !_isVideoPlayerReady
          ? _buildVideoSetupSpinner()
          : Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (details) {
                _lastDownEvent = details;
                _tapDownTimestamp = DateTime.now();
                _mouseService.onPointerDown(details);
                if (layerInteractionManager.selectedLayerId.isNotEmpty ||
                    GestureManager.instance.isBlocked) {
                  return;
                }
                bool isDoubleTap = detectDoubleTap(details);
                if (!isDoubleTap) return;

                handleDoubleTap(context, details, mainEditorConfigs);
                mainEditorCallbacks?.onDoubleTap?.call();
              },
              onPointerUp: (event) {
                _mouseService.onPointerUp(event);
                onPointerUp(event);

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final offsetDistance =
                      (event.position - _lastDownEvent!.position).distance;
                  final timeElapsed = DateTime.now()
                      .difference(_tapDownTimestamp)
                      .inMilliseconds;

                  // Ignore if pointer moved too much (exceeds tap slop)
                  if (offsetDistance >= tapSlop) return;

                  // Ignore if tap took too long (not a quick tap)
                  if (timeElapsed > tapTimeElapsed) return;

                  if (!configs.videoEditor.enablePlayButton) {
                    widget.videoController?.togglePlayState();
                  }
                  mainEditorCallbacks?.onTap?.call();
                });
              },
              onPointerSignal: isDesktop && hasSelectedLayers
                  ? (event) {
                      final hasMultiSelection = selectedLayers.length > 1;

                      final zoomEnabled = mainEditorConfigs.enableZoom;
                      final zoomGestureActive = interactiveViewer
                              .currentState?.isInteractionEnabled ==
                          true;

                      if ((hasMultiSelection && zoomEnabled) ||
                          (zoomEnabled && zoomGestureActive)) {
                        return;
                      }

                      /// Otherwise, handle scroll as a layer scaling
                      /// interaction.
                      _desktopInteractionManager.mouseScroll(event,
                          selectedLayers: selectedLayers,
                          interactiveViewer: interactiveViewer.currentState);
                    }
                  : null,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  /// That function is required so that multiselect works
                  /// correctly, even when it’s empty.
                },
                onLongPress: mainEditorCallbacks?.onLongPress,
                child: _buildInteractiveContent(),
              ),
            );
    });
  }

  Widget _buildInteractiveContent() {
    return MainEditorInteractiveContent(
      buildImage: _buildImage,
      buildVideo: _buildVideo,
      buildLayers: _buildLayers,
      callbacks: callbacks,
      sizesManager: sizesManager,
      configs: configs,
      layerInteractionManager: layerInteractionManager,
      controllers: _controllers,
      processFinalImage: _isProcessingFinalImage,
      rebuildController: _rebuildController,
      stateManager: stateManager,
      interactiveViewerKey: interactiveViewer,
      state: this,
      videoController: widget.videoController,
      isVideoEditor: _isVideoEditor,
      layerDragSelectionService: _layerDragSelectionService,
      wrapBody: mainEditorConfigs.widgets.wrapBody,
      isCropAnimating: _isCropAnimating,
    );
  }

  Widget? _buildBottomNavBar() {
    if (mainEditorConfigs.widgets.bottomBar != null) {
      return mainEditorConfigs.widgets.bottomBar!.call(
        this,
        _rebuildController.stream,
        _bottomBarKey,
      );
    }

    return hasSelectedLayers &&
            configs.layerInteraction.hideToolbarOnInteraction
        ? null
        : MainEditorBottombar(
            controllers: _controllers,
            configs: configs,
            sizesManager: sizesManager,
            bottomBarKey: _bottomBarKey,
            theme: _theme,
            openPaintEditor: openPaintEditor,
            openTextEditor: openTextEditor,
            openCropRotateEditor: openCropRotateEditor,
            openTuneEditor: openTuneEditor,
            openFilterEditor: openFilterEditor,
            openBlurEditor: openBlurEditor,
            openEmojiEditor: openEmojiEditor,
            openStickerEditor: openStickerEditor,
          );
  }

  Widget _buildLayers() {
    return InteractiveLayerStack(
      layerInteractionManager: layerInteractionManager,
      configs: configs,
      callbacks: callbacks,
      layers: activeLayers,
      editorBodySize: sizesManager.bodySize,
      editorSize: sizesManager.editorSize,
      appBarHeight: sizesManager.appBarHeight,
      bottomBarHeight: sizesManager.bottomBarHeight,
      overlayColor: kImageEditorBackground,
      isInteractive: !isSubEditorOpen,
      enableHero: !isSubEditorOpen ||
          (_activeSubEditor == SubEditor.text && !_isTextOverSubEditor),
      enableHelperLines: true,
      enableRemoveArea: true,
      removeAreaBuilder: configs.mainEditor.widgets.removeLayerArea == null
          ? null
          : (removeAreaKey, manager, rebuildStream, isLayerBeingTransformed,
                  imageBounds) =>
              configs.mainEditor.widgets.removeLayerArea!(
                removeAreaKey,
                manager,
                rebuildStream,
                isLayerBeingTransformed,
                imageBounds,
              ),
      heroResetStream: _controllers.layerHeroResetCtrl.stream,
      mouseService: _mouseService,
      isDragSelectionActive: _layerDragSelectionService.isActive,
      interactiveViewerKey: interactiveViewer,
      onCheckInteractiveViewer: _checkInteractiveViewer,
      onTextLayerTap: _onTextLayerTap,
      onPaintLayerEdit: _editPaintLayer,
      getActiveLayers: () => activeLayers,
      getEnableMultiSelectMode: () => enableMultiSelectMode,
      onAddHistory: (layers) {
        addHistory(layers: layers, blockCaptureScreenshot: true);
      },
      onUIUpdate: () {
        _controllers.uiLayerCtrl.add(null);
        mainEditorCallbacks?.handleUpdateUI();
      },
      onLayerTapDown: (layer) {
        mainEditorCallbacks?.onLayerTapDown?.call(layer);
      },
      onLayerTapUp: (layer) {
        mainEditorCallbacks?.onLayerTapUp?.call(layer);
      },
      onEditSticker: (layer) {
        callbacks.stickerEditorCallbacks?.onTapEditSticker
            ?.call(this, layer as WidgetLayer);
      },
      onLayerRemoved: (layer) {
        removeLayer(layer);
        mainEditorCallbacks?.handleUpdateUI();
      },
      onRemoveLayer: (layer) {
        mainEditorCallbacks?.handleRemoveLayer(layer);
      },
      onHoverRemoveAreaChange: (value) {
        _controllers.removeBtnCtrl.add(null);
        mainEditorCallbacks?.onHoverRemoveAreaChange?.call(value);
      },
      onTakeScreenshot: ({bool replaceLastScreenshot = false}) {
        _takeScreenshot(replaceLastScreenshot: replaceLastScreenshot);
      },
      onContextMenuToggled: (isOpen) {
        _isContextMenuOpen = isOpen;
      },
      onDuplicateLayer: (layer) {
        var duplication = _layerCopyManager.duplicateLayer(layer);
        addLayer(
          duplication,
          autoCorrectZoomOffset: false,
          autoCorrectZoomScale: false,
        );
      },
    );
  }

  Widget _buildVideoSetupSpinner() {
    return configs.videoEditor.widgets.videoSetupLoadingIndicator ??
        Center(
          child: SizedBox(
            width: 48,
            height: 48,
            child: FittedBox(
              child: PlatformCircularProgressIndicator(configs: configs),
            ),
          ),
        );
  }

  Widget _buildImage() {
    return MainEditorBackgroundImage(
      backgroundImageColorFilterKey:
          _isVideoEditor ? GlobalKey() : _backgroundImageColorFilterKey,
      heroTag: _isVideoEditor ? 'image-${configs.heroTag}' : configs.heroTag,
      configs: configs,
      editorImage: editorImage,
      isInitialized: _isInitialized ||
          stateHistoryConfigs.initStateHistory != null ||
          _stateHistoryService.isImportInProgress,
      sizesManager: sizesManager,
      stateManager: stateManager,
      blankSize: widget.blankSize,
      onCropAnimationChanged: (isAnimating) {
        setState(() {
          _isCropAnimating = isAnimating;
        });
      },
      onAllAnimationsComplete: () {
        if (_isBackgroundOverrideActive) {
          setState(() {
            _isBackgroundOverrideActive = false;
          });
        }
      },
    );
  }

  Widget _buildVideo() {
    return MainEditorBackgroundVideo(
      backgroundImageColorFilterKey: _backgroundImageColorFilterKey,
      configs: configs,
      isInitialized: _isInitialized,
      sizesManager: sizesManager,
      stateManager: stateManager,
      videoPlayer: widget.videoController!.videoPlayer,
    );
  }

  /// Builds the embedded sub-editor directly in the main editor's widget tree.
  ///
  /// The sub-editor receives the main editor's background image as an override
  /// so that the hero animation and crop animation are controlled by the main
  /// editor.
  Widget _buildEmbeddedSubEditor() {
    final subEditorMode = mainEditorConfigs.initialSubEditor!;

    // Pass the main editor's full interactive content (with
    // ExtendedInteractiveViewer, Hero, crop animation, layers, etc.)
    // as the background override. The sub-editor will use this directly
    // in its body instead of its own ExtendedInteractiveViewer + background.
    final Widget? backgroundOverride =
        _isBackgroundOverrideActive ? _buildInteractiveContent() : null;

    switch (subEditorMode) {
      case SubEditorMode.tune:
        return TuneEditor.autoSource(
          key: tuneEditor,
          editorImage: widget.blankSize == null
              ? editorImage
              : EditorImage(byteArray: kImageEditorTransparentBytes),
          videoController: widget.videoController,
          initConfigs: TuneEditorInitConfigs(
            theme: _theme,
            configs: configs,
            callbacks: callbacks,
            transformConfigs: stateManager.transformConfigs,
            layers: _layerCopyManager.copyLayerList(activeLayers),
            mainImageSize: widget.blankSize ?? sizesManager.decodedImageSize,
            mainBodySize: sizesManager.bodySize,
            convertToUint8List: false,
            appliedBlurFactor: stateManager.activeBlur,
            appliedFilters: stateManager.activeFilters,
            appliedTuneAdjustments: stateManager.activeTuneAdjustments,
            backgroundImageOverride: backgroundOverride,
            onTextLayerTap: _onTextLayerTap,
            onLayerTransformChanged: _syncLayerTransforms,
            historyScope: _editorHistoryScope,
          ),
        );
      case SubEditorMode.filter:
        return FilterEditor.autoSource(
          key: filterEditor,
          editorImage: widget.blankSize == null
              ? editorImage
              : EditorImage(byteArray: kImageEditorTransparentBytes),
          videoController: widget.videoController,
          initConfigs: FilterEditorInitConfigs(
            theme: _theme,
            configs: configs,
            callbacks: callbacks,
            transformConfigs: stateManager.transformConfigs,
            layers: _layerCopyManager.copyLayerList(activeLayers),
            mainImageSize: widget.blankSize ?? sizesManager.decodedImageSize,
            mainBodySize: sizesManager.bodySize,
            convertToUint8List: false,
            appliedBlurFactor: stateManager.activeBlur,
            appliedFilters: stateManager.activeFilters,
            appliedTuneAdjustments: stateManager.activeTuneAdjustments,
            backgroundImageOverride: backgroundOverride,
            onTextLayerTap: _onTextLayerTap,
            onLayerTransformChanged: _syncLayerTransforms,
            historyScope: _editorHistoryScope,
          ),
        );
      case SubEditorMode.blur:
        return BlurEditor.autoSource(
          key: blurEditor,
          editorImage: widget.blankSize == null
              ? editorImage
              : EditorImage(byteArray: kImageEditorTransparentBytes),
          videoController: widget.videoController,
          initConfigs: BlurEditorInitConfigs(
            theme: _theme,
            configs: configs,
            callbacks: callbacks,
            transformConfigs: stateManager.transformConfigs,
            layers: _layerCopyManager.copyLayerList(activeLayers),
            mainImageSize: widget.blankSize ?? sizesManager.decodedImageSize,
            mainBodySize: sizesManager.bodySize,
            convertToUint8List: false,
            appliedBlurFactor: stateManager.activeBlur,
            appliedFilters: stateManager.activeFilters,
            appliedTuneAdjustments: stateManager.activeTuneAdjustments,
            backgroundImageOverride: backgroundOverride,
            onTextLayerTap: _onTextLayerTap,
            onLayerTransformChanged: _syncLayerTransforms,
            historyScope: _editorHistoryScope,
          ),
        );
      default:
        // Unsupported sub-editor modes fall back to normal scaffold
        return Scaffold(
          backgroundColor: mainEditorConfigs.style.background?.call(context) ??
              kImageEditorBackground,
          resizeToAvoidBottomInset: mainEditorConfigs.resizeToAvoidBottomInset,
          appBar: _buildAppBar(),
          body: _buildBody(),
          bottomNavigationBar: _buildBottomNavBar(),
        );
    }
  }
}

/// Throwaway [TextInputClient] used by
/// [ProImageEditorState._prewarmKeyboard] to bring up the keyboard before the
/// text editor opens and hold the IME through the hero flight.
///
/// It is seeded with the edited text's editing state (so the keyboard's
/// shift/auto-capitalization context is correct) and forwards everything the
/// user types into [targetController] — the editor's shared text controller —
/// so typing already works during the flight, live in the flight shuttle.
/// The TextEditor's real field replaces the connection once the flight
/// settles. All remaining callbacks are no-ops via [noSuchMethod] (which also
/// keeps this robust against [TextInputClient] interface additions across
/// Flutter versions).
class _KeyboardWarmupClient implements TextInputClient {
  _KeyboardWarmupClient(this._value);

  TextEditingValue _value;

  /// The editor's text controller, wired once the editor route is built.
  /// While null, input only updates the local [_value].
  TextEditingController? targetController;

  @override
  TextEditingValue get currentTextEditingValue => _value;

  @override
  void updateEditingValue(TextEditingValue value) {
    _value = value;
    targetController?.value = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
