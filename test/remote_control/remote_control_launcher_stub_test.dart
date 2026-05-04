import 'package:flutter_test/flutter_test.dart';
import 'package:mashroo3/remote_control/remote_control_launcher_stub.dart';

void main() {
  test('stub launcher returns unsupported result without side effects', () async {
    final launcher = createRemoteControlLauncherImpl(
      assetPath: 'assets/mashroo3.exe',
    );

    expect(launcher.isSupported, isFalse);
    expect(launcher.unsupportedReason, isNotEmpty);

    final result = await launcher.launchOneTimeConnect(
      identifier: 'operator-1',
    );

    expect(result.success, isFalse);
    expect(result.startedWithFallback, isFalse);
    expect(result.message, launcher.unsupportedReason);
  });
}
