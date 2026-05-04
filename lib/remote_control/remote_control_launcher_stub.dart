import 'remote_control_types.dart';

class _UnsupportedRemoteControlLauncher implements RemoteControlLauncher {
  _UnsupportedRemoteControlLauncher({required this.unsupportedReason});

  @override
  final String unsupportedReason;

  @override
  bool get isSupported => false;

  @override
  Future<RemoteControlLaunchResult> launchOneTimeConnect({
    required String identifier,
  }) async {
    return RemoteControlLaunchResult(
      success: false,
      message: unsupportedReason,
    );
  }
}

RemoteControlLauncher createRemoteControlLauncherImpl({
  required String assetPath,
}) {
  return _UnsupportedRemoteControlLauncher(
    unsupportedReason: 'Mashroo3 Remote Control is supported on Windows only.',
  );
}
