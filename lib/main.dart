import 'dart:convert';

import 'package:desktop_updater/desktop_updater.dart';
import 'package:desktop_updater/updater_controller.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pwa_install/pwa_install.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _apiKeyStorageKey = 'pos_api_key';
const String _apiBaseUrl = 'https://mashroo3.net';
const String _desktopAppArchiveUrl = 'https://mashroo3.net/app-archive.json';
const double _qtyEpsilon = 1e-6;

double _roundQty(double value, [int decimals = 3]) {
  return double.parse(value.toStringAsFixed(decimals));
}

String _formatQty(double value, [int decimals = 3]) {
  final String fixed = value.toStringAsFixed(decimals);
  final String trimmed = fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  return trimmed.isEmpty ? '0' : trimmed;
}

String _tr(String key, {Map<String, String>? namedArgs}) {
  return key.tr(namedArgs: namedArgs);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  PWAInstall().setup(installCallback: () {
    debugPrint('APP INSTALLED!');
  });
  runApp(
    EasyLocalization(
      supportedLocales: const <Locale>[Locale('en'), Locale('ar')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      saveLocale: true,
      child: const _DesktopUpdateGate(
        child: PosApp(),
      ),
    ),
  );
}

class _DesktopUpdateGate extends StatefulWidget {
  const _DesktopUpdateGate({required this.child});

  final Widget child;

  @override
  State<_DesktopUpdateGate> createState() => _DesktopUpdateGateState();
}

class _DesktopUpdateGateState extends State<_DesktopUpdateGate> {
  DesktopUpdaterController? _updaterController;
  String? _currentDesktopVersion;
  bool _isChecking = true;
  bool _canLoadApp = false;
  String? _downloadError;

  bool get _supportsDesktopUpdater {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  @override
  void initState() {
    super.initState();
    _checkDesktopUpdateGate();
  }

  @override
  void dispose() {
    _updaterController?.removeListener(_onUpdaterChanged);
    _updaterController?.dispose();
    super.dispose();
  }

  void _onUpdaterChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _checkDesktopUpdateGate() async {
    if (!_supportsDesktopUpdater) {
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _canLoadApp = true;
      });
      return;
    }

    final DesktopUpdaterController controller = DesktopUpdaterController(
      appArchiveUrl: Uri.parse(_desktopAppArchiveUrl),
    );
    controller.addListener(_onUpdaterChanged);
    _updaterController = controller;
    try {
      _currentDesktopVersion = await DesktopUpdater().getCurrentVersion();
    } catch (_) {
      _currentDesktopVersion = null;
    }

    try {
      await controller.checkVersion().timeout(const Duration(seconds: 15));
      if (!mounted) return;

      setState(() {
        _isChecking = false;
        _canLoadApp = !controller.needUpdate;
      });
    } catch (_) {
      if (!mounted) return;
      // Fail open: if check fails, continue with the app normally.
      setState(() {
        _isChecking = false;
        _canLoadApp = true;
      });
    }
  }

  Future<void> _downloadAndInstall() async {
    final DesktopUpdaterController? controller = _updaterController;
    if (controller == null) return;

    setState(() {
      _downloadError = null;
    });

    try {
      await controller.downloadUpdate();
      if (!mounted) return;
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _downloadError = '$error';
      });
    }
  }

  Future<void> _restartToInstall() async {
    final DesktopUpdaterController? controller = _updaterController;
    if (controller == null) return;

    try {
      controller.restartApp();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _downloadError = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_canLoadApp) {
      return widget.child;
    }

    if (_isChecking) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        home: Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const CircularProgressIndicator(),
                      const SizedBox(height: 14),
                      Text(
                        _tr('updater.checking_title'),
                        style: Theme.of(context).textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _tr('updater.checking_subtitle'),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final DesktopUpdaterController? controller = _updaterController;
    if (controller == null) {
      return widget.child;
    }

    final double rawProgress = controller.downloadProgress;
    final double clampedProgress = rawProgress < 0
        ? 0
        : rawProgress > 1
            ? 1
            : rawProgress;
    final int progressPercent = (clampedProgress * 100).round();
    final List<ChangeModel> notes = (controller.releaseNotes ?? const <ChangeModel?>[])
        .whereType<ChangeModel>()
        .toList(growable: false);
    final bool showProgressBar = controller.isDownloading || controller.isDownloaded;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.system_update_alt_rounded,
                          size: 34,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _tr('updater.required_title'),
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(_tr('updater.required_subtitle')),
                    if ((_currentDesktopVersion ?? '').isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        _tr(
                          'updater.current_version',
                          namedArgs: <String, String>{
                            'version': _currentDesktopVersion ?? '',
                          },
                        ),
                      ),
                    ],
                    if ((controller.appVersion ?? '').isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        _tr(
                          'updater.latest_version',
                          namedArgs: <String, String>{
                            'version': controller.appVersion ?? '',
                          },
                        ),
                      ),
                    ],
                    if (notes.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 16),
                      Text(
                        _tr('updater.whats_new'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      ...notes.take(8).map((ChangeModel change) {
                        final String message = change.message.trim();
                        if (message.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('• $message'),
                        );
                      }),
                    ],
                    if (showProgressBar) ...<Widget>[
                      const SizedBox(height: 14),
                      LinearProgressIndicator(
                        value: controller.isDownloading ? clampedProgress : 1,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        controller.isDownloaded
                            ? _tr('updater.download_complete')
                            : _tr(
                                'updater.downloading_progress',
                                namedArgs: <String, String>{
                                  'percent': '$progressPercent',
                                },
                              ),
                      ),
                    ],
                    if (_downloadError != null && _downloadError!.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(
                        _tr(
                          'updater.download_error',
                          namedArgs: <String, String>{
                            'error': _downloadError!.trim(),
                          },
                        ),
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: controller.isDownloading
                            ? null
                            : controller.isDownloaded
                                ? _restartToInstall
                                : _downloadAndInstall,
                        icon: controller.isDownloading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                controller.isDownloaded
                                    ? Icons.restart_alt_rounded
                                    : Icons.download_rounded,
                              ),
                        label: Text(
                          controller.isDownloading
                              ? _tr('updater.downloading')
                              : controller.isDownloaded
                                  ? _tr('updater.restart_button')
                                  : _tr('updater.download_button'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PosApp extends StatefulWidget {
  const PosApp({super.key});

  @override
  State<PosApp> createState() => _PosAppState();
}

class _PosAppState extends State<PosApp> {
  List<Product> _products = <Product>[];
  List<Customer> _customers = <Customer>[const Customer.walkIn()];
  final List<CartItem> _cartItems = <CartItem>[];
  List<PosOrder> _orders = <PosOrder>[];

  Customer? _selectedCustomer;
  String? _apiKey;
  double? _openingCash;
  bool _isLoading = true;
  bool _isSessionLoading = false;
  String? _sessionError;

  @override
  void initState() {
    super.initState();
    _selectedCustomer = _customers.first;
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }

    setState(() {
      _apiKey = prefs.getString(_apiKeyStorageKey);
      _isLoading = false;
    });
  }

  Future<void> _saveApiKey(String rawApiKey) async {
    final String apiKey = rawApiKey.trim();
    if (apiKey.isEmpty) {
      return;
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyStorageKey, apiKey);

    if (!mounted) {
      return;
    }

    setState(() {
      _apiKey = apiKey;
      _openingCash = null;
      _products = <Product>[];
      _orders = <PosOrder>[];
      _cartItems.clear();
      _customers = <Customer>[const Customer.walkIn()];
      _selectedCustomer = _customers.first;
      _sessionError = null;
      _isSessionLoading = false;
    });
  }

  Future<void> _logout() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_apiKeyStorageKey);

    if (!mounted) {
      return;
    }

    setState(() {
      _apiKey = null;
      _openingCash = null;
      _products = <Product>[];
      _orders = <PosOrder>[];
      _cartItems.clear();
      _customers = <Customer>[const Customer.walkIn()];
      _selectedCustomer = _customers.first;
      _sessionError = null;
      _isSessionLoading = false;
    });
  }

  Future<void> _startRegisterSession(double openingCash) async {
    setState(() {
      _openingCash = openingCash;
      _sessionError = null;
      _isSessionLoading = true;
      _products = <Product>[];
      _orders = <PosOrder>[];
      _cartItems.clear();
      _customers = <Customer>[const Customer.walkIn()];
      _selectedCustomer = _customers.first;
    });

    await _loadPosData();
  }

  Future<void> _loadPosData() async {
    final String? apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      return;
    }

    setState(() {
      _isSessionLoading = true;
      _sessionError = null;
    });

    final Mashroo3ApiClient client = Mashroo3ApiClient(
      baseUrl: _apiBaseUrl,
      apiKey: apiKey,
    );

    try {
      final List<dynamic> results = await Future.wait<dynamic>(<Future<dynamic>>[
        client.fetchCatalog(),
        client.fetchCustomers(),
        client.fetchOrders(),
      ]);

      if (!mounted) {
        return;
      }

      final List<Product> products = results[0] as List<Product>;
      final List<Customer> remoteCustomers = results[1] as List<Customer>;
      final List<PosOrder> orders = results[2] as List<PosOrder>;

      final List<Customer> nextCustomers = <Customer>[
        const Customer.walkIn(),
        ...remoteCustomers.where((Customer customer) => customer.apiId != null),
      ];

      Customer selectedCustomer = nextCustomers.first;
      final int? currentSelectedId = _selectedCustomer?.apiId;
      if (currentSelectedId != null) {
        for (final Customer customer in nextCustomers) {
          if (customer.apiId == currentSelectedId) {
            selectedCustomer = customer;
            break;
          }
        }
      }

      setState(() {
        _products = products;
        _customers = nextCustomers;
        _selectedCustomer = selectedCustomer;
        _orders = orders;
        _isSessionLoading = false;
        _sessionError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSessionLoading = false;
        _sessionError = _formatError(error);
      });
    }
  }

  Future<PosActionResult> _refreshPosData() async {
    if (_isSessionLoading) {
      return PosActionResult(
        success: false,
        message: _tr('messages.data_sync_in_progress'),
      );
    }

    await _loadPosData();
    if (_sessionError != null) {
      return PosActionResult(success: false, message: _sessionError!);
    }

    return PosActionResult(
      success: true,
      message: _tr('messages.catalog_customers_synced'),
    );
  }

  String _formatError(Object error) {
    if (error is ApiException) {
      return error.message;
    }

    return _tr(
      'messages.unexpected_error',
      namedArgs: <String, String>{'error': '$error'},
    );
  }

  PosActionResult _addProductToCart(Product product) {
    final int existingIndex =
        _cartItems.indexWhere((CartItem item) => item.product.id == product.id);
    final double existingQty =
        existingIndex == -1 ? 0 : _cartItems[existingIndex].quantity;
    final double step = product.cartQtyStep;

    final double? availableQty = product.availableQty;
    if (availableQty != null && existingQty + step > availableQty + _qtyEpsilon) {
      return PosActionResult(
        success: false,
        message: _tr(
          'messages.no_more_stock',
          namedArgs: <String, String>{'product': product.name},
        ),
      );
    }

    setState(() {
      if (existingIndex == -1) {
        _cartItems.add(CartItem(product: product, quantity: step));
      } else {
        final CartItem existing = _cartItems[existingIndex];
        _cartItems[existingIndex] =
            existing.copyWith(quantity: _roundQty(existing.quantity + step));
      }
    });

    return PosActionResult(
      success: true,
      message: _tr(
        'messages.product_added',
        namedArgs: <String, String>{'product': product.name},
      ),
    );
  }

  PosActionResult _addProductByBarcode(String rawBarcode) {
    final String barcode = rawBarcode.trim();
    if (barcode.isEmpty) {
      return PosActionResult(
        success: false,
        message: _tr('messages.enter_barcode_first'),
      );
    }

    Product? matched;
    for (final Product product in _products) {
      if (_barcodesMatch(product.barcode, barcode)) {
        matched = product;
        break;
      }
    }

    if (matched == null) {
      return PosActionResult(
        success: false,
        message: _tr(
          'messages.no_product_found_barcode',
          namedArgs: <String, String>{'barcode': barcode},
        ),
      );
    }

    return _addProductToCart(matched);
  }

  bool _barcodesMatch(String productBarcode, String scannedBarcode) {
    final String left = productBarcode.trim();
    final String right = scannedBarcode.trim();

    if (left == right) {
      return true;
    }

    final String normalizedLeft = left.replaceFirst(RegExp(r'^0+'), '');
    final String normalizedRight = right.replaceFirst(RegExp(r'^0+'), '');

    return normalizedLeft.isNotEmpty && normalizedLeft == normalizedRight;
  }

  void _changeQuantity(Product product, double delta) {
    final int index =
        _cartItems.indexWhere((CartItem item) => item.product.id == product.id);

    if (index == -1) {
      return;
    }

    setState(() {
      final CartItem current = _cartItems[index];
      final double nextQty = _roundQty(current.quantity + delta);

      if (product.availableQty != null &&
          nextQty > product.availableQty! + _qtyEpsilon) {
        return;
      }

      if (nextQty <= _qtyEpsilon) {
        _cartItems.removeAt(index);
      } else {
        _cartItems[index] = current.copyWith(quantity: nextQty);
      }
    });
  }

  void _selectCustomer(Customer customer) {
    setState(() {
      _selectedCustomer = customer;
    });
  }

  Future<PosActionResult> _createCustomer(String name, String? phone) async {
    final String? apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      return PosActionResult(
        success: false,
        message: _tr('messages.missing_api_key_login_again'),
      );
    }

    final String normalizedName = name.trim();
    final String? normalizedPhone =
        phone != null && phone.trim().isNotEmpty ? phone.trim() : null;

    if (normalizedName.isEmpty) {
      return PosActionResult(
        success: false,
        message: _tr('messages.customer_name_required'),
      );
    }

    final Mashroo3ApiClient client = Mashroo3ApiClient(
      baseUrl: _apiBaseUrl,
      apiKey: apiKey,
    );

    try {
      final Customer created = await client.createCustomer(
        name: normalizedName,
        phone: normalizedPhone,
      );

      if (!mounted) {
        return PosActionResult(
          success: true,
          message: _tr('messages.customer_created'),
        );
      }

      setState(() {
        final int index =
            _customers.indexWhere((Customer c) => c.apiId == created.apiId);
        if (index == -1) {
          _customers = <Customer>[..._customers, created];
        } else {
          _customers[index] = created;
        }
        _selectedCustomer = created;
      });

      return PosActionResult(
        success: true,
        message: _tr(
          'messages.customer_created_selected',
          namedArgs: <String, String>{'name': created.name},
        ),
      );
    } catch (error) {
      return PosActionResult(success: false, message: _formatError(error));
    }
  }

  Future<PosActionResult> _createOrder(
    String? orderDescription,
    double paidAmount,
  ) async {
    final String? apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      return PosActionResult(
        success: false,
        message: _tr('messages.missing_api_key_login_again'),
      );
    }

    if (_cartItems.isEmpty) {
      return PosActionResult(
        success: false,
        message: _tr('messages.cart_empty'),
      );
    }

    final Customer customer = _selectedCustomer ?? _customers.first;
    final double totalAmount = _roundQty(_cartTotal, 2);
    final double normalizedPaidAmount = _roundQty(paidAmount, 2);

    if (normalizedPaidAmount < -_qtyEpsilon) {
      return PosActionResult(
        success: false,
        message: _tr('messages.paid_amount_negative'),
      );
    }

    if (normalizedPaidAmount > totalAmount + _qtyEpsilon) {
      return PosActionResult(
        success: false,
        message: _tr('messages.paid_amount_exceeds_order_total'),
      );
    }

    if (normalizedPaidAmount + _qtyEpsilon < totalAmount && customer.isWalkIn) {
      return PosActionResult(
        success: false,
        message: _tr('messages.select_customer_for_partial'),
      );
    }
    final List<OrderRequestItem> requestItems = _cartItems
        .map(
          (CartItem item) => OrderRequestItem(
            productId: item.product.id,
            quantity: _roundQty(item.quantity),
            unitCode: item.product.unitCode,
          ),
        )
        .toList(growable: false);

    final Mashroo3ApiClient client = Mashroo3ApiClient(
      baseUrl: _apiBaseUrl,
      apiKey: apiKey,
    );

    try {
      final PosOrder? createdOrder = await client.createOrder(
        customerId: customer.apiId,
        items: requestItems,
        orderDescription: orderDescription,
        paidAmount: normalizedPaidAmount,
      );

      if (!mounted) {
        return PosActionResult(
          success: true,
          message: _tr('messages.order_created'),
        );
      }

      final PosOrder fallbackOrder = PosOrder.fromCart(
        customerName: customer.isWalkIn ? _tr('customer.walk_in') : customer.name,
        items: requestItems,
        total: totalAmount,
        paid: normalizedPaidAmount,
      );

      setState(() {
        _orders = <PosOrder>[createdOrder ?? fallbackOrder, ..._orders];
        _cartItems.clear();
      });

      final int? orderId = createdOrder?.apiId;
      final PosOrder orderForFeedback = createdOrder ?? fallbackOrder;
      final double remainingBalance =
          _roundQty(orderForFeedback.remainingBalance, 2);
      final NumberFormat currency = NumberFormat.currency(
        locale: context.locale.toLanguageTag(),
        name: 'USD',
        symbol: '\$',
        decimalDigits: 2,
      );

      if (orderId != null && remainingBalance > _qtyEpsilon) {
        return PosActionResult(
          success: true,
          message: _tr(
            'messages.order_created_with_remaining',
            namedArgs: <String, String>{
              'order_id': '$orderId',
              'paid': currency.format(orderForFeedback.paid),
              'remaining': currency.format(remainingBalance),
            },
          ),
        );
      }

      if (orderId != null) {
        return PosActionResult(
          success: true,
          message: _tr(
            'messages.order_created_success_with_id',
            namedArgs: <String, String>{'order_id': '$orderId'},
          ),
        );
      }

      return PosActionResult(
        success: true,
        message: _tr('messages.order_created_success'),
      );
    } catch (error) {
      return PosActionResult(success: false, message: _formatError(error));
    }
  }

  double get _cartTotal => _cartItems.fold<double>(
        0,
        (double sum, CartItem item) => sum + item.lineTotal,
      );

  double get _todaySales {
    final DateTime now = DateTime.now();

    return _orders.fold<double>(0, (double sum, PosOrder order) {
      if (order.createdAt == null || _isSameDate(order.createdAt!, now)) {
        return sum + order.paid;
      }
      return sum;
    });
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: _tr('app.title'),
      debugShowCheckedModeBanner: false,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF155EEF),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      ),
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    if (_isLoading) {
      return const _LoadingScreen();
    }

    if (_apiKey == null || _apiKey!.isEmpty) {
      return ApiKeyScreen(onSubmit: _saveApiKey);
    }

    if (_openingCash == null) {
      return OpeningCashScreen(
        onSubmit: _startRegisterSession,
        onChangeApiKey: _logout,
      );
    }

    if (_isSessionLoading) {
      return const _SessionLoadingScreen();
    }

    if (_sessionError != null) {
      return _SessionErrorScreen(
        message: _sessionError!,
        onRetry: _loadPosData,
        onChangeApiKey: _logout,
      );
    }

    return PosScreen(
      apiKey: _apiKey!,
      openingCash: _openingCash!,
      products: _products,
      customers: _customers,
      selectedCustomer: _selectedCustomer,
      cartItems: _cartItems,
      cartTotal: _cartTotal,
      todaySales: _todaySales,
      onLogout: _logout,
      onRefreshData: _refreshPosData,
      onAddProduct: _addProductToCart,
      onBarcodeSubmit: _addProductByBarcode,
      onChangeQuantity: _changeQuantity,
      onCustomerSelected: _selectCustomer,
      onCreateCustomer: _createCustomer,
      onCreateOrder: _createOrder,
    );
  }
}

