// Dart imports:
import 'dart:math';

// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import '/core/models/styles/crop_rotate_editor_style.dart';

/// A custom painter for drawing crop corners and interaction elements.
///
/// This class extends [CustomPainter] and is used to draw the crop corners,
/// guide lines, and other interaction elements for a crop and rotate editor.
/// It takes into account the current view rectangle, crop rectangle, and
/// various style settings provided by the image editor theme.
class CropCornerPainter extends CustomPainter {
  /// Creates an instance of [CropCornerPainter].
  ///
  /// The constructor initializes various parameters needed to draw the crop
  /// corners and interaction elements, such as the crop rectangle, view
  /// rectangle, and other style configurations.
  ///
  /// Example:
  /// ```
  /// CropCornerPainter(
  ///   drawCircle: true,
  ///   offset: Offset.zero,
  ///   cropRect: myCropRect,
  ///   fadeInOpacity: 0.5,
  ///   interactionOpacity: 1.0,
  ///   viewRect: myViewRect,
  ///   screenSize: myScreenSize,
  ///   scaleFactor: 1.0,
  ///   imageEditorTheme: myImageEditorTheme,
  ///   cornerLength: 10.0,
  ///   cornerThickness: 2.0,
  ///   rotationScaleFactor: 1.0,
  /// )
  /// ```
  CropCornerPainter({
    required this.drawCircle,
    required this.offset,
    required this.cropRect,
    required this.fadeInOpacity,
    required this.interactionOpacity,
    required this.viewRect,
    required this.screenSize,
    required this.scaleFactor,
    required this.style,
    required this.rotationScaleFactor,
    required this.background,
    required this.helperLineColor,
    required this.cropCornerColor,
    required this.cropOverlayColor,
    required this.renderedImageSize,
  });

  /// The rectangle defining the crop area.
  ///
  /// This [Rect] represents the area of the image currently being cropped,
  /// used to draw the crop corners and other elements.
  final Rect cropRect;

  /// The rectangle representing the current viewable area.
  ///
  /// This [Rect] is used to determine the position and scaling of elements
  /// relative to the viewable area of the editor.
  final Rect viewRect;

  /// The size of the screen or canvas.
  ///
  /// This [Size] object represents the dimensions of the entire editing area,
  /// affecting how elements are drawn and scaled.
  final Size screenSize;

  /// The theme settings for the image editor.
  ///
  /// This [CropRotateEditorStyle] object provides style configurations for the
  /// elements drawn by this painter, such as colors and line thicknesses.
  final CropRotateEditorStyle style;

  /// Whether to draw circles at the crop corners.
  ///
  /// This boolean flag determines whether circular elements should be drawn at
  /// the corners of the crop rectangle for visual guidance.
  final bool drawCircle;

  /// The offset for positioning elements.
  ///
  /// This [Offset] is used to adjust the positioning of elements drawn by this
  /// painter, allowing for dynamic placement based on user interactions.
  final Offset offset;

  /// The opacity for fade-in effects.
  ///
  /// This double value represents the opacity level for fade-in effects,
  /// allowing for smooth visual transitions when the crop corners appear.
  final double fadeInOpacity;

  /// The opacity for interaction effects.
  ///
  /// This double value represents the opacity level for interaction effects,
  /// such as highlighting or accentuating elements during user actions.
  final double interactionOpacity;

  /// The width of the helper lines.
  ///
  /// This double value specifies the thickness of auxiliary lines drawn to
  /// assist with cropping, providing additional visual guides.
  double helperLineWidth = 0.5;

  /// The scale factor for resizing elements.
  ///
  /// This double value determines how much the elements are scaled, allowing
  /// for dynamic resizing based on zoom levels or screen sizes.
  final double scaleFactor;

  /// The factor for scaling elements based on rotation.
  ///
  /// This double value influences how elements are scaled when the image is
  /// rotated, ensuring that elements remain proportionate.
  final double rotationScaleFactor;

  /// The background color
  final Color background;

