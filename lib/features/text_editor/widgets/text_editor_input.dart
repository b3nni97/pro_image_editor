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
    this.readOnly = false,
  });

  /// Whether the field is read-only. While the hero flight runs, the field
  /// stays read-only so it can be focused (blinking cursor) without
  /// attaching an IME connection — typing flows through the pre-warmed
  /// throwaway client until the flight settles.
  final bool readOnly;

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

/// Marks a subtree as living inside the hero flight shuttle (the flying
/// copy in the overlay), so widgets that hold shared resources can behave
/// differently there — see the focus-node selection in
/// [_TextEditorInputState._buildInputField].
class _InFlightShuttle extends InheritedWidget {
  const _InFlightShuttle({required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_InFlightShuttle>() != null;

  @override
  bool updateShouldNotify(_InFlightShuttle oldWidget) => false;
}

class _TextEditorInputState extends State<TextEditorInput> {
  /// Focus node for the *shuttle copy* of the input field.
  ///
  /// The shuttle re-instantiates the heroine child in the overlay. If that
  /// copy attached the REAL focus node, it would steal the node's attachment
  /// (a FocusNode can only be attached to one context) — and since the copy
  /// sits inside ExcludeFocus, the real node reports `canRequestFocus ==
  /// false` and the focus hand-off after the flight silently fails (no
  /// cursor, typing goes into the throwaway IME connection). The copy gets
  /// this inert node instead; the real node never leaves the real field.
  final FocusNode _shuttleFocusNode = FocusNode(
    canRequestFocus: false,
    skipTraversal: true,
    debugLabel: 'text-editor-shuttle-copy',
  );

  @override
  void dispose() {
    _shuttleFocusNode.dispose();
    super.dispose();
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
      child: Heroine(
        continuouslyTrackTarget: true,
        // Match the layer-side heroine: text flights render above the
        // (heroine-based) image hero, which uses the default z-index of 0.
        zIndex: 10,
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
        // Builder so the focus-node choice happens at the MOUNT location:
        // the same child widget is re-instantiated inside the flight shuttle
        // (see _FittedShuttleBuilder), and the copy must not attach the real
        // focus node (see [_shuttleFocusNode]).
        child: Builder(builder: (fieldContext) {
          final inShuttle = _InFlightShuttle.of(fieldContext);
          return Container(
            padding: widget.configs.style.inputTextFieldPadding,
            decoration: BoxDecoration(
              color: widget.configs.style.inputTextFieldBackground,
              borderRadius: widget.configs.style.inputTextFieldBorderRadius,
            ),
            child: RoundedBackgroundTextField(
              key: const ValueKey('rounded-background-text-editor-field'),
              maxTextWidth: widget.maxWidth,
              controller: widget.textCtrl,
              focusNode: inShuttle ? _shuttleFocusNode : widget.focusNode,
              readOnly: widget.readOnly,
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

              /// Never autofocus: the flight shuttle builds a *copy* of this
              /// field, and an autofocusing copy re-opens the keyboard
              /// mid-flight (visible as the keyboard bouncing during the
              /// new-text close). Focus is always requested explicitly in
              /// TextEditorState.initState (directly for new text, via the
              /// settle hand-off while editing).
              autofocus: false,
            ),
          );
        }),
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
    // No size pin: inside the FittedBox the content lays out unconstrained —
    // exactly like the canvas layer does in-tree — so it measures the same
    // natural size at takeoff AND keeps growing horizontally when the text
    // changes mid-flight (a size pinned at flight start would force typed
    // characters onto a second line instead).
    return FittedBox(
      fit: BoxFit.contain,
      clipBehavior: Clip.none,
      child: child,
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
    // ExcludeFocus: the flying copy must never take focus or re-open the IME
    // (visible as the keyboard bouncing back up mid-close). _InFlightShuttle
    // additionally makes the copy attach its own inert focus node instead of
    // the real field's — a FocusNode can only be attached to one context, so
    // a copy sharing the real node would steal its attachment and break the
    // focus hand-off after the flight (no cursor, dead keyboard).
    final editorSide = ExcludeFocus(
      child: _InFlightShuttle(
        child: _editorSide(heroChild(isPush ? toHeroContext : fromHeroContext)),
      ),
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
