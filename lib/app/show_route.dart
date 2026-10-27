import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'sfx.dart';

/// A full-screen route that grows out of a card.
///
/// The page is laid out at full size from the first frame and clipped to a
/// rect that travels from [from] (the tapped card, in global coordinates) to
/// the whole screen, rounding off its corners as it goes. A 3D view inside
/// renders through the whole move, so the card becomes the window. Popping
/// runs the same move in reverse, and as the window settles back onto the
/// card the live view dissolves away, revealing the card's still beneath it
/// in the same spot.
class CardRevealRoute<T> extends PageRoute<T> {
  CardRevealRoute({required this.from, required this.builder, this.fromKey, this.fromRadius = 18, super.settings});

  final Rect from;

  /// The card itself, so the window tracks wherever it is now (the list may
  /// have moved while the route was open). Falls back to [from].
  final GlobalKey? fromKey;
  final double fromRadius;
  final WidgetBuilder builder;

  static const curve = Cubic(0.2, 0.0, 0.0, 1.0);

  @override
  TickerFuture didPush() {
    Sfx.sound('open');
    return super.didPush();
  }

  @override
  bool didPop(T? result) {
    Sfx.sound('dissolve');
    return super.didPop(result);
  }

  @override
  Duration get transitionDuration => const Duration(milliseconds: 1150);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 1150);

  /// Closing, the share of the reverse animation (at its end) spent fading
  /// the landed window into the card's still; the rest is the shrink.
  static const _fade = 0.3;

  @override
  bool get opaque => false;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) => builder(context);

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final full = Offset.zero & constraints.biggest;
        return AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, child) {
            // Opening, the window grows out of the card. Closing, it shrinks
            // back fully opaque, settling onto the card, and only once it
            // has landed does it fade into the card's still.
            final closing = animation.status == AnimationStatus.reverse;
            final double t;
            final double opacity;
            if (closing) {
              final shrink = ((animation.value - _fade) / (1 - _fade)).clamp(0.0, 1.0);
              t = 1 - Curves.easeInOutCubic.transform(1 - shrink);
              opacity = Curves.easeInOut.transform((animation.value / _fade).clamp(0.0, 1.0));
            } else {
              t = curve.transform(animation.value);
              opacity = 1;
            }
            final card = (fromKey == null ? null : visibleRectOf(fromKey!)) ?? from;
            final rect = Rect.lerp(card, full, t)!;
            final radius = lerpDouble(fromRadius, 0, Curves.easeIn.transform(t))!;
            return Stack(
              children: [
                // Dim the screen behind as the window opens.
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(color: Colors.black.withValues(alpha: 0.6 * t)),
                  ),
                ),
                Positioned.fromRect(
                  rect: rect,
                  child: Opacity(
                    opacity: opacity,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(radius),
                      child: OverflowBox(
                        alignment: Alignment.center,
                        minWidth: full.width,
                        maxWidth: full.width,
                        minHeight: full.height,
                        maxHeight: full.height,
                        child: child,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// The rect of the widget behind [key], in global coordinates.
Rect? globalRectOf(GlobalKey key) {
  final box = key.currentContext?.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// The part of the widget behind [key] that is on screen, in global
/// coordinates: its rect cut to the scroll view it sits in, if any.
Rect? visibleRectOf(GlobalKey key) {
  final rect = globalRectOf(key);
  final context = key.currentContext;
  if (rect == null || context == null) return rect;
  final viewport = Scrollable.maybeOf(context)?.context.findRenderObject() as RenderBox?;
  if (viewport == null || !viewport.hasSize) return rect;
  final clip = viewport.localToGlobal(Offset.zero) & viewport.size;
  final cut = rect.intersect(clip);
  return cut.width > 4 && cut.height > 4 ? cut : rect;
}
