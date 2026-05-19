import 'package:flutter/material.dart';

/// A Hero wrapper that automatically suppresses the overlay flight when
/// the source and destination positions are identical (or nearly so).
///
/// During a Hero flight, Flutter lifts the widget into the Navigator's
/// overlay, which renders it above all other content (including shadows
/// and other visual effects). When start and end positions are the same
/// this overlay serves no visual purpose but can cause visual artifacts.
///
/// [SmartHero] detects this case and hides the shuttle while keeping the
/// child visible in-place via [placeholderBuilder].
class SmartHero extends StatelessWidget {
  /// Creates a [SmartHero] that suppresses no-op hero flights.
  const SmartHero({
    super.key,
    required this.tag,
    required this.child,
    this.createRectTween,
    this.enabled = true,
  });

  /// The hero tag.
  final Object tag;

  /// The child widget.
  final Widget child;

  /// Optional rect tween factory for the hero animation.
  final CreateRectTween? createRectTween;

  /// Whether the smart hero behavior is enabled.
  /// When false, behaves like a normal [Hero].
  final bool enabled;

  /// Threshold in logical pixels below which positions are
  /// considered identical.
  static const double _positionThreshold = 2.0;

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: tag,
      createRectTween:
          createRectTween ?? (begin, end) => RectTween(begin: begin, end: end),
      flightShuttleBuilder: enabled ? _flightShuttleBuilder : null,
      placeholderBuilder: enabled ? _placeholderBuilder : null,
      child: child,
    );
  }

  Widget _flightShuttleBuilder(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final fromBox = fromHeroContext.findRenderObject() as RenderBox;
    final toBox = toHeroContext.findRenderObject() as RenderBox;
    final fromPos = fromBox.localToGlobal(Offset.zero);
    final toPos = toBox.localToGlobal(Offset.zero);

    final samePosition = (fromPos - toPos).distance < _positionThreshold &&
        (fromBox.size.width - toBox.size.width).abs() < _positionThreshold &&
        (fromBox.size.height - toBox.size.height).abs() < _positionThreshold;

    if (samePosition) {
      // Same position — hide shuttle so it doesn't overlay shadows.
      return const SizedBox.shrink();
    }

    // Normal flight — show destination widget.
    return direction == HeroFlightDirection.push
        ? toHeroContext.widget
        : fromHeroContext.widget;
  }

  static Widget _placeholderBuilder(
    BuildContext context,
    Size heroSize,
    Widget child,
  ) {
    // Keep the child visible in both routes during flight so the
    // image doesn't disappear when the shuttle is hidden.
    return child;
  }
}
