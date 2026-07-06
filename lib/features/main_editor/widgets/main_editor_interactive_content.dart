import 'dart:async';
import 'package:flutter/material.dart';
import 'package:heroine/heroine.dart';

import '/shared/widgets/smart_hero.dart';

import '../../../core/constants/editor_style_constants.dart';
import '/core/models/editor_callbacks/pro_image_editor_callbacks.dart';
import '/core/models/editor_configs/pro_image_editor_configs.dart';
import '/features/crop_rotate_editor/widgets/crop_layer_painter.dart';
import '/features/main_editor/controllers/main_editor_controllers.dart';
import '/features/main_editor/services/layer_interaction_manager.dart';
import '/shared/controllers/video_controller.dart';
import '/shared/services/content_recorder/widgets/content_recorder.dart';
import '/shared/widgets/extended/interactive_viewer/extended_interactive_viewer.dart';
import '/shared/widgets/layer/layer_drag_selection_area_widget.dart';
import '/shared/widgets/video/video_editor_configurable.dart';
import '/shared/widgets/video/video_editor_controls_widget.dart';
import '../../crop_rotate_editor/enums/crop_mode.enum.dart';
import '../main_editor.dart';
import '../services/layer_drag_selection_service.dart';
import '../services/sizes_manager.dart';
import '../services/state_manager.dart';
import 'main_editor_font_preloader.dart';

/// A widget representing the interactive content area of the main editor,
/// including layers, helper lines, and editing interactions.
class MainEditorInteractiveContent extends StatelessWidget {
  /// Creates a `MainEditorInteractiveContent` widget with the provided
  /// builders, managers, configurations, and callbacks.
  ///
  /// - [buildImage]: A builder function to create the image widget.
  /// - [buildVideo]: A builder function to create the video widget.
  /// - [buildLayers]: A builder function to create the layer widgets.
  /// - [buildHelperLines]: A builder function to create the helper lines
  ///   widget.
  /// - [buildRemoveArea]: A builder function to create the remove area widget.
  /// - [stateManager]: Manages the state of the editor.
  /// - [sizesManager]: Handles size-related settings and adjustments.
  /// - [state]: Represents the current state of the editor.
  /// - [configs]: Configuration settings for the editor.
  /// - [callbacks]: Provides callbacks for editor interactions.
  /// - [controllers]: Manages the main editor's controllers.
  /// - [layerInteractionManager]: Handles interactions with editor layers.
  /// - [rebuildController]: A stream controller for triggering UI rebuilds.
  /// - [interactiveViewerKey]: A key for managing the interactive viewer state.
  /// - [processFinalImage]: Indicates whether the final image is being
  ///   processed.
  const MainEditorInteractiveContent({
    super.key,
    required this.buildImage,
    required this.buildVideo,
    required this.buildLayers,
    required this.callbacks,
    required this.sizesManager,
    required this.configs,
    required this.layerInteractionManager,
    required this.controllers,
    required this.processFinalImage,
    required this.rebuildController,
    required this.stateManager,
    required this.interactiveViewerKey,
    required this.state,
    required this.isVideoEditor,
    required this.videoController,
    required this.layerDragSelectionService,
    this.wrapBody,
    this.isCropAnimating = false,
  });

  /// A builder function to create the image widget.
  final Widget Function() buildImage;

  /// A builder function to create the video widget.
  final Widget Function() buildVideo;

  /// A builder function to create the layer widgets.
  final Widget Function() buildLayers;

  /// Manages the state of the editor.
  final StateManager stateManager;

  /// Handles size-related settings and adjustments.
  final SizesManager sizesManager;

  /// Represents the current state of the editor.
  final ProImageEditorState state;

  /// Configuration settings for the editor.
  final ProImageEditorConfigs configs;

  /// Provides callbacks for editor interactions.
  final ProImageEditorCallbacks callbacks;

  /// Manages the main editor's controllers.
  final MainEditorControllers controllers;

  /// Handles interactions with editor layers.
  final LayerInteractionManager layerInteractionManager;

  /// A stream controller for triggering UI rebuilds.
  final StreamController<void> rebuildController;

