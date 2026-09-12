import 'package:flutter/material.dart';

/// One place that decides "phone or desk" for the station-owner and admin
/// portals, so "denser on phone" is a single decision rather than a guess
/// repeated on every screen.
///
/// Prefer [forWidth] inside a `LayoutBuilder`: the owner portal runs inside
/// ResponsiveNavShell, whose content column is narrower than the window once
/// the navigation rail appears, so the window width is the wrong question.
class PortalDensity {
  const PortalDensity._(this.width);

  /// Matches ResponsiveNavShell's own breakpoint, so the layout doesn't
  /// change shape at two different widths.
  static const wideBreakpoint = 800.0;

  final double width;

  factory PortalDensity.forWidth(double width) = PortalDensity._;

  factory PortalDensity.of(BuildContext context) => PortalDensity._(MediaQuery.sizeOf(context).width);

  bool get isWide => width >= wideBreakpoint;

  /// Page margins: generous on a monitor, tight on a phone held one-handed.
  EdgeInsets get pagePadding => isWide
      ? const EdgeInsets.symmetric(horizontal: 28, vertical: 24)
      : const EdgeInsets.symmetric(horizontal: 16, vertical: 16);

  /// Padding inside the band of a page header.
  EdgeInsets get headerPadding => isWide
      ? const EdgeInsets.fromLTRB(28, 26, 28, 24)
      : const EdgeInsets.fromLTRB(16, 18, 16, 16);

  EdgeInsets get cardPadding => isWide ? const EdgeInsets.all(20) : const EdgeInsets.all(16);

  /// Space between cards in a row or grid.
  double get gap => isWide ? 16 : 10;

  /// Space between one section and the next.
  double get sectionGap => isWide ? 36 : 24;

  /// How many tiles fit across, given the smallest tile worth showing.
  int columnsFor(double minTileWidth) {
    final usable = width - pagePadding.horizontal;
    final count = ((usable + gap) / (minTileWidth + gap)).floor();
    return count < 1 ? 1 : count;
  }
}
