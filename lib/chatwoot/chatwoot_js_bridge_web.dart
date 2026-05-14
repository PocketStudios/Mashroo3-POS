// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;

import 'chatwoot_controller.dart';

const bool chatwootUsesHostPage = true;

Completer<void>? _readyCompleter;
bool _scriptAttached = false;
bool _sdkRunCalled = false;
String? _lastBaseUrl;
String? _lastWebsiteToken;
bool _listenersAttached = false;
bool _isWidgetOpen = false;
bool _hadWidgetError = false;

Future<void> chatwootEnsureLoaded({
  required String baseUrl,
  required String websiteToken,
  required String locale,
}) async {
  if (baseUrl.trim().isEmpty || websiteToken.trim().isEmpty) {
    return;
  }

  final String normalizedBaseUrl = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
  final String normalizedToken = websiteToken.trim();

  if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
    await _readyCompleter!.future.timeout(const Duration(seconds: 6), onTimeout: () {});
    return;
  }

  final bool configChanged = _lastBaseUrl != normalizedBaseUrl ||
      _lastWebsiteToken != normalizedToken;
  _lastBaseUrl = normalizedBaseUrl;
  _lastWebsiteToken = normalizedToken;

  _readyCompleter = Completer<void>();
  if (_chatwootObject != null) {
    _readyCompleter!.complete();
    return;
  }

  final Object globalThis = js_util.globalThis;
  js_util.setProperty(
    globalThis,
    'chatwootSettings',
    js_util.jsify(<String, dynamic>{
      'hideMessageBubble': true,
      'showUnreadMessagesDialog': false,
      'locale': locale,
    }),
  );

  html.window.addEventListener('chatwoot:ready', _onChatwootReady);
  _ensureHostEventListeners();

  if (configChanged) {
    _sdkRunCalled = false;
  }

  if (!_scriptAttached || configChanged) {
    _scriptAttached = true;
    final html.ScriptElement script = html.ScriptElement()
      ..src = '$normalizedBaseUrl/packs/js/sdk.js'
      ..defer = true
      ..async = true;

    script.onLoad.listen((_) {
      _runSdk(baseUrl: normalizedBaseUrl, websiteToken: normalizedToken, locale: locale);
    });
    script.onError.listen((_) {
      if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
        _readyCompleter!.complete();
      }
    });

    html.document.head?.append(script);
  } else {
    _runSdk(baseUrl: normalizedBaseUrl, websiteToken: normalizedToken, locale: locale);
  }

  await _readyCompleter!.future.timeout(const Duration(seconds: 6), onTimeout: () {});
}

void _runSdk({
  required String baseUrl,
  required String websiteToken,
  required String locale,
}) {
  if (_sdkRunCalled) {
    return;
  }

  final Object globalThis = js_util.globalThis;
  final Object? sdk = _safeGetProperty(globalThis, 'chatwootSDK');
  if (sdk == null) {
    return;
  }

  _sdkRunCalled = true;
  js_util.callMethod<void>(sdk, 'run', <Object?>[
    js_util.jsify(<String, dynamic>{
      'websiteToken': websiteToken,
      'baseUrl': baseUrl,
      'locale': locale,
      'hideMessageBubble': true,
      'showUnreadMessagesDialog': false,
    }),
  ]);
}

void _onChatwootReady(html.Event _) {
  _hadWidgetError = false;
  if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
    _readyCompleter!.complete();
  }
}

Future<void> chatwootApplyState(
  ChatwootIdentityState state, {
  required String locale,
}) async {
  final Object? chatwoot = _chatwootObject;
  if (chatwoot == null) {
    return;
  }

  _safeCall(chatwoot, 'setLocale', <Object?>[locale]);

  if (!state.isIdentified) {
    _safeCall(chatwoot, 'reset', const <Object?>[]);
  } else {
    final String? identifierHash = state.identifierHash?.trim();
    if (identifierHash != null && identifierHash.isNotEmpty) {
      _safeCall(chatwoot, 'setUser', <Object?>[
        state.identifier,
        js_util.jsify(<String, dynamic>{
          if ((state.name ?? '').trim().isNotEmpty) 'name': state.name,
          if ((state.email ?? '').trim().isNotEmpty) 'email': state.email,
          'identifier_hash': identifierHash,
        }),
      ]);
    }
  }

  if (state.attributes.isNotEmpty) {
    _safeCall(
      chatwoot,
      'setCustomAttributes',
      <Object?>[js_util.jsify(state.attributes)],
    );
  }
}

Future<void> chatwootOpen() async {
  final Object? chatwoot = _chatwootObject;
  if (chatwoot == null) {
    return;
  }

  _safeCall(chatwoot, 'toggleBubbleVisibility', const <Object?>['hide']);

  if (_hadWidgetError) {
    _safeCall(chatwoot, 'reset', const <Object?>[]);
    _hadWidgetError = false;
    _safeCall(chatwoot, 'toggle', const <Object?>['open']);
    _isWidgetOpen = true;
    return;
  }

  if (_isWidgetOpen) {
    _safeCall(chatwoot, 'toggle', const <Object?>['close']);
    _isWidgetOpen = false;
  } else {
    _safeCall(chatwoot, 'toggle', const <Object?>['open']);
    _isWidgetOpen = true;
  }
}

Object? get _chatwootObject {
  final Object globalThis = js_util.globalThis;
  return _safeGetProperty(globalThis, r'$chatwoot');
}

Object? _safeGetProperty(Object target, String property) {
  try {
    return js_util.getProperty<Object?>(target, property);
  } catch (_) {
    return null;
  }
}

void _safeCall(Object target, String method, List<Object?> args) {
  try {
    js_util.callMethod<void>(target, method, args);
  } catch (_) {
    // Non-blocking by design.
  }
}

void _ensureHostEventListeners() {
  if (_listenersAttached) return;
  _listenersAttached = true;

  html.window.addEventListener('chatwoot:opened', _onChatwootOpened);
  html.window.addEventListener('chatwoot:closed', _onChatwootClosed);
  html.window.addEventListener('chatwoot:error', _onChatwootError);
}

void _onChatwootOpened(html.Event _) {
  _isWidgetOpen = true;
}

void _onChatwootClosed(html.Event _) {
  _isWidgetOpen = false;
}

void _onChatwootError(html.Event _) {
  _hadWidgetError = true;
}