  /// A key for managing the interactive viewer state.
  final GlobalKey<ExtendedInteractiveViewerState> interactiveViewerKey;

  /// Indicates whether the final image is being processed.
  final bool processFinalImage;

  /// Indicates whether the image or video editor is active.
  final bool isVideoEditor;

  /// Manages video-related functionalities within the main editor.
  final ProVideoController? videoController;

  /// Manages the drag-to-select layer interaction.
  final LayerDragSelectionService layerDragSelectionService;

  /// An optional callback to wrap only the interactive viewer content.
  ///
  /// When provided, this wraps the image/layers viewer while keeping
  /// overlays (helper lines, remove area, body items) on top.
  final Widget Function(
    ProImageEditorState editor,
    Widget content,
  )? wrapBody;

  /// Whether the initial crop animation is currently playing.
  final bool isCropAnimating;

  @override
  Widget build(BuildContext context) {
    bool hasSelectedLayers = layerInteractionManager.hasSelectedLayers;

    return Center(
      child: Stack(
        children: [
          MainEditorFontPreloader(emojiEditorConfigs: configs.emojiEditor),
          Padding(
            padding: hasSelectedLayers &&
                    configs.layerInteraction.hideToolbarOnInteraction
                ? EdgeInsets.only(
                    top: sizesManager.appBarHeight,
                    bottom: sizesManager.bottomBarHeight,
                  )
                : EdgeInsets.zero,
            child: wrapBody?.call(state, _buildInteractiveViewer()) ??
                _buildInteractiveViewer(),
          ),

          /// Build crop area overlay
          if (configs.imageGeneration.cropToImageBounds && !isCropAnimating)
            _buildCropAreaOverlay(),

          /// Build video controls
          if (isVideoEditor && configs.videoEditor.showControls)
            AnimatedOpacity(
              opacity: hasSelectedLayers ? 0 : 1,
              duration: configs.layerInteraction.videoControlsSwitchDuration,
              child: IgnorePointer(
                ignoring: hasSelectedLayers,
                child: VideoEditorConfigurable(
                  controller: videoController!,
                  child: const VideoEditorControlsWidget(),
                ),
              ),
            ),

          /// Build helper content
          if (!processFinalImage) ...[
            _buildLayerSelector(),
          ],

          /// Build custom body items
          if (configs.mainEditor.widgets.bodyItems != null)
            ...configs.mainEditor.widgets.bodyItems!(
              state,
              rebuildController.stream,
            ),
        ],
      ),
    );
  }

  Widget _buildLayerSelector() {
    return LayerDragSelectionAreaWidget(
      layerDragSelectionService: layerDragSelectionService,
    );
  }

  Widget _buildInteractiveViewer() {
    var mainConfigs = configs.mainEditor;

    // Determine the effective aspect ratio from crop state or original image.
    final transformConfigs = stateManager.transformConfigs;
    final double? effectiveAspectRatio = transformConfigs.isNotEmpty
        ? transformConfigs.cropRect.size.aspectRatio
        : (sizesManager.decodedImageSize != Size.zero
            ? sizesManager.decodedImageSize.aspectRatio
            : null);

    final fit = mainConfigs.viewportFitBuilder?.call(effectiveAspectRatio) ??
        const ViewportFitResult();

    // Auto-compute contentInset from the effective aspect ratio so the
    // pan boundaries correctly account for FittedBox letterboxing.
    final EdgeInsets effectiveContentInset =
        ViewportFitResult.computeContentInset(
      aspectRatio: effectiveAspectRatio,
      viewportSize: sizesManager.bodySize,
    );

    return ExtendedInteractiveViewer(
      key: interactiveViewerKey,
      enableExternalGestureDetector: true,
      zoomConfigs: mainConfigs,
      boundaryMargin: fit.boundaryMargin,
      contentInset: effectiveContentInset,
      minScale: fit.editorMinScale,
      maxScale: fit.editorMaxScale,
      initialMatrix4: fit.initialTransform,
      onInteractionStart: (details) {
        callbacks.mainEditorCallbacks?.onEditorZoomScaleStart?.call(details);

        controllers.uiLayerCtrl.add(null);
      },
      onInteractionUpdate: (details) {
        callbacks.mainEditorCallbacks?.onEditorZoomScaleUpdate?.call(details);
        controllers.cropLayerPainterCtrl.add(null);
      },
      onInteractionEnd: (details) {
        callbacks.mainEditorCallbacks?.onEditorZoomScaleEnd?.call(details);
        controllers.uiLayerCtrl.add(null);
        controllers.cropLayerPainterCtrl.add(null);
      },
      onMatrix4Change: (value) {
        controllers.cropLayerPainterCtrl.add(null);
        callbacks.mainEditorCallbacks?.onEditorZoomMatrix4Change?.call(value);
      },
      child: isVideoEditor
          ? Stack(
              alignment: Alignment.center,
              fit: StackFit.expand,
              children: [
                buildVideo(),
                _buildContentRecorder(),
              ],
            )
          : _buildContentRecorder(),
    );
  }

