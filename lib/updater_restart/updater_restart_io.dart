import 'dart:io';

import 'package:desktop_updater/desktop_updater.dart';

Future<String?> prepareDesktopUpdaterRestartImpl() async {
  if (!Platform.isWindows) {
    return null;
  }

  final String executablePath;
  try {
    executablePath = (await DesktopUpdater().getExecutablePath())?.trim() ?? '';
  } catch (error) {
    return 'Could not resolve executable path: $error';
  }

  if (executablePath.isEmpty) {
    return 'Could not resolve executable path.';
  }

  final int separatorIndex = executablePath.lastIndexOf(Platform.pathSeparator);
  if (separatorIndex <= 0) {
    return 'Invalid executable path: $executablePath';
  }

  final String executableDirPath = executablePath.substring(0, separatorIndex);
  final Directory executableDir = Directory(executableDirPath);
  if (!await executableDir.exists()) {
    return 'Executable directory not found: $executableDirPath';
  }

  final Directory updateDir = Directory(
    '$executableDirPath${Platform.pathSeparator}update',
  );
  if (!await updateDir.exists()) {
    return 'Downloaded update folder not found: ${updateDir.path}';
  }

  try {
    Directory.current = executableDirPath;
  } catch (error) {
    return 'Could not set working directory: $error';
  }

  return null;
}
