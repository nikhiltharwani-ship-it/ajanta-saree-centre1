import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.black),
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
// SAREE MODEL
// ============================================================

// ============================================================
// CUSTOMER MODEL - FIRESTORE
// ============================================================

class Customer {
  String id;
  String name;
  String pin;
  String gstNumber;
  double outstanding;

  Customer({
    required this.id,
    required this.name,
    required this.pin,
    required this.gstNumber,
    this.outstanding = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'pin': pin,
      'gstNumber': gstNumber,
      'outstanding': outstanding,
    };
  }

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      pin: map['pin']?.toString() ?? '',
      gstNumber: map['gstNumber']?.toString() ?? '',
      outstanding:
          (map['outstanding'] as num?)?.toDouble() ?? 0,
    );
  }
}

// ============================================================
// CUSTOMER FIRESTORE STORAGE
// ============================================================

class CustomerStorage {
  static final _customers =
      FirebaseFirestore.instance.collection('customers');

  // ==========================================================
  // CREATE CUSTOMER
  // ==========================================================

  static Future<void> save(Customer customer) async {
    await _customers.doc(customer.id).set(
          customer.toMap(),
        );
  }

  // ==========================================================
  // LOAD ALL CUSTOMERS
  // ==========================================================

  static Future<List<Customer>> load() async {
    final snapshot = await _customers.get();

    return snapshot.docs.map((doc) {
      return Customer.fromMap(doc.data());
    }).toList();
  }

  // ==========================================================
  // FIND CUSTOMER BY ID
  // ==========================================================

  static Future<Customer?> findById(String id) async {
    final doc = await _customers.doc(id).get();

    if (!doc.exists || doc.data() == null) {
      return null;
    }

    return Customer.fromMap(doc.data()!);
  }

  // ==========================================================
  // CHECK WHETHER CUSTOMER ID ALREADY EXISTS
  // ==========================================================

  static Future<bool> idExists(String id) async {
    final doc = await _customers.doc(id).get();
    return doc.exists;
  }

  // ==========================================================
  // UPDATE CUSTOMER
  // Supports changing:
  // Name
  // Customer ID
  // PIN
  // GST Number
  // ==========================================================

  static Future<void> updateCustomer({
    required String oldId,
    required Customer customer,
  }) async {
    final newId = customer.id.trim();

    // ID has not changed
    if (oldId == newId) {
      await _customers.doc(oldId).set(
            customer.toMap(),
          );
      return;
    }

    // New ID must be unique
    final newIdExists = await idExists(newId);

    if (newIdExists) {
      throw Exception(
        'Customer ID "$newId" already exists.',
      );
    }

    // Create the customer under the new ID
    await _customers.doc(newId).set(
          customer.toMap(),
        );

    // Remove the old document
    await _customers.doc(oldId).delete();
  }

  // ==========================================================
  // DELETE CUSTOMER
  // ==========================================================

  static Future<void> delete(String id) async {
    await _customers.doc(id).delete();
  }
}

// ============================================================
// CUSTOMER LIST PAGE
// ============================================================

class CustomerListPage extends StatefulWidget {
  const CustomerListPage({super.key});

  @override
  State<CustomerListPage> createState() => _CustomerListPageState();
}

class _CustomerListPageState extends State<CustomerListPage> {
  List<Customer> customers = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadCustomers();
  }

  Future<void> loadCustomers() async {
    setState(() {
      loading = true;
    });

    try {
      final data = await CustomerStorage.load();

      if (!mounted) return;

      setState(() {
        customers = data;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load customers: $e'),
        ),
      );
    }
  }

  Future<void> openCustomer([Customer? customer]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerEditPage(
          customer: customer,
        ),
      ),
    );

    loadCustomers();
  }

  Future<void> deleteCustomer(Customer customer) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Customer?'),
          content: Text(
            'Delete ${customer.name} (${customer.id})?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('DELETE'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      await CustomerStorage.delete(customer.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Customer deleted'),
        ),
      );

      loadCustomers();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Delete failed: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => openCustomer(),
        child: const Icon(Icons.add),
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : customers.isEmpty
              ? const Center(
                  child: Text(
                    'No customers found',
                    style: TextStyle(fontSize: 16),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: loadCustomers,
                  child: ListView.builder(
                    itemCount: customers.length,
                    itemBuilder: (context, index) {
                      final customer = customers[index];

                      return ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.person),
                        ),
                        title: Text(customer.name),
                        subtitle: Text(
                          'ID: ${customer.id}'
                          '${customer.gstNumber.isNotEmpty ? '\nGST: ${customer.gstNumber}' : ''}',
                        ),
                        isThreeLine:
                            customer.gstNumber.isNotEmpty,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () =>
                                  openCustomer(customer),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () =>
                                  deleteCustomer(customer),
                            ),
                          ],
                        ),
                        onTap: () =>
                            openCustomer(customer),
                      );
                    },
                  ),
                ),
    );
  }
}


// ============================================================
// CUSTOMER EDIT / CREATE PAGE
// ============================================================

class CustomerEditPage extends StatefulWidget {
  final Customer? customer;

  const CustomerEditPage({
    super.key,
    this.customer,
  });

  @override
  State<CustomerEditPage> createState() =>
      _CustomerEditPageState();
}

