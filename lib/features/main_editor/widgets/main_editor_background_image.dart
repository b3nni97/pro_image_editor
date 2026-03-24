import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '/core/models/editor_configs/pro_image_editor_configs.dart';
import '/core/models/editor_image.dart';
import '/features/filter_editor/widgets/filter_generator.dart';
import '/shared/widgets/auto_image.dart';
import '/shared/widgets/transform/transformed_content_generator.dart';
import '../../filter_editor/widgets/filtered_widget.dart';
import '../services/sizes_manager.dart';
import '../services/state_manager.dart';

/// A widget for displaying the background image in the main editor,
/// supporting color filters, size configurations, and animated crop
/// transitions for hero animations.
class MainEditorBackgroundImage extends StatefulWidget {
  /// Creates a `MainEditorBackgroundImage` with the provided configurations
  /// and dependencies.
  const MainEditorBackgroundImage({
    super.key,
    required this.stateManager,
    required this.sizesManager,
    required this.configs,
    required this.editorImage,
    required this.backgroundImageColorFilterKey,
    required this.isInitialized,
    required this.heroTag,
    required this.blankSize,
    this.onCropAnimationChanged,
    this.onAllAnimationsComplete,
  }) : assert(editorImage != null || blankSize != null,
            'Either editorImage or blankSize must be provided');

  /// The size of the blank canvas when no image is present.
  final Size? blankSize;

  /// The main image being edited in the editor.
  final EditorImage? editorImage;

  /// Manages the state of the editor.
  final StateManager stateManager;

  /// Handles size configurations and adjustments.
  final SizesManager sizesManager;

  /// Configuration settings for the editor.
  final ProImageEditorConfigs configs;

  /// A key for managing the color filter applied to the background image.
  final GlobalKey<ColorFilterGeneratorState> backgroundImageColorFilterKey;

  /// Indicates whether the editor has been fully initialized.
  final bool isInitialized;

  /// A unique hero tag for the Image Editor widget.
  final String heroTag;

  /// Called when the crop animation state changes.
  /// `true` when animation starts, `false` when it ends.
  final ValueChanged<bool>? onCropAnimationChanged;

  /// Called once when all initial animations (hero + crop) are complete.
  /// Used by embedded sub-editors to know when to switch to their own
  /// background rendering.
  final VoidCallback? onAllAnimationsComplete;

  @override
  State<MainEditorBackgroundImage> createState() =>
      _MainEditorBackgroundImageState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);

    properties
      ..add(StringProperty('heroTag', heroTag))
      ..add(FlagProperty(
        'isInitialized',
        value: isInitialized,
        ifTrue: 'initialized',
        ifFalse: 'not initialized',
        showName: true,
      ))
      ..add(DiagnosticsProperty<bool>(
        'isTransformed',
        stateManager.transformConfigs.isEmpty,
      ))
      ..add(IntProperty(
        'activeFiltersCount',
        stateManager.activeFilters.length,
      ))
      ..add(IntProperty(
        'activeTuneAdjustmentsCount',
        stateManager.activeTuneAdjustments.length,
      ))
      ..add(DoubleProperty('blurFactor', stateManager.activeBlur))
      ..add(
        DiagnosticsProperty('imageSize', sizesManager.decodedImageSize),
      )
      ..add(
        DiagnosticsProperty<EditorImage>('editorImage', editorImage),
      )
      ..add(
        DiagnosticsProperty<StateManager>('stateManager', stateManager),
      )
      ..add(
        DiagnosticsProperty<SizesManager>('sizesManager', sizesManager),
      )
      ..add(
        DiagnosticsProperty<ProImageEditorConfigs>('configs', configs),
      )
      ..add(DiagnosticsProperty<GlobalKey<ColorFilterGeneratorState>>(
        'backgroundImageColorFilterKey',
        backgroundImageColorFilterKey,
      ));
  }
}

