import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'order.dart';

/// How an order's state reads to a customer.
///
/// `my_orders_screen.dart` and `track_order_screen.dart` each carried their
/// own copy of this: the same five-arm switch over [OrderStatus] building the
/// same hand-rolled chip. Two copies of a mapping is two chances for the
/// same order to read differently depending on which screen you opened.
///
/// The colours are the product's status tokens rather than raw Material
/// swatches, so a pill here means the same thing as a pill in the owner
/// portal or admin.
class OrderStatusLook {
  const OrderStatusLook(this.label, this.color);

  /// Worded for a customer: what is happening to *their* order, not the
  /// database's state name.
  final String label;

  final Color color;

  /// Exhaustive over [OrderStatus] on purpose -- a switch expression with no
  /// default means adding a status is a compile error here rather than a
  /// silently mislabelled order on two screens.
  static OrderStatusLook of(OrderStatus status) => switch (status) {
        OrderStatus.pending => const OrderStatusLook('PENDING', AppColors.pendingClearance),
        OrderStatus.assigned => const OrderStatusLook('DRIVER ASSIGNED', AppColors.primary),
        OrderStatus.active => const OrderStatusLook('OUT FOR DELIVERY', AppColors.accent),
        OrderStatus.done => const OrderStatusLook('DELIVERED', AppColors.cleared),
        OrderStatus.cancelled => const OrderStatusLook('CANCELLED', AppColors.flagged),
      };

  /// Whether the customer can still call this order off. Mirrors what
  /// OrderService.cancelOrder actually allows, so the button only appears
  /// where it would succeed.
  static bool isCancellable(OrderStatus status) =>
      status == OrderStatus.pending || status == OrderStatus.assigned;

  /// Whether there is a driver to follow on a map.
  static bool isTrackable(OrderStatus status) =>
      status == OrderStatus.assigned || status == OrderStatus.active;
}
