import 'updater_restart_stub.dart'
    if (dart.library.io) 'updater_restart_io.dart';

Future<String?> prepareDesktopUpdaterRestart() {
  return prepareDesktopUpdaterRestartImpl();
}
