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
      flightShuttleBuilder: const _LandingMatchedFadeShuttleBuilder(),
      child: child,
    );
  }
}

/// Cross-fade shuttle whose destination side renders exactly like heroine's
/// in-tree landing.
///
/// The default [FadeShuttleBuilder] lays both hero children out INTO the
/// animated flight box, so letterboxed content (the editor image) re-fits
/// itself per frame with aspect-preserving gaps. The landing, however, lays
/// the destination child out at its real in-tree size and stretches it
/// per-axis to the remaining flight box. At the route-completion handoff the
/// flight box still trails the target by the spring's remaining delta — the
/// two rendering strategies then disagree by exactly that delta (a visible
/// few-pixel snap at the end of every editor-switch flight).
///
/// This builder renders the destination child the same way the landing does
/// (laid out at its measured in-tree size, [BoxFit.fill]-stretched into the
/// flight box), making the overlay→landing handoff pixel-identical. The
/// source side keeps the default into-box layout: it matches the in-tree
/// rendering at flight start (the box starts at the source rect) and its
/// letterbox re-fitting gives the nicer mid-flight morph while it fades out.
class _LandingMatchedFadeShuttleBuilder extends HeroineShuttleBuilder {
  const _LandingMatchedFadeShuttleBuilder();

  @override
  List<Object?> get props => [];

  @override
  Widget call(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    Widget heroChild(BuildContext heroContext) => InheritedTheme.captureAll(
          heroContext,
          (heroContext.widget as Heroine).child,
        );

    Widget fromSide() => fromHeroContext.mounted
        ? heroChild(fromHeroContext)
        : const SizedBox.shrink();

    Widget toSide() {
      if (!toHeroContext.mounted) return const SizedBox.shrink();
      final box = toHeroContext.findRenderObject();
      if (box is! RenderBox ||
          !box.hasSize ||
          box.size.isEmpty ||
          !box.size.isFinite) {
        // No measurement available — fall back to the default into-box
        // layout rather than showing nothing.
        return heroChild(toHeroContext);
      }
      return FittedBox(
        fit: BoxFit.fill,
        clipBehavior: Clip.none,
        child: SizedBox.fromSize(
          size: box.size,
          child: heroChild(toHeroContext),
        ),
      );
    }

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final value = flightDirection == HeroFlightDirection.push
            ? animation.value
            : 1 - animation.value;
        final v = value.clamp(0.0, 1.0);
        // Staggered opacities instead of a plain cross-fade: the
        // destination is fully opaque after 40% and the source only starts
        // fading at 60%, so the combined coverage never dips below full —
        // a linear cross-fade of the (identical) image content blends to
        // ~75% alpha mid-flight and visibly darkens towards the background.
        final fadeIn = (v / 0.4).clamp(0.0, 1.0);
        final fadeOut = ((1 - v) / 0.4).clamp(0.0, 1.0);
        return Stack(
          fit: StackFit.expand,
          children: [
            if (fadeOut > 0) Opacity(opacity: fadeOut, child: fromSide()),
            if (fadeIn > 0) Opacity(opacity: fadeIn, child: toSide()),
          ],
        );
      },
    );
  }
}
