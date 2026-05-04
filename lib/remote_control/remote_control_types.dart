class RemoteControlLaunchResult {
  const RemoteControlLaunchResult({
    required this.success,
    required this.message,
    this.startedWithFallback = false,
  });

  final bool success;
  final String message;
  final bool startedWithFallback;
}

abstract class RemoteControlLauncher {
  bool get isSupported;
  String get unsupportedReason;

  Future<RemoteControlLaunchResult> launchOneTimeConnect({
    required String identifier,
  });
}
