// Dart imports:
import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:heroine/heroine.dart';

import '/core/mixins/converted_callbacks.dart';
import '/core/mixins/converted_configs.dart';
import '/core/mixins/editor_configs_mixin.dart';
import '/features/text_editor/widgets/text_editor_appbar.dart';
import '/features/text_editor/widgets/text_editor_color_picker.dart';
import '/features/text_editor/widgets/text_editor_input.dart';
import '/pro_image_editor.dart';
import '/shared/extensions/color_extension.dart';
import '/shared/widgets/layer/services/hero_flight_overrides.dart';
import '/shared/widgets/slider_bottom_sheet.dart';
import 'widgets/text_editor_bottom_bar.dart';

/// A StatefulWidget that provides a text editing interface for adding and
/// editing text layers.
class TextEditor extends StatefulWidget with SimpleConfigsAccess {
  /// Creates a `TextEditor` widget.
  ///
  /// The [heroTag], [layer], [i18n], [customWidgets], and [imageEditorTheme]
  /// parameters are required.
  const TextEditor({
    super.key,
    this.heroTag,
    this.layer,
    this.callbacks = const ProImageEditorCallbacks(),
    this.configs = const ProImageEditorConfigs(),
    this.scaleFactor = 1.0,
    this.imageSize = Size.zero,
    this.heroFlightDuration,
    required this.theme,
  });

  /// Duration for the hero flight spring. When `null`, falls back to
  /// [SubEditorPageStyle.transitionDuration]. Pass the same value that was
  /// used as the page transition duration so flight and route stay in sync.
  final Duration? heroFlightDuration;
  @override
  final ProImageEditorConfigs configs;

  @override
  final ProImageEditorCallbacks callbacks;

  /// A unique hero tag for the image.
  final String? heroTag;

  /// The theme configuration for the editor.
  final ThemeData theme;

  /// The text layer data to be edited, if any.
  final TextLayer? layer;

  /// The size of the image being edited, used for boundary text wrapping.
  final Size imageSize;

  /// A factor by which the textfield is scaled.
  ///
  /// This value is used to adjust the size of the text in the editor.
  /// A value of 1.0 means no scaling, while values greater than 1.0
  /// increase the size and values less than 1.0 decrease the size.
  final double scaleFactor;

  @override
  createState() => TextEditorState();
}