  /// The resolved helper line color.
  final Color helperLineColor;

  /// The resolved crop corner color.
  final Color cropCornerColor;

  /// The resolved crop overlay color.
  final Color cropOverlayColor;

  /// The full rendered image size (not affected by crop aspect ratio).
  final Size renderedImageSize;

  double get _cropOffsetLeft => cropRect.left;
  double get _cropOffsetRight => cropRect.right;
  double get _cropOffsetTop => cropRect.top;
  double get _cropOffsetBottom => cropRect.bottom;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isInfinite ||
        !scaleFactor.isFinite ||
        !(size.width * scaleFactor).isFinite ||
        cropRect.hasNaN ||
        !cropRect.isFinite) {
      return;
    }
    _drawDarkenOutside(canvas: canvas, size: size);
    _drawCropOutline(canvas: canvas);
    if (fadeInOpacity > 0) _drawHelperAreas(canvas: canvas, size: size);
    _drawCorners(canvas: canvas, size: size);
    _drawEdgeHandles(canvas: canvas, size: size);
  }

  void _drawCropOutline({required Canvas canvas}) {
    if (fadeInOpacity <= 0) return;

    final paint = Paint()
      ..color = helperLineColor.withValues(alpha: fadeInOpacity)
      ..strokeWidth = style.cropCornerOutlineThickness
      ..style = PaintingStyle.stroke;

    if (drawCircle) {
      canvas.drawOval(cropRect, paint);
    } else {
      canvas.drawRect(cropRect, paint);
    }
  }

  /// Returns the path used to clip the overlay and blur effects.
  Path getClipPath(Size size) {
    double cropWidth = _cropOffsetRight - _cropOffsetLeft;
    double cropHeight = _cropOffsetBottom - _cropOffsetTop;

    Path cropPath = Path();

    if (drawCircle) {
      /// Create a path for the circular clip
      cropPath.addOval(
        Rect.fromCenter(
          center: Offset(
            cropWidth / 2 + _cropOffsetLeft,
            cropHeight / 2 + _cropOffsetTop,
          ),
          width: cropWidth,
          height: cropHeight,
        ),
      );
    } else {
      /// Create a path for the rectangular clip
      cropPath.addRect(
        Rect.fromCenter(
          center: Offset(
            cropWidth / 2 + _cropOffsetLeft,
            cropHeight / 2 + _cropOffsetTop,
          ),
          width: cropWidth,
          height: cropHeight,
        ),
      );
    }

    final Rect imageRect = Rect.fromCenter(
      center: Offset(
        size.width / 2 + offset.dx * scaleFactor,
        size.height / 2 + offset.dy * scaleFactor,
      ),
      width: renderedImageSize.width * scaleFactor,
      height: renderedImageSize.height * scaleFactor,
    );
    
    Path imagePath = Path()..addRect(imageRect);

    return Path.combine(PathOperation.difference, imagePath, cropPath);
  }

  void _drawDarkenOutside({
    required Canvas canvas,
    required Size size,
  }) {
    /// Draw outline darken layers
    Path path = getClipPath(size);

    Color interpolatedColor = Color.lerp(
      background,
      cropOverlayColor,
      fadeInOpacity,
    )!;

    double opacity = style.cropOverlayOpacity -
        style.cropOverlayInteractionOpacity * interactionOpacity;

    double fadeInFactor = (1 - opacity) * (1 - fadeInOpacity);

    // Old saveLayer based blur has been removed from here.

    /// Draw the darkened area
    canvas.drawPath(
      path,
      Paint()
        ..color = interpolatedColor.withValues(
            alpha: (opacity + fadeInFactor).clamp(0, 1))
        ..style = PaintingStyle.fill,
    );
  }

  void _drawCorners({
    required Canvas canvas,
    required Size size,
  }) {
    Path path = Path();

    double width = style.cropCornerThickness / rotationScaleFactor;
    if (!drawCircle) {
      double length = style.cropCornerLength / rotationScaleFactor;

      /// Top-Left
      path
        ..addRect(Rect.fromLTWH(_cropOffsetLeft - width, _cropOffsetTop - width,
            length + width, width))
        ..addRect(Rect.fromLTWH(_cropOffsetLeft - width, _cropOffsetTop - width,
            width, length + width))

        /// Top-Right
        ..addRect(Rect.fromLTWH(_cropOffsetRight - length,
            _cropOffsetTop - width, length + width, width))
        ..addRect(Rect.fromLTWH(
            _cropOffsetRight, _cropOffsetTop - width, width, length + width))

        /// Bottom-Left
        ..addRect(Rect.fromLTWH(
            _cropOffsetLeft - width, _cropOffsetBottom, length + width, width))
        ..addRect(Rect.fromLTWH(_cropOffsetLeft - width,
            _cropOffsetBottom - length, width, length + width))

        /// Bottom-Right
        ..addRect(Rect.fromLTWH(_cropOffsetRight - length, _cropOffsetBottom,
            length + width, width))
        ..addRect(Rect.fromLTWH(_cropOffsetRight, _cropOffsetBottom - length,
            width, length + width));

      canvas.drawPath(
        path,
        Paint()
          ..color = cropCornerColor.withValues(alpha: fadeInOpacity)
          ..style = PaintingStyle.fill,
      );
    } else {
      double calculateAngleFromArcLength(
          double circumference, double arcLength) {
        if (circumference <= 0 || arcLength <= 0) {
          throw ArgumentError(
              'Circumference and arc length must be positive values.');
        }
        return circumference / 360 * arcLength * pi / 180;
      }

      double angleRadians =
          calculateAngleFromArcLength(cropRect.width + width, width * 2);

      /// Top
      path
        ..addArc(
          Rect.fromCenter(
              center: cropRect.center,
              width: cropRect.width + width,
              height: cropRect.height + width),
          3 * pi / 2 - angleRadians / 2,
          angleRadians,
        )

        /// Left
        ..addArc(
          Rect.fromCenter(
              center: cropRect.center,
              width: cropRect.width + width,
              height: cropRect.height + width),
          pi - angleRadians / 2,
          angleRadians,
        )

        /// Right
        ..addArc(
          Rect.fromCenter(
              center: cropRect.center,
              width: cropRect.width + width,
              height: cropRect.height + width),
          pi / 2 - angleRadians / 2,
          angleRadians,
        )

        /// Right
        ..addArc(
          Rect.fromCenter(
              center: cropRect.center,
              width: cropRect.width + width,
              height: cropRect.height + width),
          -angleRadians / 2,
          angleRadians,
        );

      canvas.drawPath(
        path,
        Paint()
          ..color = cropCornerColor.withValues(alpha: fadeInOpacity)
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
    }
  }

  void _drawEdgeHandles({
    required Canvas canvas,
    required Size size,
  }) {
    if (drawCircle) return;

    Path path = Path();

    double width = style.cropCornerThickness / rotationScaleFactor;
    double length = style.cropMiddleEdgeLength / rotationScaleFactor;

    double centerX = _cropOffsetLeft + (_cropOffsetRight - _cropOffsetLeft) / 2;
    double centerY = _cropOffsetTop + (_cropOffsetBottom - _cropOffsetTop) / 2;

    path

      /// Top Edge Handle
      ..addRect(Rect.fromLTWH(
        centerX - length / 2,
        _cropOffsetTop - width,
        length,
        width,
      ))

      /// Bottom Edge Handle
      ..addRect(Rect.fromLTWH(
        centerX - length / 2,
        _cropOffsetBottom,
        length,
        width,
      ))

      /// Left Edge Handle
      ..addRect(Rect.fromLTWH(
        _cropOffsetLeft - width,
        centerY - length / 2,
        width,
        length,
      ))

      /// Right Edge Handle
      ..addRect(Rect.fromLTWH(
        _cropOffsetRight,
        centerY - length / 2,
        width,
        length,
      ));

    canvas.drawPath(
      path,
      Paint()
        ..color = cropCornerColor.withValues(alpha: fadeInOpacity)
        ..style = PaintingStyle.fill,
    );
  }

  void _drawHelperAreas({
    required Canvas canvas,
    required Size size,
  }) {
    Path path = Path();

    double cropWidth = _cropOffsetRight - _cropOffsetLeft;
    double cropHeight = _cropOffsetBottom - _cropOffsetTop;

    double cropAreaSpaceW = cropWidth / 3;
    double cropAreaSpaceH = cropHeight / 3;

    /// Calculation is important for the round-cropper
    double lineWidth = !drawCircle
        ? cropWidth
        : sqrt(pow(cropWidth, 2) - pow(cropAreaSpaceW, 2));
    double lineHeight = !drawCircle
        ? cropHeight
        : sqrt(pow(cropHeight, 2) - pow(cropAreaSpaceH, 2));

    double gapW = (cropWidth - lineWidth) / 2;
    double gapH = (cropHeight - lineHeight) / 2;

    for (var i = 1; i < 3; i++) {
      path
        ..addRect(
          Rect.fromLTWH(
            cropAreaSpaceW * i + _cropOffsetLeft,
            gapH + _cropOffsetTop,
            helperLineWidth,
            lineHeight,
          ),
        )
        ..addRect(
          Rect.fromLTWH(
            gapW + _cropOffsetLeft,
            cropAreaSpaceH * i + _cropOffsetTop,
            lineWidth,
            helperLineWidth,
          ),
        );
    }

    final cornerPaint = Paint()
      ..color = helperLineColor
          .withValues(alpha: fadeInOpacity * interactionOpacity)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, cornerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is! CropCornerPainter ||
        oldDelegate.drawCircle != drawCircle ||
        oldDelegate.offset != offset ||
        oldDelegate.cropRect != cropRect ||
        oldDelegate.fadeInOpacity != fadeInOpacity ||
        oldDelegate.interactionOpacity != interactionOpacity ||
        oldDelegate.viewRect != viewRect ||
        oldDelegate.screenSize != screenSize ||
        oldDelegate.scaleFactor != scaleFactor ||
        oldDelegate.style != style ||
        oldDelegate.rotationScaleFactor != rotationScaleFactor ||
        oldDelegate.background != background ||
        oldDelegate.helperLineColor != helperLineColor ||
        oldDelegate.cropCornerColor != cropCornerColor ||
        oldDelegate.cropOverlayColor != cropOverlayColor ||
        oldDelegate.renderedImageSize != renderedImageSize;
  }

  /// Create a copy of the [CropCornerPainter].
  CropCornerPainter copy() {
    return CropCornerPainter(
      drawCircle: drawCircle,
      offset: offset,
      cropRect: cropRect,
      fadeInOpacity: fadeInOpacity,
      interactionOpacity: interactionOpacity,
      viewRect: viewRect,
      screenSize: screenSize,
      scaleFactor: scaleFactor,
      style: style,
      rotationScaleFactor: rotationScaleFactor,
      background: background,
      helperLineColor: helperLineColor,
      cropCornerColor: cropCornerColor,
      cropOverlayColor: cropOverlayColor,
      renderedImageSize: renderedImageSize,
    );
  }
}

/// A custom clipper that uses the CropCornerPainter's clip path logic.
///
/// This is used to apply effects like backdrop blur exclusively to the overlay
/// area (the space outside the crop bounds) in the crop/rotate editor.
class CropOverlayClipper extends CustomClipper<Path> {
  /// Reference to the current state of the crop painter.
  final CropCornerPainter painter;

  /// Creates a [CropOverlayClipper].
  CropOverlayClipper(this.painter);

  @override
  Path getClip(Size size) {
    return painter.getClipPath(size);
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) {
    if (oldClipper is! CropOverlayClipper) return true;
    return painter.shouldRepaint(oldClipper.painter);
  }
}
