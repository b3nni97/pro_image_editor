import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '/core/models/editor_configs/pro_image_editor_configs.dart';
import '/shared/widgets/editor_scrollbar.dart';
import '/shared/widgets/flat_icon_text_button.dart';
import '../crop_rotate_editor.dart';

/// A widget representing the bottom bar for the crop editor, providing
/// options like rotate, flip, aspect ratio, and reset, as well as an inline
/// slider for straighten adjustments.
class CropEditorBottombar extends StatefulWidget {
  /// Creates a `CropEditorBottombar` with the provided configurations and
  /// callbacks.
  ///
  /// - [bottomBarScrollCtrl]: Controls the scroll behavior of the bottom bar.
  /// - [i18n]: Provides localized strings for tooltips and labels.
  /// - [configs]: Contains configurations for the crop and rotate editor.
  /// - [theme]: Defines the theme to style the bottom bar.
  /// - [tools]: List of available tools to display.
  /// - [isStraightenModeActive]: Whether straighten mode is currently active.
  /// - [straightenAngle]: Current straighten angle value.
  /// - [rebuildController]: Stream controller for triggering rebuilds.
  /// - [editorState]: Reference to the crop rotate editor state.
  /// - [onRotate]: Callback invoked when the rotate option is selected.
  /// - [onFlip]: Callback invoked when the flip option is selected.
  /// - [onOpenAspectRatioOptions]: Callback invoked when the aspect ratio
  /// options are opened.
  /// - [onReset]: Callback invoked when the reset option is selected.
  /// - [onStraighten]: Callback invoked when straighten mode is toggled.
  /// - [onStraightenChanged]: Callback invoked when slider value changes.
  /// - [onStraightenChangeEnd]: Callback invoked when slider interaction ends.
  const CropEditorBottombar({
    super.key,
    required this.bottomBarScrollCtrl,
    required this.i18n,
    required this.configs,
    required this.theme,
    required this.tools,
    required this.isStraightenModeActive,
    required this.straightenAngle,
    required this.rebuildController,
    required this.editorState,
    required this.onRotate,
    required this.onFlip,
    required this.onOpenAspectRatioOptions,
    required this.onReset,
    required this.onStraighten,
    required this.onStraightenChanged,
    required this.onStraightenChangeEnd,
  });

  /// Controls the scroll behavior of the bottom bar.
  final ScrollController bottomBarScrollCtrl;

  /// Provides localized strings for tooltips and labels.
  final I18nCropRotateEditor i18n;

  /// Configurations for the crop and rotate editor.
  final CropRotateEditorConfigs configs;

  /// Theme data for styling the bottom bar.
  final ThemeData theme;

  /// Defines which crop tools are available in the editor.
  final List<CropRotateTool> tools;

  /// Whether straighten mode is currently active.
  final bool isStraightenModeActive;

  /// Current straighten angle value (in radians).
  final double straightenAngle;

  /// Stream controller for triggering UI rebuilds.
  final StreamController<void> rebuildController;

  /// Reference to the crop rotate editor state.
  final CropRotateEditorState editorState;

  /// Callback for the rotate option.
  final Function() onRotate;

  /// Callback for the flip option.
  final Function() onFlip;

  /// Callback for opening the aspect ratio options.
  final Function() onOpenAspectRatioOptions;

  /// Callback for resetting the editor.
  final Function() onReset;

  /// Callback for toggling straighten mode.
  final Function() onStraighten;

  /// Callback when straighten slider value changes.
  final Function(double value) onStraightenChanged;

  /// Callback when straighten slider interaction ends.
  final Function(double value) onStraightenChangeEnd;

  @override
  State<CropEditorBottombar> createState() => _CropEditorBottombarState();
}

class _CropEditorBottombarState extends State<CropEditorBottombar> {
  late ValueNotifier<double> _sliderValue;

  @override
  void initState() {
    super.initState();
    _sliderValue = ValueNotifier(widget.straightenAngle);
  }