  Widget _buildContentRecorder() {
    return ContentRecorder(
      key: const ValueKey('main-editor-content-recorder'),
      autoDestroyController: false,
      controller: controllers.screenshot,
      child: Stack(
        alignment: Alignment.center,
        fit: StackFit.expand,
        children: [
          buildImage(),
          buildLayers(),
          if (configs.mainEditor.widgets.bodyItemsRecorded != null)
            ...configs.mainEditor.widgets.bodyItemsRecorded!(
                state, rebuildController.stream),
        ],
      ),
    );
  }

  Widget _buildCropAreaOverlay() {
    return SmartHero(
      tag: 'crop_layer_painter_hero',
      // Match the sub-editor screen transition: same duration, same spring
      // as the layer/text heroines.
      motion: CupertinoMotion.smooth(
        duration: configs.mainEditor.style.subEditorPage.transitionDuration,
        snapToEnd: true,
      ),
      child: StreamBuilder(
        stream: controllers.cropLayerPainterCtrl.stream,
        builder: (context, snapshot) {
          return CustomPaint(
            foregroundPainter: configs.imageGeneration.cropToImageBounds
                ? _buildCropLayerPainter(context)
                // ? CropLayerPainter(
                //     opacity:
                //         configs.mainEditor.style.outsideCaptureAreaLayerOpacity,
                //     backgroundColor:
                //         configs.mainEditor.style.background?.call(context) ??
                //             kImageEditorBackground,
                //     imgRatio: stateManager.transformConfigs.isNotEmpty
                //         ? stateManager
                //             .transformConfigs.cropRect.size.aspectRatio
                //         : sizesManager.decodedImageSize.aspectRatio,
                //     isRoundCropper: configs.cropRotateEditor.enableRoundCropper,
                //     is90DegRotated:
                //         stateManager.transformConfigs.is90DegRotated,
                //     interactiveViewerScale:
                //         interactiveViewerKey.currentState?.scaleFactor ?? 1.0,
                //     interactiveViewerOffset:
                //         interactiveViewerKey.currentState?.offset ??
                //             Offset.zero,
                //   )
                : null,
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }

  CropLayerPainter _buildCropLayerPainter(BuildContext context) {
    final transformConfigs = stateManager.transformConfigs;
    final hasTransformChanges = transformConfigs.isNotEmpty;
    final cropMode = transformConfigs.cropMode;

    return CropLayerPainter(
      opacity: configs.mainEditor.style.outsideCaptureAreaLayerOpacity,
      backgroundColor: configs.mainEditor.style.background?.call(context) ??
          kImageEditorBackground,
      imgRatio: hasTransformChanges
          ? transformConfigs.cropRect.size.aspectRatio
          : sizesManager.decodedImageSize.aspectRatio,
      isRoundCropper: cropMode == CropMode.oval,
      is90DegRotated: transformConfigs.is90DegRotated,
      interactiveViewerScale:
          interactiveViewerKey.currentState?.scaleFactor ?? 1.0,
      interactiveViewerOffset:
          interactiveViewerKey.currentState?.offset ?? Offset.zero,
    );
  }
}
