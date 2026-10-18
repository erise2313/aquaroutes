import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Opens another website page from a button inside a page, the same way the
/// nav bar and footer do: by URL where the site's router is present, so the
/// address bar changes and the browser's back button returns here.
///
/// Pushing the page instead left it on top with no back button (the site's
/// page header has none), an unchanged address, and a browser back that left
/// the site -- from "Log in" on the news page there was no way back at all.
/// [fallback] is pushed in the builds without a router (the app reuses some
/// of these screens).
void openWebPage(BuildContext context, String path, Widget fallback) {
  if (GoRouter.maybeOf(context) != null) {
    context.go(path);
    return;
  }
  Navigator.push(context, webPageRoute(fallback));
}

/// Shared page transition for website navigation (nav bar + footer links,
/// plus every internal CTA between web screens) -- the incoming page fades,
/// slides up, and scales in slightly while the outgoing page fades out
/// underneath it, so switching pages reads as a real crossfade rather than
/// new content just appearing over a static background. Falls back to an
/// instant cut when the OS "reduce motion" setting is on.
Route<T> webPageRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.of(context).disableAnimations) return child;
      final enter = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      final exit = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeInCubic);
      return FadeTransition(
        opacity: Tween<double>(begin: 0, end: 1).animate(enter),
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(enter),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1.0).animate(enter),
            child: FadeTransition(
              opacity: Tween<double>(begin: 1.0, end: 0.0).animate(exit),
              child: child,
            ),
          ),
        ),
      );
    },
  );
}
