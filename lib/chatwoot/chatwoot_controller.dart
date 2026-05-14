import 'dart:convert';

import 'package:flutter/foundation.dart'
    show ChangeNotifier, TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:http/http.dart' as http;

const String _chatDashEndpoint = 'https://mashroo3.net/api/pos/chat-dash';

class ChatwootConfig {
  const ChatwootConfig({
    required this.enabled,
    required this.baseUrl,
    required this.websiteToken,
  });

  factory ChatwootConfig.fromEnvironment() {
    final bool enabled = const bool.fromEnvironment(
      'CHATWOOT_ENABLED',
      defaultValue: false,
    );
    final String baseUrl = const String.fromEnvironment('CHATWOOT_BASE_URL')
        .trim()
        .replaceFirst(RegExp(r'/+$'), '');
    final String websiteToken =
        const String.fromEnvironment('CHATWOOT_WEBSITE_TOKEN').trim();

    return ChatwootConfig(
      enabled: enabled,
      baseUrl: baseUrl,
      websiteToken: websiteToken,
    );
  }

  final bool enabled;
  final String baseUrl;
  final String websiteToken;

  bool get isReady => enabled && baseUrl.isNotEmpty && websiteToken.isNotEmpty;
}

class ChatwootIdentityState {
  const ChatwootIdentityState._({
    required this.isIdentified,
    required this.identifier,
    this.identifierHash,
    this.name,
    this.email,
    this.attributes = const <String, dynamic>{},
  });

  factory ChatwootIdentityState.anonymous({
    Map<String, dynamic> attributes = const <String, dynamic>{},
  }) {
    return ChatwootIdentityState._(
      isIdentified: false,
      identifier: 'anonymous',
      attributes: Map<String, dynamic>.unmodifiable(attributes),
    );
  }

  factory ChatwootIdentityState.identified({
    required String identifier,
    required String identifierHash,
    String? name,
    String? email,
    Map<String, dynamic> attributes = const <String, dynamic>{},
  }) {
    return ChatwootIdentityState._(
      isIdentified: true,
      identifier: identifier,
      identifierHash: identifierHash,
      name: _cleanText(name),
      email: _cleanText(email),
      attributes: Map<String, dynamic>.unmodifiable(attributes),
    );
  }

  final bool isIdentified;
  final String identifier;
  final String? identifierHash;
  final String? name;
  final String? email;
  final Map<String, dynamic> attributes;
}

class ChatDashSignRequest {
  const ChatDashSignRequest({
    required this.identifier,
    this.name,
    this.email,
    this.attributes = const <String, dynamic>{},
  });

  final String identifier;
  final String? name;
  final String? email;
  final Map<String, dynamic> attributes;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'identifier': identifier,
      if ((name ?? '').trim().isNotEmpty) 'name': name!.trim(),
      if ((email ?? '').trim().isNotEmpty) 'email': email!.trim(),
      if (attributes.isNotEmpty) 'attributes': attributes,
    };
  }
}

class ChatDashSignResponse {
  const ChatDashSignResponse({
    required this.identifier,
    required this.identifierHash,
    this.name,
    this.email,
  });

  final String identifier;
  final String identifierHash;
  final String? name;
  final String? email;
}

class ChatDashSignerClient {
  ChatDashSignerClient({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Future<ChatDashSignResponse> sign({
    required String apiKey,
    required ChatDashSignRequest request,
  }) async {
    final Map<String, String> headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (apiKey.trim().isNotEmpty) 'x-api-key': apiKey.trim(),
    };

    final http.Response response = await _httpClient.post(
      Uri.parse(_chatDashEndpoint),
      headers: headers,
      body: jsonEncode(request.toJson()),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Signer failed with status ${response.statusCode}.');
    }

    final dynamic decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Signer returned an invalid payload.');
    }

    final String? identifier = _firstNonEmptyString(
      <dynamic>[decoded['identifier'], decoded['id'], request.identifier],
    );
    final String? identifierHash = _firstNonEmptyString(
      <dynamic>[decoded['identifier_hash'], decoded['identifierHash']],
    );

    if (identifier == null || identifierHash == null) {
      throw Exception('Signer response is missing identifier or identifier_hash.');
    }

    return ChatDashSignResponse(
      identifier: identifier,
      identifierHash: identifierHash,
      name: _firstNonEmptyString(<dynamic>[decoded['name'], request.name]),
      email: _firstNonEmptyString(<dynamic>[decoded['email'], request.email]),
    );
  }

  void close() {
    _httpClient.close();
  }
}

class ChatwootController extends ChangeNotifier {
  ChatwootController({
    ChatwootConfig? config,
    ChatDashSignerClient? signer,
  })  : config = config ?? ChatwootConfig.fromEnvironment(),
        _signer = signer ?? ChatDashSignerClient() {
    _state = ChatwootIdentityState.anonymous(
      attributes: <String, dynamic>{
        'platform': _platformLabel(),
      },
    );
  }

  final ChatwootConfig config;
  final ChatDashSignerClient _signer;

  late ChatwootIdentityState _state;
  int _requestVersion = 0;
  bool _isDisposed = false;
  String? _lastSignError;
  DateTime? _lastFailedSignAt;
  String? _lastFailedIdentifier;

  bool get isEnabled => config.isReady;
  ChatwootIdentityState get state => _state;
  String? get lastSignError => _lastSignError;

