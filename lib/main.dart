import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SharedPreferences.getInstance();
  runApp(const AjantaApp());
}

// ============================================================
// APP
// ============================================================

class AjantaApp extends StatelessWidget {
  const AjantaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ajanta Saree Centre',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.black,
        ),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const LoginPage(),
    );
  }
}

// ============================================================
// INVENTORY MODEL
// ============================================================

class Saree {
  String id;
  String name;
  String code;
  String category;
  double purchasePrice;
  double price1;
  double price2;
  double price3;
  double stock;
  String trader;
  String notes;

  Saree({
    required this.id,
    required this.name,
    required this.code,
    required this.category,
    required this.purchasePrice,
    required this.price1,
    required this.price2,
    required this.price3,
    required this.stock,
    required this.trader,
    required this.notes,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'code': code,
      'category': category,
      'purchasePrice': purchasePrice,
      'price1': price1,
      'price2': price2,
      'price3': price3,
      'stock': stock,
      'trader': trader,
      'notes': notes,
    };
  }

  factory Saree.fromJson(Map<String, dynamic> json) {
    return Saree(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      purchasePrice:
          (json['purchasePrice'] as num?)?.toDouble() ?? 0,
      price1: (json['price1'] as num?)?.toDouble() ?? 0,
      price2: (json['price2'] as num?)?.toDouble() ?? 0,
      price3: (json['price3'] as num?)?.toDouble() ?? 0,
      stock: (json['stock'] as num?)?.toDouble() ?? 0,
      trader: json['trader']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
    );
  }

  double getPrice(String priceCode) {
    switch (priceCode.toUpperCase()) {
      case 'A':
        return price1;
      case 'B':
        return price2;
      case 'C':
        return price3;
      default:
        return 0;
    }
  }
}

// ============================================================
// INVENTORY STORAGE
// ============================================================

class InventoryStorage {
  static const String key = 'ajanta_inventory';

  static Future<List<Saree>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(key);

    if (data == null || data.isEmpty) {
      return [];
    }

    try {
      final List<dynamic> decoded = jsonDecode(data);
      return decoded
          .map((item) => Saree.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<Saree> sarees) async {
    final prefs = await SharedPreferences.getInstance();

    final data = sarees.map((saree) => saree.toJson()).toList();

    await prefs.setString(
      key,
      jsonEncode(data),
    );
  }
}

// ============================================================
// LOGIN
// ============================================================

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final idController = TextEditingController();
  final pinController = TextEditingController();

  bool customer = false;

  void login() {
    if (idController.text.trim().isEmpty ||
        pinController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter ID and PIN'),
        ),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => HomePage(
          customer: customer,
        ),
      ),
    );
  }

  @override
  void dispose() {
    idController.dispose();
    pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(
                  Icons.storefront,
                  size: 75,
                ),
                const SizedBox(height: 15),

                const Text(
                  'AJANTA SAREE CENTRE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 5),

                const Text(
                  'Satna (M.P.)',
                  style: TextStyle(
                    fontSize: 16,
                  ),
                ),

                const SizedBox(height: 30),

                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: false,
                      label: Text('Admin'),
                      icon: Icon(Icons.admin_panel_settings),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      label: Text('Customer'),
                      icon: Icon(Icons.person),
                    ),
                  ],
                  selected: {customer},
                  onSelectionChanged: (value) {
                    setState(() {
                      customer = value.first;
                    });
                  },
                ),

                const SizedBox(height: 20),

                TextField(
                  controller: idController,
                  decoration: InputDecoration(
                    labelText:
                        customer ? 'Customer ID' : 'Admin ID',
                    prefixIcon: const Icon(Icons.person),
                  ),
                ),

                const SizedBox(height: 14),

                TextField(
                  controller: pinController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'PIN',
                    prefixIcon: Icon(Icons.lock),
                  ),
                ),

                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: login,
                    icon: const Icon(Icons.login),
                    label: const Text('LOGIN'),
                  ),
                ),

                const SizedBox(height: 15),

                const Text(
                  'No OTP authentication',
                  style: TextStyle(
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// HOME
// ============================================================

class HomePage extends StatefulWidget {
  final bool customer;

  const HomePage({
    super.key,
    required this.customer,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(customer: widget.customer),
      const SalesPage(),
      const InventoryPage(),
      const AccountsPage(),
      const MorePage(),
    ];

    return Scaffold(
      body: pages[selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Sales',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Stock',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Accounts',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz),
            selectedIcon: Icon(Icons.more),
            label: 'More',
          ),
        ],
      ),
    );
  }
}

