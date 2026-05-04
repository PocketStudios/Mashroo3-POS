import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'remote_control_common.dart';
import 'remote_control_types.dart';

class _IoRemoteControlLauncher implements RemoteControlLauncher {
  _IoRemoteControlLauncher({required this.assetPath});

  final String assetPath;

  @override
  bool get isSupported => Platform.isWindows;

  @override
  String get unsupportedReason =>
      'Mashroo3 Remote Control is supported on Windows only.';

  @override
  Future<RemoteControlLaunchResult> launchOneTimeConnect({
    required String identifier,
  }) async {
    if (!isSupported) {
      return RemoteControlLaunchResult(
        success: false,
        message: unsupportedReason,
      );
    }

    final String executablePath;
    try {
      executablePath = await _materializeExecutable();
    } catch (error) {
      return RemoteControlLaunchResult(
        success: false,
        message: 'Could not prepare launcher executable: $error',
      );
    }

    final _LaunchAttempt primary = await _startWithArgs(
      executablePath,
      buildRemoteControlPrimaryArgs(identifier),
    );
    if (primary.success) {
      return RemoteControlLaunchResult(
        success: true,
        message: 'Mashroo3 Remote Control started.',
      );
    }

    final _LaunchAttempt fallback = await _startWithArgs(
      executablePath,
      buildRemoteControlFallbackArgs(),
    );
    if (fallback.success) {
      return RemoteControlLaunchResult(
        success: true,
        message: 'Mashroo3 Remote Control started using fallback connect mode.',
        startedWithFallback: true,
      );
    }

    return RemoteControlLaunchResult(
      success: false,
      message: fallback.errorMessage ?? primary.errorMessage ?? 'Launch failed.',
    );
  }

  Future<String> _materializeExecutable() async {
    final ByteData data = await rootBundle.load(assetPath);
    final Directory folder =
        await Directory.systemTemp.createTemp('mashroo3_remote_control_');
    final String path = '${folder.path}${Platform.pathSeparator}mashroo3.exe';
    final File file = File(path);
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    return path;
  }

  Future<_LaunchAttempt> _startWithArgs(
    String executablePath,
    List<String> args,
  ) async {
    try {
      final Process process = await Process.start(executablePath, args);
      int? quickExitCode;
      bool exitedQuickly = true;
      try {
        quickExitCode = await process.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        exitedQuickly = false;
      }
      if (exitedQuickly && quickExitCode != null && quickExitCode != 0) {
        return _LaunchAttempt(
          success: false,
          errorMessage: 'Process exited quickly with code $quickExitCode.',
        );
      }
      return const _LaunchAttempt(success: true);
    } catch (error) {
      return _LaunchAttempt(success: false, errorMessage: '$error');
    }
  }
}

class _LaunchAttempt {
  const _LaunchAttempt({
    required this.success,
    this.errorMessage,
  });

  final bool success;
  final String? errorMessage;
}

RemoteControlLauncher createRemoteControlLauncherImpl({
  required String assetPath,
}) {
  return _IoRemoteControlLauncher(assetPath: assetPath);
}
