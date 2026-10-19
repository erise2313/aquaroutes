/// How far from the drop-off pin a driver can be before completing a
/// delivery asks "are you sure?".
const dropOffWarningMetres = 200.0;

/// "350 m" or "1.4 km".
String formatMetres(double metres) =>
    metres < 1000 ? '${(metres / 10).round() * 10} m' : '${(metres / 1000).toStringAsFixed(1)} km';

/// The question to ask before marking a delivery complete, or null when
/// there's nothing to ask: the driver is near the pin, or the phone doesn't
/// know where it is. A lost signal must never stop a driver finishing a
/// delivery, so an unknown position is treated as "don't ask" rather than
/// "too far". Pure, so it is unit-tested.
String? farFromDropOffWarning(double? metresFromDropOff) {
  if (metresFromDropOff == null || metresFromDropOff <= dropOffWarningMetres) return null;
  return "You're about ${formatMetres(metresFromDropOff)} from the drop-off pin. Mark this delivery as complete anyway?";
}
