import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'brand_theme.dart';
import 'brand_tokens.dart';

/// Theme for the in-app portals: merchant (station owner), customer and
/// driver.
///
/// The component styling now comes from [BrandTheme], which the website and
/// admin portal share -- this class only decides which palette extensions
/// ride along (the app's surfaces plus the driver portal's own palette).
///
/// **Both modes, chosen by the phone.** The mode comes from the phone
/// (providers/app_theme_provider.dart, with a Light/Dark/Follow-phone
/// override in Account settings) and every surface colour comes from
/// [AppPalette], so both modes are designed rather than one being an
/// accident.
///
/// Applied by wrapping the shells (MerchantNavigation, PublicHomeScreen) and
/// by `appRoute()` (screens/app_route.dart) for pushed screens, which do not
/// inherit a local Theme.
class AppTheme {
  AppTheme._();

  /// One radius for the whole product (see [BrandRadius]).
  static const double radius = BrandRadius.card;
  static const double radiusSmall = BrandRadius.control;

  static ThemeData get light => themeFor(Brightness.light);
  static ThemeData get dark => themeFor(Brightness.dark);

  static ThemeData themeFor(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return BrandTheme.build(
      brightness,
      extensions: [
        isDark ? AppPalette.dark : AppPalette.light,
        isDark ? DriverPalette.dark : DriverPalette.light,
      ],
    );
  }
}
