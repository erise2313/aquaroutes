import 'package:flutter/material.dart';

import '../constants/web_theme.dart';

/// The site's recurring trust motif -- a gold circular seal, used every
/// place the site communicates verification/accreditation (hero, stats
/// strip, verified station cards, the Verify Accreditation result, the
/// footer). One consistent glyph, not a different badge style per page.
class WebSeal extends StatelessWidget {
  const WebSeal({super.key, this.size = 32, this.outlined = false});

  final double size;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: outlined ? Colors.transparent : WebTheme.sealGold,
        border: outlined ? Border.all(color: WebTheme.sealGold, width: 1.5) : null,
      ),
      child: Icon(Icons.workspace_premium, color: outlined ? WebTheme.sealGold : Colors.white, size: size * 0.6),
    );
  }
}
