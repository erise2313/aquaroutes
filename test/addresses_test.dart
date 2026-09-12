import 'package:aquaroute/models/customer_address.dart';
import 'package:flutter_test/flutter_test.dart';

CustomerAddress _address(String id, {bool isDefault = false}) => CustomerAddress(
      id: id,
      label: id,
      latitude: 14.38,
      longitude: 120.88,
      isDefault: isDefault,
    );

void main() {
  group('preferredAddress', () {
    test('picks the default wherever it sits in the list', () {
      final addresses = [_address('work'), _address('home', isDefault: true)];
      expect(preferredAddress(addresses)?.id, 'home');
    });

    test('falls back to the first saved one', () {
      expect(preferredAddress([_address('work'), _address('mama')])?.id, 'work');
    });

    test('returns null when nothing is saved, so the map still decides', () {
      expect(preferredAddress(const []), isNull);
    });
  });

  test('validateAddressLabel', () {
    expect(validateAddressLabel(''), isNotNull);
    expect(validateAddressLabel('   '), isNotNull);
    expect(validateAddressLabel(null), isNotNull);
    expect(validateAddressLabel('Home'), isNull);
    expect(validateAddressLabel('x' * 41), isNotNull);
  });
}
