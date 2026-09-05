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
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.black,
        ),
        useMaterial3: true,
        inputDecorationTheme:
            const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const SessionPage(),
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

// ============================================================
// PURCHASE MODEL
// ============================================================

class Purchase {
  String id;
  DateTime date;
  String trader;
  String sareeId;
  String sareeName;
  String sareeCode;
  double quantity;
  double purchasePrice;
  double gst;
  String notes;

  Purchase({
    required this.id,
    required this.date,
    required this.trader,
    required this.sareeId,
    required this.sareeName,
    required this.sareeCode,
    required this.quantity,
    required this.purchasePrice,
    required this.gst,
    required this.notes,
  });

  // Goods value before GST
  double get total =>
      quantity * purchasePrice;

  // GST @ 5%
  double get gstAmount =>
      gst;

  // Total amount actually payable to trader
  double get grandTotal =>
      total + gstAmount;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'trader': trader,
      'sareeId': sareeId,
      'sareeName': sareeName,
      'sareeCode': sareeCode,
      'quantity': quantity,
      'purchasePrice': purchasePrice,
      'gst': gst,
      'notes': notes,
    };
  }

  factory Purchase.fromJson(
    Map<String, dynamic> json,
  ) {
    final quantity =
        (json['quantity'] as num?)?.toDouble() ?? 0;

    final purchasePrice =
        (json['purchasePrice'] as num?)?.toDouble() ?? 0;

    final goodsValue =
        quantity * purchasePrice;

    // All trader purchases use 5% GST.
    // Older saved purchases that do not have
    // a GST field are automatically migrated.
    final gst =
        json['gst'] != null
            ? (json['gst'] as num?)?.toDouble() ?? 0
            : goodsValue * 0.05;

    return Purchase(
      id: json['id']?.toString() ?? '',
      date: DateTime.tryParse(
            json['date']?.toString() ?? '',
          ) ??
          DateTime.now(),
      trader:
          json['trader']?.toString() ?? '',
      sareeId:
          json['sareeId']?.toString() ?? '',
      sareeName:
          json['sareeName']?.toString() ?? '',
      sareeCode:
          json['sareeCode']?.toString() ?? '',
      quantity: quantity,
      purchasePrice: purchasePrice,
      gst: gst,
      notes:
          json['notes']?.toString() ?? '',
    );
  }
}

// ============================================================
// PURCHASE STORAGE
// ============================================================

class PurchaseStorage {
  static const String purchasesKey =
      'ajanta_purchases';

  static const String purchaseNumberKey =
      'ajanta_purchase_number';

  static Future<List<Purchase>> load() async {
    final prefs =
        await SharedPreferences.getInstance();

    final data =
        prefs.getString(purchasesKey);

    if (data == null || data.isEmpty) {
      return [];
    }

    try {
      final decoded = jsonDecode(data) as List;

      return decoded
          .map(
            (item) => Purchase.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(
    List<Purchase> purchases,
  ) async {
    final prefs =
        await SharedPreferences.getInstance();

    await prefs.setString(
      purchasesKey,
      jsonEncode(
        purchases
            .map(
              (purchase) => purchase.toJson(),
            )
            .toList(),
      ),
    );
  }

  static Future<String> nextPurchaseId() async {
    final prefs =
        await SharedPreferences.getInstance();

    final next =
        (prefs.getInt(purchaseNumberKey) ?? 0) + 1;

    await prefs.setInt(
      purchaseNumberKey,
      next,
    );

    return 'PUR-${next.toString().padLeft(4, '0')}';
  }

  static Future<void> delete(
    String purchaseId,
  ) async {
    final purchases = await load();

    purchases.removeWhere(
      (purchase) => purchase.id == purchaseId,
    );

    await save(purchases);
  }
}

// ============================================================
// TRADER PAYMENT MODEL
// ============================================================

class TraderPayment {
  String id;
  DateTime date;
  String trader;
  double amount;
  String reference;
  String notes;

  TraderPayment({
    required this.id,
    required this.date,
    required this.trader,
    required this.amount,
    required this.reference,
    required this.notes,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'trader': trader,
      'amount': amount,
      'reference': reference,
      'notes': notes,
    };
  }

  factory TraderPayment.fromJson(
    Map<String, dynamic> json,
  ) {
    return TraderPayment(
      id: json['id']?.toString() ?? '',
      date: DateTime.tryParse(
            json['date']?.toString() ?? '',
          ) ??
          DateTime.now(),
      trader: json['trader']?.toString() ?? '',
      amount:
          (json['amount'] as num?)?.toDouble() ?? 0,
      reference:
          json['reference']?.toString() ?? '',
      notes:
          json['notes']?.toString() ?? '',
    );
  }
}

// ============================================================
// TRADER PAYMENT STORAGE
// ============================================================

class TraderPaymentStorage {
  static const String paymentsKey =
      'ajanta_trader_payments';

  static const String paymentNumberKey =
      'ajanta_trader_payment_number';

  static Future<List<TraderPayment>> load() async {
    final prefs =
        await SharedPreferences.getInstance();

    final data =
        prefs.getString(paymentsKey);

    if (data == null || data.isEmpty) {
      return [];
    }

    try {
      final decoded =
          jsonDecode(data) as List;

      return decoded
          .map(
            (item) => TraderPayment.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(
    List<TraderPayment> payments,
  ) async {
    final prefs =
        await SharedPreferences.getInstance();

    await prefs.setString(
      paymentsKey,
      jsonEncode(
        payments
            .map(
              (payment) => payment.toJson(),
            )
            .toList(),
      ),
    );
  }

  static Future<String> nextPaymentId() async {
    final prefs =
        await SharedPreferences.getInstance();

    final next =
        (prefs.getInt(paymentNumberKey) ?? 0) + 1;

    await prefs.setInt(
      paymentNumberKey,
      next,
    );

    return 'TP-${next.toString().padLeft(4, '0')}';
  }

  static Future<void> delete(
    String paymentId,
  ) async {
    final payments = await load();

    payments.removeWhere(
      (payment) => payment.id == paymentId,
    );

    await save(payments);
  }
}

// ============================================================
// ADD TRADER PAYMENT
// ============================================================

class AddTraderPaymentPage extends StatefulWidget {
  const AddTraderPaymentPage({super.key});

  @override
  State<AddTraderPaymentPage> createState() =>
      _AddTraderPaymentPageState();
}

class _AddTraderPaymentPageState
    extends State<AddTraderPaymentPage> {
  final amountController =
      TextEditingController();

  final referenceController =
      TextEditingController();

  final notesController =
      TextEditingController();

  List<Purchase> purchases = [];

  List<String> traders = [];

  String? selectedTrader;

  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadTraders();
  }

  @override
  void dispose() {
    amountController.dispose();
    referenceController.dispose();
    notesController.dispose();
    super.dispose();
  }

  Future<void> loadTraders() async {
    final data =
        await PurchaseStorage.load();

    final traderMap = <String, String>{};

    for (final purchase in data) {
      final name =
          purchase.trader.trim();

      if (name.isEmpty) {
        continue;
      }

      final key =
          name.toLowerCase();

      if (!traderMap.containsKey(key)) {
        traderMap[key] = name;
      }
    }

    final traderList =
        traderMap.values.toList();

    traderList.sort(
      (a, b) => a.toLowerCase()
          .compareTo(b.toLowerCase()),
    );

    if (!mounted) return;

    setState(() {
      purchases = data;
      traders = traderList;
      loading = false;
    });
  }

  Future<void> savePayment() async {
    if (selectedTrader == null ||
        selectedTrader!.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Please select a trader.',
          ),
        ),
      );
      return;
    }

    final amount =
        double.tryParse(
      amountController.text.trim(),
    );

    if (amount == null ||
        amount <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter a valid payment amount.',
          ),
        ),
      );
      return;
    }

