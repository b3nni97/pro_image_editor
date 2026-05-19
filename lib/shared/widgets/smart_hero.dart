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
class SmartHero extends StatefulWidget {
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

  /// Tags currently in an active (non-suppressed) hero flight.
  /// Shared between source and destination hero instances so both
  /// placeholderBuilders can hide their children during real flights.
  static final Set<Object> _flyingTags = {};

  @override
  State<SmartHero> createState() => _SmartHeroState();
}

class _SmartHeroState extends State<SmartHero> {
  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: widget.tag,
      createRectTween:
          widget.createRectTween ??
          (begin, end) => RectTween(begin: begin, end: end),
      flightShuttleBuilder:
          widget.enabled ? _flightShuttleBuilder : null,
      placeholderBuilder:
          widget.enabled ? _placeholderBuilder : null,
      child: widget.child,
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

    final samePosition =
        (fromPos - toPos).distance < SmartHero._positionThreshold &&
        (fromBox.size.width - toBox.size.width).abs() <
            SmartHero._positionThreshold &&
        (fromBox.size.height - toBox.size.height).abs() <
            SmartHero._positionThreshold;

    if (samePosition) {
      SmartHero._flyingTags.remove(widget.tag);
      // Same position — hide shuttle so it doesn't overlay shadows.
      return const SizedBox.shrink();
    }

    // Mark this tag as actively flying so BOTH source and destination
    // placeholderBuilders hide their children.
    SmartHero._flyingTags.add(widget.tag);

    // Clean up when the flight animation completes.
    void statusListener(AnimationStatus status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        SmartHero._flyingTags.remove(widget.tag);
        animation.removeStatusListener(statusListener);
      }
    }
    animation.addStatusListener(statusListener);

    // Normal flight — show destination widget's content.
    final toHero = toHeroContext.widget as Hero;
    final fromHero = fromHeroContext.widget as Hero;
    return direction == HeroFlightDirection.push
        ? toHero.child
        : fromHero.child;
  }

  Widget _placeholderBuilder(
    BuildContext context,
    Size heroSize,
    Widget child,
  ) {
    if (SmartHero._flyingTags.contains(widget.tag)) {
      // Real flight in progress — hide the original so it doesn't
      // show as a "ghost" behind the flying shuttle.
      return SizedBox(width: heroSize.width, height: heroSize.height);
    }
    // Suppressed flight — keep the child visible in-place so the
    // image doesn't disappear when the shuttle is hidden.
    return child;
  }
}