class ApiKeyScreen extends StatefulWidget {
  const ApiKeyScreen({super.key, required this.onSubmit});

  final Future<void> Function(String apiKey) onSubmit;

  @override
  State<ApiKeyScreen> createState() => _ApiKeyScreenState();
}

class _ApiKeyScreenState extends State<ApiKeyScreen> {
  final TextEditingController _apiKeyController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String value = _apiKeyController.text.trim();
    if (value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_tr('messages.api_key_required'))),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    await widget.onSubmit(value);

    if (!mounted) {
      return;
    }

    setState(() {
      _isSubmitting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _tr('api_key_screen.title'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _tr('api_key_screen.subtitle'),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _apiKeyController,
                    autofocus: true,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: _tr('api_key_screen.api_key_label'),
                      hintText: _tr('api_key_screen.api_key_hint'),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_tr('common.continue')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OpeningCashScreen extends StatefulWidget {
  const OpeningCashScreen({
    super.key,
    required this.onSubmit,
    required this.onChangeApiKey,
  });

  final Future<void> Function(double openingCash) onSubmit;
  final Future<void> Function() onChangeApiKey;

  @override
  State<OpeningCashScreen> createState() => _OpeningCashScreenState();
}

class _OpeningCashScreenState extends State<OpeningCashScreen> {
  final TextEditingController _cashController = TextEditingController();
  bool _isSubmitting = false;
  bool _isSigningOut = false;

  @override
  void dispose() {
    _cashController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String value = _cashController.text.trim().replaceAll(',', '.');
    final double? parsed = double.tryParse(value);

    if (parsed == null || parsed < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_tr('messages.enter_valid_cash_amount'))),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    await widget.onSubmit(parsed);

    if (!mounted) {
      return;
    }

    setState(() {
      _isSubmitting = false;
    });
  }

  Future<void> _signOut() async {
    setState(() {
      _isSigningOut = true;
    });

    await widget.onChangeApiKey();

    if (!mounted) {
      return;
    }

    setState(() {
      _isSigningOut = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _tr('opening_cash.title'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _tr('opening_cash.subtitle'),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _cashController,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: false,
                      decimal: true,
                    ),
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: _tr('opening_cash.label'),
                      hintText: _tr('opening_cash.hint'),
                      prefixText: '\$',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_tr('opening_cash.start_pos')),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _isSigningOut ? null : _signOut,
                      child: _isSigningOut
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_tr('common.change_api_key')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PosScreen extends StatefulWidget {
  const PosScreen({
    super.key,
    required this.apiKey,
    required this.openingCash,
    required this.products,
    required this.customers,
    required this.selectedCustomer,
    required this.cartItems,
    required this.cartTotal,
    required this.todaySales,
    required this.onLogout,
    required this.onRefreshData,
    required this.onAddProduct,
    required this.onBarcodeSubmit,
    required this.onChangeQuantity,
    required this.onCustomerSelected,
    required this.onCreateCustomer,
    required this.onCreateOrder,
  });

  final String apiKey;
  final double openingCash;
  final List<Product> products;
  final List<Customer> customers;
  final Customer? selectedCustomer;
  final List<CartItem> cartItems;
  final double cartTotal;
  final double todaySales;
  final Future<void> Function() onLogout;
  final Future<PosActionResult> Function() onRefreshData;
  final PosActionResult Function(Product product) onAddProduct;
  final PosActionResult Function(String barcode) onBarcodeSubmit;
  final void Function(Product product, double delta) onChangeQuantity;
  final void Function(Customer customer) onCustomerSelected;
  final Future<PosActionResult> Function(String name, String? phone)
      onCreateCustomer;
  final Future<PosActionResult> Function(
    String? orderDescription,
    double paidAmount,
  )
      onCreateOrder;

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final TextEditingController _barcodeController = TextEditingController();
  final FocusNode _barcodeFocusNode = FocusNode();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _orderDescriptionController =
      TextEditingController();
  final TextEditingController _paidNowController = TextEditingController();
  final Map<int, TextEditingController> _qtyControllers =
      <int, TextEditingController>{};
  final Map<int, FocusNode> _qtyFocusNodes = <int, FocusNode>{};

  bool _isSigningOut = false;
  bool _isRefreshing = false;
  bool _isCreatingCustomer = false;
  bool _isCreatingOrder = false;
  bool _allowPartialPayment = false;
  String _searchTerm = '';

  NumberFormat get _currency =>
      NumberFormat.currency(
        locale: context.locale.toLanguageTag(),
        name: 'USD',
        symbol: '\$',
        decimalDigits: 2,
      );

  @override
  void dispose() {
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    _searchController.dispose();
    _orderDescriptionController.dispose();
    _paidNowController.dispose();
    for (final TextEditingController controller in _qtyControllers.values) {
      controller.dispose();
    }
    for (final FocusNode focusNode in _qtyFocusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  void _showMessage(PosActionResult result) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success
            ? Colors.green.shade700
            : Colors.red.shade700,
      ),
    );
  }

  String _maskApiKey(String key) {
    if (key.length <= 4) {
      return '****';
    }
    return '${key.substring(0, 4)}****';
  }

  void _promptPwaInstall() {
    if (!kIsWeb) {
      _showMessage(
        PosActionResult(
          success: false,
          message: _tr('messages.pwa_install_web_only'),
        ),
      );
      return;
    }

    try {
      if (!PWAInstall().installPromptEnabled) {
        _showMessage(
          PosActionResult(
            success: false,
            message: _tr('messages.pwa_install_prompt_not_available'),
          ),
        );
        return;
      }
      PWAInstall().promptInstall_();
    } catch (error) {
      _showMessage(
        PosActionResult(
          success: false,
          message: _tr(
            'messages.pwa_install_prompt_error',
            namedArgs: <String, String>{'error': '$error'},
          ),
        ),
      );
    }
  }

  void _submitBarcode() {
    final PosActionResult result =
        widget.onBarcodeSubmit(_barcodeController.text.trim());
    _barcodeController.clear();
    _showMessage(result);
    _barcodeFocusNode.requestFocus();
  }

  Future<void> _refreshData() async {
    setState(() {
      _isRefreshing = true;
    });

    final PosActionResult result = await widget.onRefreshData();

    if (!mounted) {
      return;
    }

    setState(() {
      _isRefreshing = false;
    });

    _showMessage(result);
    _barcodeFocusNode.requestFocus();
  }

  Future<void> _createCustomerDialog() async {
    final _CustomerFormData? formData = await showDialog<_CustomerFormData>(
      context: context,
      builder: (BuildContext context) {
        return const _CreateCustomerDialog();
      },
    );

    if (!mounted || formData == null) {
      return;
    }

    setState(() {
      _isCreatingCustomer = true;
    });

    final PosActionResult result =
        await widget.onCreateCustomer(formData.name, formData.phone);

    if (!mounted) {
      return;
    }

    setState(() {
      _isCreatingCustomer = false;
    });

    _showMessage(result);
    _barcodeFocusNode.requestFocus();
  }

  Future<void> _selectCustomerDialog() async {
    final Customer? selectedCustomer = await showDialog<Customer>(
      context: context,
      builder: (BuildContext context) {
        return _CustomerSearchDialog(
          customers: widget.customers,
          selectedCustomer: widget.selectedCustomer,
        );
      },
    );

    if (!mounted || selectedCustomer == null) {
      return;
    }

    widget.onCustomerSelected(selectedCustomer);
    _barcodeFocusNode.requestFocus();
  }

  Future<void> _createOrder() async {
    final String trimmedDescription = _orderDescriptionController.text.trim();
    final double total = _roundQty(widget.cartTotal, 2);

    double paidAmount = total;
    if (_allowPartialPayment) {
      final String rawPaidNow = _paidNowController.text.trim();
      if (rawPaidNow.isEmpty) {
        _showMessage(
          PosActionResult(
            success: false,
            message: _tr('messages.enter_paid_amount_partial'),
          ),
        );
        return;
      }

      final double? parsedPaidNow = double.tryParse(rawPaidNow);
      if (parsedPaidNow == null) {
        _showMessage(
          PosActionResult(
            success: false,
            message: _tr('messages.paid_amount_invalid'),
          ),
        );
        return;
      }

      final double normalized = _roundQty(parsedPaidNow, 2);
      if (normalized < -_qtyEpsilon) {
        _showMessage(
          PosActionResult(
            success: false,
            message: _tr('messages.paid_amount_negative'),
          ),
        );
        return;
      }

      if (normalized > total + _qtyEpsilon) {
        _showMessage(
          PosActionResult(
            success: false,
            message: _tr('messages.paid_amount_exceeds_order_total'),
          ),
        );
        return;
      }

      paidAmount = normalized;
    }

    if (_allowPartialPayment &&
        _remainingAfterCheckout() > _qtyEpsilon &&
        (widget.selectedCustomer?.isWalkIn ?? true)) {
      _showMessage(
        PosActionResult(
          success: false,
          message: _tr('messages.select_customer_for_partial'),
        ),
      );
      return;
    }

    setState(() {
      _isCreatingOrder = true;
    });

    final PosActionResult result = await widget.onCreateOrder(
      trimmedDescription.isEmpty ? null : trimmedDescription,
      paidAmount,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isCreatingOrder = false;
      if (result.success) {
        _orderDescriptionController.clear();
        _paidNowController.clear();
        _allowPartialPayment = false;
      }
    });

    _showMessage(result);
    _barcodeFocusNode.requestFocus();
  }

  Future<void> _signOut() async {
    setState(() {
      _isSigningOut = true;
    });

    await widget.onLogout();

    if (!mounted) {
      return;
    }

    setState(() {
      _isSigningOut = false;
    });
  }

  List<Product> _filteredProducts() {
    if (_searchTerm.isEmpty) {
      return widget.products;
    }

    final String lower = _searchTerm.toLowerCase();
    return widget.products.where((Product product) {
      return product.name.toLowerCase().contains(lower) ||
          product.description.toLowerCase().contains(lower) ||
          product.barcode.toLowerCase().contains(lower);
    }).toList(growable: false);
  }

  double _effectivePaidNow() {
    final double total = _roundQty(widget.cartTotal, 2);
    if (!_allowPartialPayment) {
      return total;
    }

    final double? parsed = double.tryParse(_paidNowController.text.trim());
    if (parsed == null) {
      return 0;
    }

    final double normalized = _roundQty(parsed, 2);
    if (normalized < 0) {
      return 0;
    }
    if (normalized > total) {
      return total;
    }

    return normalized;
  }

  double _remainingAfterCheckout() {
    final double total = _roundQty(widget.cartTotal, 2);
    final double remaining = total - _effectivePaidNow();
    return remaining > 0 ? _roundQty(remaining, 2) : 0;
  }

  bool _isStepAligned(double value, double step) {
    if (step <= _qtyEpsilon) {
      return true;
    }
    final double scaled = value / step;
    return (scaled - scaled.roundToDouble()).abs() <= 0.001;
  }

  void _pruneQtyEditors() {
    final Set<int> validIds =
        widget.cartItems.map((CartItem item) => item.product.id).toSet();
    final List<int> staleIds = _qtyControllers.keys
        .where((int id) => !validIds.contains(id))
        .toList(growable: false);

    for (final int id in staleIds) {
      _qtyControllers.remove(id)?.dispose();
      _qtyFocusNodes.remove(id)?.dispose();
    }
  }

  TextEditingController _qtyControllerFor(CartItem item) {
    final int productId = item.product.id;
    final FocusNode focusNode = _qtyFocusNodes.putIfAbsent(
      productId,
      () => FocusNode(),
    );
    final TextEditingController controller = _qtyControllers.putIfAbsent(
      productId,
      () => TextEditingController(text: _formatQty(item.quantity)),
    );

    final String expectedValue = _formatQty(item.quantity);
    if (!focusNode.hasFocus && controller.text != expectedValue) {
      controller.text = expectedValue;
    }

    return controller;
  }

  FocusNode _qtyFocusNodeFor(int productId) {
    return _qtyFocusNodes.putIfAbsent(productId, () => FocusNode());
  }

  bool _submitTypedQuantity(
    CartItem item,
    String rawValue, {
    bool showError = true,
    bool requestMainFocus = true,
  }) {
    final int liveIndex = widget.cartItems.indexWhere(
      (CartItem current) => current.product.id == item.product.id,
    );
    if (liveIndex == -1) {
      if (requestMainFocus) {
        _barcodeFocusNode.requestFocus();
      }
      return false;
    }

    final CartItem currentItem = widget.cartItems[liveIndex];
    final Product product = currentItem.product;

    final String normalizedRaw = rawValue.trim().replaceAll(',', '.');
    if (normalizedRaw.isEmpty) {
      if (showError) {
        _showMessage(
          PosActionResult(
            success: false,
            message: _tr('messages.enter_quantity'),
          ),
        );
      }
      return false;
    }

    final double? parsed = double.tryParse(normalizedRaw);
    if (parsed == null) {
      if (showError) {
        _showMessage(
          PosActionResult(
            success: false,
            message: _tr('messages.quantity_invalid'),
          ),
        );
      }
      return false;
    }

    final double nextQty = _roundQty(parsed);
    if (nextQty < -_qtyEpsilon) {
      if (showError) {
        _showMessage(
          PosActionResult(
            success: false,
            message: _tr('messages.quantity_negative'),
          ),
        );
      }
      return false;
    }

    if (nextQty <= _qtyEpsilon) {
      widget.onChangeQuantity(product, -currentItem.quantity);
      if (requestMainFocus) {
        _barcodeFocusNode.requestFocus();
      }
      return true;
    }

    if (!product.isUnitSpecific &&
        (nextQty - nextQty.roundToDouble()).abs() > 0.001) {
      if (showError) {
        _showMessage(
          PosActionResult(
            success: false,
            message: _tr('messages.quantity_whole_number_required'),
          ),
        );
      }
      return false;
    }

    final double step = product.cartQtyStep;
    if (product.isUnitSpecific && !_isStepAligned(nextQty, step)) {
      if (showError) {
        _showMessage(
          PosActionResult(
            success: false,
            message: _tr(
              'messages.quantity_must_follow_step',
              namedArgs: <String, String>{
                'step': _formatQty(step),
                'unit': product.unitCode,
              },
            ),
          ),
        );
      }
      return false;
    }

    final double? availableQty = product.availableQty;
    if (availableQty != null && nextQty > availableQty + _qtyEpsilon) {
      if (showError) {
        _showMessage(
          PosActionResult(
            success: false,
            message: _tr(
              'messages.only_quantity_available',
              namedArgs: <String, String>{
                'available': _formatQty(availableQty),
                'unit': product.unitCode,
              },
            ),
          ),
        );
      }
      return false;
    }

    final double delta = _roundQty(nextQty - currentItem.quantity);
    if (delta.abs() <= _qtyEpsilon) {
      if (requestMainFocus) {
        _barcodeFocusNode.requestFocus();
      }
      return true;
    }

    widget.onChangeQuantity(product, delta);
    if (requestMainFocus) {
      _barcodeFocusNode.requestFocus();
    }
    return true;
  }

  void _applyStepChange(CartItem item, bool increase) {
    final TextEditingController controller = _qtyControllerFor(item);
    _submitTypedQuantity(
      item,
      controller.text,
      showError: false,
      requestMainFocus: false,
    );

    final int index = widget.cartItems
        .indexWhere((CartItem current) => current.product.id == item.product.id);
    if (index == -1) {
      _barcodeFocusNode.requestFocus();
      return;
    }

    final CartItem latest = widget.cartItems[index];
    final double step = latest.product.cartQtyStep;
    widget.onChangeQuantity(latest.product, increase ? step : -step);
    _barcodeFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final List<Product> visibleProducts = _filteredProducts();
    _pruneQtyEditors();

    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('app.title')),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Chip(
              label: Text(
                _tr(
                  'appbar.opening',
                  namedArgs: <String, String>{
                    'amount': _currency.format(widget.openingCash),
                  },
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Chip(
              label: Text(
                _tr(
                  'appbar.sales',
                  namedArgs: <String, String>{
                    'amount': _currency.format(widget.todaySales),
                  },
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Chip(
              label: Text(
                _tr(
                  'appbar.api',
                  namedArgs: <String, String>{'key': _maskApiKey(widget.apiKey)},
                ),
              ),
            ),
          ),
          PopupMenuButton<Locale>(
            tooltip: _tr('lang.switch'),
            icon: const Icon(Icons.language),
            onSelected: (Locale locale) {
              context.setLocale(locale);
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<Locale>>[
              PopupMenuItem<Locale>(
                value: const Locale('en'),
                child: Text(_tr('lang.english')),
              ),
              PopupMenuItem<Locale>(
                value: const Locale('ar'),
                child: Text(_tr('lang.arabic')),
              ),
            ],
          ),
          if (kIsWeb)
            IconButton(
              tooltip: _tr('appbar.install_app'),
              onPressed: _promptPwaInstall,
              icon: const Icon(Icons.download_for_offline),
            ),
          IconButton(
            tooltip: _tr('appbar.refresh'),
            onPressed: _isRefreshing ? null : _refreshData,
            icon: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: TextButton.icon(
              onPressed: _isSigningOut ? null : _signOut,
              icon: const Icon(Icons.logout),
              label: Text(_tr('appbar.logout')),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          if (constraints.maxWidth < 900) {
            return const _SmallScreenNotice();
          }

          final int crossAxisCount = constraints.maxWidth >= 1500
              ? 4
              : constraints.maxWidth >= 1200
                  ? 3
                  : 2;

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                Expanded(
                  flex: 3,
                  child: Column(
                    children: <Widget>[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: TextField(
                                      controller: _barcodeController,
                                      focusNode: _barcodeFocusNode,
                                      autofocus: true,
                                      onSubmitted: (_) => _submitBarcode(),
                                      decoration: InputDecoration(
                                        border: OutlineInputBorder(),
                                        labelText: _tr('barcode.input_label'),
                                        hintText: _tr('barcode.input_hint'),
                                        prefixIcon: Icon(Icons.qr_code_scanner),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  FilledButton.icon(
                                    onPressed: _submitBarcode,
                                    icon: const Icon(Icons.add_shopping_cart),
                                    label: Text(_tr('barcode.add_button')),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _searchController,
                                onChanged: (String value) {
                                  setState(() {
                                    _searchTerm = value.trim();
                                  });
                                },
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(),
                                  labelText: _tr('search.products_label'),
                                  prefixIcon: Icon(Icons.search),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: visibleProducts.isEmpty
                            ? Card(
                                child: Center(
                                  child: Text(
                                    widget.products.isEmpty
                                        ? _tr('products.none_from_api')
                                        : _tr('products.none_search'),
                                  ),
                                ),
                              )
                            : GridView.builder(
                                itemCount: visibleProducts.length,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 0.82,
                                ),
                                itemBuilder: (BuildContext context, int index) {
                                  final Product product = visibleProducts[index];
                                  return _ProductCard(
                                    product: product,
                                    currency: _currency,
                                    onAdd: () {
                                      final PosActionResult result =
                                          widget.onAddProduct(product);
                                      if (!result.success) {
                                        _showMessage(result);
                                      }
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: Column(
                    children: <Widget>[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                _tr('customer.section_title'),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        alignment: Alignment.centerLeft,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 16,
                                        ),
                                      ),
                                      onPressed: _selectCustomerDialog,
                                      icon: const Icon(Icons.search),
                                      label: Text(
                                        widget.selectedCustomer?.displayLabel ??
                                            _tr('customer.walk_in'),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    onPressed: _isCreatingCustomer
                                        ? null
                                        : _createCustomerDialog,
                                    icon: _isCreatingCustomer
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.person_add_alt),
                                    label: Text(_tr('customer.new_button')),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _orderDescriptionController,
                                minLines: 2,
                                maxLines: 4,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(),
                                  labelText: _tr('order.description_label'),
                                  hintText: _tr('order.description_hint'),
                                  prefixIcon: Icon(Icons.notes_outlined),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Card(
                          child: widget.cartItems.isEmpty
                              ? Center(
                                  child: Text(_tr('cart.empty')),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.all(8),
                                  itemCount: widget.cartItems.length,
                                  separatorBuilder:
                                      (BuildContext context, int index) {
                                    return const Divider(height: 1);
                                  },
                                  itemBuilder:
                                      (BuildContext context, int index) {
                                    final CartItem item = widget.cartItems[index];
                                    final TextEditingController qtyController =
                                        _qtyControllerFor(item);
                                    final FocusNode qtyFocusNode =
                                        _qtyFocusNodeFor(item.product.id);
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 6,
                                      ),
                                      child: Row(
                                        children: <Widget>[
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: <Widget>[
                                                Text(
                                                  item.product.name,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleSmall,
                                                ),
                                                Text(
                                                  item.product.isUnitSpecific
                                                      ? '${_currency.format(item.product.price)} / ${item.product.unitCode}'
                                                      : _currency.format(item.product.price),
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall,
                                                ),
                                                if (item.product.barcode
                                                    .isNotEmpty)
                                                  Text(
                                                    _tr(
                                                      'product.barcode',
                                                      namedArgs: <String, String>{
                                                        'barcode':
                                                            item.product.barcode,
                                                      },
                                                    ),
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall,
                                                  ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            onPressed: () =>
                                                _applyStepChange(item, false),
                                            icon: const Icon(
                                              Icons.remove_circle_outline,
                                            ),
                                          ),
                                          SizedBox(
                                            width: 148,
                                            child: TextField(
                                              controller: qtyController,
                                              focusNode: qtyFocusNode,
                                              textAlign: TextAlign.center,
                                              textInputAction:
                                                  TextInputAction.done,
                                              keyboardType:
                                                  const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                              decoration: InputDecoration(
                                                isDense: true,
                                                border:
                                                    const OutlineInputBorder(),
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 10,
                                                ),
                                                suffixText:
                                                    item.product.unitCode,
                                              ),
                                              onSubmitted:
                                                  (String value) {
                                                _submitTypedQuantity(
                                                  item,
                                                  value,
                                                );
                                              },
                                              onEditingComplete: () {
                                                _submitTypedQuantity(
                                                  item,
                                                  qtyController.text,
                                                );
                                              },
                                              onTapOutside:
                                                  (PointerDownEvent event) {
                                                _submitTypedQuantity(
                                                  item,
                                                  qtyController.text,
                                                );
                                              },
                                            ),
                                          ),
                                          IconButton(
                                            onPressed: () =>
                                                _applyStepChange(item, true),
                                            icon: const Icon(
                                              Icons.add_circle_outline,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip:
                                                _tr('cart.remove_item_tooltip'),
                                            onPressed: () =>
                                                widget.onChangeQuantity(
                                              item.product,
                                              -item.quantity,
                                            ),
                                            color: Colors.red.shade700,
                                            icon: const Icon(
                                              Icons.shopping_basket_outlined,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          SizedBox(
                                            width: 90,
                                            child: Text(
                                              _currency.format(item.lineTotal),
                                              textAlign: TextAlign.end,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            children: <Widget>[
                              _SummaryRow(
                                label: _tr('cart.lines'),
                                value: widget.cartItems.length.toString(),
                              ),
                              _SummaryRow(
                                label: _tr('cart.subtotal'),
                                value: _currency.format(widget.cartTotal),
                              ),
                              const Divider(height: 20),
                              _SummaryRow(
                                label: _tr('cart.total'),
                                value: _currency.format(widget.cartTotal),
                                isTotal: true,
                              ),
                              const SizedBox(height: 8),
                              SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                title: Text(_tr('payment.partial_title')),
                                subtitle: Text(
                                  _tr('payment.partial_subtitle'),
                                ),
                                value: _allowPartialPayment,
                                onChanged: widget.cartItems.isEmpty
                                    ? null
                                    : (bool value) {
                                        setState(() {
                                          _allowPartialPayment = value;
                                          _paidNowController.clear();
                                        });
                                      },
                              ),
                              if (_allowPartialPayment)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: TextField(
                                    controller: _paidNowController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    onChanged: (_) => setState(() {}),
                                    decoration: InputDecoration(
                                      border: OutlineInputBorder(),
                                      labelText: _tr('payment.paid_now_label'),
                                      hintText: _tr('payment.paid_now_hint'),
                                      prefixIcon: Icon(Icons.payments_outlined),
                                    ),
                                  ),
                                ),
                              _SummaryRow(
                                label: _tr('payment.paid_now'),
                                value: _currency.format(_effectivePaidNow()),
                              ),
                              _SummaryRow(
                                label: _tr('payment.remaining'),
                                value: _currency.format(_remainingAfterCheckout()),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed:
                                      _isCreatingOrder ? null : _createOrder,
                                  icon: _isCreatingOrder
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.receipt_long),
                                  label: Text(
                                    _isCreatingOrder
                                        ? _tr('order.creating')
                                        : _tr('order.create_button'),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CustomerSearchDialog extends StatefulWidget {
  const _CustomerSearchDialog({
    required this.customers,
    required this.selectedCustomer,
  });

  final List<Customer> customers;
  final Customer? selectedCustomer;

  @override
  State<_CustomerSearchDialog> createState() => _CustomerSearchDialogState();
}

class _CustomerSearchDialogState extends State<_CustomerSearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _searchTerm = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Customer> _filteredCustomers() {
    if (_searchTerm.isEmpty) {
      return widget.customers;
    }

    final String lower = _searchTerm.toLowerCase();
    return widget.customers.where((Customer customer) {
      return customer.name.toLowerCase().contains(lower) ||
          (customer.phone ?? '').toLowerCase().contains(lower);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final List<Customer> visibleCustomers = _filteredCustomers();

    return AlertDialog(
      title: Text(_tr('dialogs.select_customer_title')),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: (String value) {
                setState(() {
                  _searchTerm = value.trim();
                });
              },
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                labelText: _tr('dialogs.search_customers_label'),
                hintText: _tr('dialogs.search_customers_hint'),
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 320,
              child: visibleCustomers.isEmpty
                  ? Center(
                      child: Text(_tr('dialogs.no_customers_found')),
                    )
                  : ListView.separated(
                      itemCount: visibleCustomers.length,
                      separatorBuilder: (BuildContext context, int index) {
                        return const Divider(height: 1);
                      },
                      itemBuilder: (BuildContext context, int index) {
                        final Customer customer = visibleCustomers[index];
                        final bool isSelected =
                            customer.apiId == widget.selectedCustomer?.apiId;

                        return ListTile(
                          onTap: () => Navigator.of(context).pop(customer),
                          leading: Icon(
                            customer.isWalkIn
                                ? Icons.storefront_outlined
                                : Icons.person_outline,
                          ),
                          title: Text(customer.name),
                          subtitle: Text(
                            customer.phone?.isNotEmpty == true
                                ? customer.phone!
                                : customer.isWalkIn
                                    ? _tr('dialogs.no_linked_profile')
                                    : _tr('dialogs.no_phone'),
                          ),
                          trailing: isSelected
                              ? Icon(
                                  Icons.check_circle,
                                  color: Theme.of(context).colorScheme.primary,
                                )
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_tr('common.cancel')),
        ),
      ],
    );
  }
}

class _CreateCustomerDialog extends StatefulWidget {
  const _CreateCustomerDialog();

  @override
  State<_CreateCustomerDialog> createState() => _CreateCustomerDialogState();
}

class _CreateCustomerDialogState extends State<_CreateCustomerDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _submit() {
    final String name = _nameController.text.trim();
    final String phone = _phoneController.text.trim();

    if (name.isEmpty) {
      setState(() {
        _error = _tr('messages.customer_name_required');
      });
      return;
    }

    Navigator.of(context).pop(
      _CustomerFormData(
        name: name,
        phone: phone.isEmpty ? null : phone,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_tr('dialogs.create_customer_title')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _nameController,
              autofocus: true,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: _tr('dialogs.full_name_label'),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: _tr('dialogs.phone_optional_label'),
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_tr('common.cancel')),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(_tr('common.create')),
        ),
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.currency,
    required this.onAdd,
  });

  final Product product;
  final NumberFormat currency;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final bool outOfStock =
        product.availableQty != null && product.availableQty! <= _qtyEpsilon;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _ProductImage(product: product),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    product.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (product.barcode.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      _tr(
                        'product.barcode',
                        namedArgs: <String, String>{'barcode': product.barcode},
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 6),
                  if (product.availableQty != null)
                    Text(
                      _tr(
                        'product.available',
                        namedArgs: <String, String>{
                          'qty': _formatQty(product.availableQty!),
                          'unit': product.unitCode,
                        },
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const Spacer(),
                  Text(
                    product.isUnitSpecific
                        ? '${currency.format(product.price)} / ${product.unitCode}'
                        : currency.format(product.price),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: outOfStock ? null : onAdd,
                      icon: const Icon(Icons.add),
                      label: Text(
                        outOfStock
                            ? _tr('product.out_of_stock')
                            : _tr('product.add_to_order'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final String? imageUrl = product.imageUrl;

    if (imageUrl == null || imageUrl.isEmpty) {
      return Container(
        color: Colors.grey.shade200,
        child: const Icon(Icons.inventory_2_outlined),
      );
    }

    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      errorBuilder: (
        BuildContext context,
        Object error,
        StackTrace? stackTrace,
      ) {
        return Container(
          color: Colors.grey.shade200,
          child: const Icon(Icons.image_not_supported),
        );
      },
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.isTotal = false,
  });

  final String label;
  final String value;
  final bool isTotal;

  @override
  Widget build(BuildContext context) {
    final TextStyle? style = isTotal
        ? Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold)
        : Theme.of(context).textTheme.bodyLarge;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _SmallScreenNotice extends StatelessWidget {
  const _SmallScreenNotice();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.tablet_mac, size: 56),
                  const SizedBox(height: 16),
                  Text(
                    _tr('small_screen.title'),
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _tr('small_screen.subtitle'),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _SessionLoadingScreen extends StatelessWidget {
  const _SessionLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(_tr('session.loading_data')),
          ],
        ),
      ),
    );
  }
}

class _SessionErrorScreen extends StatefulWidget {
  const _SessionErrorScreen({
    required this.message,
    required this.onRetry,
    required this.onChangeApiKey,
  });

  final String message;
  final Future<void> Function() onRetry;
  final Future<void> Function() onChangeApiKey;

  @override
  State<_SessionErrorScreen> createState() => _SessionErrorScreenState();
}

class _SessionErrorScreenState extends State<_SessionErrorScreen> {
  bool _isRetrying = false;
  bool _isSigningOut = false;

  Future<void> _retry() async {
    setState(() {
      _isRetrying = true;
    });

    await widget.onRetry();

    if (!mounted) {
      return;
    }

    setState(() {
      _isRetrying = false;
    });
  }

  Future<void> _changeApiKey() async {
    setState(() {
      _isSigningOut = true;
    });

    await widget.onChangeApiKey();

    if (!mounted) {
      return;
    }

    setState(() {
      _isSigningOut = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _tr('session.error_title'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(widget.message),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isRetrying ? null : _retry,
                      icon: _isRetrying
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: Text(_tr('common.retry')),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _isSigningOut ? null : _changeApiKey,
                      child: _isSigningOut
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_tr('common.change_api_key')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

@immutable
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.barcode,
    required this.imageUrl,
    required this.isUnitSpecific,
    required this.sellUnitCode,
    required this.sellQtyStep,
    required this.availableQty,
  });

  final int id;
  final String name;
  final String description;
  final double price;
  final String barcode;
  final String? imageUrl;
  final bool isUnitSpecific;
  final String sellUnitCode;
  final double sellQtyStep;
  final double? availableQty;

  String get unitCode => sellUnitCode.trim().isEmpty ? 'pcs' : sellUnitCode;

  double get cartQtyStep {
    if (!isUnitSpecific) return 1;
    return sellQtyStep > 0 ? _roundQty(sellQtyStep) : 1;
  }

  factory Product.fromJson(Map<String, dynamic> json, {required String baseUrl}) {
    final int? id = _toInt(json['id']);
    if (id == null) {
      throw FormatException(_tr('errors.product_id_missing'));
    }

    final String name =
        _toString(json['name']) ?? _toString(json['title']) ?? '${_tr('fallback.product')} $id';
    final String description = _toString(json['description']) ??
        _toString(json['details']) ??
        _toString(json['summary']) ??
        _tr('fallback.no_description');

    final double price = _toDouble(json['price']) ?? 0;
    final String barcode = (_toString(json['barcode']) ??
            _toString(json['sku']) ??
            _toString(json['code']) ??
            '')
        .trim();

    final String? imageUrl = _normalizeImageUrl(
      json['image_url'] ?? json['image'] ?? json['photo_url'] ?? json['photo'],
      baseUrl,
    );

    final bool isUnitSpecific = json['is_unit_specific'] == true;
    final String sellUnitCode = _toString(json['sell_unit_code']) ?? 'pcs';
    final double sellQtyStep = _toDouble(json['sell_qty_step']) ?? 1;
    final double? availableQty = _toDouble(
      json['available_qty'] ?? json['quantity'] ?? json['stock'],
    );

    return Product(
      id: id,
      name: name,
      description: description,
      price: price,
      barcode: barcode,
      imageUrl: imageUrl,
      isUnitSpecific: isUnitSpecific,
      sellUnitCode: sellUnitCode,
      sellQtyStep: sellQtyStep,
      availableQty: availableQty,
    );
  }
}

@immutable
class Customer {
  const Customer({
    required this.apiId,
    required this.name,
    this.phone,
  });

  const Customer.walkIn()
      : apiId = null,
        name = '',
        phone = null;

  final int? apiId;
  final String name;
  final String? phone;

  bool get isWalkIn => apiId == null;

  String get displayLabel {
    if (isWalkIn) {
      return _tr('customer.walk_in');
    }
    if (phone == null || phone!.isEmpty) {
      return name;
    }
    return '$name (${phone!})';
  }

  factory Customer.fromJson(Map<String, dynamic> json) {
    final int? id = _toInt(json['id']);
    if (id == null) {
      throw FormatException(_tr('errors.customer_id_missing'));
    }

    return Customer(
      apiId: id,
      name: _toString(json['name']) ??
          _toString(json['company']) ??
          '${_tr('fallback.customer')} $id',
      phone: _toString(json['phone']),
    );
  }
}

@immutable
class CartItem {
  const CartItem({
    required this.product,
    required this.quantity,
  });

  final Product product;
  final double quantity;

  double get lineTotal => product.price * quantity;

  CartItem copyWith({double? quantity}) {
    return CartItem(
      product: product,
      quantity: quantity ?? this.quantity,
    );
  }
}

@immutable
class OrderRequestItem {
  const OrderRequestItem({
    required this.productId,
    required this.quantity,
    this.unitCode = 'pcs',
  });

  final int productId;
  final double quantity;
  final String unitCode;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'product_id': productId,
      'qty': _roundQty(quantity),
    };
  }
}

@immutable
class PosOrderItem {
  const PosOrderItem({
    required this.productId,
    required this.quantity,
    required this.price,
    required this.unitCode,
  });

  final int productId;
  final double quantity;
  final double price;
  final String unitCode;

  double get lineTotal => price * quantity;

  factory PosOrderItem.fromJson(Map<String, dynamic> json) {
    return PosOrderItem(
      productId: _toInt(json['product_id'] ?? json['id']) ?? 0,
      quantity: _toDouble(json['qty'] ?? json['quantity']) ?? 0,
      price: _toDouble(json['price']) ?? 0,
      unitCode: _toString(json['unit_code']) ?? 'pcs',
    );
  }

  factory PosOrderItem.fromRequestItem(OrderRequestItem item, {double? price}) {
    return PosOrderItem(
      productId: item.productId,
      quantity: item.quantity,
      price: price ?? 0,
      unitCode: item.unitCode,
    );
  }
}

@immutable
class PosOrder {
  const PosOrder({
    required this.apiId,
    required this.createdAt,
    required this.customerName,
    required this.total,
    required this.paid,
    required this.items,
  });

  final int? apiId;
  final DateTime? createdAt;
  final String? customerName;
  final double total;
  final double paid;
  final List<PosOrderItem> items;

  double get remainingBalance {
    final double remaining = total - paid;
    return remaining > 0 ? remaining : 0;
  }

  bool get isFullyPaid => remainingBalance <= _qtyEpsilon;

  factory PosOrder.fromJson(
    Map<String, dynamic> json, {
    List<dynamic>? fallbackItems,
  }) {
    final dynamic rawItems =
        json['order_items'] ?? json['items'] ?? fallbackItems ?? const <dynamic>[];

    final List<PosOrderItem> parsedItems = <PosOrderItem>[];
    if (rawItems is List) {
      for (final dynamic item in rawItems) {
        if (item is Map<String, dynamic>) {
          parsedItems.add(PosOrderItem.fromJson(item));
        } else if (item is Map) {
          parsedItems.add(
            PosOrderItem.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    final double total = _toDouble(json['total']) ??
        parsedItems.fold<double>(
          0,
          (double sum, PosOrderItem item) => sum + item.lineTotal,
        );
    final double paid = _toDouble(json['paid'] ?? json['paid_amount']) ?? total;

    String? customerName;
    final dynamic customerNode = json['customer'];
    if (customerNode is Map<String, dynamic>) {
      customerName = _toString(customerNode['name']);
    } else if (customerNode is Map) {
      customerName = _toString(customerNode['name']);
    }

    customerName ??= _toString(json['customer_name']);

    return PosOrder(
      apiId: _toInt(json['id']),
      createdAt: _toDateTime(json['created_at'] ?? json['date']),
      customerName: customerName,
      total: total,
      paid: paid,
      items: parsedItems,
    );
  }

  factory PosOrder.fromCart({
    required String customerName,
    required List<OrderRequestItem> items,
    required double total,
    required double paid,
  }) {
    return PosOrder(
      apiId: null,
      createdAt: DateTime.now(),
      customerName: customerName,
      total: total,
      paid: paid,
      items: items
          .map((OrderRequestItem item) => PosOrderItem.fromRequestItem(item))
          .toList(growable: false),
    );
  }
}

@immutable
class PosActionResult {
  const PosActionResult({required this.success, required this.message});

  final bool success;
  final String message;
}

@immutable
class _CustomerFormData {
  const _CustomerFormData({required this.name, this.phone});

  final String name;
  final String? phone;
}

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class Mashroo3ApiClient {
  Mashroo3ApiClient({
    required String baseUrl,
    required this.apiKey,
    http.Client? httpClient,
  })  : baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _httpClient = httpClient ?? http.Client();

  final String baseUrl;
  final String apiKey;
  final http.Client _httpClient;

  Future<List<Product>> fetchCatalog() async {
    final dynamic response = await _request('GET', '/api/catalog');
    final List<dynamic> rows = _extractList(
      response,
      listKeys: const <String>['products', 'catalog'],
    );

    final List<Product> products = <Product>[];
    for (final dynamic row in rows) {
      if (row is Map<String, dynamic>) {
        try {
          products.add(Product.fromJson(row, baseUrl: baseUrl));
        } catch (_) {
          continue;
        }
      } else if (row is Map) {
        try {
          products.add(
            Product.fromJson(Map<String, dynamic>.from(row), baseUrl: baseUrl),
          );
        } catch (_) {
          continue;
        }
      }
    }

    return products;
  }

  Future<List<Customer>> fetchCustomers() async {
    final dynamic response = await _request('GET', '/api/customers');
    final List<dynamic> rows =
        _extractList(response, listKeys: const <String>['customers']);

    final List<Customer> customers = <Customer>[];
    for (final dynamic row in rows) {
      if (row is Map<String, dynamic>) {
        try {
          customers.add(Customer.fromJson(row));
        } catch (_) {
          continue;
        }
      } else if (row is Map) {
        try {
          customers.add(Customer.fromJson(Map<String, dynamic>.from(row)));
        } catch (_) {
          continue;
        }
      }
    }

    return customers;
  }

  Future<Customer> createCustomer({
    required String name,
    String? phone,
    String? email,
    String? address,
    String? company,
  }) async {
    final Map<String, dynamic> payload = <String, dynamic>{'name': name};
    if (phone != null && phone.isNotEmpty) {
      payload['phone'] = phone;
    }
    if (email != null && email.isNotEmpty) {
      payload['email'] = email;
    }
    if (address != null && address.isNotEmpty) {
      payload['address'] = address;
    }
    if (company != null && company.isNotEmpty) {
      payload['company'] = company;
    }

    final dynamic response =
        await _request('POST', '/api/customers', body: payload);

    final dynamic dataNode = _extractDataNode(response);

    Map<String, dynamic>? customerMap;
    if (dataNode is Map<String, dynamic>) {
      final dynamic nested = dataNode['customer'];
      if (nested is Map<String, dynamic>) {
        customerMap = nested;
      } else if (nested is Map) {
        customerMap = Map<String, dynamic>.from(nested);
      } else {
        customerMap = dataNode;
      }
    } else if (dataNode is Map) {
      customerMap = Map<String, dynamic>.from(dataNode);
    }

    if (customerMap == null) {
      throw ApiException(_tr('errors.unexpected_create_customer_response'));
    }

    return Customer.fromJson(customerMap);
  }

  Future<List<PosOrder>> fetchOrders() async {
    final dynamic response = await _request('GET', '/api/orders');
    final List<dynamic> rows =
        _extractList(response, listKeys: const <String>['orders']);

    final List<PosOrder> orders = <PosOrder>[];
    for (final dynamic row in rows) {
      if (row is Map<String, dynamic>) {
        orders.add(PosOrder.fromJson(row));
      } else if (row is Map) {
        orders.add(PosOrder.fromJson(Map<String, dynamic>.from(row)));
      }
    }

    return orders;
  }

  Future<PosOrder?> createOrder({
    required List<OrderRequestItem> items,
    int? customerId,
    String? orderDescription,
    double? paidAmount,
  }) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'items': items
          .map((OrderRequestItem item) => item.toJson())
          .toList(growable: false),
    };

    if (customerId != null) {
      payload['customer_id'] = customerId;
    }
    if (orderDescription != null && orderDescription.trim().isNotEmpty) {
      payload['order_description'] = orderDescription.trim();
    }
    if (paidAmount != null) {
      payload['paid'] = _roundQty(paidAmount, 2);
    }

    final dynamic response =
        await _request('POST', '/api/orders', body: payload);
    final dynamic dataNode = _extractDataNode(response);

    Map<String, dynamic>? orderMap;
    List<dynamic>? rawItems;

    if (dataNode is Map<String, dynamic>) {
      final dynamic nestedOrder = dataNode['order'];
      if (nestedOrder is Map<String, dynamic>) {
        orderMap = nestedOrder;
        final dynamic nestedItems = dataNode['items'] ?? dataNode['order_items'];
        if (nestedItems is List) {
          rawItems = nestedItems;
        }
      } else if (nestedOrder is Map) {
        orderMap = Map<String, dynamic>.from(nestedOrder);
        final dynamic nestedItems = dataNode['items'] ?? dataNode['order_items'];
        if (nestedItems is List) {
          rawItems = nestedItems;
        }
      } else {
        orderMap = dataNode;
        final dynamic nestedItems = dataNode['items'] ?? dataNode['order_items'];
        if (nestedItems is List) {
          rawItems = nestedItems;
        }
      }
    } else if (dataNode is Map) {
      orderMap = Map<String, dynamic>.from(dataNode);
      final dynamic nestedItems = dataNode['items'] ?? dataNode['order_items'];
      if (nestedItems is List) {
        rawItems = nestedItems;
      }
    }

    if (orderMap == null) {
      return null;
    }

    return PosOrder.fromJson(orderMap, fallbackItems: rawItems);
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final Uri uri = Uri.parse('$baseUrl${path.startsWith('/') ? path : '/$path'}');

    try {
      late final http.Response response;

      switch (method) {
        case 'GET':
          response = await _httpClient.get(uri, headers: _headers);
          break;
        case 'POST':
          response = await _httpClient.post(
            uri,
            headers: _headers,
            body: body == null ? null : jsonEncode(body),
          );
          break;
        default:
          throw ApiException(
            _tr(
              'errors.unsupported_method',
              namedArgs: <String, String>{'method': method},
            ),
          );
      }

      dynamic decoded;
      if (response.body.isNotEmpty) {
        try {
          decoded = jsonDecode(response.body);
        } catch (_) {
          decoded = null;
        }
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          _extractErrorMessage(decoded) ??
              _tr(
                'errors.request_failed_status',
                namedArgs: <String, String>{
                  'status': '${response.statusCode}',
                },
              ),
          statusCode: response.statusCode,
        );
      }

      if (decoded is Map<String, dynamic> && decoded['ok'] == false) {
        throw ApiException(
          _extractErrorMessage(decoded) ??
              _tr(
                'errors.api_returned_ok_false',
                namedArgs: <String, String>{
                  'method': method,
                  'path': path,
                },
              ),
          statusCode: response.statusCode,
        );
      }

      return decoded;
    } catch (error) {
      if (error is ApiException) {
        rethrow;
      }

      throw ApiException(
        _tr(
          'errors.network_error_calling',
          namedArgs: <String, String>{
            'path': path,
            'error': '$error',
          },
        ),
      );
    }
  }

  Map<String, String> get _headers {
    return <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
      'X-API-Key': apiKey,
      'x-api-key': apiKey,
    };
  }

  dynamic _extractDataNode(dynamic response) {
    if (response is Map<String, dynamic>) {
      if (response.containsKey('data')) {
        return response['data'];
      }
      return response;
    }

    if (response is Map) {
      final Map<String, dynamic> map = Map<String, dynamic>.from(response);
      if (map.containsKey('data')) {
        return map['data'];
      }
      return map;
    }

    return response;
  }

  List<dynamic> _extractList(
    dynamic response, {
    List<String> listKeys = const <String>[],
  }) {
    final dynamic dataNode = _extractDataNode(response);

    if (dataNode is List) {
      return dataNode;
    }

    if (dataNode is Map<String, dynamic>) {
      for (final String key in listKeys) {
        final dynamic candidate = dataNode[key];
        if (candidate is List) {
          return candidate;
        }
      }

      final dynamic items = dataNode['items'];
      if (items is List) {
        return items;
      }
    }

    if (dataNode is Map) {
      final Map<String, dynamic> map = Map<String, dynamic>.from(dataNode);
      for (final String key in listKeys) {
        final dynamic candidate = map[key];
        if (candidate is List) {
          return candidate;
        }
      }

      final dynamic items = map['items'];
      if (items is List) {
        return items;
      }
    }

    return const <dynamic>[];
  }

  String? _extractErrorMessage(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      final dynamic message =
          decoded['message'] ?? decoded['error'] ?? decoded['errors'];
      if (message is String && message.trim().isNotEmpty) {
        return message;
      }
      if (message is List && message.isNotEmpty) {
        return message.first.toString();
      }
      if (message is Map && message.isNotEmpty) {
        return message.values.first.toString();
      }
    }

    if (decoded is Map) {
      final Map<String, dynamic> map = Map<String, dynamic>.from(decoded);
      final dynamic message = map['message'] ?? map['error'] ?? map['errors'];
      if (message is String && message.trim().isNotEmpty) {
        return message;
      }
      if (message is List && message.isNotEmpty) {
        return message.first.toString();
      }
      if (message is Map && message.isNotEmpty) {
        return message.values.first.toString();
      }
    }

    return null;
  }
}

int? _toInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is double) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

double? _toDouble(dynamic value) {
  if (value is double) {
    return value;
  }
  if (value is int) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.trim());
  }
  return null;
}

String? _toString(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  return value.toString();
}

DateTime? _toDateTime(dynamic value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  return null;
}

String? _normalizeImageUrl(dynamic value, String baseUrl) {
  final String? raw = _toString(value);
  if (raw == null || raw.isEmpty) {
    return null;
  }

  if (raw.startsWith('http://') || raw.startsWith('https://')) {
    return raw;
  }

  if (raw.startsWith('/')) {
    return '$baseUrl$raw';
  }

  return '$baseUrl/$raw';
}
