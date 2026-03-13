// ignore_for_file: deprecated_member_use_from_same_package
// TODO: Remove the deprecated values when releasing version 12.0.0.

import 'package:flutter/material.dart';

import '/features/crop_rotate_editor/enums/crop_mode.enum.dart';
import '/features/crop_rotate_editor/enums/crop_tool_enum.dart';
import '/features/crop_rotate_editor/models/aspect_ratio_item.dart';
import '/features/crop_rotate_editor/models/rotate_direction.dart';
import '../custom_widgets/crop_rotate_editor_widgets.dart';
import '../icons/crop_rotate_editor_icons.dart';
import '../styles/crop_rotate_editor_style.dart';
import 'utils/base_sub_editor_configs.dart';
import 'utils/editor_safe_area.dart';
import 'utils/zoom_configs.dart';

export '/features/crop_rotate_editor/enums/crop_tool_enum.dart';
export '/features/crop_rotate_editor/models/rotate_direction.dart';
export '/features/crop_rotate_editor/models/transform_configs.dart';
export '../custom_widgets/crop_rotate_editor_widgets.dart';
export '../icons/crop_rotate_editor_icons.dart';
export '../styles/crop_rotate_editor_style.dart';

/// Configuration options for a crop and rotate editor.
///
/// `CropRotateEditorConfigs` allows you to define various settings for a
/// crop and rotate editor. You can enable or disable specific features like
/// cropping, rotating, and maintaining aspect ratio. Additionally, you can
/// specify an initial aspect ratio for cropping.
///
/// Example usage:
/// ```dart
/// CropRotateEditorConfigs(
///   enabled: true,
///   enabledRotate: true,
///   enabledAspectRatio: true,
///   initAspectRatio: CropAspectRatios.custom,
/// );
/// ```
class CropRotateEditorConfigs extends ZoomConfigs
    implements BaseSubEditorConfigs {
  /// Creates an instance of CropRotateEditorConfigs with optional settings.
  ///
  /// By default, all options are enabled, and the initial aspect ratio is set
  /// to `CropAspectRatios.custom`.
  const CropRotateEditorConfigs({
    super.enableZoom,
    super.editorMinScale,
    super.editorMaxScale,
    super.enableDoubleTapZoom,
    super.doubleTapZoomFactor,
    super.doubleTapZoomDuration,
    super.doubleTapZoomCurve,
    super.boundaryMargin,
    this.viewPadding,
    this.desktopCornerDragArea = 7,
    this.mobileCornerDragArea = kMinInteractiveDimension,
    this.enableGesturePop = true,
    @Deprecated(
      'Use tools inside MainEditorConfigs instead, e.g. tools: '
      '[SubEditorMode.cropRotate]',
    )
    this.enabled = true,
    @Deprecated('Use tools instead, e.g. tools: [CropRotateTool.rotate]')
    this.showRotateButton = true,
    @Deprecated('Use tools instead, e.g. tools: [CropRotateTool.flip]')
    this.showFlipButton = true,
    @Deprecated('Use tools instead, e.g. tools: [CropRotateTool.aspectRatio]')
    this.showAspectRatioButton = true,
    @Deprecated('Use tools instead, e.g. tools: [CropRotateTool.reset]')
    this.showResetButton = true,
    this.tools = const [
      CropRotateTool.rotate,
      CropRotateTool.straighten,
      CropRotateTool.perspective,
      CropRotateTool.flip,
      CropRotateTool.aspectRatio,
      CropRotateTool.reset,
    ],
    this.invertMouseScroll = false,
    this.invertDragDirection = false,
    this.initialCropMode = CropMode.rectangular,
    this.enableTransformLayers = true,
    this.enableProvideImageInfos = false,
    this.enableDoubleTap = true,
    this.enableFlipAnimation = true,
    this.showLayers = true,
    this.initAspectRatio,
    this.rotateAnimationCurve = Curves.decelerate,
    this.scaleAnimationCurve = Curves.decelerate,
    this.cropDragAnimationCurve = Curves.decelerate,
    this.flipAnimationCurve = Curves.decelerate,
    this.fadeInOutsideCropAreaAnimationCurve = Curves.decelerate,
    this.aspectRatioChangeAnimationCurve = Curves.decelerate,
    this.rotateDirection = RotateDirection.left,
    this.opacityOutsideCropAreaDuration = const Duration(milliseconds: 100),
    this.animationDuration = const Duration(milliseconds: 250),
    this.aspectRatioChangeAnimationDuration = const Duration(milliseconds: 250),
    this.fadeInOutsideCropAreaAnimationDuration =
        const Duration(milliseconds: 350),
    this.cropDragAnimationDuration = const Duration(milliseconds: 400),
    this.cropDragOutOfBoundsDelay = const Duration(milliseconds: 350),
    this.maxScale = 7,
    this.mouseScaleFactor = 0.1,
    this.doubleTapScaleFactor = 2,
    this.minAspectRatio,
    this.maxAspectRatio,
    this.aspectRatios = const [
      AspectRatioItem(text: 'Free', value: -1),
      AspectRatioItem(text: 'Original', value: 0.0),
      AspectRatioItem(text: '1*1', value: 1.0 / 1.0),
      AspectRatioItem(text: '4*3', value: 4.0 / 3.0),
      AspectRatioItem(text: '3*4', value: 3.0 / 4.0),
      AspectRatioItem(text: '16*9', value: 16.0 / 9.0),
      AspectRatioItem(text: '9*16', value: 9.0 / 16.0)
    ],
    this.safeArea = const EditorSafeArea(),
    this.style = const CropRotateEditorStyle(),
    this.icons = const CropRotateEditorIcons(),
    this.widgets = const CropRotateEditorWidgets(),
    this.maxWidthFactor,
    this.scrollPhysics = const BouncingScrollPhysics(),
  })  : assert(maxScale >= 1, 'maxScale must be greater than or equal to 1'),
        assert(desktopCornerDragArea > 0,
            'desktopCornerDragArea must be positive'),
        assert(
            mobileCornerDragArea > 0, 'mobileCornerDragArea must be positive'),
        assert(
            maxWidthFactor == null ||
                (maxWidthFactor > 0 && maxWidthFactor <= 1),
            'maxWidthFactor must be greater than 0 and less than 1'),
        assert(doubleTapScaleFactor > 1,
            'doubleTapScaleFactor must be greater than 1');

  /// {@macro enableGesturePop}
  @override
  final bool enableGesturePop;

  /// Indicates whether the editor is enabled.
  @Deprecated(
    'Use tools inside MainEditorConfigs instead, e.g. tools: '
    '[SubEditorMode.cropRotate]',
  )
  final bool enabled;

  /// Whether to show a button to rotate the image.
  @Deprecated('Use tools instead, e.g. tools: [CropRotateTool.rotate]')
  final bool showRotateButton;

  /// Whether to show a button to flip the image.
  @Deprecated('Use tools instead, e.g. tools: [CropRotateTool.flip]')
  final bool showFlipButton;

  /// Whether to show a button to change the aspect ratio.
  @Deprecated('Use tools instead, e.g. tools: [CropRotateTool.aspectRatio]')
  final bool showAspectRatioButton;

  /// Whether to show a button to reset all transformations.
  @Deprecated('Use tools instead, e.g. tools: [CropRotateTool.reset]')
  final bool showResetButton;

  /// Show the layers from the main-editor.
  final bool showLayers;

  /// Layers will also be transformed like the crop-rotate image.
  final bool enableTransformLayers;

  /// Enables double-tap zoom functionality when set to true.
  final bool enableDoubleTap;

  /// Enables flip-animation when set to true.
  final bool enableFlipAnimation;

  /// Determines if the mouse scroll direction should be inverted.
  final bool invertMouseScroll;

  /// Determines if the drag direction should be inverted.
  final bool invertDragDirection;

  /// The initial crop mode to be used when the crop/rotate editor is opened.
  ///
  /// This determines the default cropping behavior or aspect ratio that will be
  /// presented to the user before any manual adjustments are made.
  final CropMode initialCropMode;

  /// Defines the padding for the view outside the image boundaries.
  final EdgeInsets? viewPadding;

  /// Defines which crop-rotate tools are available in the editor.
  ///
  /// The order of the tools in this list determines the order in the UI.
  /// Simply include the tools you want and leave out the ones you don’t.
  ///
  /// Example:
  /// ```dart
  /// PaintEditorConfigs(
  ///   tools: [
  ///      CropRotateTool.rotate,
  ///      CropRotateTool.flip,
  ///      CropRotateTool.aspectRatio,
  ///      CropRotateTool.reset,
  ///   ],
  /// )
  /// ```
  final List<CropRotateTool> tools;

  /// A boolean flag that determines whether the `imageInfos` parameter
  /// should be included in the `onDone` callback.
  ///
  /// When set to `true`, the `imageInfos` parameter will be provided in the
  /// `onDone` callback of the crop editor, containing detailed information
  /// about the edited image. If set to `false`, `imageInfos` will be `null`.
  final bool enableProvideImageInfos;

  /// The initial aspect ratio for cropping.
  ///
  /// For free aspect ratio use `-1` and for original aspect ratio use `0.0`.
  final double? initAspectRatio;

  /// The minimum aspect ratio for cropping in free mode.
  final double? minAspectRatio;

  /// The maximum aspect ratio for cropping in free mode.
  final double? maxAspectRatio;

  /// The maximum scale allowed for the view.
  final double maxScale;

  /// The scaling factor applied to mouse scrolling.
  final double mouseScaleFactor;

  /// The scaling factor applied when double-tapping.
  final double doubleTapScaleFactor;

  /// Specifies the maximum width factor for scaling the content.
  ///
  /// - **Android**: The default value is `0.9`. This setting resolves an issue
  ///  related to the back button functionality, as outlined in
  ///  [GitHub Issue #303](https://github.com/hm21/pro_image_editor/issues/303).
  ///
  /// - **Other Platforms**: The default value is `1.0`, which allows the
  ///  content to utilize the full available width without any scaling
  ///  adjustment.
  ///
  /// This property can be customized to fine-tune the scaling behavior based
  /// on the specific requirements of the platform or application context.
  final double? maxWidthFactor;

  /// The scroll physics used for calculating scale and pan behavior.
  final ScrollPhysics scrollPhysics;

  /// The allowed aspect ratios for cropping.
  ///
  /// For free aspect ratio use `-1` and for original aspect ratio use `0.0`.
  final List<AspectRatioItem> aspectRatios;

  /// The duration for the animation controller that handles rotation and
  /// scale animations.
  final Duration animationDuration;

  /// The duration of drag-crop animations.
  final Duration cropDragAnimationDuration;

  /// The duration of aspect ratio change animations.
  final Duration aspectRatioChangeAnimationDuration;

  /// The delay before the snapback animation plays when the crop area is out of bounds.
  final Duration cropDragOutOfBoundsDelay;

  /// Fade in animation from content outside the crop area.
  final Duration fadeInOutsideCropAreaAnimationDuration;

  /// The duration of the outside crop area opacity.
  final Duration opacityOutsideCropAreaDuration;

  /// The curve used for the rotation animation.
  final Curve rotateAnimationCurve;

  /// The curve used for the flip animation.
  final Curve flipAnimationCurve;

  /// The curve used for the scale animation, which is triggered when the
  /// image needs to resize due to rotation.
  final Curve scaleAnimationCurve;

  /// The animation curve used for crop animations.
  final Curve cropDragAnimationCurve;

  /// The animation curve used for aspect ratio change animations.
  final Curve aspectRatioChangeAnimationCurve;

  /// The animation curve used for the fade in animation from content outside
  /// the crop area.
  final Curve fadeInOutsideCropAreaAnimationCurve;

  /// The direction in which the image will be rotated.
  final RotateDirection rotateDirection;

  /// Defines the size of the draggable area on corners of the crop rectangle
  /// for desktop devices.
  final double desktopCornerDragArea;

  /// Defines the size of the draggable area on corners of the crop rectangle
  /// for mobile devices.
  final double mobileCornerDragArea;

  /// Defines the safe area configuration for the editor.
  final EditorSafeArea safeArea;

  /// Style configuration for the crop and rotate editor.
  final CropRotateEditorStyle style;

  /// Icons used in the crop and rotate editor.
  final CropRotateEditorIcons icons;

  /// Widgets associated with the crop and rotate editor.
  final CropRotateEditorWidgets widgets;

  /// Creates a copy of this `CropRotateEditorConfigs` object with the given
  /// fields replaced with new values.
  ///
  /// The [copyWith] method allows you to create a new instance of
  /// [CropRotateEditorConfigs] with some properties updated while keeping the
  /// others unchanged.
  CropRotateEditorConfigs copyWith({
    bool? enableGesturePop,
    bool? enabled,
    @Deprecated('Use tools instead, e.g. tools: [CropRotateTool.rotate]')
    bool? showRotateButton,
    @Deprecated('Use tools instead, e.g. tools: [CropRotateTool.flip]')
    bool? showFlipButton,
    @Deprecated('Use tools instead, e.g. tools: [CropRotateTool.aspectRatio]')
    bool? showAspectRatioButton,
    @Deprecated('Use tools instead, e.g. tools: [CropRotateTool.reset]')
    bool? showResetButton,
    List<CropRotateTool>? tools,
    EdgeInsets? viewPadding,
    bool? showLayers,
    bool? enableTransformLayers,
    bool? enableDoubleTap,
    bool? enableFlipAnimation,
    bool? invertMouseScroll,
    bool? invertDragDirection,
    CropMode? initialCropMode,
    bool? enableProvideImageInfos,
    double? initAspectRatio,
    double? minAspectRatio,
    double? maxAspectRatio,
    double? maxScale,
    double? mouseScaleFactor,
    double? doubleTapScaleFactor,
    double? maxWidthFactor,
    List<AspectRatioItem>? aspectRatios,
    Duration? animationDuration,
    Duration? aspectRatioChangeAnimationDuration,
    Duration? cropDragAnimationDuration,
    Duration? cropDragOutOfBoundsDelay,
    Duration? fadeInOutsideCropAreaAnimationDuration,
    Duration? opacityOutsideCropAreaDuration,
    Curve? rotateAnimationCurve,
    Curve? flipAnimationCurve,
    Curve? scaleAnimationCurve,
    Curve? cropDragAnimationCurve,
    Curve? aspectRatioChangeAnimationCurve,
    Curve? fadeInOutsideCropAreaAnimationCurve,
    RotateDirection? rotateDirection,
    double? desktopCornerDragArea,
    double? mobileCornerDragArea,
    EditorSafeArea? safeArea,
    CropRotateEditorStyle? style,
    CropRotateEditorIcons? icons,
    CropRotateEditorWidgets? widgets,
  }) {
    return CropRotateEditorConfigs(
      enableGesturePop: enableGesturePop ?? this.enableGesturePop,
      enabled: enabled ?? this.enabled,
      showRotateButton: showRotateButton ?? this.showRotateButton,
      showFlipButton: showFlipButton ?? this.showFlipButton,
      showAspectRatioButton:
          showAspectRatioButton ?? this.showAspectRatioButton,
      showResetButton: showResetButton ?? this.showResetButton,
      tools: tools ?? this.tools,
      viewPadding: viewPadding ?? this.viewPadding,
      showLayers: showLayers ?? this.showLayers,
      enableTransformLayers:
          enableTransformLayers ?? this.enableTransformLayers,
      enableDoubleTap: enableDoubleTap ?? this.enableDoubleTap,
      enableFlipAnimation: enableFlipAnimation ?? this.enableFlipAnimation,
      invertMouseScroll: invertMouseScroll ?? this.invertMouseScroll,
      invertDragDirection: invertDragDirection ?? this.invertDragDirection,
      initialCropMode: initialCropMode ?? this.initialCropMode,
      enableProvideImageInfos:
          enableProvideImageInfos ?? this.enableProvideImageInfos,
      initAspectRatio: initAspectRatio ?? this.initAspectRatio,
      minAspectRatio: minAspectRatio ?? this.minAspectRatio,
      maxAspectRatio: maxAspectRatio ?? this.maxAspectRatio,
      maxScale: maxScale ?? this.maxScale,
      mouseScaleFactor: mouseScaleFactor ?? this.mouseScaleFactor,
      doubleTapScaleFactor: doubleTapScaleFactor ?? this.doubleTapScaleFactor,
      maxWidthFactor: maxWidthFactor ?? this.maxWidthFactor,
      aspectRatios: aspectRatios ?? this.aspectRatios,
      animationDuration: animationDuration ?? this.animationDuration,
      aspectRatioChangeAnimationDuration: aspectRatioChangeAnimationDuration ??
          this.aspectRatioChangeAnimationDuration,
      cropDragAnimationDuration:
          cropDragAnimationDuration ?? this.cropDragAnimationDuration,
      cropDragOutOfBoundsDelay:
          cropDragOutOfBoundsDelay ?? this.cropDragOutOfBoundsDelay,
      fadeInOutsideCropAreaAnimationDuration:
          fadeInOutsideCropAreaAnimationDuration ??
              this.fadeInOutsideCropAreaAnimationDuration,
      opacityOutsideCropAreaDuration:
          opacityOutsideCropAreaDuration ?? this.opacityOutsideCropAreaDuration,
      rotateAnimationCurve: rotateAnimationCurve ?? this.rotateAnimationCurve,
      flipAnimationCurve: flipAnimationCurve ?? this.flipAnimationCurve,
      scaleAnimationCurve: scaleAnimationCurve ?? this.scaleAnimationCurve,
      cropDragAnimationCurve:
          cropDragAnimationCurve ?? this.cropDragAnimationCurve,
      aspectRatioChangeAnimationCurve: aspectRatioChangeAnimationCurve ??
          this.aspectRatioChangeAnimationCurve,
      fadeInOutsideCropAreaAnimationCurve:
          fadeInOutsideCropAreaAnimationCurve ??
              this.fadeInOutsideCropAreaAnimationCurve,
      rotateDirection: rotateDirection ?? this.rotateDirection,
      desktopCornerDragArea:
          desktopCornerDragArea ?? this.desktopCornerDragArea,
      mobileCornerDragArea: mobileCornerDragArea ?? this.mobileCornerDragArea,
      safeArea: safeArea ?? this.safeArea,
      style: style ?? this.style,
      icons: icons ?? this.icons,
      widgets: widgets ?? this.widgets,
    );
  }
}
