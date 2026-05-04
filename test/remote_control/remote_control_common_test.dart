import 'package:flutter_test/flutter_test.dart';
import 'package:mashroo3/remote_control/remote_control_common.dart';

void main() {
  group('buildRemoteControlIdentifier', () {
    test('prefers selected customer display label', () {
      final String identifier = buildRemoteControlIdentifier(
        selectedCustomerDisplayLabel: 'John Doe (70123456)',
        selectedCustomerApiId: 44,
        maskedApiKey: 'abcd****',
      );
      expect(identifier, 'John Doe (70123456)');
    });

    test('falls back to selected customer API id', () {
      final String identifier = buildRemoteControlIdentifier(
        selectedCustomerDisplayLabel: '   ',
        selectedCustomerApiId: 44,
        maskedApiKey: 'abcd****',
      );
      expect(identifier, 'customer-44');
    });

    test('falls back to masked API key', () {
      final String identifier = buildRemoteControlIdentifier(
        selectedCustomerDisplayLabel: '',
        selectedCustomerApiId: null,
        maskedApiKey: 'abcd****',
      );
      expect(identifier, 'abcd****');
    });

    test('uses terminal fallback when all else missing', () {
      final String identifier = buildRemoteControlIdentifier(
        selectedCustomerDisplayLabel: null,
        selectedCustomerApiId: null,
        maskedApiKey: '',
      );
      expect(identifier, 'pos-terminal');
    });
  });

  group('remote control arguments', () {
    test('builds connect args without dashes', () {
      final List<String> args = buildRemoteControlConnectArgs();
      expect(args, const <String>['connect']);
    });
  });
}
