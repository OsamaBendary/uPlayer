import 'package:flutter/material.dart';

/// Shared by every artwork Hero in the app (library headers, player
/// screen artwork).
///
/// Flutter's default Hero flight shuttle builds the *destination* side's
/// widget for the whole animation. For artwork, the destination is often
/// a different `QueryArtworkWidget` query than whatever's already on
/// screen (e.g. PlayerScreen queries the specific tapped song's artwork,
/// which may not be the album's "representative" track already cached
/// from the list) — so the flight can end up visibly waiting on a fresh
/// decode instead of just... flying the photo that's already there.
///
/// This shuttle always rides on the FROM side's widget instead, which by
/// definition is already built, decoded, and on screen the instant the
/// flight starts (it's the widget being flown away from) — regardless of
/// whether this is a push or a pop. Once the flight lands, the
/// destination route's real widget tree takes over normally; if that
/// specific image wasn't cached, it pops in right after instead of
/// stalling the whole transition.
Widget artworkFlightShuttleBuilder(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
    ) {
  final fromHero = fromHeroContext.widget as Hero;
  return fromHero.child;
}