// ============================================================
// DASHBOARD
// ============================================================

class DashboardPage extends StatelessWidget {
  final bool customer;

  const DashboardPage({
    super.key,
    required this.customer,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            customer
                ? 'MY ACCOUNT'
                : 'AJANTA SAREE CENTRE',
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.bold,
            ),
          ),

          const Text('Satna (M.P.)'),

          const SizedBox(height: 20),

          _dashboardCard(
            icon: Icons.receipt_long,
            title: "Today's Sales",
            value: '₹0',
          ),

          _dashboardCard(
            icon: Icons.shopping_cart,
            title: "Today's Purchases",
            value: '₹0',
          ),

          _dashboardCard(
            icon: Icons.people,
            title: 'Customer Outstanding',
            value: '₹0',
          ),

          _dashboardCard(
            icon: Icons.store,
            title: 'Trader Outstanding',
            value: '₹0',
          ),

          _dashboardCard(
            icon: Icons.inventory_2,
            title: 'Total Stock',
            value: '0',
          ),
        ],
      ),
    );
  }

  Widget _dashboardCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, size: 30),
        title: Text(title),
        trailing: Text(
          value,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ============================================================
// INVENTORY PAGE
// ============================================================

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  List<Saree> sarees = [];
  bool loading = true;

  final searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadInventory();
  }

  Future<void> loadInventory() async {
    final data = await InventoryStorage.load();

    if (!mounted) return;

    setState(() {
      sarees = data;
      loading = false;
    });
  }

  Future<void> saveInventory() async {
    await InventoryStorage.save(sarees);
  }

  List<Saree> get filteredSarees {
    final search = searchController.text.trim().toLowerCase();

    if (search.isEmpty) {
      return sarees;
    }

    return sarees.where((saree) {
      return saree.name.toLowerCase().contains(search) ||
          saree.code.toLowerCase().contains(search) ||
          saree.category.toLowerCase().contains(search);
    }).toList();
  }

  Future<void> addSaree() async {
    final result = await Navigator.push<Saree>(
      context,
      MaterialPageRoute(
        builder: (_) => const SareeFormPage(),
      ),
    );

    if (result != null) {
      setState(() {
        sarees.add(result);
      });

      await saveInventory();
    }
  }

  Future<void> editSaree(Saree saree) async {
    final result = await Navigator.push<Saree>(
      context,
      MaterialPageRoute(
        builder: (_) => SareeFormPage(
          saree: saree,
        ),
      ),
    );

    if (result != null) {
      final index =
          sarees.indexWhere((item) => item.id == result.id);

      if (index != -1) {
        setState(() {
          sarees[index] = result;
        });

        await saveInventory();
      }
    }
  }

  Future<void> deleteSaree(Saree saree) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Delete Saree?'),
          content: Text(
            'Delete "${saree.name}" from inventory?',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, true),
              child: const Text('DELETE'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      setState(() {
        sarees.removeWhere(
          (item) => item.id == saree.id,
        );
      });

      await saveInventory();
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = filteredSarees;

    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Inventory',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            IconButton(
              onPressed: addSaree,
              icon: const Icon(Icons.add),
              tooltip: 'Add Saree',
            ),
          ],
        ),
        body: loading
            ? const Center(
                child: CircularProgressIndicator(),
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: searchController,
                      onChanged: (_) {
                        setState(() {});
                      },
                      decoration: InputDecoration(
                        hintText:
                            'Search saree, code or category',
                        prefixIcon:
                            const Icon(Icons.search),
                        suffixIcon:
                            searchController.text.isNotEmpty
                                ? IconButton(
                                    onPressed: () {
                                      searchController.clear();
                                      setState(() {});
                                    },
                                    icon:
                                        const Icon(Icons.clear),
                                  )
                                : null,
                      ),
                    ),
                  ),

                  Expanded(
                    child: items.isEmpty
                        ? _emptyInventory()
                        : ListView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(
                              12,
                              0,
                              12,
                              90,
                            ),
                            itemCount: items.length,
                            itemBuilder: (_, index) {
                              final saree = items[index];

                              return _sareeCard(saree);
                            },
                          ),
                  ),
                ],
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: addSaree,
          icon: const Icon(Icons.add),
          label: const Text('Add Saree'),
        ),
      ),
    );
  }

  Widget _emptyInventory() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.inventory_2_outlined,
              size: 75,
            ),
            const SizedBox(height: 15),
            const Text(
              'No sarees added yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add your first saree to start building your inventory.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: addSaree,
              icon: const Icon(Icons.add),
              label: const Text('Add Saree'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sareeCard(Saree saree) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    saree.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') {
                      editSaree(saree);
                    } else if (value == 'delete') {
                      deleteSaree(saree);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        leading: Icon(Icons.edit),
                        title: Text('Edit'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete),
                        title: Text('Delete'),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            if (saree.code.isNotEmpty)
              Text(
                'Code: ${saree.code}',
                style: const TextStyle(
                  color: Colors.grey,
                ),
              ),

            if (saree.category.isNotEmpty)
              Text(
                'Category: ${saree.category}',
                style: const TextStyle(
                  color: Colors.grey,
                ),
              ),

            const Divider(height: 22),

            Row(
              children: [
                Expanded(
                  child: _priceBox(
                    'A',
                    saree.price1,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _priceBox(
                    'B',
                    saree.price2,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _priceBox(
                    'C',
                    saree.price3,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                const Icon(
                  Icons.inventory_2,
                  size: 20,
                ),
                const SizedBox(width: 6),
                Text(
                  'Stock: ${_formatNumber(saree.stock)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  'Purchase ₹${_formatNumber(saree.purchasePrice)}',
                  style: const TextStyle(
                    color: Colors.grey,
                  ),
                ),
              ],
            ),

            if (saree.trader.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Trader: ${saree.trader}',
                style: const TextStyle(
                  color: Colors.grey,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _priceBox(
    String code,
    double price,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 10,
        horizontal: 8,
      ),
      decoration: BoxDecoration(
        border: Border.all(),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            code,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '₹${_formatNumber(price)}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ADD / EDIT SAREE
// ============================================================

class SareeFormPage extends StatefulWidget {
  final Saree? saree;

  const SareeFormPage({
    super.key,
    this.saree,
  });

  @override
  State<SareeFormPage> createState() =>
      _SareeFormPageState();
}

class _SareeFormPageState extends State<SareeFormPage> {
  final nameController = TextEditingController();
  final codeController = TextEditingController();
  final categoryController = TextEditingController();
  final purchaseController = TextEditingController();
  final price1Controller = TextEditingController();
  final price2Controller = TextEditingController();
  final price3Controller = TextEditingController();
  final stockController = TextEditingController();
  final traderController = TextEditingController();
  final notesController = TextEditingController();

  bool get editing => widget.saree != null;

  @override
  void initState() {
    super.initState();

    final saree = widget.saree;

    if (saree != null) {
      nameController.text = saree.name;
      codeController.text = saree.code;
      categoryController.text = saree.category;
      purchaseController.text =
          _numberForEditing(saree.purchasePrice);
      price1Controller.text =
          _numberForEditing(saree.price1);
      price2Controller.text =
          _numberForEditing(saree.price2);
      price3Controller.text =
          _numberForEditing(saree.price3);
      stockController.text =
          _numberForEditing(saree.stock);
      traderController.text = saree.trader;
      notesController.text = saree.notes;
    }
  }

  String _numberForEditing(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value.toString();
  }

  double _parse(String value) {
    return double.tryParse(
          value.replaceAll(',', '').trim(),
        ) ??
        0;
  }

  void save() {
    if (nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saree name is required'),
        ),
      );
      return;
    }

    final old = widget.saree;

    final saree = Saree(
      id: old?.id ??
          DateTime.now()
              .microsecondsSinceEpoch
              .toString(),
      name: nameController.text.trim(),
      code: codeController.text.trim(),
      category: categoryController.text.trim(),
      purchasePrice: _parse(purchaseController.text),
      price1: _parse(price1Controller.text),
      price2: _parse(price2Controller.text),
      price3: _parse(price3Controller.text),
      stock: _parse(stockController.text),
      trader: traderController.text.trim(),
      notes: notesController.text.trim(),
    );

    Navigator.pop(context, saree);
  }

  @override
  void dispose() {
    nameController.dispose();
    codeController.dispose();
    categoryController.dispose();
    purchaseController.dispose();
    price1Controller.dispose();
    price2Controller.dispose();
    price3Controller.dispose();
    stockController.dispose();
    traderController.dispose();
    notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          editing ? 'Edit Saree' : 'Add Saree',
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Basic Information',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 15),

            TextField(
              controller: nameController,
              textCapitalization:
                  TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Saree Name *',
                prefixIcon: Icon(Icons.checkroom),
              ),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: codeController,
              decoration: const InputDecoration(
                labelText: 'Saree Code',
                prefixIcon: Icon(Icons.qr_code),
              ),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: categoryController,
              decoration: const InputDecoration(
                labelText: 'Category',
                prefixIcon: Icon(Icons.category),
              ),
            ),

            const SizedBox(height: 25),

            const Text(
              'Pricing',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 15),

            TextField(
              controller: purchaseController,
              keyboardType:
                  const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Purchase Price',
                prefixText: '₹ ',
                prefixIcon: Icon(Icons.shopping_cart),
              ),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: price1Controller,
              keyboardType:
                  const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Price 1 — Code A',
                prefixText: '₹ ',
                prefixIcon: Icon(Icons.sell),
              ),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: price2Controller,
              keyboardType:
                  const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Price 2 — Code B',
                prefixText: '₹ ',
                prefixIcon: Icon(Icons.sell),
              ),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: price3Controller,
              keyboardType:
                  const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Price 3 — Code C',
                prefixText: '₹ ',
                prefixIcon: Icon(Icons.sell),
              ),
            ),

            const SizedBox(height: 25),

            const Text(
              'Stock & Supplier',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 15),

            TextField(
              controller: stockController,
              keyboardType:
                  const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Current / Opening Stock',
                prefixIcon: Icon(Icons.inventory_2),
              ),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: traderController,
              decoration: const InputDecoration(
                labelText: 'Trader / Supplier',
                prefixIcon: Icon(Icons.store),
              ),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes',
                prefixIcon: Icon(Icons.notes),
              ),
            ),

            const SizedBox(height: 30),

            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: save,
                icon: const Icon(Icons.save),
                label: Text(
                  editing
                      ? 'UPDATE SAREE'
                      : 'SAVE SAREE',
                ),
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SALES PLACEHOLDER
// ============================================================

class SalesPage extends StatelessWidget {
  const SalesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sales'),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(25),
            child: Text(
              'INVOICE MODULE\n\n'
              'The next stage will add:\n\n'
              'A → Price 1\n'
              'B → Price 2\n'
              'C → Price 3\n\n'
              'GST • Invoice numbering • PDF • '
              'Customer ledger',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// ACCOUNTS PLACEHOLDER
// ============================================================

class AccountsPage extends StatelessWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Accounts'),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(25),
            child: Text(
              'ACCOUNTS\n\n'
              'Customers\n'
              'Customer Outstanding\n'
              'Payments\n'
              'Trader / Supplier Ledger\n'
              'Purchase Bills',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// MORE
// ============================================================

class MorePage extends StatelessWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('More'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            ListTile(
              leading: Icon(Icons.shopping_bag),
              title: Text('Purchases'),
            ),
            ListTile(
              leading: Icon(Icons.assignment_return),
              title: Text('Returns'),
            ),
            ListTile(
              leading: Icon(Icons.account_balance_wallet),
              title: Text('Cashbook'),
            ),
            ListTile(
              leading: Icon(Icons.bar_chart),
              title: Text('Reports'),
            ),
            ListTile(
              leading: Icon(Icons.backup),
              title: Text('Backup / Restore'),
            ),
            ListTile(
              leading: Icon(Icons.settings),
              title: Text('Settings'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// HELPERS
// ============================================================

String _formatNumber(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }

  return value.toStringAsFixed(2);
}
