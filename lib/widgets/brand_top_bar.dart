import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'wasa_shield_logo.dart';

/// One link in the bar: its label, whether it's the page you're on, and what
/// to do about it. Deliberately not tied to a route type -- the website
/// navigates by URL, the portals by tab index, and the admin build has no
/// router at all.
class BrandNavLink {
  const BrandNavLink({required this.label, required this.isActive, required this.onTap});

  final String label;
  final bool isActive;
  final VoidCallback onTap;
}

/// What the bar worked out about the space it has, handed to the caller so
/// the trailing actions can respond to it.
///
/// The website's cluster genuinely depends on all three: [compact] tightens
/// the locale toggle and drops the separator rule, and [hasRoomForPrimary]
/// decides whether the primary button survives once the links have collapsed.
/// Passing a fixed list of widgets instead would silently lose that.
class BrandBarLayout {
  const BrandBarLayout({required this.compact, required this.isWide, required this.hasRoomForPrimary});

  /// Below ~700px: no room for a separator rule plus its margins.
  final bool compact;

  /// The full link row fits, so it's shown instead of the menu button.
  final bool isWide;

  /// Enough room for the one primary action even if the links collapsed.
  final bool hasRoomForPrimary;
}

/// The association's top bar: brand mark, a row of links that collapses to a
/// menu when it stops fitting, and a caller-supplied trailing cluster.
///
/// Extracted from the public website's nav bar so the station-owner and admin
/// portals can wear the same header instead of a Material NavigationRail --
/// the single biggest reason the three surfaces read as different products.
///
/// Colours are parameters rather than read from a theme on purpose. The
/// website's own palette is a ThemeExtension that only its ThemeData
/// registers, and `WebTheme.of` falls back to the *light* palette wherever it
/// isn't -- so a bar that read it directly would paint light paper with navy
/// ink inside the owner portal's dark mode, and a light strip above admin's
/// navy band.
class BrandTopBar extends StatelessWidget implements PreferredSizeWidget {
  const BrandTopBar({
    super.key,
    required this.links,
    required this.actionsBuilder,
    required this.actionsWidth,
    required this.onBrandTap,
    required this.background,
    required this.foreground,
    required this.borderColor,
    required this.activeColor,
    required this.underlineColor,
    this.menuTooltip = 'Open menu',
  });

  final List<BrandNavLink> links;

  /// Built with the layout the bar computed, so the cluster can tighten
  /// itself the same way the links do.
  final List<Widget> Function(BuildContext context, BrandBarLayout layout) actionsBuilder;

  /// How much room the trailing cluster needs, measured by the caller with
  /// [measureText]. The bar can't measure arbitrary widgets, and guessing is
  /// precisely what used to clip "For Station Owners" and drop the last three
  /// links off the row.
  final double actionsWidth;

  final VoidCallback onBrandTap;

  final Color background;

  /// Wordmark, link labels and icons.
  final Color foreground;

  final Color borderColor;

  /// The active link's label.
  final Color activeColor;

  /// The rule under the active link -- the association's gold on every
  /// surface, which is what makes "you are here" read the same way
  /// throughout.
  final Color underlineColor;

  final String menuTooltip;

  /// Taller than Material's default 56/64 on purpose: this is an association
  /// product whose users skew older, and the extra height buys real breathing
  /// room around the brand mark and a full-size primary button.
  @override
  Size get preferredSize => const Size.fromHeight(80);

  /// Wider than the 1100 column the page sections below use. Matching that
  /// column exactly looked tidy but left only ~600px for seven nav links.
  static const double maxContentWidth = 1500;
  static const double gutter = 24;