  @override
  void didUpdateWidget(covariant CropEditorBottombar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.straightenAngle != oldWidget.straightenAngle) {
      _sliderValue.value = widget.straightenAngle;
    }
  }

  @override
  void dispose() {
    _sliderValue.dispose();
    super.dispose();
  }

  void _updateSliderValue(double value) {
    _sliderValue.value = value;
    widget.onStraightenChanged(value);
  }

  _ToolItem _getItem(CropRotateTool tool) {
    switch (tool) {
      case CropRotateTool.rotate:
        return _ToolItem(
          key: const ValueKey('crop-rotate-editor-rotate-btn'),
          label: widget.i18n.rotate,
          icon: widget.configs.icons.rotate,
          onTap: widget.onRotate,
        );
      case CropRotateTool.flip:
        return _ToolItem(
          key: const ValueKey('crop-rotate-editor-flip-btn'),
          label: widget.i18n.flip,
          icon: widget.configs.icons.flip,
          onTap: widget.onFlip,
        );
      case CropRotateTool.aspectRatio:
        return _ToolItem(
          key: const ValueKey('crop-rotate-editor-ratio-btn'),
          label: widget.i18n.ratio,
          icon: widget.configs.icons.aspectRatio,
          onTap: widget.onOpenAspectRatioOptions,
        );
      case CropRotateTool.reset:
        return _ToolItem(
          key: const ValueKey('crop-rotate-editor-reset-btn'),
          label: widget.i18n.reset,
          icon: widget.configs.icons.reset,
          onTap: widget.onReset,
        );
      case CropRotateTool.straighten:
        return _ToolItem(
          key: const ValueKey('crop-rotate-editor-straighten-btn'),
          label: widget.i18n.straighten,
          icon: widget.configs.icons.straighten,
          onTap: widget.onStraighten,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: widget.theme,
      child: SafeArea(
        child: Container(
          color: widget.configs.style.bottomBarBackground,
          padding: widget.isStraightenModeActive
              ? const EdgeInsets.symmetric(vertical: 8)
              : EdgeInsets.zero,
          child: widget.isStraightenModeActive
              ? _buildSlider()
              : _buildTools(),
        ),
      ),
    );
  }

  Widget _buildSlider() {
    const double maxAngle = pi / 4; // 45 degrees in radians
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Angle display
        Text(
          '${(_sliderValue.value * 180 / pi).toStringAsFixed(1)}°',
          style: TextStyle(
            color: widget.configs.style.appBarColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        // Slider
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: RepaintBoundary(
            child: ValueListenableBuilder(
              valueListenable: _sliderValue,
              builder: (_, value, __) {
                return widget.configs.widgets.slider?.call(
                      widget.editorState,
                      widget.rebuildController.stream,
                      value,
                      _updateSliderValue,
                      widget.onStraightenChangeEnd,
                    ) ??
                    Slider(
                      min: -maxAngle,
                      max: maxAngle,
                      divisions: 180,
                      value: value,
                      onChanged: _updateSliderValue,
                      onChangeEnd: widget.onStraightenChangeEnd,
                    );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTools() {
    return EditorScrollbar(
      controller: widget.bottomBarScrollCtrl,
      child: BottomAppBar(
        height: kToolbarHeight,
        color: widget.configs.style.bottomBarBackground,
        padding: EdgeInsets.zero,
        child: Center(
          child: SingleChildScrollView(
            controller: widget.bottomBarScrollCtrl,
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: min(MediaQuery.sizeOf(context).width, 500),
                maxWidth: 500,
              ),
              child: Wrap(
                direction: Axis.horizontal,
                alignment: WrapAlignment.spaceAround,
                children: widget.tools
                    .map((tool) => _buildTool(_getItem(tool)))
                    .toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTool(_ToolItem item) {
    Color foregroundColor = widget.configs.style.appBarColor;
    return FlatIconTextButton(
      key: item.key,
      label: Text(
        item.label,
        style: TextStyle(fontSize: 10.0, color: foregroundColor),
      ),
      icon: Icon(item.icon, color: foregroundColor),
      onPressed: item.onTap,
    );
  }
}

class _ToolItem {
  const _ToolItem({
    required this.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final Key key;
  final String label;
  final IconData icon;
  final Function() onTap;
}
