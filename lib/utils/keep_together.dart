/// Display form of an ID such as GW-STN-2026-0001 that never splits across
/// lines: an invisible word joiner after each hyphen removes the line-break
/// chance there, so a narrow phone shows the whole code on one line instead
/// of "GW-" / "STN-2026-0001". For display only -- don't store or compare
/// the result.
String keepTogether(String code) => code.replaceAll('-', '-⁠');
