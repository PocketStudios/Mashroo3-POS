import 'chatwoot_controller.dart';
import 'chatwoot_js_bridge_stub.dart'
    if (dart.library.html) 'chatwoot_js_bridge_web.dart' as bridge;

bool get chatwootUsesHostPage => bridge.chatwootUsesHostPage;

Future<void> chatwootEnsureLoaded({
  required String baseUrl,
  required String websiteToken,
  required String locale,
}) {
  return bridge.chatwootEnsureLoaded(
    baseUrl: baseUrl,
    websiteToken: websiteToken,
    locale: locale,
  );
}

Future<void> chatwootApplyState(
  ChatwootIdentityState state, {
  required String locale,
}) {
  return bridge.chatwootApplyState(state, locale: locale);
}

Future<void> chatwootOpen() {
  return bridge.chatwootOpen();
}
