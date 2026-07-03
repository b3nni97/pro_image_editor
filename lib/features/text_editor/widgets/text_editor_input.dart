import 'package:flutter/material.dart';
import 'package:heroine/heroine.dart';

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
    required this.heroFlightDuration,
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

  /// Duration for the hero flight spring, matched to the sub-editor page
  /// transition (see [SubEditorPageStyle.transitionDuration]) so flight and
  /// route fade end together.
  final Duration heroFlightDuration;

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
      child: Heroine(
        continuouslyTrackTarget: true,
        // Spring tuned to the sub-editor page transition: flight and route
        // fade end together (no long settle tail), no bounce. snapToEnd lets
        // the flight report completion promptly, which also shortens the
        // waits keyed on isTagInFlight (focus hand-off etc.).
        motion: CupertinoMotion.smooth(
          duration: widget.heroFlightDuration,
          snapToEnd: true,
        ),
        // Keep the hidden field laid out at its *current* natural size while
        // in flight (heroine's default placeholder pins the size captured at
        // flight start). Typing during the flight changes the text width;
        // with the pinned width the landing rendered the field too narrow
        // and the new character briefly wrapped to a second line.
        placeholderBuilder: (context, heroSize, child) => IgnorePointer(
          child: Opacity(opacity: 0, child: child),
        ),
        flightShuttleBuilder: _FittedShuttleBuilder(maxWidth: widget.maxWidth),
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
            textAlign:
                widget.textCtrl.text.isEmpty ? TextAlign.center : widget.align,
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

            /// Never autofocus: the flight shuttle builds a *copy* of this
            /// field, and an autofocusing copy re-opens the keyboard
            /// mid-flight (visible as the keyboard bouncing during the
            /// new-text close). Focus is always requested explicitly in
            /// TextEditorState.initState (directly for new text, via the
            /// keep-alive hand-off while editing).
            autofocus: false,
          ),
        ),
      ),
    );
  }
}

/// Scales the destination hero content into the animated flight box.
///
/// Heroine's default [FadeShuttleBuilder] re-lays-out both hero children at
/// the flight-box size on every frame (`Stack(fit: StackFit.expand)`), which
/// makes text re-wrap and jump around during the flight. This builder instead
/// renders the destination child once at its natural size and scales it
/// visually via [FittedBox] — the text keeps its layout for the whole flight.
///
/// Used for both directions: on push the destination is the editor field, on
/// pop it is the canvas layer (heroine falls back to the source hero's shuttle
/// builder when the destination has none).
class _FittedShuttleBuilder extends HeroineShuttleBuilder {
  const _FittedShuttleBuilder({required this.maxWidth});

  /// The editor field's max text width — the shuttle mirrors the field's real
  /// layout environment so the text lays out at its intrinsic width.
  final double maxWidth;

  @override
  List<Object?> get props => [maxWidth];

  /// The editor-field side: recreate the field's real layout environment
  /// (IntrinsicWidth capped at [maxWidth], like TextEditorInput.build) so the
  /// text lays out at its intrinsic width and can never wrap mid-flight.
  Widget _editorSide(Widget child) {
    return FittedBox(
      fit: BoxFit.contain,
      clipBehavior: Clip.none,
      child: IntrinsicWidth(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }

  /// The canvas-layer side: pin the content to its measured natural size so
  /// FittedBox scales instead of re-layouting.
  Widget _layerSide(Widget child, BuildContext heroContext) {
    final renderBox = heroContext.findRenderObject();
    final naturalSize =
        renderBox is RenderBox && renderBox.hasSize ? renderBox.size : null;
    return FittedBox(
      fit: BoxFit.contain,
      clipBehavior: Clip.none,
      child: SizedBox.fromSize(
        size: naturalSize,
        child: child,
      ),
    );
  }

  @override
  Widget call(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    // A hero can be unmounted mid-flight (e.g. the canvas layer being swapped
    // right after an edit); reading `.widget` on a defunct element throws.
    Widget heroChild(BuildContext heroContext) => heroContext.mounted
        ? InheritedTheme.captureAll(
            heroContext,
            (heroContext.widget as Heroine).child,
          )
        : const SizedBox.shrink();

    // The two hero endpoints differ slightly in geometry (the editor field
    // reserves cursor width + input padding, the canvas layer doesn't), so a
    // single-content shuttle makes the text jump ~1-3px sideways at one
    // endpoint. Cross-fade both contents instead — each rendered
    // pixel-faithfully in its own layout environment — so the shuttle matches
    // the source exactly at t=0 and the destination exactly at t=1. The texts
    // are identical, so the mid-flight blend is invisible.
    final isPush = flightDirection == HeroFlightDirection.push;
    // ExcludeFocus: the editor-side copy shares the real field's FocusNode —
    // the flying copy must never be able to attach it to the focus tree or
    // re-open the IME (visible as the keyboard bouncing back up mid-close).
    final editorSide = ExcludeFocus(
      child: _editorSide(heroChild(isPush ? toHeroContext : fromHeroContext)),
    );
    final layerSide = _layerSide(
      heroChild(isPush ? fromHeroContext : toHeroContext),
      isPush ? fromHeroContext : toHeroContext,
    );
    final fromSide = isPush ? layerSide : editorSide;
    final toSide = isPush ? editorSide : layerSide;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        // 0 = fully the source hero, 1 = fully the destination hero.
        final t = (isPush ? animation.value : 1 - animation.value)
            .clamp(0.0, 1.0)
            .toDouble();
        // A plain cross-fade dips to ~75% combined alpha mid-flight (two 50%
        // layers don't add up to opaque), which reads as the text briefly
        // turning translucent. Instead, fade the destination in over the
        // first 40% and the source out over the last 40%, so at least one
        // layer is fully opaque at all times. The contents are near-identical
        // so the full-opacity overlap in the middle is invisible.
        final toOpacity = (t / 0.4).clamp(0.0, 1.0).toDouble();
        final fromOpacity = ((1 - t) / 0.4).clamp(0.0, 1.0).toDouble();
        return Stack(
          children: [
            if (fromOpacity > 0)
              Positioned.fill(
                child: Opacity(opacity: fromOpacity, child: fromSide),
              ),
            if (toOpacity > 0)
              Positioned.fill(
                child: Opacity(opacity: toOpacity, child: toSide),
              ),
          ],
        );
      },
    );
  }
}
