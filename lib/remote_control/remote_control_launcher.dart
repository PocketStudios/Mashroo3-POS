import 'remote_control_launcher_stub.dart'
    if (dart.library.io) 'remote_control_launcher_io.dart';
import 'remote_control_types.dart';

export 'remote_control_types.dart';

RemoteControlLauncher createRemoteControlLauncher({
  required String assetPath,
}) {
  return createRemoteControlLauncherImpl(assetPath: assetPath);
}
