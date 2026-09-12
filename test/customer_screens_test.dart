import 'package:aquaroute/constants/app_colors.dart';
import 'package:aquaroute/constants/app_theme.dart';
import 'package:aquaroute/models/order.dart';
import 'package:aquaroute/models/order_status_look.dart';
import 'package:aquaroute/widgets/portal/portal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The customer screens read Supabase in initState and can't be mounted, so
/// their geometry is covered as compositions -- the same approach that caught
/// three real overflow bugs in the portals. These are the shapes the restyle
/// introduced: an order card whose amount cannot wrap, a login gate whose
/// buttons now stack, and a status pill on its own line.
final _themes = <String, ThemeData>{
  'light': AppTheme.light,
  'dark': AppTheme.dark,
};

Future<void> _pump(
  WidgetTester tester,
  ThemeData theme,
  Widget child, {
  required Size size,
  required double textScale,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    key: ValueKey('customer-${identityHashCode(theme)}'),
    theme: theme,
    home: MediaQuery(
      data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Mirrors my_orders_screen and track_order_screen, which build the same card
/// from the same shared mapping.
Widget _orderCard() => Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final look = OrderStatusLook.of(OrderStatus.active);
        return PortalCard(
          accent: look.color,
          onTap: () {},
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Buenavista Water Refilling Station', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              StatusPill(label: look.label, color: look.color),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text('3 × Slim 5-gal refill · Purified', style: theme.textTheme.bodyMedium),
                  ),
                  const SizedBox(width: 12),
                  // A peso amount has no space to wrap at.
                  Text('₱1,240.00', style: theme.textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 4),
              Text('Placed Sep 12, 2026 10:45 AM', style: theme.textTheme.bodySmall),
            ],
          ),
        );
      },
    );

Widget _loginGate() => PortalEmptyState(
      icon: Icons.local_shipping_outlined,
      title: 'Sign in to place an order',
      message: 'Browsing the bulletin board and the station map never needs an account -- only ordering does.',
      action: PortalActionRow(
        children: [
          FilledButton(onPressed: () {}, child: const Text('Sign in')),
          OutlinedButton(onPressed: () {}, child: const Text('Create account')),
        ],
      ),
    );

Widget _priceSummary() => Builder(
      builder: (context) {
        Widget line(String label, String value, {bool bold = false}) {
          final style = bold ? const TextStyle(fontWeight: FontWeight.bold) : null;
          return Row(
            children: [
              Expanded(child: Text(label, style: style)),
              Text(value, style: style),
            ],
          );
        }

        return Container(
          padding: const EdgeInsets.all(12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Column(
            children: [
              line('3 × Slim 5-gal refill', '₱75.00'),
              const SizedBox(height: 4),
              line('Delivery', '₱15.00'),
              const Divider(height: 16),
              line('Total due on delivery', '₱90.00', bold: true),
            ],
          ),
        );
      },
    );

Widget _notice() => const StatusCallout(
      accent: AppColors.flagged,
      icon: Icons.warning_amber_rounded,
      title: 'This station is currently closed and not accepting orders. Please pick another station.',
    );

void main() {
  group('customer screen compositions', () {
    final pieces = <String, Widget Function()>{
      'order card': _orderCard,
      'login gate': _loginGate,
      'price summary': _priceSummary,
      'notice': _notice,
    };

    testWidgets('lay out without overflow across widths, text sizes and modes', (tester) async {
      for (final piece in pieces.entries) {
        for (final theme in _themes.entries) {
          for (final width in [360.0, 768.0, 1280.0]) {
            for (final scale in [1.0, 1.3, 2.0]) {
              await _pump(
                tester,
                theme.value,
                piece.value(),
                size: Size(width, 900),
                textScale: scale,
              );
              expect(
                tester.takeException(),
                isNull,
                reason: '${piece.key} on ${theme.key} at ${width}px, text scale $scale',
              );
            }
          }
        }
      }
    });

    testWidgets('the order card shows the shared status wording', (tester) async {
      await _pump(tester, AppTheme.light, _orderCard(), size: const Size(390, 844), textScale: 1.0);

      expect(find.text('OUT FOR DELIVERY'), findsOneWidget);
      expect(find.text('₱1,240.00'), findsOneWidget);
    });
  });
}
