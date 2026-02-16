import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _apiKeyStorageKey = 'pos_api_key';
const String _apiBaseUrl = 'https://mashroo3.net';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PosApp());
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
      return const PosActionResult(
        success: false,
        message: 'Data sync is already in progress!',
      );
    }

    await _loadPosData();

    if (_sessionError != null) {
      return PosActionResult(success: false, message: _sessionError!);
    }

    return const PosActionResult(
      success: true,
      message: 'Catalog and customers synced.',
    );
  }

  String _formatError(Object error) {
    if (error is ApiException) {
      return error.message;
    }

    return 'Unexpected error: $error';
  }

  PosActionResult _addProductToCart(Product product) {
    final int existingIndex =
        _cartItems.indexWhere((CartItem item) => item.product.id == product.id);
    final int existingQty =
        existingIndex == -1 ? 0 : _cartItems[existingIndex].quantity;

    final int? availableQty = product.availableQty;
    if (availableQty != null && existingQty >= availableQty) {
      return PosActionResult(
        success: false,
        message: 'No more stock available for ${product.name}.',
      );
    }

    setState(() {
      if (existingIndex == -1) {
        _cartItems.add(CartItem(product: product, quantity: 1));
      } else {
        final CartItem existing = _cartItems[existingIndex];
        _cartItems[existingIndex] =
            existing.copyWith(quantity: existing.quantity + 1);
      }
    });

    return PosActionResult(success: true, message: '${product.name} added.');
  }

  PosActionResult _addProductByBarcode(String rawBarcode) {
    final String barcode = rawBarcode.trim();
    if (barcode.isEmpty) {
      return const PosActionResult(
        success: false,
        message: 'Enter a barcode first.',
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
        message: 'No product found for barcode $barcode.',
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

  void _changeQuantity(Product product, int delta) {
    final int index =
        _cartItems.indexWhere((CartItem item) => item.product.id == product.id);

    if (index == -1) {
      return;
    }

    setState(() {
      final CartItem current = _cartItems[index];
      final int nextQty = current.quantity + delta;

      if (product.availableQty != null && nextQty > product.availableQty!) {
        return;
      }

      if (nextQty <= 0) {
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
      return const PosActionResult(
        success: false,
        message: 'Missing API key. Please log in again.',
      );
    }

    final String normalizedName = name.trim();
    final String? normalizedPhone =
        phone != null && phone.trim().isNotEmpty ? phone.trim() : null;

    if (normalizedName.isEmpty) {
      return const PosActionResult(
        success: false,
        message: 'Customer name is required.',
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
        return const PosActionResult(
          success: true,
          message: 'Customer created.',
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
        message: '${created.name} created and selected.',
      );
    } catch (error) {
      return PosActionResult(success: false, message: _formatError(error));
    }
  }

  Future<PosActionResult> _createOrder() async {
    final String? apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      return const PosActionResult(
        success: false,
        message: 'Missing API key. Please log in again.',
      );
    }

    if (_cartItems.isEmpty) {
      return const PosActionResult(
        success: false,
        message: 'Cart is empty.',
      );
    }

    final Customer customer = _selectedCustomer ?? _customers.first;
    final List<OrderRequestItem> requestItems = _cartItems
        .map(
          (CartItem item) =>
              OrderRequestItem(productId: item.product.id, quantity: item.quantity),
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
      );

      if (!mounted) {
        return const PosActionResult(
          success: true,
          message: 'Order created.',
        );
      }

      final PosOrder fallbackOrder = PosOrder.fromCart(
        customerName: customer.name,
        items: requestItems,
        total: _cartTotal,
      );

      setState(() {
        _orders = <PosOrder>[createdOrder ?? fallbackOrder, ..._orders];
        _cartItems.clear();
      });

      final int? orderId = createdOrder?.apiId;
      if (orderId != null) {
        return PosActionResult(
          success: true,
          message: 'Order #$orderId created successfully.',
        );
      }

      return const PosActionResult(
        success: true,
        message: 'Order created successfully.',
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
        return sum + order.total;
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
      title: 'Mashroo3 POS',
      debugShowCheckedModeBanner: false,
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
        const SnackBar(content: Text('API key is required.')),
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
                    'POS Activation',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Enter your API key to connect with Mashroo3 API.',
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _apiKeyController,
                    autofocus: true,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: 'API key',
                      hintText: 'Paste API key here',
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
                          : const Text('Continue'),
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
        const SnackBar(content: Text('Enter a valid cash amount.')),
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
                    'Open Register',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Enter the opening cash amount currently in the register.',
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
                    decoration: const InputDecoration(
                      labelText: 'Opening cash',
                      hintText: '0.00',
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
                          : const Text('Start POS'),
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
                          : const Text('Change API key'),
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
  final void Function(Product product, int delta) onChangeQuantity;
  final void Function(Customer customer) onCustomerSelected;
  final Future<PosActionResult> Function(String name, String? phone)
      onCreateCustomer;
  final Future<PosActionResult> Function() onCreateOrder;

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final TextEditingController _barcodeController = TextEditingController();
  final FocusNode _barcodeFocusNode = FocusNode();
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _currency = NumberFormat.simpleCurrency();

  bool _isSigningOut = false;
  bool _isRefreshing = false;
  bool _isCreatingCustomer = false;
  bool _isCreatingOrder = false;
  String _searchTerm = '';

  @override
  void dispose() {
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    _searchController.dispose();
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

  Future<void> _createOrder() async {
    setState(() {
      _isCreatingOrder = true;
    });

    final PosActionResult result = await widget.onCreateOrder();

    if (!mounted) {
      return;
    }

    setState(() {
      _isCreatingOrder = false;
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

  @override
  Widget build(BuildContext context) {
    final List<Product> visibleProducts = _filteredProducts();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mashroo3 POS'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Chip(
              label: Text('Opening: ${_currency.format(widget.openingCash)}'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Chip(
              label: Text('Sales: ${_currency.format(widget.todaySales)}'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Chip(
              label: Text('API: ${_maskApiKey(widget.apiKey)}'),
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
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
              label: const Text('Log out'),
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
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        labelText: 'Barcode scanner input',
                                        hintText:
                                            'Scan barcode then press Enter',
                                        prefixIcon: Icon(Icons.qr_code_scanner),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  FilledButton.icon(
                                    onPressed: _submitBarcode,
                                    icon: const Icon(Icons.add_shopping_cart),
                                    label: const Text('Add'),
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
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  labelText: 'Search products',
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
                                        ? 'No products returned from API.'
                                        : 'No products matched your search.',
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
                                'Customer',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: DropdownButtonFormField<Customer>(
                                      initialValue: widget.selectedCustomer,
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                      ),
                                      items: widget.customers
                                          .map(
                                            (Customer customer) =>
                                                DropdownMenuItem<Customer>(
                                              value: customer,
                                              child: Text(customer.displayLabel),
                                            ),
                                          )
                                          .toList(growable: false),
                                      onChanged: (Customer? selected) {
                                        if (selected != null) {
                                          widget.onCustomerSelected(selected);
                                        }
                                      },
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
                                    label: const Text('New'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Card(
                          child: widget.cartItems.isEmpty
                              ? const Center(
                                  child: Text('Cart is empty.'),
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
                                                  _currency.format(
                                                    item.product.price,
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
                                                widget.onChangeQuantity(
                                              item.product,
                                              -1,
                                            ),
                                            icon: const Icon(
                                              Icons.remove_circle_outline,
                                            ),
                                          ),
                                          Text(item.quantity.toString()),
                                          IconButton(
                                            onPressed: () =>
                                                widget.onChangeQuantity(
                                              item.product,
                                              1,
                                            ),
                                            icon: const Icon(
                                              Icons.add_circle_outline,
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
                                label: 'Items',
                                value: widget.cartItems
                                    .fold<int>(
                                      0,
                                      (int sum, CartItem item) =>
                                          sum + item.quantity,
                                    )
                                    .toString(),
                              ),
                              _SummaryRow(
                                label: 'Subtotal',
                                value: _currency.format(widget.cartTotal),
                              ),
                              const Divider(height: 20),
                              _SummaryRow(
                                label: 'Total',
                                value: _currency.format(widget.cartTotal),
                                isTotal: true,
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
                                        ? 'Creating...'
                                        : 'Create Order',
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
        _error = 'Customer name is required.';
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
      title: const Text('Create customer'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _nameController,
              autofocus: true,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Full name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Phone (optional)',
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
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Create'),
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
    final bool outOfStock = product.availableQty != null && product.availableQty! <= 0;

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
                  const SizedBox(height: 6),
                  if (product.availableQty != null)
                    Text(
                      'Available: ${product.availableQty}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const Spacer(),
                  Text(
                    currency.format(product.price),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: outOfStock ? null : onAdd,
                      icon: const Icon(Icons.add),
                      label: Text(outOfStock ? 'Out of stock' : 'Add to order'),
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
                    'This POS view is optimized for laptops and tablets.',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Use a wider screen to access the full product and checkout layout.',
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
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Loading catalog, customers, and orders...'),
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
                    'Could not load POS data',
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
                      label: const Text('Retry'),
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
                          : const Text('Change API key'),
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
    required this.availableQty,
  });

  final int id;
  final String name;
  final String description;
  final double price;
  final String barcode;
  final String? imageUrl;
  final int? availableQty;

  factory Product.fromJson(Map<String, dynamic> json, {required String baseUrl}) {
    final int? id = _toInt(json['id']);
    if (id == null) {
      throw const FormatException('Product id is missing.');
    }

    final String name =
        _toString(json['name']) ?? _toString(json['title']) ?? 'Product $id';
    final String description = _toString(json['description']) ??
        _toString(json['details']) ??
        _toString(json['summary']) ??
        'No description';

    final double price = _toDouble(json['price']) ?? 0;
    final String barcode = _toString(json['barcode']) ??
        _toString(json['sku']) ??
        _toString(json['code']) ??
        id.toString();

    final String? imageUrl = _normalizeImageUrl(
      json['image_url'] ?? json['image'] ?? json['photo_url'] ?? json['photo'],
      baseUrl,
    );

    final int? availableQty =
        _toInt(json['available_qty'] ?? json['quantity'] ?? json['stock']);

    return Product(
      id: id,
      name: name,
      description: description,
      price: price,
      barcode: barcode,
      imageUrl: imageUrl,
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
        name = 'Walk-in Customer',
        phone = null;

  final int? apiId;
  final String name;
  final String? phone;

  bool get isWalkIn => apiId == null;

  String get displayLabel {
    if (phone == null || phone!.isEmpty) {
      return name;
    }
    return '$name (${phone!})';
  }

  factory Customer.fromJson(Map<String, dynamic> json) {
    final int? id = _toInt(json['id']);
    if (id == null) {
      throw const FormatException('Customer id is missing.');
    }

    return Customer(
      apiId: id,
      name: _toString(json['name']) ??
          _toString(json['company']) ??
          'Customer $id',
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
  final int quantity;

  double get lineTotal => product.price * quantity;

  CartItem copyWith({int? quantity}) {
    return CartItem(
      product: product,
      quantity: quantity ?? this.quantity,
    );
  }
}

@immutable
class OrderRequestItem {
  const OrderRequestItem({required this.productId, required this.quantity});

  final int productId;
  final int quantity;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'product_id': productId,
      'qty': quantity,
    };
  }
}

@immutable
class PosOrderItem {
  const PosOrderItem({
    required this.productId,
    required this.quantity,
    required this.price,
  });

  final int productId;
  final int quantity;
  final double price;

  double get lineTotal => price * quantity;

  factory PosOrderItem.fromJson(Map<String, dynamic> json) {
    return PosOrderItem(
      productId: _toInt(json['product_id'] ?? json['id']) ?? 0,
      quantity: _toInt(json['qty'] ?? json['quantity']) ?? 0,
      price: _toDouble(json['price']) ?? 0,
    );
  }

  factory PosOrderItem.fromRequestItem(OrderRequestItem item, {double? price}) {
    return PosOrderItem(
      productId: item.productId,
      quantity: item.quantity,
      price: price ?? 0,
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
    required this.items,
  });

  final int? apiId;
  final DateTime? createdAt;
  final String? customerName;
  final double total;
  final List<PosOrderItem> items;

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
      items: parsedItems,
    );
  }

  factory PosOrder.fromCart({
    required String customerName,
    required List<OrderRequestItem> items,
    required double total,
  }) {
    return PosOrder(
      apiId: null,
      createdAt: DateTime.now(),
      customerName: customerName,
      total: total,
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
      throw const ApiException('Unexpected create customer response.');
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
  }) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'items': items
          .map((OrderRequestItem item) => item.toJson())
          .toList(growable: false),
    };

    if (customerId != null) {
      payload['customer_id'] = customerId;
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
          throw ApiException('Unsupported method: $method');
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
              'Request failed with status ${response.statusCode}.',
          statusCode: response.statusCode,
        );
      }

      if (decoded is Map<String, dynamic> && decoded['ok'] == false) {
        throw ApiException(
          _extractErrorMessage(decoded) ??
              'API returned ok=false for $method $path.',
          statusCode: response.statusCode,
        );
      }

      return decoded;
    } catch (error) {
      if (error is ApiException) {
        rethrow;
      }

      throw ApiException('Network error while calling $path: $error');
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
