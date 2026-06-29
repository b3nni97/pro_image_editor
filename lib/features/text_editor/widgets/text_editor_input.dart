import 'dart:math';

import 'package:flutter/material.dart';

import '/core/models/editor_callbacks/text_editor_callbacks.dart';
import '/core/models/editor_configs/pro_image_editor_configs.dart';
import '/core/models/layers/layer.dart';
import 'rounded_background_text/rounded_background_text_field.dart';

/// A widget for managing the text input in the text editor, providing a
/// customizable input area with styling and configuration options.
class TextEditorInput extends StatefulWidget {
  /// Creates a `TextEditorInput` widget with the required configurations,
  /// callbacks, and styling for text input management.
  ///
  /// - [callbacks]: Optional callbacks for text editor interactions.
  /// - [configs]: Configuration settings for the text editor.
  /// - [i18n]: Localization strings for tooltips and labels.
  /// - [heroTag]: Optional tag for hero animations during transitions.
  /// - [selectedTextStyle]: The text style applied to the input text.
  /// - [align]: The alignment of the text in the input field.
  /// - [textFontSize]: The font size of the input text.
  /// - [textColor]: The color of the input text.
  /// - [backgroundColor]: The background color of the text input field.
  /// - [layer]: The text layer being edited, if applicable.
  /// - [focusNode]: The focus node for managing input focus.
  /// - [textCtrl]: The text editing controller for managing input content.
  const TextEditorInput({
    super.key,
    required this.callbacks,
    required this.configs,
    required this.heroTag,
    required this.enableHero,
    required this.focusNode,
    required this.i18n,
    required this.selectedTextStyle,
    required this.align,
    required this.textFontSize,
    required this.scaleFactor,
    required this.textColor,
    required this.backgroundColor,
    required this.layer,
    required this.textCtrl,
    required this.maxWidth,
    required this.cursorWidth,
  });

  /// Optional callbacks for text editor interactions.
  final TextEditorCallbacks? callbacks;

  /// Configuration settings for the text editor.
  final TextEditorConfigs configs;

  /// Localization strings for tooltips and labels.
  final I18nTextEditor i18n;

  /// Optional tag for hero animations during transitions.
  final String? heroTag;

  /// Whether the field participates in the hero flight. When `false` the hero
  /// uses a non-matching tag and stays inert (no flight), which keeps the real
  /// field mounted — used for new text while open so the keyboard is reliable.
  final bool enableHero;

  /// The text style applied to the input text.
  final TextStyle selectedTextStyle;

  /// The alignment of the text in the input field.
  final TextAlign align;

  /// The font size of the input text.
  final double textFontSize;

  /// The width of the text cursor in the text editor input, measured in
  /// logical pixels.
  final double cursorWidth;

  /// The maximum width available for the text before the text will overflow.
  final double maxWidth;

  /// The scale factor to transform the textfield
  final double scaleFactor;

  /// The color of the input text.
  final Color textColor;

  /// The background color of the text input field.
  final Color backgroundColor;

  /// The text layer being edited, if applicable.
  final TextLayer? layer;

  /// The focus node for managing input focus.
  final FocusNode focusNode;

  /// The text editing controller for managing input content.
  final TextEditingController textCtrl;

  @override
  State<TextEditorInput> createState() => _TextEditorInputState();
}

class _TextEditorInputState extends State<TextEditorInput> {
  Widget _flightShuttleBuilder(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final Hero toHero = toHeroContext.widget as Hero;

    final isOpening = flightDirection == HeroFlightDirection.push;

    if (isOpening) {
      void animationStatusListener(AnimationStatus status) {
        if (status == AnimationStatus.completed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.focusNode.requestFocus();
          });
          animation.removeStatusListener(animationStatusListener);
        }
      }