  void setAnonymous({Map<String, dynamic> attributes = const <String, dynamic>{}}) {
    _requestVersion += 1;
    _lastSignError = null;
    _state = ChatwootIdentityState.anonymous(
      attributes: _sanitizeAttributes(attributes),
    );
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  void updateAttributes(Map<String, dynamic> attributes) {
    final Map<String, dynamic> sanitized = _sanitizeAttributes(attributes);
    if (_state.isIdentified &&
        _state.identifierHash != null &&
        _state.identifierHash!.trim().isNotEmpty) {
      _state = ChatwootIdentityState.identified(
        identifier: _state.identifier,
        identifierHash: _state.identifierHash!,
        name: _state.name,
        email: _state.email,
        attributes: sanitized,
      );
    } else {
      _state = ChatwootIdentityState.anonymous(attributes: sanitized);
    }

    if (!_isDisposed) {
      notifyListeners();
    }
  }

  Future<void> identifyWithHmac({
    required String apiKey,
    required String identifier,
    String? name,
    String? email,
    Map<String, dynamic> attributes = const <String, dynamic>{},
  }) async {
    if (!isEnabled) {
      return;
    }

    final String normalizedIdentifier = identifier.trim();
    if (normalizedIdentifier.isEmpty) {
      setAnonymous(attributes: attributes);
      return;
    }

    final int requestVersion = ++_requestVersion;
    final Map<String, dynamic> sanitizedAttributes =
        _sanitizeAttributes(attributes);
    final DateTime now = DateTime.now();

    if (_lastFailedIdentifier == normalizedIdentifier &&
        _lastFailedSignAt != null &&
        now.difference(_lastFailedSignAt!).inSeconds < 20) {
      _state = ChatwootIdentityState.anonymous(attributes: sanitizedAttributes);
      notifyListeners();
      return;
    }

    try {
      final ChatDashSignResponse signed = await _signer.sign(
        apiKey: apiKey,
        request: ChatDashSignRequest(
          identifier: normalizedIdentifier,
          name: _cleanText(name),
          email: _cleanText(email),
          attributes: sanitizedAttributes,
        ),
      );

      if (_isDisposed || requestVersion != _requestVersion) {
        return;
      }

      _lastSignError = null;
      _lastFailedSignAt = null;
      _lastFailedIdentifier = null;
      _state = ChatwootIdentityState.identified(
        identifier: signed.identifier,
        identifierHash: signed.identifierHash,
        name: signed.name,
        email: signed.email,
        attributes: sanitizedAttributes,
      );
      notifyListeners();
    } catch (error) {
      if (_isDisposed || requestVersion != _requestVersion) {
        return;
      }

      _lastSignError = '$error';
      _lastFailedSignAt = now;
      _lastFailedIdentifier = normalizedIdentifier;
      _state = ChatwootIdentityState.anonymous(
        attributes: sanitizedAttributes,
      );
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _signer.close();
    super.dispose();
  }
}

String buildChatwootBootstrapHtml({
  required String baseUrl,
  required String websiteToken,
  required String locale,
}) {
  final String baseUrlJson = jsonEncode(baseUrl);
  final String websiteTokenJson = jsonEncode(websiteToken);
  final String localeJson = jsonEncode(locale);

  return '''
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <style>
      html, body {
        margin: 0;
        padding: 0;
        width: 100%;
        height: 100%;
        background: #ffffff;
      }
    </style>
  </head>
  <body>
    <script>
      window.chatwootSettings = {
        hideMessageBubble: true,
        showUnreadMessagesDialog: false,
        locale: $localeJson,
      };
      (function (d, t) {
        var BASE_URL = $baseUrlJson;
        var g = d.createElement(t), s = d.getElementsByTagName(t)[0];
        g.src = BASE_URL + '/packs/js/sdk.js';
        g.defer = true;
        g.async = true;
        s.parentNode.insertBefore(g, s);
        g.onload = function () {
          window.chatwootSDK.run({
            websiteToken: $websiteTokenJson,
            baseUrl: BASE_URL,
          });
          var tries = 0;
          var bootstrapInterval = setInterval(function () {
            tries += 1;
            if (window.\$chatwoot) {
              window.\$chatwoot.toggleBubbleVisibility('hide');
              window.\$chatwoot.toggle('open');
              clearInterval(bootstrapInterval);
            } else if (tries >= 80) {
              clearInterval(bootstrapInterval);
            }
          }, 150);
        };
      })(document, 'script');
    </script>
  </body>
</html>
''';
}

Map<String, dynamic> _sanitizeAttributes(Map<String, dynamic> rawAttributes) {
  final Map<String, dynamic> result = <String, dynamic>{
    'platform': _platformLabel(),
  };

  rawAttributes.forEach((String key, dynamic value) {
    final String normalizedKey = key.trim();
    if (normalizedKey.isEmpty) {
      return;
    }

    final dynamic normalizedValue = _normalizeAttributeValue(value);
    if (normalizedValue == null) {
      return;
    }

    result[normalizedKey] = normalizedValue;
  });

  return result;
}

dynamic _normalizeAttributeValue(dynamic value) {
  if (value == null) return null;
  if (value is num || value is bool) return value;
  if (value is DateTime) return value.toIso8601String();

  final String text = value.toString().trim();
  if (text.isEmpty) return null;
  if (text.length <= 250) return text;
  return text.substring(0, 250);
}

String _platformLabel() {
  if (kIsWeb) return 'web';
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'android';
    case TargetPlatform.iOS:
      return 'ios';
    case TargetPlatform.macOS:
      return 'macos';
    case TargetPlatform.windows:
      return 'windows';
    case TargetPlatform.linux:
      return 'linux';
    case TargetPlatform.fuchsia:
      return 'fuchsia';
  }
}

String? _firstNonEmptyString(List<dynamic> candidates) {
  for (final dynamic candidate in candidates) {
    final String? value = _cleanText(candidate?.toString());
    if (value != null) {
      return value;
    }
  }
  return null;
}

String? _cleanText(String? value) {
  if (value == null) return null;
  final String normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return null;
  if (normalized.length <= 150) return normalized;
  return normalized.substring(0, 150);
}
