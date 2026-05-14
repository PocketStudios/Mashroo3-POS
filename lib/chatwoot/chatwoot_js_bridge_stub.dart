import 'chatwoot_controller.dart';

const bool chatwootUsesHostPage = false;

Future<void> chatwootEnsureLoaded({
  required String baseUrl,
  required String websiteToken,
  required String locale,
}) async {}

Future<void> chatwootApplyState(
  ChatwootIdentityState state, {
  required String locale,
}) async {}

Future<void> chatwootOpen() async {}