class _MainEditorBackgroundImageState extends State<MainEditorBackgroundImage>
    with SingleTickerProviderStateMixin {
  AnimationController? _cropAnimCtrl;
  Animation<double>? _cropAnimation;

  /// The transform configs captured when the crop animation starts.
  TransformConfigs? _targetTransformConfigs;

  /// The full (uncropped) rect to animate from.
  Rect? _fullRect;

  /// Whether the crop animation has completed.
  bool _cropAnimDone = false;

  /// Whether onAllAnimationsComplete has been called already.
  bool _didNotifyAnimationsComplete = false;

  /// Tracks the previous initialized state to detect transitions.
  bool _wasInitialized = false;

  @override
  void didUpdateWidget(covariant MainEditorBackgroundImage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isInitialized && !_wasInitialized) {
      _wasInitialized = true;
      _checkAndStartCropAnimation();
    }
  }

  @override
  void dispose() {
    _cropAnimCtrl?.dispose();
    super.dispose();
  }

  /// Checks if aspect ratio clamping produced a crop and starts the
  /// animated transition from full rect to cropped rect.
  void _checkAndStartCropAnimation() {
    final tc = widget.stateManager.transformConfigs;

    // Only animate if a crop has actually been applied
    if (tc.isEmpty || tc.originalSize.isInfinite) {
      _cropAnimDone = true;
      _notifyAllAnimationsCompleteIfReady();
      return;
    }

    final origSize = tc.originalSize;
    final fullCropRect = Rect.fromLTWH(
      0,
      0,
      origSize.width,
      origSize.height,
    );

    // If cropRect equals fullRect, no crop animation needed
    if ((tc.cropRect.left - fullCropRect.left).abs() < 0.5 &&
        (tc.cropRect.top - fullCropRect.top).abs() < 0.5 &&
        (tc.cropRect.width - fullCropRect.width).abs() < 0.5 &&
        (tc.cropRect.height - fullCropRect.height).abs() < 0.5) {
      _cropAnimDone = true;
      _notifyAllAnimationsCompleteIfReady();
      return;
    }

    _targetTransformConfigs = tc;
    _fullRect = fullCropRect;
    _cropAnimDone = false;

    _cropAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _cropAnimation = CurvedAnimation(
      parent: _cropAnimCtrl!,
      curve: Curves.easeInOut,
    );

    _cropAnimCtrl!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onCropAnimationChanged?.call(false);
        setState(() {
          _cropAnimDone = true;
        });
        _notifyAllAnimationsCompleteIfReady();
      }
    });

    // Start after the current frame so the hero transition settles first
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Notify parent that crop animation is starting
        widget.onCropAnimationChanged?.call(true);
        _cropAnimCtrl!.forward();
      }
    });
  }

  /// Returns interpolated transform configs during the crop animation.
  TransformConfigs _animatedTransformConfigs() {
    final t = _cropAnimation!.value;
    final target = _targetTransformConfigs!;
    final animatedRect = Rect.lerp(_fullRect!, target.cropRect, t)!;
    return target.copyWith(cropRect: animatedRect);
  }

  /// Notifies the parent that all animations are done (hero settled + crop
  /// done). Only fires once.
  void _notifyAllAnimationsCompleteIfReady() {
    if (_didNotifyAnimationsComplete) return;
    if (!widget.isInitialized || !_cropAnimDone) return;
    _didNotifyAnimationsComplete = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onAllAnimationsComplete?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;

    return Hero(
      tag: w.heroTag,
      createRectTween: (begin, end) => RectTween(begin: begin, end: end),
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    final w = widget;

    // Before initialization: show raw image for hero animation
    if (!w.isInitialized) {
      return w.editorImage != null
          ? AutoImage(
              w.editorImage!,
              fit: BoxFit.contain,
              configs: w.configs,
            )
          : SizedBox.fromSize(size: w.blankSize);
    }

    // Crop animation in progress: interpolate the crop rect
    if (!_cropAnimDone &&
        _cropAnimation != null &&
        _targetTransformConfigs != null) {
      return AnimatedBuilder(
        animation: _cropAnimation!,
        builder: (context, child) {
          return TransformedContentGenerator(
            transformConfigs: _animatedTransformConfigs(),
            configs: w.configs,
            child: child!,
          );
        },
        child: FilteredWidget(
          filterKey: w.backgroundImageColorFilterKey,
          width: w.sizesManager.decodedImageSize.width,
          height: w.sizesManager.decodedImageSize.height,
          configs: w.configs,
          image: w.editorImage,
          blankSize: w.blankSize,
          filters: w.stateManager.activeFilters,
          tuneAdjustments: w.stateManager.activeTuneAdjustments,
          blurFactor: w.stateManager.activeBlur,
        ),
      );
    }

    // Normal state: show final transformed image
    return TransformedContentGenerator(
      transformConfigs: w.stateManager.transformConfigs,
      configs: w.configs,
      child: FilteredWidget(
        filterKey: w.backgroundImageColorFilterKey,
        width: w.sizesManager.decodedImageSize.width,
        height: w.sizesManager.decodedImageSize.height,
        configs: w.configs,
        image: w.editorImage,
        blankSize: w.blankSize,
        filters: w.stateManager.activeFilters,
        tuneAdjustments: w.stateManager.activeTuneAdjustments,
        blurFactor: w.stateManager.activeBlur,
      ),
    );
  }
}