      animation.addStatusListener(animationStatusListener);
    }

    final shuttleChild =
        InheritedTheme.captureAll(fromHeroContext, toHero.child);

    // Normalize to the shortest equivalent angle in (-π, π] so a layer that
    // was rotated several full turns (e.g. 720°) doesn't make the hero
    // shuttle spin around multiple times — it takes the shortest visual path
    // to straight instead.
    var layerRotation = (widget.layer?.rotation ?? 0.0) % (2 * pi);
    if (layerRotation > pi) layerRotation -= 2 * pi;
    final rotationTween =
        Tween<double>(begin: layerRotation, end: 0.0);

    final content = isOpening
        ? IntrinsicWidth(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: widget.maxWidth),
              child: shuttleChild,
            ),
          )
        : shuttleChild;

    if (layerRotation != 0) {
      // Use the Layer hero's content and size for the shuttle.
      // This ensures the shuttle has the exact same proportions
      // as the layer, eliminating size mismatch at the layer
      // endpoint.
      final fromHero = fromHeroContext.widget as Hero;
      final layerRb = fromHeroContext.findRenderObject() as RenderBox?;
      final naturalSize = (layerRb != null && layerRb.hasSize)
          ? layerRb.size
          : null;

      return AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final angle = rotationTween.evaluate(animation);

          // No correction needed when straight.
          if (angle.abs() < 0.001 || naturalSize == null) {
            return FittedBox(fit: BoxFit.contain, child: child);
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final sw = constraints.maxWidth;
              final sh = constraints.maxHeight;

              final w = naturalSize.width;
              final h = naturalSize.height;

              final absA = angle.abs();
              final cosA = cos(absA);
              final sinA = sin(absA);
              final aabbW = w * cosA + h * sinA;
              final aabbH = w * sinA + h * cosA;

              final fittedScale = min(sw / w, sh / h);
              final neededScale = min(sw / aabbW, sh / aabbH);
              final correction = neededScale / fittedScale;

              return FittedBox(
                fit: BoxFit.contain,
                child: Transform.scale(
                  scale: correction,
                  child: Transform.rotate(
                    angle: angle,
                    child: child,
                  ),
                ),
              );
            },
          );
        },
        child: SizedBox.fromSize(
          size: naturalSize ?? Size.zero,
          child: fromHero.child,
        ),
      );
    }

    return FittedBox(
      fit: BoxFit.contain,
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: widget.configs.inputTextFieldAlign,
      child: Padding(
        padding: widget.configs.style.textFieldPadding,
        child: SingleChildScrollView(
          clipBehavior: Clip.none,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: widget.configs.style.textFieldMargin,
          child: IntrinsicWidth(
            child: SingleChildScrollView(
              clipBehavior: Clip.none,
              physics: const NeverScrollableScrollPhysics(),
              padding: widget.configs.enableAutoOverflow
                  ? null
                  : const EdgeInsets.symmetric(horizontal: 16.0),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: widget.maxWidth),
                child: _buildInputField(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField() {
    // When the hero is disabled we use a tag that has no counterpart on the
    // main editor, so the Hero stays inert (no flight) and the real field is
    // never unmounted. New text uses this while open (reliable keyboard) and
    // switches to the real tag only on close, so the text flies into place.
    final heroTag = widget.enableHero
        ? (widget.heroTag ?? 'Text-Image-Editor-Empty-Hero')
        : 'Text-Editor-Inert-No-Hero';
    return Transform.scale(
      scale: widget.scaleFactor,
      child: Hero(
        flightShuttleBuilder: _flightShuttleBuilder,
        tag: heroTag,
        child: Container(
          padding: widget.configs.style.inputTextFieldPadding,
          decoration: BoxDecoration(
            color: widget.configs.style.inputTextFieldBackground,
            borderRadius: widget.configs.style.inputTextFieldBorderRadius,
          ),
          child: RoundedBackgroundTextField(
            key: const ValueKey('rounded-background-text-editor-field'),
            maxTextWidth: widget.maxWidth,
            controller: widget.textCtrl,
            focusNode: widget.focusNode,
            textFieldBuilder: widget.configs.widgets.textFieldBuilder,
            onChanged: (value) {
              widget.callbacks?.handleChanged(value);
              setState(() {});
            },
            onEditingComplete: widget.callbacks?.handleEditingComplete,
            onSubmitted: widget.callbacks?.handleSubmitted,
            textAlign: widget.textCtrl.text.isEmpty
                ? TextAlign.center
                : widget.align,
            configs: widget.configs,
            cursorHeight: widget.textFontSize,
            cursorWidth: widget.cursorWidth,
            hint: widget.i18n.inputHintText,
            hintStyle: widget.selectedTextStyle.copyWith(
              color: widget.configs.style.inputHintColor?.call(context) ??
                  const Color(0xFFBDBDBD),
              fontSize: widget.textFontSize,
              shadows: [],
            ),
            backgroundColor: widget.backgroundColor,
            style: widget.selectedTextStyle.copyWith(
              color: widget.textColor,
              fontSize: widget.textFontSize,
              letterSpacing: 0,
              decoration: TextDecoration.none,
              shadows: [],
            ),

            /// New text has no hero flight, so the field stays mounted and can
            /// autofocus directly. While editing, focus is instead handed over
            /// from the keep-alive field after the flight, so autofocus is off.
            autofocus: widget.layer == null,
          ),
        ),
      ),
    );
  }
}
