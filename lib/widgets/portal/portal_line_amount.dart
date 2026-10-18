import 'package:flutter/material.dart';

/// An order line with its peso amount: side by side when both fit, the
/// amount dropping under the line when they don't.
///
/// The cards used a Row with the line Expanded and the amount fixed, and a
/// peso amount has nowhere to wrap -- so once body text went to 18 and a
/// reader raised their phone's text size, the amount ran off the card on a
/// narrow phone. A Wrap keeps the usual layout and only breaks the line when
/// it must.
class PortalLineAmount extends StatelessWidget {
  const PortalLineAmount({super.key, required this.line, required this.amount});

  /// Usually the order line text; wraps within the card's width.
  final Widget line;

  /// The amount; never wraps, so it takes its own line when it must.
  final Widget amount;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 12,
      runSpacing: 4,
      children: [line, amount],
    );
  }
}