/// The state class for the `TextEditor` widget.
class TextEditorState extends State<TextEditor>
    with
        ImageEditorConvertedConfigs,
        ImageEditorConvertedCallbacks,
        SimpleConfigsAccessState {
  /// A stream controller used to manage UI updates.
  ///
  /// This stream is used to broadcast events when the UI needs to be rebuilt.
  /// Public so custom bottom bars can listen for updates.
  late final StreamController<void> uiStream;

  /// The index of the currently selected option in the bottom bar.
  ///
  /// Used by custom bottom bar implementations to track which option
  /// category (e.g. font, color, alignment, background) is active.
  int selectedOptionIndex = 0;

  /// Controller for managing text input.
  final TextEditingController textCtrl = TextEditingController();

  /// Node for managing focus on the text input.
  final FocusNode focusNode = FocusNode();

  /// Focus node for the hidden "keep-alive" text field.
  ///
  /// Opening the editor (both new text and editing) runs a hero flight that
  /// temporarily removes the real text field from the tree, which would close
  /// the keyboard. This off-screen field lives *outside* the hero, so focusing
  /// it on open brings the keyboard up immediately and keeps it up; once the
  /// flight completes, focus is handed off to the real field (moving focus
  /// between two text fields does not dismiss the keyboard).
  final FocusNode keepAliveFocusNode = FocusNode();

  /// For new text the hero is inert while open (so the field stays mounted and
  /// the keyboard is reliable). This flag flips to `true` right before closing
  /// so the *closing* flight runs — the text flies to its placed position on
  /// the canvas. (Editing always uses the hero, so this only matters for new
  /// text.)
  bool _useHeroForClose = false;

  /// Alignment of the text.
  late TextAlign align;

  /// Style applied to the selected text.
  late TextStyle selectedTextStyle;

  /// Mode for managing the background color of the text layer.
  late LayerBackgroundMode backgroundColorMode;

  /// Represents the dimensions of the body.
  Size editorBodySize = Size.infinite;

  late double _fontScale;
  final double _cursorWidth = 2.0;

  double? get _maxTextWidth {
    if (textEditorConfigs.enableImageBoundaryTextWrap &&
        widget.imageSize != Size.zero) {
      return widget.imageSize.width - 32 - _cursorWidth;
    }
    return textEditorConfigs.enableAutoOverflow
        ? editorBodySize.width - 32 - _cursorWidth
        : null;
  }

  /// Gets the primary color.
  Color get primaryColor => _primaryColor;
  late Color _primaryColor = textEditorConfigs.initialPrimaryColor;
  set primaryColor(Color color) {
    setState(() {
      _primaryColor = color;
      textEditorCallbacks?.handleColorChanged(color.toHex());
    });
  }

  /// Gets the secondary color.
  Color get secondaryColor => _secondaryColor ?? getContrastColor(primaryColor);
  late Color? _secondaryColor = textEditorConfigs.initialSecondaryColor;
  set secondaryColor(Color color) {
    setState(() {
      _secondaryColor = color;
    });
  }

  @override
  void initState() {
    super.initState();
    uiStream = StreamController.broadcast();
    align = textEditorConfigs.initialTextAlign;
    _fontScale = textEditorConfigs.initFontScale;
    backgroundColorMode = textEditorConfigs.initialBackgroundColorMode;

    selectedTextStyle = widget.layer?.textStyle ??
        textEditorConfigs.customTextStyles?.first ??
        textEditorConfigs.defaultTextStyle;
    _initializeFromLayer();

    textEditorCallbacks?.onInit?.call();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      if (!mounted) return;
      if (widget.layer == null) {
        // New text opens without a hero flight, so the real field can be
        // focused directly and the keyboard opens right away.
        focusNode.requestFocus();
      } else {
        // Editing runs a hero flight during which the real field is hidden
        // (and mirrored in the flight shuttle). Focus the hidden keep-alive
        // field so the keyboard comes up early and stays up, then hand focus
        // to the real field once the route transition is done (moving focus
        // between two text fields doesn't dismiss the keyboard).
        //
        // The focus request is deferred two frames: the first frames of the
        // push already carry the editor's expensive initial build + the hero
        // flight start, and kicking off the IME in the same frame batch
        // amplifies the visible stall at the start of the transition.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) keepAliveFocusNode.requestFocus();
          });
        });
        _handOffFocusWhenSettled();
      }
      textEditorCallbacks?.onAfterViewInit?.call();
    });
  }

  /// Hands focus from the keep-alive field to the real field once the hero
  /// flight has fully settled.
  ///
  /// Re-attaching the IME to the real field costs a heavy frame; doing it at
  /// route completion (like before) caused a visible stutter right when the
  /// landing was still following the keyboard up. The keep-alive field keeps
  /// the keyboard alive in the meantime, and typing already works because
  /// both fields share the same [TextEditingController]. The deadline is a
  /// safety net in case the flight never reports its end.
  Future<void> _handOffFocusWhenSettled() async {
    final tag = widget.heroTag;
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (mounted &&
        tag != null &&
        HeroineController.isTagInFlight(tag) &&
        DateTime.now().isBefore(deadline)) {
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted) return;
    // Never grab focus once the editor started closing — the open flight can
    // end right around the pop, and re-focusing then re-opens the keyboard
    // mid-close (visible as the keyboard bouncing back up).
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    focusNode.requestFocus();
  }

  @override
  void dispose() {
    uiStream.close();
    textCtrl.dispose();
    focusNode.dispose();
    keepAliveFocusNode.dispose();
    super.dispose();
  }

  @override
  void setState(void Function() fn) {
    uiStream.add(null);
    textEditorCallbacks?.handleUpdateUI();
    super.setState(fn);
  }

  /// Initializes the text editor from the provided text layer data.
  void _initializeFromLayer() {
    if (widget.layer != null) {
      textCtrl.text = widget.layer!.text;
      align = widget.layer!.align;
      _fontScale = widget.layer!.fontScale;
      backgroundColorMode = widget.layer!.colorMode;
      if (widget.layer!.customSecondaryColor) {
        _primaryColor = widget.layer!.color;
        _secondaryColor = widget.layer!.background;
      } else {
        _primaryColor = backgroundColorMode == LayerBackgroundMode.background
            ? widget.layer!.background
            : widget.layer!.color;
      }
    }
  }

  /// Calculates the contrast color for a given color.
  Color getContrastColor(Color color) {
    int d = color.computeLuminance() > 0.5 ? 0 : 255;

    return Color.fromRGBO(d, d, d, color.a);
  }

  /// Gets the text color based on the selected color mode.
  Color get _textColor {
    switch (backgroundColorMode) {
      case LayerBackgroundMode.onlyColor:
      case LayerBackgroundMode.backgroundAndColor:
      case LayerBackgroundMode.harmonized:
        return primaryColor;
      case LayerBackgroundMode.background:
        return secondaryColor;
      default:
        return primaryColor;
    }
  }

  /// Gets the background color based on the selected color mode.
  Color get _backgroundColor {
    switch (backgroundColorMode) {
      case LayerBackgroundMode.onlyColor:
        return Colors.transparent;
      case LayerBackgroundMode.backgroundAndColor:
        return secondaryColor;
      case LayerBackgroundMode.background:
        return primaryColor;
      case LayerBackgroundMode.harmonized:
        return _harmonizedBackground;
      default:
        return secondaryColor.withValues(alpha: 0.5);
    }
  }

  /// Computes a harmonized background color from the primary color
  /// using the `dynamic_color` package for Material You harmonization.
  Color get _harmonizedBackground {
    final scheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: primaryColor.computeLuminance() > 0.5
          ? Brightness.dark
          : Brightness.light,
    ).harmonized();
    return scheme.primaryContainer;
  }

  /// Gets the text font size based on the selected font scale.
  double get _textFontSize {
    return textEditorConfigs.initFontSize * _fontScale;
  }

  /// Toggles the text alignment between left, center, and right.
  void toggleTextAlign() {
    TextAlign nextTextAlign(TextAlign currentAlign) {
      switch (currentAlign) {
        case TextAlign.left:
          return TextAlign.center;
        case TextAlign.center:
          return TextAlign.right;
        case TextAlign.right:
        default:
          return TextAlign.left;
      }
    }

    align = nextTextAlign(align);
    textEditorCallbacks?.handleTextAlignChanged(align);
    setState(() {});
  }

  /// Toggles the background mode between various color modes.
  void toggleBackgroundMode() {
    LayerBackgroundMode nextBackgroundMode(LayerBackgroundMode currentMode) {
      switch (currentMode) {
        case LayerBackgroundMode.onlyColor:
          return LayerBackgroundMode.backgroundAndColor;
        case LayerBackgroundMode.backgroundAndColor:
          return LayerBackgroundMode.background;
        case LayerBackgroundMode.background:
          return LayerBackgroundMode.backgroundAndColorWithOpacity;
        case LayerBackgroundMode.backgroundAndColorWithOpacity:
          return LayerBackgroundMode.harmonized;
        case LayerBackgroundMode.harmonized:
          return LayerBackgroundMode.onlyColor;
      }
    }

    backgroundColorMode = nextBackgroundMode(backgroundColorMode);
    textEditorCallbacks?.handleBackgroundModeChanged(backgroundColorMode);
    setState(() {});
  }

  /// Gets the current font scale.
  double get fontScale => _fontScale;

  /// Sets the font scale to a new value.
  ///
  /// The new value is adjusted to one decimal place before being set.
  /// After setting the new value, the state is updated and the
  /// [textEditorCallbacks] are notified of the change.
  ///
  /// [value] - The new font scale value.
  set fontScale(double value) {
    _fontScale = (value * 10).ceilToDouble() / 10;
    setState(() {});
    textEditorCallbacks?.handleFontScaleChanged(value);
  }

  /// Displays a range slider for adjusting the line width of the paint tool.
  ///
  /// This method shows a range slider in a modal bottom sheet for adjusting the
  /// line width of the paint tool.
  void openFontScaleBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: textEditorConfigs.style.fontScaleBottomSheetBackground,
      builder: (BuildContext context) => SliderBottomSheet<TextEditorState>(
        value: _fontScale,
        title: i18n.textEditor.fontScale,
        headerTextStyle: textEditorConfigs.style.fontSizeBottomSheetTitle,
        resetIcon: textEditorConfigs.icons.resetFontScale,
        max: textEditorConfigs.maxFontScale,
        min: textEditorConfigs.minFontScale,
        divisions:
            (textEditorConfigs.maxFontScale - textEditorConfigs.minFontScale) ~/
                0.1,
        state: this,
        showFactorInTitle: true,
        closeButton: textEditorConfigs.widgets.fontSizeCloseButton,
        customSlider: textEditorConfigs.widgets.sliderFontSize,
        designMode: designMode,
        theme: widget.theme,
        rebuildController: uiStream,
        onValueChanged: (value) {
          fontScale = value;
        },
      ),
    );
  }

  /// Update the current text style.
  void setTextStyle(TextStyle style) {
    setState(() {
      selectedTextStyle = style;
    });
  }

  /// Drops focus before the editor pops. The closing flight's shuttle builds
  /// a copy of the text field that shares the real [FocusNode] — if that node
  /// is still focused when the copy mounts, its EditableText re-opens the IME
  /// connection and the keyboard briefly pops back up mid-flight.
  void _unfocusBeforeClose() {
    focusNode.unfocus();
    keepAliveFocusNode.unfocus();
  }

  /// Closes the editor without applying changes.
  void close() {
    _unfocusBeforeClose();
    Navigator.pop(context);
    textEditorCallbacks?.handleCloseEditor();
  }

  /// Handles the "Done" action, either by applying changes or closing the
  /// editor.
  void done() {
    _unfocusBeforeClose();
    if (textCtrl.text.trim().isNotEmpty || widget.layer != null) {
      TextLayer layer = TextLayer(
        text: textCtrl.text.trim(),
        background: _backgroundColor,
        color: _textColor,
        align: align,
        fontScale: _fontScale,
        colorMode: backgroundColorMode,
        textStyle: selectedTextStyle,
        customSecondaryColor: _secondaryColor != null,
        maxTextWidth: (textEditorConfigs.enableAutoWrapOnLayer ||
                textEditorConfigs.enableImageBoundaryTextWrap)
            ? _maxTextWidth
            : null,
      );

      if (widget.layer == null) {
        // New text: the hero tag switches from inert to real on close, so the
        // rebuild must happen *before* the pop → defer the pop one frame.
        setState(() => _useHeroForClose = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop(layer);
        });
      } else {
        // Publish the edited content as the hero override *before* popping,
        // with the layer's current scale, so the canvas layer already renders
        // the new text during the closing flight (correct end size, no
        // old-text flash).
        layer.scale = widget.layer!.scale;
        HeroFlightOverrides.instance.set(widget.layer!.id, layer);
        Navigator.of(context).pop(layer);
      }
    } else {
      Navigator.of(context).pop();
    }
    textEditorCallbacks?.handleDone();
  }

  /// Exports the current text layer state.
  TextLayer? exportStateHistory() {
    if (textCtrl.text.trim().isNotEmpty || widget.layer != null) {
      return TextLayer(
        text: textCtrl.text.trim(),
        background: _backgroundColor,
        color: _textColor,
        align: align,
        fontScale: _fontScale,
        colorMode: backgroundColorMode,
        textStyle: selectedTextStyle,
        customSecondaryColor: _secondaryColor != null,
        maxTextWidth: (textEditorConfigs.enableAutoWrapOnLayer ||
                textEditorConfigs.enableImageBoundaryTextWrap)
            ? _maxTextWidth
            : null,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ExtendedPopScope(
          canPop: textEditorConfigs.enableGesturePop,
          child: Theme(
            data: widget.theme.copyWith(
                tooltipTheme:
                    widget.theme.tooltipTheme.copyWith(preferBelow: true)),
            child: SafeArea(
              top: textEditorConfigs.safeArea.top,
              bottom: textEditorConfigs.safeArea.bottom,
              left: textEditorConfigs.safeArea.left,
              right: textEditorConfigs.safeArea.right,
              child: Scaffold(
                resizeToAvoidBottomInset:
                    textEditorConfigs.resizeToAvoidBottomInset,
                backgroundColor:
                    textEditorConfigs.style.background?.call(context) ??
                        const Color(0x9B000000),
                appBar: _buildAppBar(constraints),
                body: _buildBody(),
                bottomNavigationBar: _buildBottomBar(),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Builds the app bar for the text editor.
  PreferredSizeWidget? _buildAppBar(BoxConstraints constraints) {
    if (textEditorConfigs.widgets.appBar != null) {
      return textEditorConfigs.widgets.appBar!.call(this, uiStream.stream);
    }

    return TextEditorAppBar(
      textEditorConfigs: textEditorConfigs,
      i18n: i18n.textEditor,
      onClose: close,
      onDone: done,
      align: align,
      onToggleTextAlign: toggleTextAlign,
      onOpenFontScaleBottomSheet: openFontScaleBottomSheet,
      onToggleBackgroundMode: toggleBackgroundMode,
      designMode: designMode,
      constraints: constraints,
    );
  }

  /// Builds the bottom navigation bar of the paint editor.
  /// Returns a [Widget] representing the bottom navigation bar.
  Widget? _buildBottomBar() {
    if (textEditorConfigs.widgets.bottomBar != null) {
      return textEditorConfigs.widgets.bottomBar!.call(this, uiStream.stream);
    }

    if (isDesktop &&
        widget.configs.textEditor.customTextStyles?.isNotEmpty == false) {
      return const SizedBox(height: kBottomNavigationBarHeight);
    }

    return null;
  }

  /// Builds the body of the text editor.
  Widget _buildBody() {
    return LayoutBuilder(builder: (_, constraints) {
      editorBodySize = constraints.biggest;

      Widget textField = _buildTextField();
      if (textEditorConfigs.widgets.wrapTextField != null) {
        textField = textEditorConfigs.widgets.wrapTextField!(this, textField);
      }

      Widget content = Stack(
        children: [
          // Keep-alive is only needed while editing (the hero flight unmounts
          // the real field). New text opens without a hero, so it isn't used.
          if (widget.layer != null) _buildKeepAliveField(),
          textField,
          _buildColorPicker(),
          if (textEditorConfigs.showSelectFontStyleBottomBar)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: kBottomNavigationBarHeight,
              child: TextEditorBottomBar(
                configs: widget.configs,
                selectedStyle: selectedTextStyle,
                onFontChange: setTextStyle,
              ),
            ),
        ],
      );

      if (textEditorConfigs.widgets.wrapBody != null) {
        content = textEditorConfigs.widgets.wrapBody!(this, content);
      }

      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: textEditorConfigs.enableTapOutsideToSave ? done : null,
        child: Stack(
          children: [
            content,
            if (textEditorConfigs.widgets.bodyItems != null)
              ...textEditorConfigs.widgets.bodyItems!(
                this,
                uiStream.stream,
              ),
            if (textEditorConfigs.widgets.bodyItemsOverlay != null)
              ...textEditorConfigs.widgets.bodyItemsOverlay!(
                this,
                uiStream.stream,
              ),
          ],
        ),
      );
    });
  }

  Widget _buildColorPicker() {
    return TextEditorColorPicker(
      state: this,
      configs: configs,
      primaryColor: primaryColor,
      rebuildController: uiStream,
      selectedTextStyle: selectedTextStyle,
      onUpdateColor: (color) {
        primaryColor = color;
      },
    );
  }

  /// Builds the hidden keep-alive text field.
  ///
  /// It sits outside the hero (so it is never unmounted by the flight) and is
  /// focused on open to bring the keyboard up immediately and keep it up. Once
  /// the hero flight completes, focus is handed to the real field. It is laid
  /// out at 1×1 and fully transparent so it is invisible and doesn't capture
  /// pointers, but still mountable/focusable so the IME stays attached.
  ///
  /// Its IME configuration MUST mirror the real field (see
  /// [RoundedBackgroundTextField]); otherwise the keyboard reconfigures during
  /// the focus hand-off and visibly jumps (e.g. light/dark appearance, layout,
  /// suggestion bar).
  Widget _buildKeepAliveField() {
    return Positioned(
      left: 0,
      top: 0,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0,
          child: SizedBox(
            width: 1,
            height: 1,
            child: TextField(
              // Share the real controller so the keep-alive mirrors the exact
              // text *and* selection. The IME's shift/auto-capitalization
              // state derives from text + cursor position, so an empty field
              // would hand off with a different shift state (e.g. capital at
              // start vs. lowercase mid-word). Sharing also means characters
              // typed during the flight aren't lost.
              controller: textCtrl,
              focusNode: keepAliveFocusNode,
              maxLines: null,
              style: const TextStyle(fontSize: 1),
              decoration: const InputDecoration.collapsed(hintText: ''),
              // ── Mirror RoundedBackgroundTextField's IME config ──
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.newline,
              keyboardAppearance: widget.theme.brightness,
              autocorrect: textEditorConfigs.enableAutocorrect,
              smartDashesType: SmartDashesType.enabled,
              smartQuotesType: SmartQuotesType.enabled,
              enableSuggestions: textEditorConfigs.enableSuggestions,
            ),
          ),
        ),
      ),
    );
  }

  /// Builds the text field for text input.
  Widget _buildTextField() {
    return TextEditorInput(
      callbacks: textEditorCallbacks,
      configs: textEditorConfigs,
      heroTag: widget.heroTag,
      // Editing always flies; new text flies only on close (see done()).
      enableHero: widget.layer != null || _useHeroForClose,
      heroFlightDuration: widget.heroFlightDuration ??
          mainEditorConfigs.style.subEditorPage.transitionDuration,
      align: align,
      backgroundColor: _backgroundColor,
      textCtrl: textCtrl,
      scaleFactor: widget.scaleFactor,
      focusNode: focusNode,
      i18n: i18n.textEditor,
      layer: widget.layer,
      selectedTextStyle: selectedTextStyle,
      textColor: _textColor,
      textFontSize: _textFontSize,
      maxWidth: _maxTextWidth ?? double.infinity,
      cursorWidth: _cursorWidth,
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);

    properties
      ..add(StringProperty('heroTag', widget.heroTag))
      ..add(DoubleProperty('scaleFactor', widget.scaleFactor))
      ..add(DiagnosticsProperty<TextLayer?>('layer', widget.layer))
      ..add(DiagnosticsProperty<Size>('imageSize', widget.imageSize))
      ..add(DiagnosticsProperty<ThemeData>('theme', widget.theme))
      ..add(DiagnosticsProperty<TextAlign>('align', align))
      ..add(DiagnosticsProperty<TextStyle>(
          'selectedTextStyle', selectedTextStyle))
      ..add(EnumProperty<LayerBackgroundMode>(
          'backgroundColorMode', backgroundColorMode))
      ..add(DoubleProperty('fontScale', _fontScale))
      ..add(ColorProperty('primaryColor', primaryColor))
      ..add(ColorProperty('secondaryColor', secondaryColor))
      ..add(DiagnosticsProperty<Size>('editorBodySize', editorBodySize));
  }
}