class _CustomerEditPageState
    extends State<CustomerEditPage> {
  late TextEditingController nameController;
  late TextEditingController idController;
  late TextEditingController pinController;
  late TextEditingController gstController;

  bool saving = false;

  bool get isEditing => widget.customer != null;

  @override
  void initState() {
    super.initState();

    nameController = TextEditingController(
      text: widget.customer?.name ?? '',
    );

    idController = TextEditingController(
      text: widget.customer?.id ?? '',
    );

    pinController = TextEditingController(
      text: widget.customer?.pin ?? '',
    );

    gstController = TextEditingController(
      text: widget.customer?.gstNumber ?? '',
    );
  }

  Future<void> saveCustomer() async {
    final name = nameController.text.trim();
    final id = idController.text.trim();
    final pin = pinController.text.trim();
    final gst = gstController.text.trim();

    if (name.isEmpty || id.isEmpty || pin.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Name, Customer ID and PIN are required',
          ),
        ),
      );
      return;
    }

    setState(() {
      saving = true;
    });

    try {
      if (isEditing) {
        final updatedCustomer = Customer(
          id: id,
          name: name,
          pin: pin,
          gstNumber: gst,
          outstanding:
              widget.customer!.outstanding,
        );

        await CustomerStorage.updateCustomer(
          oldId: widget.customer!.id,
          customer: updatedCustomer,
        );
      } else {
        final exists =
            await CustomerStorage.idExists(id);

        if (exists) {
          throw Exception(
            'Customer ID "$id" already exists.',
          );
        }

        final newCustomer = Customer(
          id: id,
          name: name,
          pin: pin,
          gstNumber: gst,
        );

        await CustomerStorage.save(newCustomer);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEditing
                ? 'Customer updated successfully'
                : 'Customer created successfully',
          ),
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        saving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst(
              'Exception: ',
              '',
            ),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    idController.dispose();
    pinController.dispose();
    gstController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEditing
              ? 'Edit Customer'
              : 'Create Customer',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Customer Name *',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: idController,
              decoration: const InputDecoration(
                labelText: 'Customer ID *',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'PIN *',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: gstController,
              decoration: const InputDecoration(
                labelText: 'GST Number (Optional)',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: saving
                    ? null
                    : saveCustomer,
                child: saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        isEditing
                            ? 'UPDATE CUSTOMER'
                            : 'CREATE CUSTOMER',
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
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

  double getPrice(String code) {
    switch (code.trim().toUpperCase()) {
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
      final decoded = jsonDecode(data) as List;

      return decoded
          .map(
            (item) => Saree.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<Saree> sarees) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      key,
      jsonEncode(
        sarees.map((saree) => saree.toJson()).toList(),
      ),
    );
  }
}

// ============================================================
// INVOICE ITEM
// ============================================================

class InvoiceItem {
  String sareeId;
  String sareeName;
  String sareeCode;
  String priceCode;
  double quantity;
  double price;

  InvoiceItem({
    required this.sareeId,
    required this.sareeName,
    required this.sareeCode,
    required this.priceCode,
    required this.quantity,
    required this.price,
  });

  double get total => quantity * price;

  Map<String, dynamic> toJson() {
    return {
      'sareeId': sareeId,
      'sareeName': sareeName,
      'sareeCode': sareeCode,
      'priceCode': priceCode,
      'quantity': quantity,
      'price': price,
    };
  }
}

// ============================================================
// INVOICE MODEL
// ============================================================

class Invoice {
  String number;
  DateTime date;
  String customerName;
  List<InvoiceItem> items;
  double subtotal;
  double gst;
  double grandTotal;
  double paid;
  double outstanding;

  Invoice({
    required this.number,
    required this.date,
    required this.customerName,
    required this.items,
    required this.subtotal,
    required this.gst,
    required this.grandTotal,
    required this.paid,
    required this.outstanding,
  });

  Map<String, dynamic> toJson() {
    return {
      'number': number,
      'date': date.toIso8601String(),
      'customerName': customerName,
      'items': items.map((e) => e.toJson()).toList(),
      'subtotal': subtotal,
      'gst': gst,
      'grandTotal': grandTotal,
      'paid': paid,
      'outstanding': outstanding,
    };
  }
}

// ============================================================
// INVOICE STORAGE
// ============================================================

class InvoiceStorage {
  static const String invoicesKey = 'ajanta_invoices';
  static const String numberKey = 'ajanta_invoice_number';

  static Future<List<Invoice>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(invoicesKey);

    if (data == null || data.isEmpty) {
      return [];
    }

    try {
      final decoded = jsonDecode(data) as List;

      return decoded.map((item) {
        final map = Map<String, dynamic>.from(item);

        final items = (map['items'] as List? ?? [])
            .map(
              (x) => InvoiceItem(
                sareeId: x['sareeId']?.toString() ?? '',
                sareeName: x['sareeName']?.toString() ?? '',
                sareeCode: x['sareeCode']?.toString() ?? '',
                priceCode: x['priceCode']?.toString() ?? '',
                quantity:
                    (x['quantity'] as num?)?.toDouble() ?? 0,
                price:
                    (x['price'] as num?)?.toDouble() ?? 0,
              ),
            )
            .toList();

        return Invoice(
          number: map['number']?.toString() ?? '',
          date: DateTime.tryParse(
                map['date']?.toString() ?? '',
              ) ??
              DateTime.now(),
          customerName:
              map['customerName']?.toString() ?? '',
          items: items,
          subtotal:
              (map['subtotal'] as num?)?.toDouble() ?? 0,
          gst: (map['gst'] as num?)?.toDouble() ?? 0,
          grandTotal:
              (map['grandTotal'] as num?)?.toDouble() ?? 0,
          paid: (map['paid'] as num?)?.toDouble() ?? 0,
          outstanding:
              (map['outstanding'] as num?)?.toDouble() ?? 0,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<Invoice> invoices) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      invoicesKey,
      jsonEncode(
        invoices.map((invoice) => invoice.toJson()).toList(),
      ),
    );
  }

  static Future<String> nextInvoiceNumber() async {
    final prefs = await SharedPreferences.getInstance();

    final now = DateTime.now();

    final financialYearStart =
        now.month >= 4 ? now.year : now.year - 1;

    final financialYearEnd = financialYearStart + 1;

    final yearText =
        '$financialYearStart-$financialYearEnd';

    final next =
        (prefs.getInt(numberKey) ?? 0) + 1;

    await prefs.setInt(numberKey, next);

    return '$yearText/${next.toString().padLeft(3, '0')}';
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

// ============================================================
// ADMIN LOGIN CREDENTIALS
// EDIT THESE VALUES IN FUTURE IF REQUIRED
// ============================================================

const String admin1Id = 'nikhilasc';
const String admin1Pin = '0521';

const String admin2Id = 'kailashasc';
const String admin2Pin = '2105';

// ============================================================
// LOGIN STATE
// ============================================================

class _LoginPageState extends State<LoginPage> {
  final idController = TextEditingController();
  final pinController = TextEditingController();

  bool customer = false;

  Future<void> login() async {
  final enteredId = idController.text.trim();
  final enteredPin = pinController.text.trim();

  if (enteredId.isEmpty || enteredPin.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please enter ID and PIN'),
      ),
    );
    return;
  }

  // ==========================================================
  // ADMIN LOGIN
  // ==========================================================

  if (!customer) {
    final admins = {
      'nikhilasc': '0521',
      'kailashasc': '2105',
    };

    if (admins[enteredId] == enteredPin) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const HomePage(customer: false),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid Admin ID or PIN'),
        ),
      );
    }

    return;
  }

  // ==========================================================
  // CUSTOMER LOGIN — FIRESTORE
  // ==========================================================

  try {
    final snapshot = await FirebaseFirestore.instance
    .collection('customers')
    .where('id', isEqualTo: enteredId)
    .where('pin', isEqualTo: enteredPin)
    .limit(1)
    .get();

    if (!mounted) return;

    if (snapshot.docs.isNotEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const HomePage(customer: true),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid Customer ID or PIN'),
        ),
      );
    }
  } catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Customer login failed: $e'),
      ),
    );
  }
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
                ),

                const SizedBox(height: 30),

                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: false,
                      label: Text('Admin'),
                      icon: Icon(
                        Icons.admin_panel_settings,
                      ),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      label: Text('Customer'),
                      icon: Icon(
                        Icons.person,
                      ),
                    ),
                  ],
                  selected: {customer},
                  onSelectionChanged: (value) {
                    setState(() {
                      customer = value.first;
                      idController.clear();
                      pinController.clear();
                    });
                  },
                ),

                const SizedBox(height: 20),

                TextField(
                  controller: idController,
                  decoration: InputDecoration(
                    labelText: customer
                        ? 'Customer ID'
                        : 'Admin ID',
                    prefixIcon: const Icon(
                      Icons.person,
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                TextField(
                  controller: pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'PIN',
                    prefixIcon: Icon(
                      Icons.lock,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: login,
                    icon: const Icon(
                      Icons.login,
                    ),
                    label: const Text(
                      'LOGIN',
                    ),
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
          _card(
            Icons.receipt_long,
            "Today's Sales",
            '₹0',
          ),
          _card(
            Icons.shopping_cart,
            "Today's Purchases",
            '₹0',
          ),
          _card(
            Icons.people,
            'Customer Outstanding',
            '₹0',
          ),
          _card(
            Icons.store,
            'Trader Outstanding',
            '₹0',
          ),
        ],
      ),
    );
  }

  Widget _card(
    IconData icon,
    String title,
    String value,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, size: 30),
        title: Text(title),
        trailing: Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ============================================================
// SALES / INVOICE LIST
// ============================================================

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  List<Invoice> invoices = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadInvoices();
  }

  Future<void> loadInvoices() async {
    final data = await InvoiceStorage.load();

    if (!mounted) return;

    setState(() {
      invoices = data;
      loading = false;
    });
  }

  Future<void> createInvoice() async {
    final result = await Navigator.push<Invoice>(
      context,
      MaterialPageRoute(
        builder: (_) => const CreateInvoicePage(),
      ),
    );

    if (result != null) {
      setState(() {
        invoices.insert(0, result);
      });

      await InvoiceStorage.save(invoices);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Sales & Invoices',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : invoices.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(30),
                    child: Column(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.receipt_long,
                          size: 75,
                        ),
                        const SizedBox(height: 15),
                        const Text(
                          'No invoices yet',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Create your first invoice.',
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: createInvoice,
                          icon: const Icon(Icons.add),
                          label:
                              const Text('Create Invoice'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: invoices.length,
                  itemBuilder: (_, index) {
                    final invoice = invoices[index];

                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(
                            Icons.receipt_long,
                          ),
                        ),
                        title: Text(
                          invoice.number,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          invoice.customerName.isEmpty
                              ? 'Cash Customer'
                              : invoice.customerName,
                        ),
                        trailing: Text(
                          '₹${_formatNumber(invoice.grandTotal)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: createInvoice,
        icon: const Icon(Icons.add),
        label: const Text('New Invoice'),
      ),
    );
  }
}

// ============================================================
// CREATE INVOICE
// ============================================================

class CreateInvoicePage extends StatefulWidget {
  const CreateInvoicePage({super.key});

  @override
  State<CreateInvoicePage> createState() =>
      _CreateInvoicePageState();
}

class _CreateInvoicePageState
    extends State<CreateInvoicePage> {
  final customerController = TextEditingController();
  final paidController = TextEditingController();

  List<Saree> sarees = [];
  List<InvoiceItem> items = [];

  String invoiceNumber = '';
  bool loading = true;

  double get subtotal {
    return items.fold(
      0,
      (sum, item) => sum + item.total,
    );
  }

  double get gst {
    return subtotal * 0.05;
  }

  double get grandTotal {
    return subtotal + gst;
  }

  double get paid {
    return double.tryParse(
          paidController.text.replaceAll(',', '').trim(),
        ) ??
        0;
  }

  double get outstanding {
    final value = grandTotal - paid;
    return value < 0 ? 0 : value;
  }

  @override
  void initState() {
    super.initState();
    initialize();
    paidController.addListener(() {
      setState(() {});
    });
  }

  Future<void> initialize() async {
    final inventory = await InventoryStorage.load();
    final number = await InvoiceStorage.nextInvoiceNumber();

    if (!mounted) return;

    setState(() {
      sarees = inventory;
      invoiceNumber = number;
      loading = false;
    });
  }

  Future<void> addItem() async {
    Future<void> addItem() async {
  final result =
      await showModalBottomSheet<InvoiceItem>(
    context: context,
    isScrollControlled: true,
    builder: (_) => AddInvoiceItemSheet(
      sarees: sarees,
    ),
  );

  if (result != null) {
    setState(() {
      items.add(result);
    });
  }
    }

    final result =
        await showModalBottomSheet<InvoiceItem>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddInvoiceItemSheet(
        sarees: sarees,
      ),
    );

    if (result != null) {
      setState(() {
        items.add(result);
      });
    }
  }

  Future<void> saveInvoice() async {
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add at least one item to the invoice.',
          ),
        ),
      );
      return;
    }

    final invoice = Invoice(
      number: invoiceNumber,
      date: DateTime.now(),
      customerName:
          customerController.text.trim(),
      items: items,
      subtotal: subtotal,
      gst: gst,
      grandTotal: grandTotal,
      paid: paid,
      outstanding: outstanding,
    );

    Navigator.pop(context, invoice);
  }

  @override
  void dispose() {
    customerController.dispose();
    paidController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Invoice'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AJANTA SAREE CENTRE',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Invoice No: $invoiceNumber',
                    ),
                    Text(
                      'Date: ${_dateText(DateTime.now())}',
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: customerController,
              decoration: const InputDecoration(
                labelText: 'Customer Name',
                prefixIcon: Icon(Icons.person),
              ),
            ),

            const SizedBox(height: 20),

            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Items',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: addItem,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),

            const SizedBox(height: 10),

            if (items.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: Text(
                      'No items added',
                    ),
                  ),
                ),
              ),

            ...items.asMap().entries.map(
              (entry) {
                final index = entry.key;
                final item = entry.value;

                return Card(
                  child: ListTile(
                    title: Text(
                      item.sareeName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      '${item.sareeCode.isEmpty ? '' : '${item.sareeCode} • '}${item.quantity} × ₹${_formatNumber(item.price)} • Code ${item.priceCode}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '₹${_formatNumber(item.total)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            setState(() {
                              items.removeAt(index);
                            });
                          },
                          icon: const Icon(Icons.delete),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 20),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _summaryRow(
                      'Subtotal',
                      subtotal,
                    ),
                    _summaryRow(
                      'GST @ 5%',
                      gst,
                    ),
                    const Divider(),
                    _summaryRow(
                      'Grand Total',
                      grandTotal,
                      bold: true,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 15),

            TextField(
              controller: paidController,
              keyboardType:
                  const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount Received',
                prefixText: '₹ ',
                prefixIcon:
                    Icon(Icons.payments),
              ),
            ),

            const SizedBox(height: 12),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _summaryRow(
                  'Outstanding',
                  outstanding,
                  bold: true,
                ),
              ),
            ),

            const SizedBox(height: 25),

            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: saveInvoice,
                icon: const Icon(Icons.save),
                label: const Text('SAVE INVOICE'),
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(
    String title,
    double value, {
    bool bold = false,
  }) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontWeight: bold
                    ? FontWeight.bold
                    : FontWeight.normal,
                fontSize: bold ? 17 : 15,
              ),
            ),
          ),
          Text(
            '₹${_formatNumber(value)}',
            style: TextStyle(
              fontWeight: bold
                  ? FontWeight.bold
                  : FontWeight.normal,
              fontSize: bold ? 18 : 15,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ADD INVOICE ITEM SHEET
// ============================================================

class AddInvoiceItemSheet extends StatefulWidget {
  final List<Saree> sarees;

  const AddInvoiceItemSheet({
    super.key,
    required this.sarees,
  });

  @override
  State<AddInvoiceItemSheet> createState() =>
      _AddInvoiceItemSheetState();
}

class _AddInvoiceItemSheetState
    extends State<AddInvoiceItemSheet> {
  Saree? selectedSaree;

  final nameController = TextEditingController();
  final quantityController =
      TextEditingController(text: '1');
  final priceController = TextEditingController();
  final priceCodeController = TextEditingController();

  // 0 = Existing Saree
  // 1 = Manual Item
  // 2 = Goods Return
  int itemType = 0;

  // Existing saree pricing:
  // A / B / C / Manual
  String priceMode = 'A';

  double selectedPrice = 0;

  String? error;

  // ==========================================================
  // UPDATE AUTOMATIC PRICE
  // ==========================================================

  void updatePrice() {
    if (selectedSaree == null) {
      setState(() {
        selectedPrice = 0;
      });
      return;
    }

    if (priceMode == 'Manual') {
      final manualPrice = double.tryParse(
            priceController.text
                .replaceAll(',', '')
                .trim(),
          ) ??
          0;

      setState(() {
        selectedPrice = manualPrice;
        error = null;
      });

      return;
    }

    final code = priceMode;

    if (code == 'A' ||
        code == 'B' ||
        code == 'C') {
      setState(() {
        selectedPrice =
            selectedSaree!.getPrice(code);
        error = null;
      });
    }
  }

  // ==========================================================
  // SAVE ITEM
  // ==========================================================

  void save() {
    final quantity = double.tryParse(
          quantityController.text
              .replaceAll(',', '')
              .trim(),
        ) ??
        0;

    if (quantity <= 0) {
      setState(() {
        error = 'Enter a valid quantity.';
      });
      return;
    }

    // ========================================================
    // GOODS RETURN
    // ========================================================

    if (itemType == 2) {
      final name = nameController.text.trim();

      if (name.isEmpty && selectedSaree == null) {
        setState(() {
          error =
              'Enter or select the returned saree/item name.';
        });
        return;
      }

      final priceText = priceController.text
          .replaceAll(',', '')
          .trim();

      final enteredPrice =
          double.tryParse(priceText);

      if (enteredPrice == null ||
          enteredPrice == 0) {
        setState(() {
          error =
              'Enter the return amount.';
        });
        return;
      }

      // Always store a return as a negative price.
      final returnPrice =
          -enteredPrice.abs();

      final returnName = name.isNotEmpty
          ? name
          : selectedSaree!.name;

      final returnCode =
          selectedSaree?.code ?? '';

      Navigator.pop(
        context,
        InvoiceItem(
          sareeId:
              selectedSaree?.id ?? '',
          sareeName: returnName,
          sareeCode: returnCode,
          priceCode: 'RETURN',
          quantity: quantity,
          price: returnPrice,
        ),
      );

      return;
    }

    // ========================================================
    // MANUAL ITEM
    // ========================================================

    if (itemType == 1) {
      final name = nameController.text.trim();

      if (name.isEmpty) {
        setState(() {
          error = 'Enter the item name.';
        });
        return;
      }

      final price = double.tryParse(
            priceController.text
                .replaceAll(',', '')
                .trim(),
          ) ??
          0;

      if (price <= 0) {
        setState(() {
          error = 'Enter a valid price.';
        });
        return;
      }

      Navigator.pop(
        context,
        InvoiceItem(
          sareeId: '',
          sareeName: name,
          sareeCode: '',
          priceCode: 'MANUAL',
          quantity: quantity,
          price: price,
        ),
      );

      return;
    }

    // ========================================================
    // EXISTING SAREE
    // ========================================================

    if (selectedSaree == null) {
      setState(() {
        error = 'Please select a saree.';
      });
      return;
    }

    double price = 0;
    String priceCode = '';

    if (priceMode == 'Manual') {
      price = double.tryParse(
            priceController.text
                .replaceAll(',', '')
                .trim(),
          ) ??
          0;

      priceCode = 'MANUAL';

      if (price <= 0) {
        setState(() {
          error = 'Enter a valid manual price.';
        });
        return;
      }
    } else {
      priceCode = priceMode;
      price = selectedSaree!.getPrice(priceCode);

      if (price <= 0) {
        setState(() {
          error =
              'No price is set for code $priceCode.';
        });
        return;
      }
    }

    Navigator.pop(
      context,
      InvoiceItem(
        sareeId: selectedSaree!.id,
        sareeName: selectedSaree!.name,
        sareeCode: selectedSaree!.code,
        priceCode: priceCode,
        quantity: quantity,
        price: price,
      ),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    quantityController.dispose();
    priceController.dispose();
    priceCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 20,
        bottom:
            MediaQuery.of(context).viewInsets.bottom +
                20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Text(
              'Add Invoice Item',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 20),

            // ==================================================
            // ITEM TYPE
            // ==================================================

            DropdownButtonFormField<int>(
              value: itemType,
              decoration: const InputDecoration(
                labelText: 'Item Type',
                prefixIcon:
                    Icon(Icons.category),
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 0,
                  child: Text(
                    'Existing Saree',
                  ),
                ),
                DropdownMenuItem(
                  value: 1,
                  child: Text(
                    'Manual Item',
                  ),
                ),
                DropdownMenuItem(
                  value: 2,
                  child: Text(
                    'Goods Return',
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  itemType = value ?? 0;
                  error = null;
                  selectedPrice = 0;
                  priceController.clear();
                  nameController.clear();
                  selectedSaree = null;
                });
              },
            ),

            const SizedBox(height: 18),

            // ==================================================
            // EXISTING SAREE
            // ==================================================

            if (itemType == 0) ...[
              DropdownButtonFormField<Saree>(
                value: selectedSaree,
                isExpanded: true,
                decoration:
                    const InputDecoration(
                  labelText: 'Select Saree',
                  prefixIcon:
                      Icon(Icons.checkroom),
                  border: OutlineInputBorder(),
                ),
                items:
                    widget.sarees.map((saree) {
                  return DropdownMenuItem<Saree>(
                    value: saree,
                    child: Text(
                      saree.code.isEmpty
                          ? saree.name
                          : '${saree.name} (${saree.code})',
                      overflow:
                          TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    selectedSaree = value;
                    selectedPrice = 0;
                  });

                  updatePrice();
                },
              ),

              const SizedBox(height: 15),

              // =================================================
              // PRICE MODE
              // =================================================

              DropdownButtonFormField<String>(
                value: priceMode,
                decoration:
                    const InputDecoration(
                  labelText: 'Price Type',
                  prefixIcon:
                      Icon(Icons.sell),
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'A',
                    child: Text(
                      'A — Price 1',
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'B',
                    child: Text(
                      'B — Price 2',
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'C',
                    child: Text(
                      'C — Price 3',
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'Manual',
                    child: Text(
                      'Manual Price',
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    priceMode =
                        value ?? 'A';
                    selectedPrice = 0;
                    error = null;
                  });

                  updatePrice();
                },
              ),

              const SizedBox(height: 15),

              if (priceMode == 'Manual')
                TextField(
                  controller:
                      priceController,
                  keyboardType:
                      const TextInputType
                          .numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) =>
                      updatePrice(),
                  decoration:
                      const InputDecoration(
                    labelText:
                        'Manual Selling Price',
                    prefixText: '₹ ',
                    prefixIcon:
                        Icon(Icons.edit),
                    border:
                        OutlineInputBorder(),
                  ),
                ),

              if (priceMode == 'Manual')
                const SizedBox(height: 12),

              Card(
                child: Padding(
                  padding:
                      const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      Text(
                        priceMode == 'Manual'
                            ? 'Manual Price'
                            : 'Automatic Price',
                        style:
                            const TextStyle(
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        selectedPrice > 0
                            ? '₹${_formatNumber(selectedPrice)}'
                            : priceMode ==
                                    'Manual'
                                ? 'Enter manual price'
                                : 'Select A, B or C',
                        style:
                            const TextStyle(
                          fontSize: 22,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // ==================================================
            // MANUAL ITEM
            // ==================================================

            if (itemType == 1) ...[
              TextField(
                controller: nameController,
                decoration:
                    const InputDecoration(
                  labelText:
                      'Item / Saree Name',
                  prefixIcon:
                      Icon(Icons.edit),
                  border:
                      OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 15),

              TextField(
                controller: priceController,
                keyboardType:
                    const TextInputType
                        .numberWithOptions(
                  decimal: true,
                ),
                decoration:
                    const InputDecoration(
                  labelText:
                      'Selling Price',
                  prefixText: '₹ ',
                  prefixIcon:
                      Icon(Icons.sell),
                  border:
                      OutlineInputBorder(),
                ),
              ),
            ],

            // ==================================================
            // GOODS RETURN
            // ==================================================

            if (itemType == 2) ...[
              const Text(
                'Goods Return',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'Enter the returned item name manually, '
                'or select a saree from inventory.',
              ),

              const SizedBox(height: 15),

              TextField(
                controller: nameController,
                decoration:
                    const InputDecoration(
                  labelText:
                      'Returned Item / Saree Name',
                  hintText:
                      'Enter name if needed',
                  prefixIcon:
                      Icon(Icons.edit),
                  border:
                      OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 15),

              DropdownButtonFormField<Saree>(
                value: selectedSaree,
                isExpanded: true,
                decoration:
                    const InputDecoration(
                  labelText:
                      'Or Select Existing Saree',
                  prefixIcon:
                      Icon(Icons.checkroom),
                  border:
                      OutlineInputBorder(),
                ),
                items:
                    widget.sarees.map((saree) {
                  return DropdownMenuItem<Saree>(
                    value: saree,
                    child: Text(
                      saree.code.isEmpty
                          ? saree.name
                          : '${saree.name} (${saree.code})',
                      overflow:
                          TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    selectedSaree = value;

                    if (nameController
                        .text
                        .trim()
                        .isEmpty) {
                      nameController.text =
                          value?.name ?? '';
                    }
                  });
                },
              ),

              const SizedBox(height: 15),

              TextField(
                controller: priceController,
                keyboardType:
                    const TextInputType
                        .numberWithOptions(
                  decimal: true,
                ),
                decoration:
                    const InputDecoration(
                  labelText:
                      'Return Amount',
                  hintText:
                      'Example: 1500',
                  prefixText: '₹ ',
                  prefixIcon:
                      Icon(Icons.undo),
                  border:
                      OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 5),

              const Text(
                'The app will automatically record this as a negative amount.',
                style: TextStyle(
                  fontSize: 12,
                ),
              ),
            ],

            const SizedBox(height: 15),

            // ==================================================
            // QUANTITY
            // ==================================================

            TextField(
              controller:
                  quantityController,
              keyboardType:
                  const TextInputType
                      .numberWithOptions(
                decimal: true,
              ),
              decoration:
                  const InputDecoration(
                labelText: 'Quantity',
                prefixIcon:
                    Icon(Icons.numbers),
                border:
                    OutlineInputBorder(),
              ),
            ),

            if (error != null) ...[
              const SizedBox(height: 10),
              Text(
                error!,
                style:
                    const TextStyle(
                  color: Colors.red,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ],

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: save,
                icon:
                    const Icon(Icons.add),
                label: const Text(
                  'ADD TO INVOICE',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// INVENTORY
// ============================================================

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() =>
      _InventoryPageState();
}

class _InventoryPageState
    extends State<InventoryPage> {
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

  List<Saree> get filtered {
    final search =
        searchController.text.trim().toLowerCase();

    if (search.isEmpty) {
      return sarees;
    }

    return sarees.where((saree) {
      return saree.name
              .toLowerCase()
              .contains(search) ||
          saree.code
              .toLowerCase()
              .contains(search) ||
          saree.category
              .toLowerCase()
              .contains(search);
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
      final index = sarees.indexWhere(
        (x) => x.id == result.id,
      );

      if (index != -1) {
        setState(() {
          sarees[index] = result;
        });

        await saveInventory();
      }
    }
  }

  Future<void> deleteSaree(Saree saree) async {
    final confirm =
        await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Saree?'),
        content: Text(
          'Delete "${saree.name}"?',
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
      ),
    );

    if (confirm == true) {
      setState(() {
        sarees.removeWhere(
          (x) => x.id == saree.id,
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
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Inventory',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
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
                  child: filtered.isEmpty
                      ? const Center(
                          child: Text(
                            'No sarees found',
                          ),
                        )
                      : ListView.builder(
                          padding:
                              const EdgeInsets.all(12),
                          itemCount: filtered.length,
                          itemBuilder: (_, index) {
                            final saree =
                                filtered[index];

                            return Card(
                              child: ListTile(
                                title: Text(
                                  saree.name,
                                  style:
                                      const TextStyle(
                                    fontWeight:
                                        FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  'A ₹${_formatNumber(saree.price1)}   '
                                  'B ₹${_formatNumber(saree.price2)}   '
                                  'C ₹${_formatNumber(saree.price3)}\n'
                                  'Stock: ${_formatNumber(saree.stock)}',
                                ),
                                isThreeLine: true,
                                trailing:
                                    PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value ==
                                        'edit') {
                                      editSaree(saree);
                                    } else {
                                      deleteSaree(
                                          saree);
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child:
                                          Text('Edit'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child:
                                          Text('Delete'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton:
          FloatingActionButton.extended(
        onPressed: addSaree,
        icon: const Icon(Icons.add),
        label: const Text('Add Saree'),
      ),
    );
  }
}

// ============================================================
// SAREE FORM
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

class _SareeFormPageState
    extends State<SareeFormPage> {
  final name = TextEditingController();
  final code = TextEditingController();
  final category = TextEditingController();
  final purchase = TextEditingController();
  final price1 = TextEditingController();
  final price2 = TextEditingController();
  final price3 = TextEditingController();
  final stock = TextEditingController();
  final trader = TextEditingController();
  final notes = TextEditingController();

  @override
  void initState() {
    super.initState();

    final s = widget.saree;

    if (s != null) {
      name.text = s.name;
      code.text = s.code;
      category.text = s.category;
      purchase.text =
          _formatNumber(s.purchasePrice);
      price1.text =
          _formatNumber(s.price1);
      price2.text =
          _formatNumber(s.price2);
      price3.text =
          _formatNumber(s.price3);
      stock.text =
          _formatNumber(s.stock);
      trader.text = s.trader;
      notes.text = s.notes;
    }
  }

  double parse(String value) {
    return double.tryParse(
          value.replaceAll(',', '').trim(),
        ) ??
        0;
  }

  void save() {
    if (name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Saree name is required.',
          ),
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
      name: name.text.trim(),
      code: code.text.trim(),
      category: category.text.trim(),
      purchasePrice: parse(purchase.text),
      price1: parse(price1.text),
      price2: parse(price2.text),
      price3: parse(price3.text),
      stock: parse(stock.text),
      trader: trader.text.trim(),
      notes: notes.text.trim(),
    );

    Navigator.pop(context, saree);
  }

  @override
  void dispose() {
    name.dispose();
    code.dispose();
    category.dispose();
    purchase.dispose();
    price1.dispose();
    price2.dispose();
    price3.dispose();
    stock.dispose();
    trader.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.saree == null
              ? 'Add Saree'
              : 'Edit Saree',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(
              labelText: 'Saree Name *',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: code,
            decoration: const InputDecoration(
              labelText: 'Saree Code',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: category,
            decoration: const InputDecoration(
              labelText: 'Category',
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: purchase,
            keyboardType:
                const TextInputType.numberWithOptions(
              decimal: true,
            ),
            decoration: const InputDecoration(
              labelText: 'Purchase Price',
              prefixText: '₹ ',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: price1,
            keyboardType:
                const TextInputType.numberWithOptions(
              decimal: true,
            ),
            decoration: const InputDecoration(
              labelText: 'Price 1 — A',
              prefixText: '₹ ',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: price2,
            keyboardType:
                const TextInputType.numberWithOptions(
              decimal: true,
            ),
            decoration: const InputDecoration(
              labelText: 'Price 2 — B',
              prefixText: '₹ ',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: price3,
            keyboardType:
                const TextInputType.numberWithOptions(
              decimal: true,
            ),
            decoration: const InputDecoration(
              labelText: 'Price 3 — C',
              prefixText: '₹ ',
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: stock,
            keyboardType:
                const TextInputType.numberWithOptions(
              decimal: true,
            ),
            decoration: const InputDecoration(
              labelText: 'Stock',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: trader,
            decoration: const InputDecoration(
              labelText: 'Trader / Supplier',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: notes,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notes',
            ),
          ),
          const SizedBox(height: 25),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: save,
              icon: const Icon(Icons.save),
              label: Text(
                widget.saree == null
                    ? 'SAVE SAREE'
                    : 'UPDATE SAREE',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ACCOUNTS
// ============================================================

class AccountsPage extends StatelessWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Accounts',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.people),
              ),
              title: const Text(
                'Customers',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: const Text(
                'Create and manage customer accounts',
              ),
              trailing: const Icon(
                Icons.arrow_forward_ios,
                size: 18,
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const CustomerListPage(),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 8),

          Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.payments),
              ),
              title: const Text('Payments'),
              subtitle: const Text(
                'Record customer payments',
              ),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Payments module will be added next.',
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 8),

          Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(
                  Icons.account_balance_wallet,
                ),
              ),
              title: const Text(
                'Customer Outstanding',
              ),
              subtitle: const Text(
                'View outstanding balances',
              ),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Outstanding module will be connected next.',
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 8),

          Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.store),
              ),
              title: const Text(
                'Traders / Suppliers',
              ),
              subtitle: const Text(
                'Manage supplier accounts',
              ),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Trader module will be added later.',
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// CREATE CUSTOMER
// ============================================================

class CreateCustomerPage
    extends StatefulWidget {
  const CreateCustomerPage({
    super.key,
  });

  @override
  State<CreateCustomerPage> createState() =>
      _CreateCustomerPageState();
}

class _CreateCustomerPageState
    extends State<CreateCustomerPage> {
  final nameController =
      TextEditingController();

  final idController =
      TextEditingController();

  final pinController =
      TextEditingController();

  final gstController =
      TextEditingController();

  bool saving = false;

  Future<void> saveCustomer() async {
    final name =
        nameController.text.trim();

    final id =
        idController.text.trim();

    final pin =
        pinController.text.trim();

    final gst =
        gstController.text.trim();

    if (name.isEmpty) {
      showMessage(
        'Customer name is required.',
      );
      return;
    }

    if (id.isEmpty) {
      showMessage(
        'Customer ID is required.',
      );
      return;
    }

    if (pin.isEmpty) {
      showMessage(
        'Customer PIN is required.',
      );
      return;
    }

    if (pin.length < 4) {
      showMessage(
        'Customer PIN must contain at least 4 digits.',
      );
      return;
    }

    setState(() {
      saving = true;
    });

    try {
      final cleanId =
          id.toLowerCase();

      final exists =
          await CustomerStorage.idExists(
        cleanId,
      );

      if (exists) {
        if (!mounted) return;

        setState(() {
          saving = false;
        });

        showMessage(
          'This Customer ID already exists. Please choose another.',
        );

        return;
      }

      final customer = Customer(
        id: cleanId,
        name: name,
        pin: pin,
        gstNumber: gst,
        outstanding: 0,
      );

      await CustomerStorage.save(
        customer,
      );

      if (!mounted) return;

      Navigator.pop(
        context,
        customer,
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        saving = false;
      });

      showMessage(
        'Could not create customer: $e',
      );
    }
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    idController.dispose();
    pinController.dispose();
    gstController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Create Customer',
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding:
              const EdgeInsets.all(16),
          children: [
            const Card(
              child: Padding(
                padding:
                    EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.person_add,
                      size: 35,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Create a unique customer login',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            TextField(
              controller:
                  nameController,
              textCapitalization:
                  TextCapitalization.words,
              decoration:
                  const InputDecoration(
                labelText:
                    'Customer Name *',
                prefixIcon:
                    Icon(Icons.person),
              ),
            ),

            const SizedBox(height: 14),

            TextField(
              controller:
                  idController,
              textCapitalization:
                  TextCapitalization.none,
              decoration:
                  const InputDecoration(
                labelText:
                    'Customer ID *',
                hintText:
                    'Example: cust001',
                prefixIcon:
                    Icon(Icons.badge),
              ),
            ),

            const SizedBox(height: 14),

            TextField(
              controller:
                  pinController,
              keyboardType:
                  TextInputType.number,
              obscureText: true,
              decoration:
                  const InputDecoration(
                labelText:
                    'Customer PIN *',
                hintText:
                    'Minimum 4 digits',
                prefixIcon:
                    Icon(Icons.lock),
              ),
            ),

            const SizedBox(height: 14),

            TextField(
              controller:
                  gstController,
              textCapitalization:
                  TextCapitalization.characters,
              decoration:
                  const InputDecoration(
                labelText:
                    'GST Number (Optional)',
                hintText:
                    'Leave blank if not applicable',
                prefixIcon:
                    Icon(Icons.receipt_long),
              ),
            ),

            const SizedBox(height: 10),

            const Text(
              '* Required fields',
              style: TextStyle(
                fontSize: 12,
              ),
            ),

            const SizedBox(height: 25),

            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: saving
                    ? null
                    : saveCustomer,
                icon: saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.save,
                      ),
                label: Text(
                  saving
                      ? 'SAVING...'
                      : 'CREATE CUSTOMER',
                ),
              ),
            ),

            const SizedBox(height: 20),

            const Card(
              child: Padding(
                padding:
                    EdgeInsets.all(14),
                child: Text(
                  'The Customer ID must be unique. '
                  'The GST number is optional and can be left blank.',
                ),
              ),
            ),
          ],
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('More'),
      ),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          ListTile(
            leading: Icon(Icons.shopping_bag),
            title: Text('Purchases'),
          ),
          ListTile(
            leading: Icon(Icons.assignment_return),
            title: Text('Returns'),
          ),
          ListTile(
            leading: Icon(
              Icons.account_balance_wallet,
            ),
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

String _dateText(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.year}';
}
