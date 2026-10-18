import 'package:flutter/painting.dart';

/// The product's one typeface: Atkinson Hyperlegible, bundled in
/// assets/fonts (see pubspec.yaml).
///
/// It replaced Fraunces for headings and the system sans for body text. Most
/// of the people who must succeed with GenTri WASA -- station owners and
/// WASA officers -- are older readers; Atkinson was designed by the Braille
/// Institute for low-vision readers and gives look-alike characters (l, 1, I;
/// 0, O) distinct shapes, which matters for order numbers, plates and phone
/// numbers. Only Regular and Bold exist, so lighter or in-between weights are
/// never asked for.
class BrandFonts {
  BrandFonts._();

  static const String family = 'AtkinsonHyperlegible';

  /// Headings and display numbers. Same named parameters the former
  /// Fraunces helper took, so call sites read the same. Any weight of 600
  /// or more renders Bold; anything lighter renders Regular.
  static TextStyle display({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
  }) {
    final bold = (fontWeight ?? FontWeight.w700).index >= FontWeight.w600.index;
    return TextStyle(
      fontFamily: family,
      fontSize: fontSize,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      color: color,
      height: height,
    );
  }
}
