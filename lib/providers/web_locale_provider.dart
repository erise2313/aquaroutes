import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Language for the public website's nav/headings/key copy (screens/web/*).
/// Deliberately scoped to just the website, not the whole app -- the
/// mobile portals aren't touched by this.
enum WebLocale { en, tl }

class WebLocaleNotifier extends Notifier<WebLocale> {
  @override
  WebLocale build() => WebLocale.en;

  void toggle() => state = state == WebLocale.en ? WebLocale.tl : WebLocale.en;
}

final webLocaleProvider = NotifierProvider<WebLocaleNotifier, WebLocale>(WebLocaleNotifier.new);