    final paymentId =
        await TraderPaymentStorage
            .nextPaymentId();

    final payment =
        TraderPayment(
      id: paymentId,
      date: DateTime.now(),
      trader: selectedTrader!.trim(),
      amount: amount,
      reference:
          referenceController.text.trim(),
      notes:
          notesController.text.trim(),
    );

    final payments =
        await TraderPaymentStorage.load();

    payments.add(payment);

    await TraderPaymentStorage.save(
      payments,
    );

    if (!mounted) return;

    Navigator.pop(
      context,
      payment,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Pay Trader',
        ),
      ),
      body: loading
          ? const Center(
              child:
                  CircularProgressIndicator(),
            )
          : traders.isEmpty
              ? const Center(
                  child: Text(
                    'No traders found.\n'
                    'Please add a purchase first.',
                    textAlign:
                        TextAlign.center,
                  ),
                )
              : SingleChildScrollView(
                  padding:
                      const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .stretch,
                    children: [
                      DropdownButtonFormField<String>(
  value:
      selectedTrader,
  decoration:
      const InputDecoration(
    labelText:
        'Select Trader',
    border:
        OutlineInputBorder(),
  ),
  menuMaxHeight: 350,
  items:
      traders.map(
    (trader) {
      return DropdownMenuItem<String>(
        value: trader,
        child:
            Text(trader),
      );
    },
  ).toList(),
  onChanged:
      (value) {
    setState(() {
      selectedTrader =
          value;
    });
  },
),

                      const SizedBox(
                        height: 16,
                      ),

                      TextField(
                        controller:
                            amountController,
                        keyboardType:
                            const TextInputType
                                .numberWithOptions(
                          decimal: true,
                        ),
                        decoration:
                            const InputDecoration(
                          labelText:
                              'Payment Amount',
                          prefixText: '₹ ',
                          border:
                              OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(
                        height: 16,
                      ),

                      TextField(
                        controller:
                            referenceController,
                        decoration:
                            const InputDecoration(
                          labelText:
                              'Reference / Transaction No.',
                          border:
                              OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(
                        height: 16,
                      ),

                      TextField(
                        controller:
                            notesController,
                        maxLines: 3,
                        decoration:
                            const InputDecoration(
                          labelText:
                              'Notes',
                          border:
                              OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(
  height: 24,
),
FilledButton.icon(
                        onPressed:
                            savePayment,
                        icon: const Icon(
                          Icons
                              .payments,
                        ),
                        label: const Text(
                          'SAVE PAYMENT',
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

// ============================================================
// TRADER LEDGER PAGE
// ============================================================

class TraderLedgerPage extends StatefulWidget {
  const TraderLedgerPage({super.key});

  @override
  State<TraderLedgerPage> createState() =>
      _TraderLedgerPageState();
}

class _TraderLedgerPageState
    extends State<TraderLedgerPage> {
  List<Purchase> purchases = [];
  List<TraderPayment> payments = [];

  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadLedger();
  }

  Future<void> loadLedger() async {
    final purchaseData =
        await PurchaseStorage.load();

    final paymentData =
        await TraderPaymentStorage.load();

    if (!mounted) return;

    setState(() {
      purchases = purchaseData;
      payments = paymentData;
      loading = false;
    });
  }

  String normalizeTrader(String name) {
    return name.trim().toLowerCase();
  }

  String displayTraderName(String name) {
    final trimmed = name.trim();

    if (trimmed.isEmpty) {
      return 'Unknown Trader';
    }

    return trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, String> traderNames = {};

    for (final purchase in purchases) {
      final key =
          normalizeTrader(purchase.trader);

      if (key.isNotEmpty &&
          !traderNames.containsKey(key)) {
        traderNames[key] =
            displayTraderName(purchase.trader);
      }
    }

    for (final payment in payments) {
      final key =
          normalizeTrader(payment.trader);

      if (key.isNotEmpty &&
          !traderNames.containsKey(key)) {
        traderNames[key] =
            displayTraderName(payment.trader);
      }
    }

    final traderKeys =
        traderNames.keys.toList()..sort();

    return Scaffold(
  appBar: AppBar(
    title: const Text(
      'Trader Ledger',
    ),
    actions: [
      IconButton(
        tooltip: 'Pay Trader',
        icon: const Icon(
          Icons.payments,
        ),
        onPressed: () async {
          final result =
              await Navigator.push<TraderPayment>(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const AddTraderPaymentPage(),
            ),
          );

          if (result == null) return;

          await loadLedger();
        },
      ),
    ],
  ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : traderKeys.isEmpty
              ? const Center(
                  child: Text(
                    'No trader transactions found.',
                  ),
                )
              : ListView.builder(
                  padding:
                      const EdgeInsets.all(12),
                  itemCount:
                      traderKeys.length,
                  itemBuilder:
                      (context, index) {
                    final traderKey =
                        traderKeys[index];

                    final traderName =
                        traderNames[traderKey] ??
                            'Unknown Trader';

                    final traderPurchases =
                        purchases.where(
                      (purchase) =>
                          normalizeTrader(
                            purchase.trader,
                          ) ==
                          traderKey,
                    );

                    final traderPayments =
                        payments.where(
                      (payment) =>
                          normalizeTrader(
                            payment.trader,
                          ) ==
                          traderKey,
                    );

                    final totalGoods =
    traderPurchases.fold<double>(
  0,
  (sum, purchase) =>
      sum + purchase.total,
);

final totalGST =
    traderPurchases.fold<double>(
  0,
  (sum, purchase) =>
      sum + purchase.gstAmount,
);

final totalPayable =
    traderPurchases.fold<double>(
  0,
  (sum, purchase) =>
      sum + purchase.grandTotal,
);

                    final totalPaid =
                        traderPayments.fold<double>(
                      0,
                      (sum, payment) =>
                          sum + payment.amount,
                    );

                    final outstanding =
    totalPayable -
        totalPaid;

                    return Card(
                      margin:
                          const EdgeInsets.only(
                        bottom: 12,
                      ),
                      child: Padding(
                        padding:
                            const EdgeInsets.all(
                          16,
                        ),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                          children: [
                            Text(
                              traderName,
                              style:
                                  const TextStyle(
                                fontSize: 18,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),

                            const SizedBox(
                              height: 12,
                            ),

                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment
                                      .spaceBetween,
                              children: [
                                const Text(
                                  'Purchases',
                                ),
                                Text(
                                  '₹${totalPurchases.toStringAsFixed(2)}',
                                  style:
                                      const TextStyle(
                                    fontWeight:
                                        FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(
                              height: 6,
                            ),

                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment
                                      .spaceBetween,
                              children: [
                                const Text(
                                  'Paid',
                                ),
                                Text(
                                  '₹${totalPaid.toStringAsFixed(2)}',
                                  style:
                                      const TextStyle(
                                    fontWeight:
                                        FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),

                            const Divider(
                              height: 20,
                            ),

                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment
                                      .spaceBetween,
                              children: [
                                const Text(
                                  'Outstanding',
                                  style:
                                      TextStyle(
                                    fontWeight:
                                        FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '₹${outstanding.toStringAsFixed(2)}',
                                  style:
                                      TextStyle(
                                    fontSize: 16,
                                    fontWeight:
                                        FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

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
  String customerId;
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
    required this.customerId,
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
      'customerId': customerId,
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
  customerId:
      map['customerId']?.toString() ?? '',
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

    // ==========================================================
  // RECALCULATE INVOICE PAYMENTS FOR CUSTOMERS
  // ==========================================================

  static Future<void> recalculateCustomerPayments(
    Set<String> customerIds,
  ) async {
    if (customerIds.isEmpty) return;

    final invoices = await load();
    final payments = await PaymentStorage.load();

    for (final customerId in customerIds) {
      final normalizedCustomerId = customerId.trim();

      if (normalizedCustomerId.isEmpty) {
        continue;
      }

      final customerInvoices = invoices
          .where(
            (invoice) =>
                invoice.customerId.trim() ==
                normalizedCustomerId,
          )
          .toList();

      final customerPayments = payments
          .where(
            (payment) =>
                payment.customerId.trim() ==
                    normalizedCustomerId &&
                payment.amount > 0,
          )
          .toList();

      customerInvoices.sort((a, b) {
        final dateCompare = a.date.compareTo(b.date);

        if (dateCompare != 0) {
          return dateCompare;
        }

        return a.number.compareTo(b.number);
      });

      customerPayments.sort((a, b) {
        final dateCompare = a.date.compareTo(b.date);

        if (dateCompare != 0) {
          return dateCompare;
        }

        return a.id.compareTo(b.id);
      });

      for (final invoice in customerInvoices) {
        invoice.paid = 0;

        invoice.outstanding =
            invoice.grandTotal > 0
                ? invoice.grandTotal
                : 0;
      }

      for (final payment in customerPayments) {
        double remainingPayment = payment.amount;

        for (final invoice in customerInvoices) {
          if (remainingPayment <= 0) {
            break;
          }

          if (invoice.grandTotal <= 0) {
            continue;
          }

          final remainingInvoiceAmount =
              invoice.grandTotal - invoice.paid;

          if (remainingInvoiceAmount <= 0) {
            continue;
          }

          final amountToApply =
              remainingPayment < remainingInvoiceAmount
                  ? remainingPayment
                  : remainingInvoiceAmount;

          invoice.paid += amountToApply;

          invoice.outstanding =
              invoice.grandTotal - invoice.paid;

          if (invoice.outstanding < 0) {
            invoice.outstanding = 0;
          }

          remainingPayment -= amountToApply;
        }
      }
    }

    await save(invoices);
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
// PAYMENT MODEL
// ============================================================

class Payment {
  String id;
  String customerId;
  String customerName;
  DateTime date;
  double amount;
  String reference;
  String notes;

  Payment({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.date,
    required this.amount,
    this.reference = '',
    this.notes = '',
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customerId': customerId,
      'customerName': customerName,
      'date': date.toIso8601String(),
      'amount': amount,
      'reference': reference,
      'notes': notes,
    };
  }

  factory Payment.fromJson(Map<String, dynamic> map) {
    return Payment(
      id: map['id']?.toString() ?? '',
      customerId:
          map['customerId']?.toString() ?? '',
      customerName:
          map['customerName']?.toString() ?? '',
      date: DateTime.tryParse(
            map['date']?.toString() ?? '',
          ) ??
          DateTime.now(),
      amount:
          (map['amount'] as num?)?.toDouble() ?? 0,
      reference:
          map['reference']?.toString() ?? '',
      notes:
          map['notes']?.toString() ?? '',
    );
  }
}

// ============================================================
// PAYMENT STORAGE
// ============================================================

class PaymentStorage {
  static const String paymentsKey =
      'ajanta_payments';

  static const String paymentNumberKey =
      'ajanta_payment_number';

  // ==========================================================
  // LOAD PAYMENTS
  // ==========================================================

  static Future<List<Payment>> load() async {
    final prefs =
        await SharedPreferences.getInstance();

    final data = prefs.getString(paymentsKey);

    if (data == null || data.isEmpty) {
      return [];
    }

    try {
      final decoded = jsonDecode(data) as List;

      return decoded
          .map(
            (item) => Payment.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ==========================================================
  // SAVE PAYMENTS
  // ==========================================================

  static Future<void> save(
    List<Payment> payments,
  ) async {
    final prefs =
        await SharedPreferences.getInstance();

    await prefs.setString(
      paymentsKey,
      jsonEncode(
        payments
            .map((payment) => payment.toJson())
            .toList(),
      ),
    );
  }

  // ==========================================================
  // GENERATE PAYMENT ID
  // ==========================================================

  static Future<String> nextPaymentId() async {
    final prefs =
        await SharedPreferences.getInstance();

    final next =
        (prefs.getInt(paymentNumberKey) ?? 0) + 1;

    await prefs.setInt(
      paymentNumberKey,
      next,
    );

    return 'PAY-${next.toString().padLeft(4, '0')}';
  }

  // ==========================================================
  // DELETE ONE PAYMENT
  // ==========================================================

        static Future<void> delete(
    String paymentId,
  ) async {
    final payments = await load();

    payments.removeWhere(
      (payment) => payment.id == paymentId,
    );

    await save(payments);
        }
    }

// ============================================================
// SESSION MANAGEMENT
// ============================================================

class SessionManager {
  static const String loggedInKey =
      'asc_logged_in';

  static const String customerKey =
      'asc_logged_in_customer';

  static const String customerIdKey =
      'asc_customer_id';

  static Future<void> saveAdminSession() async {
    final prefs =
        await SharedPreferences.getInstance();

    await prefs.setBool(loggedInKey, true);
    await prefs.setBool(customerKey, false);
    await prefs.remove(customerIdKey);
  }

  static Future<void> saveCustomerSession(
    String customerId,
  ) async {
    final prefs =
        await SharedPreferences.getInstance();

    await prefs.setBool(loggedInKey, true);
    await prefs.setBool(customerKey, true);
    await prefs.setString(
      customerIdKey,
      customerId,
    );
  }

  static Future<bool> isLoggedIn() async {
    final prefs =
        await SharedPreferences.getInstance();

    return prefs.getBool(loggedInKey) ?? false;
  }

  static Future<bool> isCustomer() async {
    final prefs =
        await SharedPreferences.getInstance();

    return prefs.getBool(customerKey) ?? false;
  }

  static Future<String> getCustomerId() async {
    final prefs =
        await SharedPreferences.getInstance();

    return prefs.getString(customerIdKey) ?? '';
  }

  static Future<void> logout() async {
    final prefs =
        await SharedPreferences.getInstance();

    await prefs.remove(loggedInKey);
    await prefs.remove(customerKey);
    await prefs.remove(customerIdKey);
  }
}

// ============================================================
// SESSION CHECK
// ============================================================

class SessionPage extends StatefulWidget {
  const SessionPage({super.key});

  @override
  State<SessionPage> createState() =>
      _SessionPageState();
}

class _SessionPageState extends State<SessionPage> {
  @override
  void initState() {
    super.initState();
    checkSession();
  }

  Future<void> checkSession() async {
    final loggedIn =
        await SessionManager.isLoggedIn();

    if (!mounted) return;

    if (!loggedIn) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const LoginPage(),
        ),
      );
      return;
    }

    final customer =
        await SessionManager.isCustomer();

    if (!mounted) return;

    String? customerId;

    if (customer) {
      customerId =
          await SessionManager.getCustomerId();
    }

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => HomePage(
          customer: customer,
          customerId: customerId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
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

bool customer = true;

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
      await SessionManager.saveAdminSession();

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const HomePage(
            customer: false,
          ),
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
      await SessionManager.saveCustomerSession(
        enteredId,
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomePage(
            customer: true,
            customerId: enteredId,
          ),
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
// ============================================================
// CUSTOMER PORTAL
// ============================================================

class CustomerPortalPage extends StatefulWidget {
  final String customerId;

  const CustomerPortalPage({
    super.key,
    required this.customerId,
  });

  @override
  State<CustomerPortalPage> createState() =>
      _CustomerPortalPageState();
}

class _CustomerPortalPageState
    extends State<CustomerPortalPage> {
  Customer? customer;
  List<Invoice> invoices = [];
  bool loading = true;

  double get totalPaid {
    return invoices.fold(
      0,
      (sum, invoice) => sum + invoice.paid,
    );
  }

  double get totalOutstanding {
    return invoices.fold(
      0,
      (sum, invoice) => sum + invoice.outstanding,
    );
  }

  Future<void> loadData() async {
    try {
      final loadedCustomer =
          await CustomerStorage.findById(widget.customerId);

      final allInvoices =
          await InvoiceStorage.load();

      final customerInvoices = allInvoices
          .where(
            (invoice) =>
                invoice.customerId.trim() ==
                widget.customerId.trim(),
          )
          .toList();

      customerInvoices.sort(
        (a, b) => b.date.compareTo(a.date),
      );

      if (!mounted) return;

      setState(() {
        customer = loadedCustomer;
        invoices = customerInvoices;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to load customer data: $e',
          ),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    loadData();
  }

  void logout() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const LoginPage(),
      ),
      (route) => false,
    );
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
        title: const Text('Customer Portal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: logout,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // CUSTOMER PROFILE
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Welcome',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      customer?.name ?? 'Customer',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Customer ID: ${widget.customerId}',
                    ),
                    if ((customer?.gstNumber ?? '')
                        .trim()
                        .isNotEmpty)
                      Text(
                        'GST: ${customer!.gstNumber}',
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // SUMMARY
            Row(
              children: [
                Expanded(
                  child: Card(
                    child: Padding(
                      padding:
                          const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.payments_outlined,
                            size: 30,
                          ),
                          const SizedBox(height: 8),
                          const Text('Paid'),
                          const SizedBox(height: 4),
                          Text(
                            '₹${totalPaid.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight:
                                  FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding:
                          const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 30,
                          ),
                          const SizedBox(height: 8),
                          const Text('Outstanding'),
                          const SizedBox(height: 4),
                          Text(
                            '₹${totalOutstanding.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight:
                                  FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            const Text(
              'My Invoices',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            if (invoices.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: Text(
                      'No invoices found.',
                    ),
                  ),
                ),
              ),

            ...invoices.map(
              (invoice) {
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
                      '${invoice.date.day.toString().padLeft(2, '0')}/'
                      '${invoice.date.month.toString().padLeft(2, '0')}/'
                      '${invoice.date.year}\n'
                      'Paid: ₹${invoice.paid.toStringAsFixed(2)}  •  '
                      'Due: ₹${invoice.outstanding.toStringAsFixed(2)}',
                    ),
                    isThreeLine: true,
                    trailing: Text(
                      '₹${invoice.grandTotal.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (_) {
                          return AlertDialog(
                            title: Text(
                              'Invoice ${invoice.number}',
                            ),
                            content: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Total: ₹${invoice.grandTotal.toStringAsFixed(2)}',
                                  ),
                                  Text(
                                    'Paid: ₹${invoice.paid.toStringAsFixed(2)}',
                                  ),
                                  Text(
                                    'Outstanding: ₹${invoice.outstanding.toStringAsFixed(2)}',
                                  ),
                                  const Divider(),
                                  ...invoice.items.map(
                                    (item) {
                                      return Padding(
                                        padding:
                                            const EdgeInsets
                                                .symmetric(
                                          vertical: 4,
                                        ),
                                        child: Text(
                                          '${item.sareeName}  '
                                          '× ${item.quantity}  '
                                          '₹${item.total.toStringAsFixed(2)}',
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(
                                    context,
                                  );
                                },
                                child:
                                    const Text('Close'),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                );
              },
            ),

            const SizedBox(height: 20),

            // PROFILE
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.person_outline,
                ),
                title: const Text('My Profile'),
                subtitle: Text(
                  'ID: ${widget.customerId}',
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                ),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) {
                      return AlertDialog(
                        title:
                            const Text('My Profile'),
                        content: Column(
                          mainAxisSize:
                              MainAxisSize.min,
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Name: ${customer?.name ?? ''}',
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Customer ID: ${customer?.id ?? widget.customerId}',
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'GST: ${customer?.gstNumber ?? 'Not provided'}',
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(
                                context,
                              );
                            },
                            child:
                                const Text('Close'),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),

            const SizedBox(height: 12),

            OutlinedButton.icon(
              onPressed: logout,
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
            ),
          ],
        ),
      ),
    );
  }
}
class HomePage extends StatefulWidget {
  final bool customer;
  final String? customerId;

  const HomePage({
    super.key,
    required this.customer,
    this.customerId,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    // CUSTOMER APP
    if (widget.customer) {
      return CustomerPortalPage(
        customerId: widget.customerId ?? '',
      );
    }

    // ADMIN APP
    final pages = [
      DashboardPage(customer: false),
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

    if (result == null) return;

    setState(() {
      invoices.insert(0, result);
    });

        await InvoiceStorage.save(invoices);

    // ==========================================================
    // UPDATE INVENTORY STOCK AFTER INVOICE
    // ==========================================================

    final sarees = await InventoryStorage.load();

    for (final item in result.items) {
      if (item.sareeId.trim().isEmpty) {
        continue;
      }

      final index = sarees.indexWhere(
        (saree) => saree.id == item.sareeId,
      );

      if (index == -1) {
        continue;
      }

      if (item.priceCode == 'RETURN') {
        // Returned goods come back into stock.
        sarees[index].stock += item.quantity;
      } else {
        // Normal sale reduces stock.
        sarees[index].stock -= item.quantity;

        // Never allow stock to become negative.
        if (sarees[index].stock < 0) {
          sarees[index].stock = 0;
        }
      }
    }

    await InventoryStorage.save(sarees);

    // ==========================================================
    // RECORD AMOUNT RECEIVED WITH THE INVOICE AS A PAYMENT
    // ==========================================================

    if (result.paid > 0 &&
        result.customerId.trim().isNotEmpty) {
      final paymentId =
          await PaymentStorage.nextPaymentId();

      final payment = Payment(
        id: paymentId,
        customerId: result.customerId,
        customerName: result.customerName,
        date: result.date,
        amount: result.paid,
        reference: 'Invoice ${result.number}',
        notes: 'Amount received with invoice',
      );

      final payments =
          await PaymentStorage.load();

      payments.add(payment);

      await PaymentStorage.save(payments);
    }

    // ==========================================================
    // RECALCULATE CUSTOMER INVOICE BALANCES
    // ==========================================================

    if (result.customerId.trim().isNotEmpty) {
      await InvoiceStorage.recalculateCustomerPayments(
        {result.customerId},
      );
    }

    // Reload the invoices so the Sales screen
    // displays the recalculated Paid/Outstanding values.
    final updatedInvoices =
        await InvoiceStorage.load();

    if (!mounted) return;

    setState(() {
      invoices = updatedInvoices;
    });
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
List<Customer> customers = [];

Customer? selectedCustomer;

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
  final customerList = await CustomerStorage.load();
  final number = await InvoiceStorage.nextInvoiceNumber();

  if (!mounted) return;

  setState(() {
    sarees = inventory;
    customers = customerList;
    invoiceNumber = number;
    loading = false;
  });
  }

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

  Future<void> saveInvoice() async {
    if (selectedCustomer == null) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Please select a customer.',
      ),
    ),
  );
  return;
    }
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
  customerId: selectedCustomer?.id ?? '',
  customerName:
      selectedCustomer?.name ?? '',
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

            DropdownButtonFormField<Customer>(
  value: selectedCustomer,
  decoration: const InputDecoration(
    labelText: 'Customer',
    prefixIcon: Icon(Icons.person),
    border: OutlineInputBorder(),
  ),
  items: customers.map((customer) {
    return DropdownMenuItem<Customer>(
      value: customer,
      child: Text(
        '${customer.name} (${customer.id})',
      ),
    );
  }).toList(),
  onChanged: (customer) {
    setState(() {
      selectedCustomer = customer;
    });
  },
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
                onChanged: (_) {
    setState(() {});
  },
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
  final inventoryData =
      await InventoryStorage.load();

  final purchaseData =
      await PurchaseStorage.load();

  final traderMap = <String, String>{};

  for (final purchase in purchaseData) {
    final name =
        purchase.trader.trim();

    if (name.isEmpty) {
      continue;
    }

    final key =
        name.toLowerCase();

    if (!traderMap.containsKey(key)) {
      traderMap[key] = name;
    }
  }

  final traderList =
      traderMap.values.toList();

  traderList.sort(
    (a, b) => a.toLowerCase()
        .compareTo(b.toLowerCase()),
  );

  if (!mounted) return;

  setState(() {
    sarees = inventoryData;
    traders = traderList;
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
    title: const Text(
      'Payments',
      style: TextStyle(
        fontWeight: FontWeight.bold,
      ),
    ),
    subtitle: const Text(
      'Record and manage customer payments',
    ),
    trailing: const Icon(
      Icons.arrow_forward_ios,
      size: 18,
    ),
    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const PaymentsPage(),
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
      style: TextStyle(
        fontWeight: FontWeight.bold,
      ),
    ),
    subtitle: const Text(
      'View customer balances and account history',
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
              const CustomerOutstandingPage(),
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
// ADD PURCHASE PAGE
// ============================================================

class AddPurchasePage extends StatefulWidget {
  const AddPurchasePage({super.key});

  @override
  State<AddPurchasePage> createState() =>
      _AddPurchasePageState();
}

class _AddPurchasePageState
    extends State<AddPurchasePage> {
  final traderController =
      TextEditingController();

  final quantityController =
      TextEditingController();

  final priceController =
      TextEditingController();

  final notesController =
      TextEditingController();

  List<Saree> sarees = [];

List<String> traders = [];

Saree? selectedSaree;

String? selectedTrader;

bool newTrader = false;

bool loading = true;
  @override
  void initState() {
    super.initState();
    loadInventory();
  }

  @override
  void dispose() {
    traderController.dispose();
    quantityController.dispose();
    priceController.dispose();
    notesController.dispose();
    super.dispose();
  }

  Future<void> loadInventory() async {
  final inventoryData =
      await InventoryStorage.load();

  final purchaseData =
      await PurchaseStorage.load();

  final traderMap = <String, String>{};

  for (final purchase in purchaseData) {
    final name =
        purchase.trader.trim();

    if (name.isEmpty) {
      continue;
    }

    final key =
        name.toLowerCase();

    if (!traderMap.containsKey(key)) {
      traderMap[key] = name;
    }
  }

  final traderList =
      traderMap.values.toList();

  traderList.sort(
    (a, b) => a.toLowerCase()
        .compareTo(b.toLowerCase()),
  );

  if (!mounted) return;

  setState(() {
    sarees = inventoryData;
    traders = traderList;
    loading = false;
  });
  }

  Future<void> savePurchase() async {
    if (selectedSaree == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Please select a saree.',
          ),
        ),
      );
      return;
    }

    final trader =
        traderController.text.trim();

    final quantity =
        double.tryParse(
          quantityController.text.trim(),
        );

    final purchasePrice =
        double.tryParse(
          priceController.text.trim(),
        );

    if (trader.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter trader name.',
          ),
        ),
      );
      return;
    }

    if (quantity == null ||
        quantity <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter a valid quantity.',
          ),
        ),
      );
      return;
    }

    if (purchasePrice == null ||
        purchasePrice < 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter a valid purchase price.',
          ),
        ),
      );
      return;
    }

    final purchaseId =
        await PurchaseStorage
            .nextPurchaseId();

    final purchase = Purchase(
      id: purchaseId,
      date: DateTime.now(),
      trader: trader,
      sareeId: selectedSaree!.id,
      sareeName: selectedSaree!.name,
      sareeCode: selectedSaree!.code,
      quantity: quantity,
      purchasePrice: purchasePrice,
      gst: quantity * purchasePrice * 0.05,
      notes: notesController.text.trim(),
    );

    // Save purchase record.
    final purchases =
        await PurchaseStorage.load();

    purchases.add(purchase);

    await PurchaseStorage.save(
      purchases,
    );

    // Increase inventory stock.
    final inventory =
        await InventoryStorage.load();

    final index =
        inventory.indexWhere(
      (saree) =>
          saree.id == selectedSaree!.id,
    );

    if (index != -1) {
      inventory[index].stock += quantity;

      // Update purchase price in the
      // inventory master as well.
      inventory[index].purchasePrice =
          purchasePrice;

      await InventoryStorage.save(
        inventory,
      );
    }

    if (!mounted) return;

    Navigator.pop(
      context,
      purchase,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Add Purchase',
        ),
      ),
      body: loading
          ? const Center(
              child:
                  CircularProgressIndicator(),
            )
          : sarees.isEmpty
              ? const Center(
                  child: Text(
                    'No inventory items found.\n'
                    'Please add a saree first.',
                    textAlign:
                        TextAlign.center,
                  ),
                )
              : SingleChildScrollView(
                  padding:
                      const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .stretch,
                    children: [
                      DropdownButtonFormField<
                          Saree>(
                        value: selectedSaree,
                        decoration:
                            const InputDecoration(
                          labelText:
                              'Select Saree',
                          border:
                              OutlineInputBorder(),
                        ),
                        items: sarees.map(
                          (saree) {
                            return DropdownMenuItem<
                                Saree>(
                              value: saree,
                              child: Text(
                                '${saree.name} '
                                '(${saree.code})',
                              ),
                            );
                          },
                        ).toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedSaree =
                                value;

                            if (value != null) {
                              priceController
                                  .text =
                                  value
                                      .purchasePrice
                                      .toString();
                            }
                          });
                        },
                      ),

                      const SizedBox(
                        height: 16,
                      ),

                      DropdownButtonFormField<String>(
  value: newTrader
      ? '__new__'
      : selectedTrader,
  isExpanded: true,
  menuMaxHeight: 350,
  decoration: const InputDecoration(
    labelText: 'Trader',
    border: OutlineInputBorder(),
  ),
  items: [
    ...traders.map(
      (trader) {
        return DropdownMenuItem<String>(
          value: trader,
          child: Text(
            trader,
            overflow:
                TextOverflow.ellipsis,
          ),
        );
      },
    ),
    const DropdownMenuItem<String>(
      value: '__new__',
      child: Text(
        '+ Add New Trader',
      ),
    ),
  ],
  onChanged: (value) {
    if (value == '__new__') {
      setState(() {
        selectedTrader = null;
        newTrader = true;
        traderController.clear();
      });
      return;
    }

    setState(() {
      selectedTrader = value;
      newTrader = false;

      if (value != null) {
        traderController.text = value;
      }
    });
  },
),
                      if (newTrader) ...[
  const SizedBox(height: 12),

  TextField(
    controller:
        traderController,
    decoration:
        const InputDecoration(
      labelText:
          'New Trader Name',
      border:
          OutlineInputBorder(),
    ),
  ),
],

                      const SizedBox(
                        height: 16,
                      ),

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
                          labelText:
                              'Quantity',
                          hintText:
                              'e.g. 10',
                          border:
                              OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(
                        height: 16,
                      ),

                      TextField(
  controller:
      priceController,
  keyboardType:
      const TextInputType
          .numberWithOptions(
    decimal: true,
  ),
  onChanged: (_) {
    setState(() {});
  },
  decoration:
      const InputDecoration(
                          labelText:
                              'Purchase Price',
                          prefixText: '₹ ',
                          border:
                              OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(
                        height: 16,
                      ),

                      TextField(
                        controller:
                            notesController,
                        maxLines: 3,
                        decoration:
                            const InputDecoration(
                          labelText:
                              'Notes',
                          border:
                              OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(
                        height: 24,
                      ),

                      const SizedBox(
  height: 16,
),

Card(
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Builder(
      builder: (context) {
        final quantity =
            double.tryParse(
                  quantityController.text.trim(),
                ) ??
                0;

        final purchasePrice =
    double.tryParse(
          priceController.text.trim(),
        ) ??
        0;

        final goodsValue =
            quantity * purchasePrice;

        final gstAmount =
            goodsValue * 0.05;

        final totalPayable =
            goodsValue + gstAmount;

        return Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Purchase Summary',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(
              height: 12,
            ),

            Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Goods Value',
                ),
                Text(
                  '₹ ${goodsValue.toStringAsFixed(2)}',
                ),
              ],
            ),

            const SizedBox(
              height: 8,
            ),

            Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'GST @ 5%',
                ),
                Text(
                  '₹ ${gstAmount.toStringAsFixed(2)}',
                ),
              ],
            ),

            const Divider(
              height: 20,
            ),

            Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total Payable',
                  style: TextStyle(
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                Text(
                  '₹ ${totalPayable.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    ),
  ),
),

const SizedBox(
  height: 16,
),
                      
                      FilledButton.icon(
                        onPressed:
                            savePurchase,
                        icon: const Icon(
                          Icons.save,
                        ),
                        label: const Text(
                          'SAVE PURCHASE',
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

// ============================================================
// PURCHASES PAGE
// ============================================================

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key});

  @override
  State<PurchasesPage> createState() =>
      _PurchasesPageState();
}

class _PurchasesPageState
    extends State<PurchasesPage> {
  List<Purchase> purchases = [];

  @override
  void initState() {
    super.initState();
    loadPurchases();
  }

  Future<void> loadPurchases() async {
    final data =
        await PurchaseStorage.load();

    if (!mounted) return;

    data.sort(
      (a, b) => b.date.compareTo(a.date),
    );

    setState(() {
      purchases = data;
    });
  }

  Future<void> addPurchase() async {
    final result =
        await Navigator.push<Purchase>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const AddPurchasePage(),
      ),
    );

    if (result == null) return;

    await loadPurchases();
  }

    Future<void> deletePurchase(
    Purchase purchase,
  ) async {
    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Delete Purchase?',
          ),
          content: Text(
            'Purchase ${purchase.id} will be permanently deleted.\n\n'
            'Stock of ${purchase.sareeName} will also be reduced by '
            '${purchase.quantity}.\n\n'
            'This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  false,
                );
              },
              child: const Text(
                'CANCEL',
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  true,
                );
              },
              child: const Text(
                'DELETE',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    // Remove the purchase record.
    await PurchaseStorage.delete(
      purchase.id,
    );

    // Reverse the stock added by this purchase.
    final inventory =
        await InventoryStorage.load();

    final index =
        inventory.indexWhere(
      (saree) =>
          saree.id == purchase.sareeId,
    );

    if (index != -1) {
      inventory[index].stock -=
          purchase.quantity;

      if (inventory[index].stock < 0) {
        inventory[index].stock = 0;
      }

      await InventoryStorage.save(
        inventory,
      );
    }

    await loadPurchases();

    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      const SnackBar(
        content: Text(
          'Purchase deleted and stock adjusted.',
        ),
      ),
    );
    }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Purchases',
        ),
      ),
      body: purchases.isEmpty
          ? const Center(
              child: Text(
                'No purchases found.',
              ),
            )
          : ListView.builder(
              padding:
                  const EdgeInsets.all(12),
              itemCount:
                  purchases.length,
              itemBuilder:
                  (context, index) {
                final purchase =
                    purchases[index];

                return Card(
                  margin:
                      const EdgeInsets.only(
                    bottom: 10,
                  ),
                  child: ListTile(
                    leading:
                        const CircleAvatar(
                      child: Icon(
                        Icons
                            .shopping_bag,
                      ),
                    ),
                    title: Text(
                      purchase.sareeName
                              .trim()
                              .isEmpty
                          ? 'Purchase'
                          : purchase
                              .sareeName,
                      style:
                          const TextStyle(
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      '${purchase.id}\n'
                      'Trader: ${purchase.trader}\n'
                      'Qty: ${purchase.quantity}  •  '
                      '₹${purchase.purchasePrice.toStringAsFixed(2)} each\n'
                      'Total: ₹${purchase.total.toStringAsFixed(2)}',
                    ),
                    isThreeLine: true,
                    trailing:
                        IconButton(
                      icon: const Icon(
                        Icons
                            .delete_outline,
                      ),
                      onPressed: () =>
                          deletePurchase(
                        purchase,
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton:
          FloatingActionButton.extended(
        onPressed: addPurchase,
        icon: const Icon(
          Icons.add,
        ),
        label: const Text(
          'Purchase',
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
          leading: const Icon(Icons.shopping_bag),
          title: const Text('Purchases'),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PurchasesPage(),
              ),
            );
          },
        ),
                    ListTile(
            leading: const Icon(
              Icons.account_balance,
            ),
            title: const Text(
              'Trader Ledger',
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      const TraderLedgerPage(),
                ),
              );
            },
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
// ============================================================
// PAYMENTS PAGE
// ============================================================

class PaymentsPage extends StatefulWidget {
  const PaymentsPage({super.key});

  @override
  State<PaymentsPage> createState() =>
      _PaymentsPageState();
}

class _PaymentsPageState
    extends State<PaymentsPage> {
  List<Payment> payments = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadPayments();
  }

  Future<void> loadPayments() async {
    final data = await PaymentStorage.load();

    if (!mounted) return;

    setState(() {
      payments = data;
      loading = false;
    });
  }

      Future<void> addPayment() async {
    final result =
        await Navigator.push<Payment>(
      context,
      MaterialPageRoute(
        builder: (_) => const AddPaymentPage(),
      ),
    );

    if (result == null) return;

    setState(() {
      payments.insert(0, result);
    });

    await PaymentStorage.save(payments);

    // Recalculate this customer's invoices
    // after recording the payment.
    if (result.customerId.trim().isNotEmpty) {
      await InvoiceStorage.recalculateCustomerPayments(
        {result.customerId},
      );
    }
      }

  Future<void> deletePayment(
    Payment payment,
  ) async {
    final confirm =
        await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Delete Payment?',
          ),
          content: Text(
            'This will permanently delete payment '
            '${payment.id} of ₹${payment.amount.toStringAsFixed(2)} '
            'from ${payment.customerName}.\n\n'
            'This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  false,
                );
              },
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  true,
                );
              },
              child: const Text('DELETE'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

        final affectedCustomerId =
        payment.customerId;

    await PaymentStorage.delete(
      payment.id,
    );

    if (affectedCustomerId.trim().isNotEmpty) {
      await InvoiceStorage.recalculateCustomerPayments(
        {affectedCustomerId},
      );
    }

    if (!mounted) return;

    setState(() {
      payments.removeWhere(
        (item) => item.id == payment.id,
      );
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Payment deleted',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Payments',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      body: loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : payments.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize:
                        MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.payments_outlined,
                        size: 60,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'No payments recorded',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Tap + to record a payment',
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding:
                      const EdgeInsets.all(12),
                  itemCount: payments.length,
                  itemBuilder:
                      (context, index) {
                    final payment =
                        payments[index];

                    return Card(
                      child: ListTile(
                        leading:
                            const CircleAvatar(
                          child: Icon(
                            Icons.currency_rupee,
                          ),
                        ),

                        title: Text(
                          payment.customerName,
                          style:
                              const TextStyle(
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),

                        subtitle: Text(
                          '${payment.id}\n'
                          '${payment.date.day.toString().padLeft(2, '0')}/'
                          '${payment.date.month.toString().padLeft(2, '0')}/'
                          '${payment.date.year}'
                          '${payment.reference.isEmpty ? '' : '\nRef: ${payment.reference}'}',
                        ),

                        isThreeLine:
                            payment.reference
                                .isNotEmpty,

                        trailing: Row(
                          mainAxisSize:
                              MainAxisSize.min,
                          children: [
                            Text(
                              '₹${payment.amount.toStringAsFixed(2)}',
                              style:
                                  const TextStyle(
                                fontWeight:
                                    FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),

                            PopupMenuButton<
                                String>(
                              onSelected:
                                  (value) {
                                if (value ==
                                    'delete') {
                                  deletePayment(
                                    payment,
                                  );
                                }
                              },
                              itemBuilder:
                                  (_) => const [
                                PopupMenuItem(
                                  value:
                                      'delete',
                                  child: Text(
                                    'Delete',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

      floatingActionButton:
          FloatingActionButton.extended(
        onPressed: addPayment,
        icon: const Icon(Icons.add),
        label: const Text(
          'Add Payment',
        ),
      ),
    );
  }
}

// ============================================================
// ADD PAYMENT PAGE
// ============================================================

class AddPaymentPage extends StatefulWidget {
  const AddPaymentPage({super.key});

  @override
  State<AddPaymentPage> createState() =>
      _AddPaymentPageState();
}

class _AddPaymentPageState
    extends State<AddPaymentPage> {
  List<Customer> customers = [];

  Customer? selectedCustomer;

  final amountController =
      TextEditingController();

  final referenceController =
      TextEditingController();

  final notesController =
      TextEditingController();

  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadCustomers();
  }

  Future<void> loadCustomers() async {
    final data =
        await CustomerStorage.load();

    if (!mounted) return;

    setState(() {
      customers = data;
      loading = false;
    });
  }

  Future<void> savePayment() async {
    if (selectedCustomer == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Please select a customer',
          ),
        ),
      );
      return;
    }

    final amount =
        double.tryParse(
      amountController.text.trim(),
    );

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter a valid payment amount',
          ),
        ),
      );
      return;
    }

    final paymentId =
        await PaymentStorage.nextPaymentId();

    final payment = Payment(
      id: paymentId,
      customerId:
          selectedCustomer!.id,
      customerName:
          selectedCustomer!.name,
      date: DateTime.now(),
      amount: amount,
      reference:
          referenceController.text.trim(),
      notes:
          notesController.text.trim(),
    );

    if (!mounted) return;

    Navigator.pop(
      context,
      payment,
    );
  }

  @override
  void dispose() {
    amountController.dispose();
    referenceController.dispose();
    notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Add Payment',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      body: loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : customers.isEmpty
              ? const Center(
                  child: Text(
                    'No customers found.\n'
                    'Create a customer first.',
                    textAlign:
                        TextAlign.center,
                  ),
                )
              : ListView(
                  padding:
                      const EdgeInsets.all(16),
                  children: [
                    DropdownButtonFormField<
                        Customer>(
                      value: selectedCustomer,
                      isExpanded: true,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Customer *',
                        prefixIcon:
                            Icon(Icons.person),
                        border:
                            OutlineInputBorder(),
                      ),
                      items: customers.map(
                        (customer) {
                          return DropdownMenuItem<
                              Customer>(
                            value: customer,
                            child: Text(
                              '${customer.name} (${customer.id})',
                              overflow:
                                  TextOverflow.ellipsis,
                            ),
                          );
                        },
                      ).toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedCustomer =
                              value;
                        });
                      },
                    ),

                    const SizedBox(height: 18),

                    TextField(
                      controller:
                          amountController,
                      keyboardType:
                          const TextInputType
                              .numberWithOptions(
                        decimal: true,
                      ),
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Payment Amount *',
                        prefixText: '₹ ',
                        prefixIcon:
                            Icon(
                          Icons.currency_rupee,
                        ),
                        border:
                            OutlineInputBorder(),
                      ),
                    ),

                    const SizedBox(height: 18),

                    TextField(
                      controller:
                          referenceController,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Reference / Receipt No.',
                        prefixIcon:
                            Icon(Icons.receipt),
                        border:
                            OutlineInputBorder(),
                      ),
                    ),

                    const SizedBox(height: 18),

                    TextField(
                      controller:
                          notesController,
                      maxLines: 3,
                      decoration:
                          const InputDecoration(
                        labelText: 'Notes',
                        prefixIcon:
                            Icon(Icons.notes),
                        border:
                            OutlineInputBorder(),
                      ),
                    ),

                    const SizedBox(height: 25),

                    SizedBox(
                      width:
                          double.infinity,
                      height: 52,
                      child:
                          FilledButton.icon(
                        onPressed:
                            savePayment,
                        icon: const Icon(
                          Icons.save,
                        ),
                        label: const Text(
                          'SAVE PAYMENT',
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

// ============================================================
// CUSTOMER OUTSTANDING
// ============================================================

class CustomerOutstandingPage
    extends StatefulWidget {
  const CustomerOutstandingPage({
    super.key,
  });

  @override
  State<CustomerOutstandingPage> createState() =>
      _CustomerOutstandingPageState();
}

class _CustomerOutstandingPageState
    extends State<CustomerOutstandingPage> {
  List<Customer> customers = [];
  List<Invoice> invoices = [];
  List<Payment> payments = [];

  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    try {
      final loadedCustomers =
          await CustomerStorage.load();

      final loadedInvoices =
          await InvoiceStorage.load();

      final loadedPayments =
          await PaymentStorage.load();

      if (!mounted) return;

      setState(() {
        customers = loadedCustomers;
        invoices = loadedInvoices;
        payments = loadedPayments;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to load outstanding data: $e',
          ),
        ),
      );
    }
  }

  double totalSalesForCustomer(
    String customerId,
  ) {
    return invoices
        .where(
          (invoice) =>
              invoice.customerId.trim() ==
              customerId.trim(),
        )
        .fold(
          0,
          (sum, invoice) =>
              sum + invoice.grandTotal,
        );
  }

  double totalPaymentsForCustomer(
    String customerId,
  ) {
    return payments
        .where(
          (payment) =>
              payment.customerId.trim() ==
              customerId.trim(),
        )
        .fold(
          0,
          (sum, payment) =>
              sum + payment.amount,
        );
  }

  double balanceForCustomer(
    String customerId,
  ) {
    return totalSalesForCustomer(customerId) -
        totalPaymentsForCustomer(customerId);
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
        title: const Text(
          'Customer Outstanding',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      body: customers.isEmpty
          ? const Center(
              child: Text(
                'No customers found.',
              ),
            )
          : RefreshIndicator(
              onRefresh: loadData,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: customers.length,
                itemBuilder: (context, index) {
                  final customer =
                      customers[index];

                  final sales =
                      totalSalesForCustomer(
                    customer.id,
                  );

                  final paid =
                      totalPaymentsForCustomer(
                    customer.id,
                  );

                  final balance =
                      sales - paid;

                  return Card(
                    child: ListTile(
                      leading:
                          const CircleAvatar(
                        child: Icon(
                          Icons.person,
                        ),
                      ),

                      title: Text(
                        customer.name,
                        style:
                            const TextStyle(
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                      subtitle: Text(
                        '${customer.id}\n'
                        'Sales: ₹${sales.toStringAsFixed(2)}\n'
                        'Paid: ₹${paid.toStringAsFixed(2)}',
                      ),

                      isThreeLine: true,

                      trailing: Column(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        crossAxisAlignment:
                            CrossAxisAlignment.end,
                        children: [
                          Text(
                            balance >= 0
                                ? 'Due'
                                : 'Credit',
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '₹${balance.abs().toStringAsFixed(2)}',
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),

                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                CustomerAccountDetailPage(
                              customer: customer,
                              invoices: invoices
                                  .where(
                                    (invoice) =>
                                        invoice.customerId
                                            .trim() ==
                                        customer.id
                                            .trim(),
                                  )
                                  .toList(),
                              payments: payments
                                  .where(
                                    (payment) =>
                                        payment.customerId
                                            .trim() ==
                                        customer.id
                                            .trim(),
                                  )
                                  .toList(),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
    );
  }
}

// ============================================================
// CUSTOMER ACCOUNT DETAIL
// ============================================================

class CustomerAccountDetailPage
    extends StatelessWidget {
  final Customer customer;
  final List<Invoice> invoices;
  final List<Payment> payments;

  const CustomerAccountDetailPage({
    super.key,
    required this.customer,
    required this.invoices,
    required this.payments,
  });

  double get totalSales {
    return invoices.fold(
      0,
      (sum, invoice) =>
          sum + invoice.grandTotal,
    );
  }

  double get totalPaid {
    return payments.fold(
      0,
      (sum, payment) =>
          sum + payment.amount,
    );
  }

  double get balance {
    return totalSales - totalPaid;
  }

  @override
  Widget build(BuildContext context) {
    final sortedInvoices =
        List<Invoice>.from(invoices)
          ..sort(
            (a, b) =>
                b.date.compareTo(a.date),
          );

    final sortedPayments =
        List<Payment>.from(payments)
          ..sort(
            (a, b) =>
                b.date.compareTo(a.date),
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          customer.name,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ==================================================
          // CUSTOMER
          // ==================================================

          Card(
            child: Padding(
              padding:
                  const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Customer ID: ${customer.id}',
                  ),
                  if (customer
                      .gstNumber
                      .trim()
                      .isNotEmpty)
                    Text(
                      'GST: ${customer.gstNumber}',
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ==================================================
          // ACCOUNT SUMMARY
          // ==================================================

          Card(
            child: Padding(
              padding:
                  const EdgeInsets.all(16),
              child: Column(
                children: [
                  _AccountAmountRow(
                    label: 'Total Sales',
                    amount: totalSales,
                  ),
                  const Divider(),
                  _AccountAmountRow(
                    label: 'Total Payments',
                    amount: totalPaid,
                  ),
                  const Divider(),
                  _AccountAmountRow(
                    label: balance >= 0
                        ? 'Outstanding'
                        : 'Customer Credit',
                    amount: balance.abs(),
                    bold: true,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ==================================================
          // INVOICES
          // ==================================================

          const Text(
            'Invoices',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          if (sortedInvoices.isEmpty)
            const Card(
              child: Padding(
                padding:
                    EdgeInsets.all(16),
                child: Text(
                  'No invoices found.',
                ),
              ),
            ),

          ...sortedInvoices.map(
            (invoice) {
              return Card(
                child: ListTile(
                  leading:
                      const Icon(
                    Icons.receipt_long,
                  ),
                  title: Text(
                    invoice.number,
                    style:
                        const TextStyle(
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    '${invoice.date.day.toString().padLeft(2, '0')}/'
                    '${invoice.date.month.toString().padLeft(2, '0')}/'
                    '${invoice.date.year}\n'
                    'Paid: ₹${invoice.paid.toStringAsFixed(2)}  •  '
                    'Due: ₹${invoice.outstanding.toStringAsFixed(2)}',
                  ),
                  trailing: Text(
                    '₹${invoice.grandTotal.toStringAsFixed(2)}',
                    style:
                        const TextStyle(
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 24),

          // ==================================================
          // PAYMENTS
          // ==================================================

          const Text(
            'Payments',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          if (sortedPayments.isEmpty)
            const Card(
              child: Padding(
                padding:
                    EdgeInsets.all(16),
                child: Text(
                  'No payments found.',
                ),
              ),
            ),

          ...sortedPayments.map(
            (payment) {
              return Card(
                child: ListTile(
                  leading:
                      const Icon(
                    Icons.payments,
                  ),
                  title: Text(
                    payment.id,
                    style:
                        const TextStyle(
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    '${payment.date.day.toString().padLeft(2, '0')}/'
                    '${payment.date.month.toString().padLeft(2, '0')}/'
                    '${payment.date.year}'
                    '${payment.reference.isEmpty ? '' : '\nRef: ${payment.reference}'}',
                  ),
                  trailing: Text(
                    '₹${payment.amount.toStringAsFixed(2)}',
                    style:
                        const TextStyle(
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ACCOUNT AMOUNT ROW
// ============================================================

class _AccountAmountRow
    extends StatelessWidget {
  final String label;
  final double amount;
  final bool bold;

  const _AccountAmountRow({
    required this.label,
    required this.amount,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment:
          MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: bold
                ? FontWeight.bold
                : FontWeight.normal,
            fontSize: bold ? 16 : 14,
          ),
        ),
        Text(
          '₹${amount.toStringAsFixed(2)}',
          style: TextStyle(
            fontWeight: bold
                ? FontWeight.bold
                : FontWeight.normal,
            fontSize: bold ? 17 : 14,
          ),
        ),
      ],
    );
  }
}
