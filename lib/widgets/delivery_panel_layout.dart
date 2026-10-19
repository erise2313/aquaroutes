import 'package:flutter/material.dart';

/// The driver's active-delivery screen: map, delivery details, and the
/// START / COMPLETE / COULDN'T DELIVER buttons.
///
/// The details scroll and the buttons stay pinned above the system bar, so
/// on any phone size or text size the delivery can always be started and
/// completed. The card used to be a fixed share of the screen with a
/// Spacer, and on a smaller phone or with larger text NAVIGATE, START and
/// COMPLETE fell off the bottom.
class DeliveryPanelLayout extends StatelessWidget {
  const DeliveryPanelLayout({
    super.key,
    required this.map,
    required this.details,
    required this.actions,
    required this.background,
  });

  final Widget map;
  final Widget details;
  final Widget actions;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final card = Container(
          color: background,
          child: LayoutBuilder(
            builder: (context, card) => Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: details,
                  ),
                ),
                SafeArea(
                  top: false,
                  // Normally the buttons fit and sit still. Only on a very
                  // short screen (a landscape phone at the largest text) do
                  // they take at most 70% of the card and scroll themselves.
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: card.maxHeight * 0.7),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      child: actions,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        if (constraints.maxWidth > constraints.maxHeight) {
          return Row(
            children: [
              Expanded(child: map),
              Expanded(child: card),
            ],
          );
        }
        // A bounded share for the map so the details always get room.
        final mapHeight = (constraints.maxHeight * 0.36).clamp(120.0, 340.0);
        return Column(
          children: [
            SizedBox(height: mapHeight, child: map),
            Expanded(child: card),
          ],
        );
      },
    );
  }
}
