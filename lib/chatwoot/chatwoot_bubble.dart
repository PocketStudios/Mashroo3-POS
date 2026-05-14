import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'chatwoot_controller.dart';
import 'chatwoot_js_bridge.dart';

class ChatwootAppShell extends StatelessWidget {
  const ChatwootAppShell({
    super.key,
    required this.controller,
    required this.navigatorKey,
    required this.child,
    this.showLauncher = true,
  });

  final ChatwootController controller;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  final bool showLauncher;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, _) {
        if (!controller.isEnabled) {
          return child;
        }

        if (!showLauncher) {
          return child;
        }

        return Stack(
          children: <Widget>[
            Positioned.fill(child: child),
            Positioned(
              right: 18,
              bottom: 18,
              child: FloatingActionButton.extended(
                heroTag: 'mashroo3_chatwoot_bubble',
                onPressed: () => _openChat(context),
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: Text('chatwoot.launcher'.tr()),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openChat(BuildContext context) async {
    await openSupportChat(
      context: context,
      navigatorKey: navigatorKey,
      controller: controller,
    );
  }
}

Future<void> openSupportChat({
  required BuildContext context,
  required GlobalKey<NavigatorState> navigatorKey,
  required ChatwootController controller,
}) async {
  if (!controller.isEnabled) {
    return;
  }

  if (kIsWeb && chatwootUsesHostPage) {
      final String locale = Localizations.localeOf(context).languageCode;
      await chatwootEnsureLoaded(
        baseUrl: controller.config.baseUrl,
        websiteToken: controller.config.websiteToken,
        locale: locale,
      );
      await chatwootApplyState(controller.state, locale: locale);
      await chatwootOpen();
      return;
    }

    final BuildContext? navigatorContext = navigatorKey.currentContext;
    final BuildContext dialogContext = navigatorContext ?? context;
    if (Navigator.maybeOf(dialogContext) == null) {
      return;
    }
    await showDialog<void>(
      context: dialogContext,
      useRootNavigator: true,
      builder: (BuildContext context) {
        return _ChatwootDialog(controller: controller);
      },
    );
  }

class _ChatwootDialog extends StatefulWidget {
  const _ChatwootDialog({required this.controller});

  final ChatwootController controller;

  @override
  State<_ChatwootDialog> createState() => _ChatwootDialogState();
}

class _ChatwootDialogState extends State<_ChatwootDialog> {
  InAppWebViewController? _webViewController;
  bool _isReady = false;
  bool _hasError = false;
  String _fingerprint = '';
  bool _lastAppliedIdentified = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    _syncIdentityState();
  }

  Future<void> _syncIdentityState() async {
    if (!mounted) return;
    if (!_isReady || _hasError) return;

    final InAppWebViewController? controller = _webViewController;
    if (controller == null) return;

    final ChatwootIdentityState state = widget.controller.state;
    final String nextFingerprint = _buildFingerprint(state);
    if (nextFingerprint == _fingerprint) return;

    _fingerprint = nextFingerprint;

    final String locale = Localizations.localeOf(context).languageCode;
    final String localeJson = jsonEncode(locale);
    await controller.evaluateJavascript(
      source: 'if (window.\$chatwoot) { window.\$chatwoot.setLocale($localeJson); }',
    );

    if (_lastAppliedIdentified && !state.isIdentified) {
      await controller.evaluateJavascript(
        source: 'if (window.\$chatwoot) { window.\$chatwoot.reset(); }',
      );
      await controller.evaluateJavascript(
        source: 'if (window.\$chatwoot) { window.\$chatwoot.setLocale($localeJson); }',
      );
    }

    if (state.isIdentified &&
        state.identifierHash != null &&
        state.identifierHash!.trim().isNotEmpty) {
      final String identifierJson = jsonEncode(state.identifier);
      final Map<String, dynamic> user = <String, dynamic>{
        if ((state.name ?? '').trim().isNotEmpty) 'name': state.name,
        if ((state.email ?? '').trim().isNotEmpty) 'email': state.email,
        'identifier_hash': state.identifierHash,
      };
      final String userJson = jsonEncode(user);

      await controller.evaluateJavascript(
        source:
            'if (window.\$chatwoot) { window.\$chatwoot.setUser($identifierJson, $userJson); }',
      );
    }

    if (state.attributes.isNotEmpty) {
      final String attributesJson = jsonEncode(state.attributes);
      await controller.evaluateJavascript(
        source:
            'if (window.\$chatwoot) { window.\$chatwoot.setCustomAttributes($attributesJson); }',
      );
    }

    await controller.evaluateJavascript(
      source:
          'if (window.\$chatwoot) { window.\$chatwoot.toggleBubbleVisibility(\"hide\"); window.\$chatwoot.toggle(\"open\"); }',
    );

    _lastAppliedIdentified = state.isIdentified;
  }

  String _buildFingerprint(ChatwootIdentityState state) {
    return jsonEncode(<String, dynamic>{
      'identified': state.isIdentified,
      'identifier': state.identifier,
      'identifierHash': state.identifierHash,
      'name': state.name,
      'email': state.email,
      'attributes': state.attributes,
    });
  }

  @override
  Widget build(BuildContext context) {
    final ChatwootConfig config = widget.controller.config;
    final String html = buildChatwootBootstrapHtml(
      baseUrl: config.baseUrl,
      websiteToken: config.websiteToken,
      locale: Localizations.localeOf(context).languageCode,
    );

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: SizedBox(
        width: 920,
        height: 720,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.support_agent_rounded),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'chatwoot.title'.tr(),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: 'common.close'.tr(),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _hasError
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text(
                          'chatwoot.load_error'.tr(),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : InAppWebView(
                      initialData: InAppWebViewInitialData(data: html),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        mediaPlaybackRequiresUserGesture: false,
                        thirdPartyCookiesEnabled: true,
                        javaScriptCanOpenWindowsAutomatically: true,
                        transparentBackground: false,
                      ),
                      onWebViewCreated: (InAppWebViewController controller) {
                        _webViewController = controller;
                      },
                      onLoadStop: (
                        InAppWebViewController controller,
                        WebUri? _,
                      ) async {
                        _isReady = true;
                        _hasError = false;
                        await _syncIdentityState();
                      },
                      onReceivedError: (
                        InAppWebViewController controller,
                        WebResourceRequest request,
                        WebResourceError error,
                      ) {
                        if (!mounted) return;
                        setState(() {
                          _hasError = true;
                        });
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