  /// The same TextPainter measurement the bar uses internally, exposed so a
  /// caller sizes its actions on the same basis rather than by eye.
  static double measureText(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  /// Width the full link row needs, from the labels actually being rendered.
  /// A fixed pixel breakpoint can't work: the Tagalog labels run far wider
  /// than the English ones, so any threshold tuned for one locale clips the
  /// other. Measured at the bold weight so the row doesn't resize when the
  /// active page changes.
  static double measureLinks(List<BrandNavLink> links) {
    const style = TextStyle(fontSize: 14, fontWeight: FontWeight.w700);
    var total = 0.0;
    for (final link in links) {
      total += measureText(link.label, style) + 24; // button padding + margin
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: background,
        border: Border(bottom: BorderSide(color: borderColor, width: 1)),
      ),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxContentWidth),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: gutter),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Everything that isn't the link row, measured the same way,
                  // so the decision below is "do the links actually fit?"
                  // rather than a guess.
                  final brandWidth = 32 +
                      10 +
                      measureText('GENTRI WASA', GoogleFonts.fraunces(fontSize: 19, fontWeight: FontWeight.w600)) +
                      12;

                  final isWide = constraints.maxWidth >= brandWidth + 20 + measureLinks(links) + actionsWidth + 16;
                  final hasRoomForPrimary = isWide || constraints.maxWidth >= brandWidth + 48 + actionsWidth + 24;
                  final compact = constraints.maxWidth < 700;
                  final layout = BrandBarLayout(compact: compact, isWide: isWide, hasRoomForPrimary: hasRoomForPrimary);

                  return Row(
                    children: [
                      // Bounded rather than Flexible: as a flex child the
                      // brand claimed an equal share of the row's free space
                      // and then used only part of it, and Row leaves that
                      // unused remainder at the *end* -- which is the dead
                      // space that used to show up to the right of the primary
                      // button. Capping it keeps the wordmark able to
                      // ellipsize without hoarding slack that belongs to the
                      // link row.
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.45),
                        child: InkWell(
                          onTap: onBrandTap,
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            // Vertical only: a horizontal inset here would
                            // push the shield off the content column the
                            // headline below starts on.
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Self-coloured (its own gradient and a white
                                // drop), so it reads on warm paper and on
                                // admin's navy alike.
                                const WasaShieldLogo(size: 32),
                                // Below ~420px the wordmark would ellipsize to
                                // a couple of letters anyway; the shield alone
                                // reads better and gives the row back ~110px.
                                if (constraints.maxWidth >= 420) ...[
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: Text(
                                      'GENTRI WASA',
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.fraunces(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 19,
                                        color: foreground,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: compact ? 6 : 20),
                      if (isWide)
                        // Centred inside the slack rather than left-aligned:
                        // hugging the logo left every bit of leftover width in
                        // one pocket next to the actions, which is what made
                        // the bar look lopsided on wide screens.
                        Expanded(
                          child: Center(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: links
                                    .map((l) => _BrandNavLinkView(
                                          link: l,
                                          idleColor: foreground,
                                          activeColor: activeColor,
                                          underlineColor: underlineColor,
                                        ))
                                    .toList(),
                              ),
                            ),
                          ),
                        )
                      else
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: PopupMenuButton<int>(
                              icon: Icon(Icons.menu, color: foreground),
                              tooltip: menuTooltip,
                              onSelected: (i) => links[i].onTap(),
                              itemBuilder: (context) => [
                                for (var i = 0; i < links.length; i++)
                                  PopupMenuItem(value: i, child: Text(links[i].label)),
                              ],
                            ),
                          ),
                        ),
                      ...actionsBuilder(context, layout),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandNavLinkView extends StatefulWidget {
  const _BrandNavLinkView({
    required this.link,
    required this.idleColor,
    required this.activeColor,
    required this.underlineColor,
  });

  final BrandNavLink link;
  final Color idleColor;
  final Color activeColor;
  final Color underlineColor;

  @override
  State<_BrandNavLinkView> createState() => _BrandNavLinkViewState();
}

class _BrandNavLinkViewState extends State<_BrandNavLinkView> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.link.isActive
        ? widget.activeColor
        : (_hovering ? widget.activeColor.withValues(alpha: 0.7) : widget.idleColor);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: TextButton(
          onPressed: widget.link.onTap,
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 150),
                style: TextStyle(
                  color: color,
                  fontWeight: widget.link.isActive ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 14,
                ),
                child: Text(widget.link.label),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 2.5,
                width: widget.link.isActive ? 22 : 0,
                decoration: BoxDecoration(color: widget.underlineColor, borderRadius: BorderRadius.circular(1)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
