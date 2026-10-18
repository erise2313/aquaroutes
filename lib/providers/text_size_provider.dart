import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The in-app text size, applied on top of the phone's (or browser's) own
/// text size -- never instead of it.
///
/// Many older users never find the system setting, so the app offers one of
/// its own in Account settings. It multiplies rather than replaces: someone
/// who already set their phone to large text and picks Large here gets both.
enum AppTextSize {
  normal(1.0, 'Normal'),
  large(1.15, 'Large'),
  extraLarge(1.3, 'Extra large');

  const AppTextSize(this.factor, this.label);

  final double factor;
  final String label;
}

const _prefsKey = 'app_text_size';

class TextSizeNotifier extends Notifier<AppTextSize> {
  @override
  AppTextSize build() {
    _restore();
    return AppTextSize.normal;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefsKey);
      for (final size in AppTextSize.values) {
        if (size.name == stored) state = size;
      }
    } catch (_) {
      // Storage unavailable: Normal for this session.
    }
  }

  Future<void> set(AppTextSize size) async {
    state = size;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, size.name);
    } catch (_) {
      // Applies for this session; just isn't remembered.
    }
  }
}

final textSizeProvider = NotifierProvider<TextSizeNotifier, AppTextSize>(TextSizeNotifier.new);

/// Wraps [child] so every text below it is scaled by [size] on top of the
/// system text scale. Used as MaterialApp's builder.
class AppTextScale extends ConsumerWidget {
  const AppTextScale({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = ref.watch(textSizeProvider);
    if (size == AppTextSize.normal) return child;
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(textScaler: _MultipliedScaler(media.textScaler, size.factor)),
      child: child,
    );
  }
}

/// The system scaler (which on Android 14+ is non-linear) followed by a
/// fixed factor, so the in-app choice keeps the system's shape.
class _MultipliedScaler extends TextScaler {
  const _MultipliedScaler(this.base, this.factor);

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => base.textScaleFactor * factor;

  @override
  bool operator ==(Object other) => other is _MultipliedScaler && other.base == base && other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}
