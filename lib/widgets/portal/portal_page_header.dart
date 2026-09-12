import 'package:flutter/material.dart';

import 'portal_density.dart';

/// The portals' page header: an eyebrow, a title in the display face, an
/// optional subtitle, actions, and a slot beneath for tabs or filters.
///
/// This is the station-owner side's answer to `WebPageHeader`
/// (lib/widgets/web_page_header.dart), which can't be reused directly because
/// it reads the website's own palette. The shape is deliberately the same, so
/// a station owner moving between the public site and their portal sees one
/// product. Admin keeps its navy band in `AdminPageHeader`.
///
/// Colours come from the theme, so it inverts with dark mode on both portals.
class PortalPageHeader extends StatelessWidget {
  const PortalPageHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.actions = const [],
    this.bottom,
    this.leading,
    this.showBack,
  });

  final String title;

  /// Small caps above the title -- the section this page belongs to.
  final String? eyebrow;

  final String? subtitle;
  final List<Widget> actions;

  /// Tabs, a filter bar, or anything that belongs to the header rather than
  /// the page body.
  final Widget? bottom;

  final Widget? leading;

  /// Defaults to "whatever this route can do" -- a pushed screen gets a back
  /// button, a tab page doesn't.
  final bool? showBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final density = PortalDensity.of(context);
    final canPop = showBack ?? (ModalRoute.of(context)?.canPop ?? false);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        border: Border(bottom: BorderSide(color: scheme.outline.withValues(alpha: 0.5))),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: density.headerPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (canPop)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back),
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                  if (leading != null) Padding(padding: const EdgeInsets.only(right: 12), child: leading!),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (eyebrow != null) ...[
                          Text(
                            eyebrow!.toUpperCase(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.secondary,
                              letterSpacing: 1.6,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                        Text(title, style: theme.textTheme.headlineSmall),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle!,
                            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (actions.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    // Wraps rather than overflows once the system font size is
                    // turned up on a narrow phone.
                    Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: actions),
                  ],
                ],
              ),
              if (bottom != null) ...[SizedBox(height: density.isWide ? 18 : 12), bottom!],
            ],
          ),
        ),
      ),
    );
  }
}
