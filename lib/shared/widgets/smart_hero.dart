import 'package:flutter/material.dart';
import 'package:heroine/heroine.dart';

/// A [Heroine] wrapper that automatically skips the flight when the source
/// and destination positions are identical (or nearly so).
///
/// During a flight, the widget is lifted into the navigator's overlay, which
/// renders it above all other content (including shadows and other visual
/// effects). When start and end positions are the same this overlay serves
/// no visual purpose but can cause visual artifacts — [SmartHero] detects
/// this case via [Heroine.shouldTransition] and skips the flight entirely,
/// so both children simply stay in place.
///
/// Using [Heroine] (instead of a plain [Hero]) also means these transitions
/// share one flight system with the layer heroes: stacking is controlled via
/// [zIndex] (e.g. text layers above the image), and motion is consistently
/// spring-driven.
class SmartHero extends StatelessWidget {
  /// Creates a [SmartHero] that skips no-op hero flights.
  const SmartHero({
    super.key,
    required this.tag,
    required this.child,
    this.motion,
    this.zIndex,
    this.enabled = true,
    this.positionThreshold = 1.0,
  });

  /// Threshold in logical pixels below which the source and destination
  /// positions are considered identical and the flight is skipped.
  ///
  /// Keep it above zero: transform measurements (sub-editor scaling,
  /// letterbox math) carry sub-pixel float noise, and a zero threshold would
  /// lift a visually motionless flight into the overlay. Anything below the
  /// threshold snaps instead of animating, so keep it small enough to stay
  /// imperceptible.
  final double positionThreshold;

  /// The hero tag.
  final Object tag;

  /// The child widget.
  final Widget child;

  /// The motion for flights towards this hero. Defaults to a smooth spring.
  final Motion? motion;

  /// Overlay stacking order among simultaneous heroine flights — higher
  /// values render above lower ones (e.g. text layers above the image).
  final int? zIndex;

  /// Whether the no-op suppression is enabled.
  /// When false, behaves like a normal [Heroine] (always flies).
  final bool enabled;

  bool _shouldTransition(HeroineTransitionDetails details) {
    if (!enabled) return true;
    final from = details.fromLocation?.boundingBox;
    final to = details.toLocation?.boundingBox;
    // Without measurements there is nothing to compare — fly normally.
    if (from == null || to == null) return true;
    return (from.center - to.center).distance >= positionThreshold ||
        (from.width - to.width).abs() >= positionThreshold ||
        (from.height - to.height).abs() >= positionThreshold;
  }

  @override
  Widget build(BuildContext context) {
    return Heroine(
      tag: tag,
      motion: motion ?? const CupertinoMotion.smooth(snapToEnd: true),
      zIndex: zIndex,
      shouldTransition: _shouldTransition,
      child: child,
    );
  }
}
