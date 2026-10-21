import 'package:flutter/foundation.dart';

/// "This data changed" signals between screens that stay alive.
///
/// The customer app keeps its tabs alive in an IndexedStack, and each tab
/// loads its data once. A new saved address or review written from another
/// screen never reached them, so testers saw the change only after
/// restarting the app (APP-105, APP-150, APP-153). Whoever writes the data
/// calls the matching `...Changed()`; screens showing it listen and reload.
class DataChanges {
  DataChanges._();

  /// The signed-in customer's saved addresses.
  static final addresses = ValueNotifier<int>(0);

  /// Station facts customers see: ratings and review counts.
  static final stations = ValueNotifier<int>(0);

  static void addressesChanged() => addresses.value++;
  static void stationsChanged() => stations.value++;
}
