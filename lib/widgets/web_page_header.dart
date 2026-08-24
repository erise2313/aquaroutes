import 'package:flutter/material.dart';

import '../constants/web_theme.dart';
import 'wave_divider.dart';

/// Consistent header band for every interior website page (About, How It
/// Works, For Owners, FAQ, Verify, Jug Clearinghouse, Resources, Events,
/// Contact, Stations Directory) -- signals "you're in a content page" the
/// same way every time, wave-transitioning into the paper body below,
/// instead of every page inventing its own plain top-of-page title.
class WebPageHeader extends StatelessWidget {
  const WebPageHeader({super.key, required this.title, this.subtitle, this.eyebrow});

  final String title;
  final String? subtitle;
  final String? eyebrow;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: WebTheme.foam,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (eyebrow != null) ...[
                    Text(eyebrow!, style: WebTheme.eyebrow),
                    const SizedBox(height: 10),
                  ],
                  Text(title, style: WebTheme.display(fontSize: 32)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 10),
                    Text(subtitle!, style: const TextStyle(fontSize: 16, height: 1.5, color: WebTheme.inkNavy)),
                  ],
                ],
              ),
            ),
          ),
        ),
        const WaveDivider(topColor: WebTheme.foam, bottomColor: WebTheme.paper, height: 32),
      ],
    );
  }
}
