import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

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
// AUTHENTICATION + CLOUD SYNC
// ============================================================

const String _adminDomain = 'ajantasareecentre.app';
const String _customerDomain = 'customers.ajantasareecentre.app';

String _adminEmail(String id) => '${id.toLowerCase()}@$_adminDomain';
String _customerEmail(String id) => '${id.toLowerCase()}@$_customerDomain';

class AuthService {
  static final FirebaseAuth auth = FirebaseAuth.instance;
  static final FirebaseFirestore db = FirebaseFirestore.instance;
  static String? currentAdminId;

  static bool get signedIn => auth.currentUser != null;

  static Future<void> loginAdmin(String id, String pin) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('loginAdmin')
        .call({'adminId': id.trim().toLowerCase(), 'pin': pin.trim()});
    final token = (result.data as Map)['token']?.toString() ?? '';
    if (token.isEmpty) throw Exception('Admin authentication failed.');
    await auth.signInWithCustomToken(token);
    currentAdminId = id.trim().toLowerCase();
  }

  static Future<void> loginCustomer(String id, String pin) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('loginCustomer')
        .call({'customerId': id.trim().toLowerCase(), 'pin': pin.trim()});
    final token = (result.data as Map)['token']?.toString() ?? '';
    if (token.isEmpty) throw Exception('Customer authentication failed.');
    await auth.signInWithCustomToken(token);
  }

  static Future<void> signOut() async {
    currentAdminId = null;
    await auth.signOut();
  }

  static Future<bool> isAdmin() async {
    final user = auth.currentUser;
    if (user == null) return false;
    try {
      final token = await user.getIdTokenResult(true);
      return token.claims?['role']?.toString() == 'admin';
    } catch (_) {
      return false;
    }
  }

  static Future<String> currentCustomerId() async {
    final user = auth.currentUser;
    if (user == null) return '';
    try {
      final token = await user.getIdTokenResult();
      final value = token.claims?['customerId']?.toString() ?? '';
      if (value.isNotEmpty) return value;
    } catch (_) {}
    try {
      final doc = await db.collection('userProfiles').doc(user.uid).get();
      return doc.data()?['customerId']?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }
}
class CloudSyncService {
  static final FirebaseFirestore db = FirebaseFirestore.instance;

  static Future<List<Map<String, dynamic>>> loadMaps({
    required String collection,
    required String localKey,
    String? customerId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final local = _decodeLocal(prefs.getString(localKey));
    final admin = await AuthService.isAdmin();

    try {
      Query query = db.collection(collection);
      final cid = customerId?.trim();
      if (cid != null && cid.isNotEmpty) {
        query = query.where('customerId', isEqualTo: cid);
      }
      final snapshot = await query.get();
      final cloud = <String, Map<String, dynamic>>{};
      for (final doc in snapshot.docs) {
        final raw = doc.data();
        if (raw is Map) cloud[doc.id] = Map<String, dynamic>.from(raw);
      }

      if (admin && cid == null && local.isNotEmpty) {
        for (final item in local) {
          final id = _recordId(item);
          if (id.isEmpty || cloud.containsKey(id)) continue;
          try {
            await db.collection(collection).doc(id).set(item);
            cloud[id] = Map<String, dynamic>.from(item);
          } catch (_) {}
        }
      }

      final result = cloud.values.toList();
      await prefs.setString(localKey, jsonEncode(result));
      return result;
    } catch (_) {
      if (customerId != null && customerId.trim().isNotEmpty) {
        return local
            .where((e) => (e['customerId']?.toString() ?? '').trim() == customerId.trim())
            .toList();
      }
      return local;
    }
  }

  static Future<void> saveMaps({
    required String collection,
    required String localKey,
    required List<Map<String, dynamic>> items,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(localKey, jsonEncode(items));

    if (!await AuthService.isAdmin() && !AuthService.signedIn) return;
    for (final item in items) {
      final id = _recordId(item);
      if (id.isEmpty) continue;
      try {
        await db.collection(collection).doc(id).set(item, SetOptions(merge: true));
      } catch (_) {}
    }
  }

  static Future<void> delete({required String collection, required String id}) async {
    if (id.trim().isEmpty) return;
    try {
      await db.collection(collection).doc(id).delete();
    } catch (_) {}
  }

  static List<Map<String, dynamic>> _decodeLocal(String? data) {
    if (data == null || data.isEmpty) return [];
    try {
      final decoded = jsonDecode(data) as List;
      return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return [];
    }
  }

  static String _recordId(Map<String, dynamic> item) {
    return (item['id'] ?? item['number'] ?? '').toString();
  }

  static Future<void> migrateAllLocalBusinessData() async {
    // Each storage load merges local legacy records into Firestore.
    await InventoryStorage.load();
    await PurchaseStorage.load();
    await TraderPaymentStorage.load();
    await InvoiceStorage.load();
    await PaymentStorage.load();
    await CashbookStorage.load();
    await ReturnStorage.load();
  }
}

class LegacyMigrationService {
  static Future<void> syncLegacyCustomers() async {
    if (!await AuthService.isAdmin()) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('asc_legacy_customers_migrated');
    final already = raw == '1';
    if (already) return;

    final localRaw = prefs.getString('asc_customers');
    if (localRaw == null || localRaw.isEmpty) {
      await prefs.setString('asc_legacy_customers_migrated', '1');
      return;
    }

    List<dynamic> decoded;
    try { decoded = jsonDecode(localRaw) as List; } catch (_) { return; }
    for (final entry in decoded) {
      final map = Map<String, dynamic>.from(entry);
      final id = map['id']?.toString().trim().toLowerCase() ?? '';
      final pin = map['pin']?.toString() ?? '';
      if (id.isEmpty || pin.length < 4) continue;
      try {
        await FirebaseFunctions.instance.httpsCallable('ensureCustomerAccount').call({
          'customerId': id,
          'pin': pin,
          'name': map['name']?.toString() ?? '',
          'gstNumber': map['gstNumber']?.toString() ?? '',
        });
      } catch (_) {}
    }
    await prefs.setString('asc_legacy_customers_migrated', '1');
  }
}

// ============================================================
// DATA EXPORT / PDF HELPERS
// ============================================================

class FileShareService {
  static Future<File> writeTempBytes(String filename, List<int> bytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<void> shareFile(File file, {String? text}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, name: file.uri.pathSegments.last)],
        text: text,
      ),
    );
  }
}

class PdfService {
  static Future<List<int>> invoicePdf(Invoice invoice) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          pw.Center(child: pw.Text('AJANTA SAREE CENTRE', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold))),
          pw.Center(child: pw.Text('Satna (M.P.)')),
          pw.SizedBox(height: 16),
          pw.Text('Invoice: ${invoice.number}'),
          pw.Text('Date: ${_dateText(invoice.date)}'),
          pw.Text('Customer: ${invoice.customerName.isEmpty ? 'Cash Customer' : invoice.customerName}'),
          if (invoice.customerId.isNotEmpty) pw.Text('Customer ID: ${invoice.customerId}'),
          pw.SizedBox(height: 12),
          pw.Table.fromTextArray(
            headers: const ['Item', 'Code', 'Qty', 'Rate', 'Amount'],
            data: invoice.items.map((item) => [
              item.sareeName,
              item.sareeCode,
              _formatNumber(item.quantity),
              '₹${_formatNumber(item.price)}',
              '₹${_formatNumber(item.total)}',
            ]).toList(),
          ),
          pw.SizedBox(height: 12),
          pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Subtotal: ₹${_formatNumber(invoice.subtotal)}')),
          pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('GST @ 5%: ₹${_formatNumber(invoice.gst)}')),
          pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Grand Total: ₹${_formatNumber(invoice.grandTotal)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
          pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Paid: ₹${_formatNumber(invoice.paid)}')),
          pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Outstanding: ₹${_formatNumber(invoice.outstanding)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
          pw.SizedBox(height: 18),
          pw.Center(child: pw.Text('Thankyou for shopping with us')),
        ],
      ),
    );
    return doc.save();
  }

  static Future<void> shareInvoice(Invoice invoice) async {
    final bytes = await invoicePdf(invoice);
    final file = await FileShareService.writeTempBytes(
      'Invoice_${invoice.number.replaceAll('/', '-')}.pdf',
      bytes,
    );
    await FileShareService.shareFile(file, text: 'Ajanta Saree Centre Invoice ${invoice.number}');
  }

  static Future<void> shareTextReport(String title, String text) async {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(build: (_) => [
      pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 12),
      pw.Text(text),
    ]));
    final bytes = await doc.save();
    final file = await FileShareService.writeTempBytes('ASC_$title.pdf', bytes);
    await FileShareService.shareFile(file, text: title);
  }
}

class ExcelService {
  static Future<File> createWorkbook() async {
    final excel = Excel.createExcel();
    if (excel.sheets.keys.contains('Sheet1')) excel.delete('Sheet1');

    final inventory = await InventoryStorage.load();
    final purchases = await PurchaseStorage.load();
    final invoices = await InvoiceStorage.load();
    final payments = await PaymentStorage.load();
    final traderPayments = await TraderPaymentStorage.load();
    final customers = await CustomerStorage.load();
    final cashbook = await CashbookStorage.load();
    final returns = await ReturnStorage.load();

    final s1 = excel['Inventory'];
    s1.appendRow([TextCellValue('ID'), TextCellValue('Name'), TextCellValue('Code'), TextCellValue('Category'), TextCellValue('Purchase Price'), TextCellValue('Price A'), TextCellValue('Price B'), TextCellValue('Price C'), TextCellValue('Stock'), TextCellValue('Trader')]);
    for (final s in inventory) {
      s1.appendRow([TextCellValue(s.id), TextCellValue(s.name), TextCellValue(s.code), TextCellValue(s.category), DoubleCellValue(s.purchasePrice), DoubleCellValue(s.price1), DoubleCellValue(s.price2), DoubleCellValue(s.price3), DoubleCellValue(s.stock), TextCellValue(s.trader)]);
    }

    final s2 = excel['Sales'];
    s2.appendRow([TextCellValue('Invoice'), TextCellValue('Date'), TextCellValue('Customer ID'), TextCellValue('Customer'), TextCellValue('Subtotal'), TextCellValue('GST'), TextCellValue('Total'), TextCellValue('Paid'), TextCellValue('Outstanding')]);
    for (final i in invoices) {
      s2.appendRow([TextCellValue(i.number), TextCellValue(_dateText(i.date)), TextCellValue(i.customerId), TextCellValue(i.customerName), DoubleCellValue(i.subtotal), DoubleCellValue(i.gst), DoubleCellValue(i.grandTotal), DoubleCellValue(i.paid), DoubleCellValue(i.outstanding)]);
    }

    final s3 = excel['Purchases'];
    s3.appendRow([TextCellValue('ID'), TextCellValue('Date'), TextCellValue('Trader'), TextCellValue('Item'), TextCellValue('Qty'), TextCellValue('Rate'), TextCellValue('Goods Value'), TextCellValue('GST'), TextCellValue('Payable')]);
    for (final p in purchases) {
      s3.appendRow([TextCellValue(p.id), TextCellValue(_dateText(p.date)), TextCellValue(p.trader), TextCellValue(p.sareeName), DoubleCellValue(p.quantity), DoubleCellValue(p.purchasePrice), DoubleCellValue(p.total), DoubleCellValue(p.gstAmount), DoubleCellValue(p.grandTotal)]);
    }

    final s4 = excel['Payments'];
    s4.appendRow([TextCellValue('ID'), TextCellValue('Date'), TextCellValue('Customer ID'), TextCellValue('Customer'), TextCellValue('Amount'), TextCellValue('Reference'), TextCellValue('Notes')]);
    for (final p in payments) {
      s4.appendRow([TextCellValue(p.id), TextCellValue(_dateText(p.date)), TextCellValue(p.customerId), TextCellValue(p.customerName), DoubleCellValue(p.amount), TextCellValue(p.reference), TextCellValue(p.notes)]);
    }

    final s5 = excel['Trader Payments'];
    s5.appendRow([TextCellValue('ID'), TextCellValue('Date'), TextCellValue('Trader'), TextCellValue('Amount'), TextCellValue('Reference'), TextCellValue('Notes')]);
    for (final p in traderPayments) {
      s5.appendRow([TextCellValue(p.id), TextCellValue(_dateText(p.date)), TextCellValue(p.trader), DoubleCellValue(p.amount), TextCellValue(p.reference), TextCellValue(p.notes)]);
    }

    final s6 = excel['Customers'];
    s6.appendRow([TextCellValue('ID'), TextCellValue('Name'), TextCellValue('GST'), TextCellValue('Outstanding')]);
    for (final c in customers) s6.appendRow([TextCellValue(c.id), TextCellValue(c.name), TextCellValue(c.gstNumber), DoubleCellValue(c.outstanding)]);

    final s7 = excel['Cashbook'];
    s7.appendRow([TextCellValue('ID'), TextCellValue('Date'), TextCellValue('Type'), TextCellValue('Category'), TextCellValue('Amount'), TextCellValue('Notes')]);
    for (final c in cashbook) s7.appendRow([TextCellValue(c.id), TextCellValue(_dateText(c.date)), TextCellValue(c.type), TextCellValue(c.category), DoubleCellValue(c.amount), TextCellValue(c.notes)]);

    final s8 = excel['Returns'];
    s8.appendRow([TextCellValue('ID'), TextCellValue('Date'), TextCellValue('Type'), TextCellValue('Party'), TextCellValue('Item'), TextCellValue('Qty'), TextCellValue('Goods Value'), TextCellValue('GST')]);
    for (final r in returns) s8.appendRow([TextCellValue(r.id), TextCellValue(_dateText(r.date)), TextCellValue(r.type), TextCellValue(r.partyName), TextCellValue(r.sareeName), DoubleCellValue(r.quantity), DoubleCellValue(r.amount), DoubleCellValue(r.gst)]);

    final bytes = excel.save();
    if (bytes == null) throw Exception('Unable to create Excel file.');
    return FileShareService.writeTempBytes('Ajanta_Saree_Centre_Backup.xlsx', bytes);
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
  String authUid;

  Customer({
    required this.id,
    required this.name,
    required this.pin,
    required this.gstNumber,
    this.outstanding = 0,
    this.authUid = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'pin': pin,
      'gstNumber': gstNumber,
      'outstanding': outstanding,
      'authUid': authUid,
    };
  }

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      pin: map['pin']?.toString() ?? '',
      gstNumber: map['gstNumber']?.toString() ?? '',
      outstanding: (map['outstanding'] as num?)?.toDouble() ?? 0,
      authUid: map['authUid']?.toString() ?? '',
    );
  }
}

// ============================================================
// CUSTOMER FIRESTORE STORAGE
// ============================================================

class CustomerStorage {
  static final _customers = FirebaseFirestore.instance.collection('customers');
  static const String localKey = 'asc_customers';

  static Future<void> save(Customer customer) async {
    final exists = await idExists(customer.id);
    if (!exists && customer.authUid.isEmpty) {
      try {
        final result = await FirebaseFunctions.instance
            .httpsCallable('createCustomerAccount')
            .call({
          'customerId': customer.id.trim().toLowerCase(),
          'name': customer.name,
          'pin': customer.pin,
          'gstNumber': customer.gstNumber,
        });
        final uid = result.data is Map ? result.data['uid']?.toString() ?? '' : '';
        customer.authUid = uid;
      } catch (e) {
        // Keep local/cloud customer record usable while functions are being configured.
      }
    }

    await _customers.doc(customer.id).set(customer.toMap(), SetOptions(merge: true));
    final customers = await loadLocal();
    final index = customers.indexWhere((c) => c.id == customer.id);
    if (index == -1) customers.add(customer); else customers[index] = customer;
    await _saveLocal(customers);
  }

  static Future<List<Customer>> load() async {
    final admin = await AuthService.isAdmin();
    try {
      Query query = _customers;
      if (!admin) {
        final cid = await AuthService.currentCustomerId();
        if (cid.isEmpty) return [];
        query = _customers.where('id', isEqualTo: cid);
      }
      final snapshot = await query.get();
      final result = snapshot.docs.map((doc) => Customer.fromMap(doc.data() as Map<String, dynamic>)).toList();
      await _saveLocal(result);
      return result;
    } catch (_) {
      final local = await loadLocal();
      if (admin) return local;
      final cid = await AuthService.currentCustomerId();
      return local.where((c) => c.id == cid).toList();
    }
  }

  static Future<List<Customer>> loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(localKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded.map((e) => Customer.fromMap(Map<String, dynamic>.from(e))).toList();
    } catch (_) { return []; }
  }

  static Future<void> _saveLocal(List<Customer> customers) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(localKey, jsonEncode(customers.map((c) => c.toMap()).toList()));
  }

  static Future<Customer?> findById(String id) async {
    try {
      final doc = await _customers.doc(id).get();
      if (doc.exists && doc.data() != null) return Customer.fromMap(doc.data()!);
    } catch (_) {}
    final local = await loadLocal();
    for (final c in local) if (c.id == id) return c;
    return null;
  }

  static Future<bool> idExists(String id) async {
    try { return (await _customers.doc(id.trim().toLowerCase()).get()).exists; }
    catch (_) { return (await loadLocal()).any((c) => c.id == id.trim().toLowerCase()); }
  }

  static Future<void> updateCustomer({required String oldId, required Customer customer}) async {
    await FirebaseFunctions.instance.httpsCallable('updateCustomerAccount').call({
      'oldCustomerId': oldId,
      'customerId': customer.id.trim().toLowerCase(),
      'name': customer.name,
      'pin': customer.pin,
      'gstNumber': customer.gstNumber,
    });
    if (oldId != customer.id) await CloudSyncService.delete(collection: 'customers', id: oldId);
    await saveLocalOnly(customer);
  }

  static Future<void> updateOutstanding(String customerId, double outstanding) async {
    final cid = customerId.trim().toLowerCase();
    if (cid.isEmpty) return;
    try {
      await _customers.doc(cid).set({'outstanding': outstanding}, SetOptions(merge: true));
    } catch (_) {}
    final local = await loadLocal();
    final i = local.indexWhere((c) => c.id == cid);
    if (i != -1) {
      local[i].outstanding = outstanding;
      await _saveLocal(local);
    }
  }

  static Future<void> saveLocalOnly(Customer customer) async {
    final data = await loadLocal();
    final i = data.indexWhere((c) => c.id == customer.id);
    if (i == -1) data.add(customer); else data[i] = customer;
    await _saveLocal(data);
  }

  static Future<void> delete(String id) async {
    final confirmedId = id.trim().toLowerCase();
    await FirebaseFunctions.instance.httpsCallable('deleteCustomerAccount').call({'customerId': confirmedId});
    await CloudSyncService.delete(collection: 'customers', id: confirmedId);
    final data = await loadLocal();
    data.removeWhere((c) => c.id == confirmedId);
    await _saveLocal(data);
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
// INVENTORY STORAGE
// ============================================================

class InventoryStorage {
  static const String key = 'ajanta_inventory';
  static const String collection = 'inventory';

  static Future<List<Saree>> load() async {
    final maps = await CloudSyncService.loadMaps(
      collection: collection,
      localKey: key,
    );
    return maps.map((m) => Saree.fromJson(m)).toList();
  }

  static Future<void> save(List<Saree> sarees) async {
    await CloudSyncService.saveMaps(
      collection: collection,
      localKey: key,
      items: sarees.map((s) => s.toJson()).toList(),
    );
  }

  static Future<void> delete(String sareeId) async {
    final sarees = await load();
    sarees.removeWhere((s) => s.id == sareeId);
    await save(sarees);
    await CloudSyncService.delete(collection: collection, id: sareeId);
  }
}

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
  static const String purchasesKey = 'ajanta_purchases';
  static const String purchaseNumberKey = 'ajanta_purchase_number';
  static const String collection = 'purchases';
  static Future<List<Purchase>> load() async {
    final maps = await CloudSyncService.loadMaps(collection: collection, localKey: purchasesKey);
    return maps.map((m) => Purchase.fromJson(m)).toList();
  }
  static Future<void> save(List<Purchase> purchases) async {
    await CloudSyncService.saveMaps(collection: collection, localKey: purchasesKey, items: purchases.map((p) => p.toJson()).toList());
  }
  static Future<String> nextPurchaseId() async {
    final prefs = await SharedPreferences.getInstance(); final next = (prefs.getInt(purchaseNumberKey) ?? 0) + 1; await prefs.setInt(purchaseNumberKey, next); return 'PUR-${next.toString().padLeft(4, '0')}';
  }
  static Future<void> delete(String purchaseId) async {
    final purchases = await load(); purchases.removeWhere((p) => p.id == purchaseId); await save(purchases); await CloudSyncService.delete(collection: collection, id: purchaseId);
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
  static const String paymentsKey = 'ajanta_trader_payments';
  static const String paymentNumberKey = 'ajanta_trader_payment_number';
  static const String collection = 'traderPayments';
  static Future<List<TraderPayment>> load() async {
    final maps = await CloudSyncService.loadMaps(collection: collection, localKey: paymentsKey);
    return maps.map((m) => TraderPayment.fromJson(m)).toList();
  }
  static Future<void> save(List<TraderPayment> payments) async {
    await CloudSyncService.saveMaps(collection: collection, localKey: paymentsKey, items: payments.map((p) => p.toJson()).toList());
  }
  static Future<String> nextPaymentId() async {
    final prefs = await SharedPreferences.getInstance(); final next = (prefs.getInt(paymentNumberKey) ?? 0) + 1; await prefs.setInt(paymentNumberKey, next); return 'TP-${next.toString().padLeft(4, '0')}';
  }
  static Future<void> delete(String paymentId) async {
    final payments = await load(); payments.removeWhere((p) => p.id == paymentId); await save(payments); await CloudSyncService.delete(collection: collection, id: paymentId);
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
    await CashbookStorage.add(
      CashbookEntry(
        id: payment.id,
        date: payment.date,
        type: 'Expense',
        category: 'Trader Payment',
        amount: payment.amount,
        notes: payment.reference.isEmpty ? payment.trader : payment.reference,
      ),
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

class TraderLedgerPage extends StatefulWidget{const TraderLedgerPage({super.key});@override State<TraderLedgerPage> createState()=>_TraderLedgerPageState();}
class _TraderLedgerPageState extends State<TraderLedgerPage>{List<Purchase> purchases=[];List<TraderPayment> payments=[];List<ReturnRecord> returns=[];bool loading=true;@override void initState(){super.initState();load();}Future<void>load()async{final p=await PurchaseStorage.load();final t=await TraderPaymentStorage.load();final r=await ReturnStorage.load();if(mounted)setState((){purchases=p;payments=t;returns=r;loading=false;});}
Future<void>payTrader()async{final result=await Navigator.push<TraderPayment>(context,MaterialPageRoute(builder:(_)=>const AddTraderPaymentPage()));if(result!=null){final list=await TraderPaymentStorage.load();if(!list.any((x)=>x.id==result.id)){list.add(result);await TraderPaymentStorage.save(list);await CashbookStorage.add(CashbookEntry(id:result.id,date:result.date,type:'Expense',category:'Trader Payment',amount:result.amount,notes:'${result.trader} ${result.reference}'.trim()));}await load();}}
Future<void>deletePayment(TraderPayment p)async{final ok=await showDialog<bool>(context:context,builder:(_)=>AlertDialog(title:const Text('PERMANENT DELETE'),content:Text('Delete trader payment ${p.id} of ₹${_formatNumber(p.amount)}?\n\nThis cannot be undone and will increase the trader outstanding balance.'),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('CANCEL')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('DELETE'))]));if(ok!=true)return;await TraderPaymentStorage.delete(p.id);await CashbookStorage.deleteBySource(p.id);await load();}
@override Widget build(BuildContext context){final grouped=<String,Map<String,dynamic>>{};for(final p in purchases){final k=p.trader.trim().toLowerCase();final g=grouped.putIfAbsent(k,()=>{'name':p.trader,'goods':0.0,'gst':0.0,'payable':0.0,'paid':0.0,'return':0.0});g['goods']+=p.total;g['gst']+=p.gstAmount;g['payable']+=p.grandTotal;}for(final r in returns.where((x)=>x.type=='PURCHASE_RETURN')){final k=r.partyName.trim().toLowerCase();final g=grouped.putIfAbsent(k,()=>{'name':r.partyName,'goods':0.0,'gst':0.0,'payable':0.0,'paid':0.0,'return':0.0});g['return']+=r.total;}for(final p in payments){final k=p.trader.trim().toLowerCase();final g=grouped.putIfAbsent(k,()=>{'name':p.trader,'goods':0.0,'gst':0.0,'payable':0.0,'paid':0.0,'return':0.0});g['paid']+=p.amount;}
return Scaffold(appBar:AppBar(title:const Text('Trader Ledger'),actions:[IconButton(onPressed:payTrader,icon:const Icon(Icons.payments))]),body:loading?const Center(child:CircularProgressIndicator()):grouped.isEmpty?const Center(child:Text('No trader transactions.')):ListView(padding:const EdgeInsets.all(12),children:grouped.values.map((g){final outstanding=(g['payable'] as double)-(g['return'] as double)-(g['paid'] as double);return Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(g['name'] as String,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const SizedBox(height:10),Text('Goods Value: ₹${_formatNumber(g['goods'])}'),Text('GST @ 5%: ₹${_formatNumber(g['gst'])}'),Text('Total Payable: ₹${_formatNumber(g['payable'])}'),Text('Purchase Returns: ₹${_formatNumber(g['return'])}'),Text('Paid: ₹${_formatNumber(g['paid'])}'),const Divider(),Text(outstanding>=0?'Outstanding: ₹${_formatNumber(outstanding)}':'Credit: ₹${_formatNumber(outstanding.abs())}',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:16))])));}).toList()));}
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
  static const String collection = 'invoices';

  static Future<List<Invoice>> load() async {
    final admin = await AuthService.isAdmin();
    final cid = admin ? null : await AuthService.currentCustomerId();
    final maps = await CloudSyncService.loadMaps(collection: collection, localKey: invoicesKey, customerId: cid);
    return maps.map((map) {
      final items = (map['items'] as List? ?? []).map((x) {
        final m = Map<String, dynamic>.from(x);
        return InvoiceItem(
          sareeId: m['sareeId']?.toString() ?? '',
          sareeName: m['sareeName']?.toString() ?? '',
          sareeCode: m['sareeCode']?.toString() ?? '',
          priceCode: m['priceCode']?.toString() ?? '',
          quantity: (m['quantity'] as num?)?.toDouble() ?? 0,
          price: (m['price'] as num?)?.toDouble() ?? 0,
        );
      }).toList();
      return Invoice(
        number: map['number']?.toString() ?? '',
        date: DateTime.tryParse(map['date']?.toString() ?? '') ?? DateTime.now(),
        customerId: map['customerId']?.toString() ?? '',
        customerName: map['customerName']?.toString() ?? '',
        items: items,
        subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0,
        gst: (map['gst'] as num?)?.toDouble() ?? 0,
        grandTotal: (map['grandTotal'] as num?)?.toDouble() ?? 0,
        paid: (map['paid'] as num?)?.toDouble() ?? 0,
        outstanding: (map['outstanding'] as num?)?.toDouble() ?? 0,
      );
    }).toList();
  }

  static Future<void> save(List<Invoice> invoices) async {
    await CloudSyncService.saveMaps(collection: collection, localKey: invoicesKey, items: invoices.map((i) => i.toJson()).toList());
  }

  static Future<void> delete(String number) async {
    final invoices = await load(); final removed = invoices.where((i) => i.number == number).toList(); invoices.removeWhere((i) => i.number == number); await save(invoices); await CloudSyncService.delete(collection: collection, id: number);
    final customerIds = removed.map((i) => i.customerId).where((x) => x.trim().isNotEmpty).toSet();
    if (customerIds.isNotEmpty) await recalculateCustomerPayments(customerIds);
  }

  static Future<void> recalculateCustomerPayments(Set<String> customerIds) async {
    if (customerIds.isEmpty) return;
    final invoices = await loadAdminForCalculation();
    final payments = await PaymentStorage.load();
    for (final customerId in customerIds) {
      final cid = customerId.trim();
      final customerInvoices = invoices.where((i) => i.customerId.trim() == cid).toList()..sort((a,b) { final c=a.date.compareTo(b.date); return c != 0 ? c : a.number.compareTo(b.number); });
      final customerPayments = payments.where((p) => p.customerId.trim() == cid && p.amount > 0).toList()..sort((a,b) { final c=a.date.compareTo(b.date); return c != 0 ? c : a.id.compareTo(b.id); });
      for (final invoice in customerInvoices) { invoice.paid = 0; invoice.outstanding = invoice.grandTotal > 0 ? invoice.grandTotal : 0; }
      for (final payment in customerPayments) {
        var remaining = payment.amount;
        for (final invoice in customerInvoices) {
          if (remaining <= 0) break;
          final due = invoice.grandTotal - invoice.paid;
          if (due <= 0) continue;
          final applied = remaining < due ? remaining : due;
          invoice.paid += applied; invoice.outstanding = (invoice.grandTotal - invoice.paid).clamp(0, double.infinity); remaining -= applied;
        }
      }
    }
    await save(invoices);
  }

  static Future<List<Invoice>> loadAdminForCalculation() async {
    final prefs = await SharedPreferences.getInstance();
    final oldCustomerFlag = prefs.getBool('asc_logged_in_customer');
    // Admin calculations are always based on the cached full dataset if available.
    if (await AuthService.isAdmin()) return load();
    final raw = prefs.getString(invoicesKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded.map((item) {
        final map=Map<String,dynamic>.from(item);
        final items=(map['items'] as List? ?? []).map((x){ final m=Map<String,dynamic>.from(x); return InvoiceItem(sareeId:m['sareeId']?.toString()??'',sareeName:m['sareeName']?.toString()??'',sareeCode:m['sareeCode']?.toString()??'',priceCode:m['priceCode']?.toString()??'',quantity:(m['quantity'] as num?)?.toDouble()??0,price:(m['price'] as num?)?.toDouble()??0);}).toList();
        return Invoice(number:map['number']?.toString()??'',date:DateTime.tryParse(map['date']?.toString()??'')??DateTime.now(),customerId:map['customerId']?.toString()??'',customerName:map['customerName']?.toString()??'',items:items,subtotal:(map['subtotal'] as num?)?.toDouble()??0,gst:(map['gst'] as num?)?.toDouble()??0,grandTotal:(map['grandTotal'] as num?)?.toDouble()??0,paid:(map['paid'] as num?)?.toDouble()??0,outstanding:(map['outstanding'] as num?)?.toDouble()??0);
      }).toList();
    } catch (_) { return []; }
  }

  static Future<String> nextInvoiceNumber() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now(); final start = now.month >= 4 ? now.year : now.year - 1; final end = start + 1; final yearText = '$start-$end';
    final next = (prefs.getInt(numberKey) ?? 0) + 1; await prefs.setInt(numberKey, next); return '$yearText/${next.toString().padLeft(3, '0')}';
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
  static const String paymentsKey = 'ajanta_payments';
  static const String paymentNumberKey = 'ajanta_payment_number';
  static const String collection = 'payments';

  static Future<List<Payment>> load() async {
    final admin = await AuthService.isAdmin(); final cid = admin ? null : await AuthService.currentCustomerId();
    final maps = await CloudSyncService.loadMaps(collection: collection, localKey: paymentsKey, customerId: cid);
    return maps.map((map) => Payment.fromJson(map)).toList();
  }
  static Future<void> save(List<Payment> payments) async {
    await CloudSyncService.saveMaps(collection: collection, localKey: paymentsKey, items: payments.map((p) => p.toJson()).toList());
  }
  static Future<String> nextPaymentId() async { final prefs=await SharedPreferences.getInstance(); final next=(prefs.getInt(paymentNumberKey)??0)+1; await prefs.setInt(paymentNumberKey,next); return 'PAY-${next.toString().padLeft(4,'0')}'; }
  static Future<void> delete(String paymentId) async { final payments=await load(); final removed=payments.where((p)=>p.id==paymentId).toList(); payments.removeWhere((p)=>p.id==paymentId); await save(payments); await CloudSyncService.delete(collection:collection,id:paymentId); for(final p in removed){ if(p.customerId.trim().isNotEmpty) await InvoiceStorage.recalculateCustomerPayments({p.customerId}); await CashbookStorage.deleteBySource(p.id); } }
}

// ============================================================
// SESSION MANAGEMENT
// ============================================================

class SessionManager {
  static const String loggedInKey = 'asc_logged_in';
  static const String customerKey = 'asc_logged_in_customer';
  static const String customerIdKey = 'asc_customer_id';
  static const String adminIdKey = 'asc_admin_id';

  static Future<void> saveAdminSession([String? adminId]) async { final prefs=await SharedPreferences.getInstance(); await prefs.setBool(loggedInKey,true); await prefs.setBool(customerKey,false); await prefs.remove(customerIdKey); if(adminId!=null) await prefs.setString(adminIdKey,adminId); }
  static Future<void> saveCustomerSession(String customerId) async { final prefs=await SharedPreferences.getInstance(); await prefs.setBool(loggedInKey,true); await prefs.setBool(customerKey,true); await prefs.setString(customerIdKey,customerId); await prefs.remove(adminIdKey); }
  static Future<bool> isLoggedIn() async => FirebaseAuth.instance.currentUser != null || ((await SharedPreferences.getInstance()).getBool(loggedInKey) ?? false);
  static Future<bool> isCustomer() async { final prefs=await SharedPreferences.getInstance(); return prefs.getBool(customerKey) ?? false; }
  static Future<String> getCustomerId() async { final prefs=await SharedPreferences.getInstance(); return prefs.getString(customerIdKey) ?? await AuthService.currentCustomerId(); }
  static Future<void> logout() async { final prefs=await SharedPreferences.getInstance(); await prefs.remove(loggedInKey); await prefs.remove(customerKey); await prefs.remove(customerIdKey); await prefs.remove(adminIdKey); await AuthService.signOut(); }
}

// ============================================================
// SESSION CHECK
// ============================================================

class SessionPage extends StatefulWidget {
  const SessionPage({super.key});
  @override State<SessionPage> createState()=>_SessionPageState();
}
class _SessionPageState extends State<SessionPage>{
  @override void initState(){super.initState(); checkSession();}
  Future<void> checkSession() async {
    final loggedIn = FirebaseAuth.instance.currentUser != null || await SessionManager.isLoggedIn();
    if(!mounted)return;
    if(!loggedIn){Navigator.pushReplacement(context,MaterialPageRoute(builder:(_)=>const LoginPage()));return;}
    bool customer = await SessionManager.isCustomer();
    if (FirebaseAuth.instance.currentUser != null) {
      try {
        final token = await FirebaseAuth.instance.currentUser!.getIdTokenResult();
        customer = token.claims?['role']?.toString() == 'customer';
        if (customer) {
          final cid = token.claims?['customerId']?.toString() ?? '';
          if (cid.isNotEmpty) await SessionManager.saveCustomerSession(cid);
        }
      } catch (_) {}
    }
    if(!mounted)return;
    if(customer){
      final cid=await SessionManager.getCustomerId();
      if(cid.isEmpty){await SessionManager.logout(); if(!mounted)return; Navigator.pushReplacement(context,MaterialPageRoute(builder:(_)=>const LoginPage()));return;}
      Navigator.pushReplacement(context,MaterialPageRoute(builder:(_)=>HomePage(customer:true,customerId:cid)));
    } else {
      Navigator.pushReplacement(context,MaterialPageRoute(builder:(_)=>const HomePage(customer:false)));
    }
  }
  @override Widget build(BuildContext context)=>const Scaffold(body:Center(child:CircularProgressIndicator()));
}

// ============================================================
// LOGIN
// ============================================================

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

const String admin1Id = 'nikhilasc';
const String admin1Pin = '0521';
const String admin2Id = 'kailashasc';
const String admin2Pin = '2105';

class _LoginPageState extends State<LoginPage> {
  final idController = TextEditingController();
  final pinController = TextEditingController();
  bool customer = true;
  bool loading = false;

  Future<void> login() async {
    final id=idController.text.trim(); final pin=pinController.text.trim();
    if(id.isEmpty || pin.isEmpty){ ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Please enter ID and PIN'))); return; }
    setState(() => loading=true);
    try {
      if(!customer){
        await AuthService.loginAdmin(id,pin); await SessionManager.saveAdminSession(id);
        if(!mounted) return; Navigator.pushReplacement(context,MaterialPageRoute(builder:(_)=>const HomePage(customer:false)));
      } else {
        await AuthService.loginCustomer(id.toLowerCase(),pin); await SessionManager.saveCustomerSession(id.toLowerCase());
        if(!mounted) return; Navigator.pushReplacement(context,MaterialPageRoute(builder:(_)=>HomePage(customer:true,customerId:id.toLowerCase())));
      }
    } catch(e){ if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString().replaceFirst('Exception: ','')))); }
    finally { if(mounted) setState(()=>loading=false); }
  }
  @override void dispose(){ idController.dispose(); pinController.dispose(); super.dispose(); }
  @override Widget build(BuildContext context){
    return Scaffold(body:SafeArea(child:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:Column(children:[
      const Icon(Icons.storefront,size:75), const SizedBox(height:15), const Text('AJANTA SAREE CENTRE',textAlign:TextAlign.center,style:TextStyle(fontSize:25,fontWeight:FontWeight.bold)), const SizedBox(height:5), const Text('Satna (M.P.)'), const SizedBox(height:30),
      SegmentedButton<bool>(segments:const[ButtonSegment(value:false,label:Text('Admin'),icon:Icon(Icons.admin_panel_settings)),ButtonSegment(value:true,label:Text('Customer'),icon:Icon(Icons.person))],selected:{customer},onSelectionChanged:(v)=>setState((){customer=v.first;idController.clear();pinController.clear();})),
      const SizedBox(height:20), TextField(controller:idController,decoration:InputDecoration(labelText:customer?'Customer ID':'Admin ID',prefixIcon:const Icon(Icons.person))), const SizedBox(height:14),
      TextField(controller:pinController,obscureText:true,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'PIN',prefixIcon:Icon(Icons.lock))), const SizedBox(height:20),
      SizedBox(width:double.infinity,height:50,child:FilledButton.icon(onPressed:loading?null:login,icon:loading?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.login),label:Text(loading?'PLEASE WAIT':'LOGIN'))), const SizedBox(height:15), const Text('No OTP authentication',style:TextStyle(fontSize:12)),
    ])))));
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

class DashboardPage extends StatefulWidget {
  final bool customer;
  const DashboardPage({super.key, required this.customer});
  @override State<DashboardPage> createState()=>_DashboardPageState();
}
class _DashboardPageState extends State<DashboardPage>{
  double sales=0,purchases=0,customerOutstanding=0,traderOutstanding=0;
  bool loading=true;
  @override void initState(){super.initState();load();}
  Future<void> load() async {
    final now=DateTime.now(); final start=DateTime(now.year,now.month,now.day);
    final end=start.add(const Duration(days:1));
    final invoices=await InvoiceStorage.load(); final pur=await PurchaseStorage.load(); final pays=await PaymentStorage.load(); final tp=await TraderPaymentStorage.load(); final customers=await CustomerStorage.load();
    sales=invoices.where((i)=>!i.date.isBefore(start)&&i.date.isBefore(end)).fold(0,(s,i)=>s+i.grandTotal);
    purchases=pur.where((p)=>!p.date.isBefore(start)&&p.date.isBefore(end)).fold(0,(s,p)=>s+p.grandTotal);
    customerOutstanding=customers.fold(0,(s,c)=>s+c.outstanding);
    final payBy=<String,double>{}; for(final p in tp){payBy[p.trader.toLowerCase()]=(payBy[p.trader.toLowerCase()]??0)+p.amount;}
    traderOutstanding=0; final grouped=<String,double>{}; for(final p in pur){grouped[p.trader.toLowerCase()]=(grouped[p.trader.toLowerCase()]??0)+p.grandTotal;}
    for(final e in grouped.entries){traderOutstanding += e.value-(payBy[e.key]??0);}
    if(mounted)setState(()=>loading=false);
  }
  Widget card(IconData icon,String title,double value)=>Card(child:ListTile(leading:Icon(icon,size:30),title:Text(title),trailing:Text('₹${_formatNumber(value)}',style:const TextStyle(fontWeight:FontWeight.bold))));
  @override Widget build(BuildContext context){return RefreshIndicator(onRefresh:load,child:SafeArea(child:ListView(padding:const EdgeInsets.all(16),children:[Text(widget.customer?'MY ACCOUNT':'AJANTA SAREE CENTRE',style:const TextStyle(fontSize:23,fontWeight:FontWeight.bold)),const Text('Satna (M.P.)'),const SizedBox(height:20),loading?const Center(child:CircularProgressIndicator()):Column(children:[card(Icons.receipt_long,"Today's Sales",sales),card(Icons.shopping_cart,"Today's Purchases",purchases),card(Icons.people,'Customer Outstanding',customerOutstanding),card(Icons.store,'Trader Outstanding',traderOutstanding)])])));}
}

// ============================================================
// SALES / INVOICE LIST
// ============================================================

class SalesPage extends StatefulWidget { const SalesPage({super.key}); @override State<SalesPage> createState()=>_SalesPageState(); }
class _SalesPageState extends State<SalesPage>{
  List<Invoice> invoices=[]; bool loading=true;
  @override void initState(){super.initState();loadInvoices();}
  Future<void> loadInvoices() async {final d=await InvoiceStorage.load();if(!mounted)return;setState((){invoices=d..sort((a,b)=>b.date.compareTo(a.date));loading=false;});}
  Future<void> createInvoice() async {
    final result=await Navigator.push<Invoice>(context,MaterialPageRoute(builder:(_)=>const CreateInvoicePage())); if(result==null)return;
    final list=await InvoiceStorage.load(); list.insert(0,result); await InvoiceStorage.save(list);
    final sarees=await InventoryStorage.load();
    for(final item in result.items){if(item.sareeId.trim().isEmpty)continue;final i=sarees.indexWhere((s)=>s.id==item.sareeId);if(i==-1)continue;if(item.priceCode=='RETURN')sarees[i].stock+=item.quantity;else{sarees[i].stock-=item.quantity;if(sarees[i].stock<0)sarees[i].stock=0;}}
    await InventoryStorage.save(sarees);
    if(result.paid>0 && result.customerId.trim().isNotEmpty){final payment=Payment(id:await PaymentStorage.nextPaymentId(),customerId:result.customerId,customerName:result.customerName,date:result.date,amount:result.paid,reference:'Invoice ${result.number}',notes:'Amount received with invoice');final pays=await PaymentStorage.load();pays.add(payment);await PaymentStorage.save(pays);await CashbookStorage.add(CashbookEntry(id:payment.id,date:payment.date,type:'Income',category:'Customer Payment',amount:payment.amount,notes:'${payment.reference}'));}
    if(result.customerId.trim().isNotEmpty)await InvoiceStorage.recalculateCustomerPayments({result.customerId});
    await loadInvoices();
  }
  Future<void> deleteInvoice(Invoice invoice) async {
    final ok=await showDialog<bool>(context:context,builder:(_)=>AlertDialog(title:const Text('PERMANENT DELETE'),content:Text('Delete invoice ${invoice.number}?\n\nThis permanently removes the invoice and reverses its inventory effect. Payments linked to this invoice remain customer payments.\n\nThis action cannot be undone.'),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('CANCEL')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('DELETE'))]));
    if(ok!=true)return;
    final sarees=await InventoryStorage.load(); for(final item in invoice.items){if(item.sareeId.trim().isEmpty)continue;final i=sarees.indexWhere((s)=>s.id==item.sareeId);if(i==-1)continue;if(item.priceCode=='RETURN'){sarees[i].stock-=item.quantity;if(sarees[i].stock<0)sarees[i].stock=0;}else{sarees[i].stock+=item.quantity;}} await InventoryStorage.save(sarees);
    await InvoiceStorage.delete(invoice.number); await loadInvoices();
  }
  @override Widget build(BuildContext context){return Scaffold(appBar:AppBar(title:const Text('Sales & Invoices',style:TextStyle(fontWeight:FontWeight.bold))),body:loading?const Center(child:CircularProgressIndicator()):invoices.isEmpty?const Center(child:Text('No invoices yet.')):ListView.builder(padding:const EdgeInsets.all(12),itemCount:invoices.length,itemBuilder:(context,index){final invoice=invoices[index];return Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.receipt_long)),title:Text(invoice.number,style:const TextStyle(fontWeight:FontWeight.bold)),subtitle:Text('${invoice.customerName.isEmpty?'Cash Customer':invoice.customerName}\nPaid ₹${_formatNumber(invoice.paid)} • Due ₹${_formatNumber(invoice.outstanding)}'),isThreeLine:true,trailing:PopupMenuButton<String>(onSelected:(v)async{if(v=='pdf')await PdfService.shareInvoice(invoice);if(v=='delete')await deleteInvoice(invoice);},itemBuilder:(_)=>const[PopupMenuItem(value:'pdf',child:Text('PDF / Share')),PopupMenuItem(value:'delete',child:Text('Delete'))])));}),floatingActionButton:FloatingActionButton.extended(onPressed:createInvoice,icon:const Icon(Icons.add),label:const Text('New Invoice')));}
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

  if (!mounted) return;

  setState(() {
    sarees = inventoryData;
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
      await InventoryStorage.delete(saree.id);
      await loadInventory();
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
  onChanged: (_) {
    setState(() {});
  },
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
// CASHBOOK
// ============================================================

class CashbookEntry {
  String id; DateTime date; String type; String category; double amount; String notes;
  CashbookEntry({required this.id,required this.date,required this.type,required this.category,required this.amount,required this.notes});
  Map<String,dynamic> toJson()=>{'id':id,'date':date.toIso8601String(),'type':type,'category':category,'amount':amount,'notes':notes};
  factory CashbookEntry.fromJson(Map<String,dynamic> m)=>CashbookEntry(id:m['id']?.toString()??'',date:DateTime.tryParse(m['date']?.toString()??'')??DateTime.now(),type:m['type']?.toString()??'Expense',category:m['category']?.toString()??'',amount:(m['amount'] as num?)?.toDouble()??0,notes:m['notes']?.toString()??'');
}
class CashbookStorage {
  static const key='ajanta_cashbook'; static const collection='cashbook';
  static Future<List<CashbookEntry>> load() async {final maps=await CloudSyncService.loadMaps(collection:collection,localKey:key);return maps.map(CashbookEntry.fromJson).toList();}
  static Future<void> save(List<CashbookEntry> e) async=>CloudSyncService.saveMaps(collection:collection,localKey:key,items:e.map((x)=>x.toJson()).toList());
  static Future<void> add(CashbookEntry e) async {final d=await load();d.removeWhere((x)=>x.id==e.id);d.add(e);await save(d);}
  static Future<void> delete(String id) async {final d=await load();d.removeWhere((x)=>x.id==id);await save(d);await CloudSyncService.delete(collection:collection,id:id);}
  static Future<void> deleteBySource(String id)=>delete(id);
}
class CashbookPage extends StatefulWidget {
  const CashbookPage({super.key});
  @override
  State<CashbookPage> createState() => _CashbookPageState();
}

class _CashbookPageState extends State<CashbookPage> {
  List<CashbookEntry> entries = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final data = await CashbookStorage.load();
    data.sort((a, b) => b.date.compareTo(a.date));
    if (!mounted) return;
    setState(() {
      entries = data;
      loading = false;
    });
  }

  Future<void> addEntry() async {
    final result = await Navigator.push<CashbookEntry>(
      context,
      MaterialPageRoute(builder: (_) => const AddCashbookEntryPage()),
    );
    if (result != null) {
      await CashbookStorage.add(result);
      await load();
    }
  }

  Future<void> deleteEntry(CashbookEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete cashbook entry?'),
        content: Text(
          'Delete ${entry.category} ₹${_formatNumber(entry.amount)} permanently?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await CashbookStorage.delete(entry.id);
      await load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cashbook')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : entries.isEmpty
              ? const Center(child: Text('No cashbook entries.'))
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          entry.type == 'Income'
                              ? Icons.arrow_downward
                              : Icons.arrow_upward,
                        ),
                        title: Text(
                          entry.category,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${_dateText(entry.date)}\n${entry.notes}',
                        ),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('₹${_formatNumber(entry.amount)}'),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => deleteEntry(entry),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: addEntry,
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
    );
  }
}
class AddCashbookEntryPage extends StatefulWidget{const AddCashbookEntryPage({super.key});@override State<AddCashbookEntryPage> createState()=>_AddCashbookEntryPageState();}
class _AddCashbookEntryPageState extends State<AddCashbookEntryPage>{final amount=TextEditingController();final category=TextEditingController();final notes=TextEditingController();String type='Expense';Future<void>save()async{final a=double.tryParse(amount.text.trim());if(a==null||a<=0||category.text.trim().isEmpty)return;final e=CashbookEntry(id:'CB-${DateTime.now().microsecondsSinceEpoch}',date:DateTime.now(),type:type,category:category.text.trim(),amount:a,notes:notes.text.trim());if(mounted)Navigator.pop(context,e);} @override void dispose(){amount.dispose();category.dispose();notes.dispose();super.dispose();}@override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Add Cashbook Entry')),body:ListView(padding:const EdgeInsets.all(16),children:[DropdownButtonFormField<String>(value:type,items:const[DropdownMenuItem(value:'Income',child:Text('Income')),DropdownMenuItem(value:'Expense',child:Text('Expense'))],onChanged:(v)=>setState(()=>type=v??'Expense'),decoration:const InputDecoration(labelText:'Type')),const SizedBox(height:16),TextField(controller:category,decoration:const InputDecoration(labelText:'Category')),const SizedBox(height:16),TextField(controller:amount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Amount',prefixText:'₹ ')),const SizedBox(height:16),TextField(controller:notes,maxLines:3,decoration:const InputDecoration(labelText:'Notes')),const SizedBox(height:24),FilledButton(onPressed:save,child:const Text('SAVE ENTRY'))]));}

// ============================================================
// RETURNS
// ============================================================

class ReturnRecord {
  String id; DateTime date; String type; String partyName; String sareeId; String sareeName; String sareeCode; double quantity; double amount; double gst; String notes;
  ReturnRecord({required this.id,required this.date,required this.type,required this.partyName,required this.sareeId,required this.sareeName,required this.sareeCode,required this.quantity,required this.amount,required this.gst,required this.notes});
  double get total=>amount+gst;
  Map<String,dynamic> toJson()=>{'id':id,'date':date.toIso8601String(),'type':type,'partyName':partyName,'sareeId':sareeId,'sareeName':sareeName,'sareeCode':sareeCode,'quantity':quantity,'amount':amount,'gst':gst,'notes':notes};
  factory ReturnRecord.fromJson(Map<String,dynamic> m)=>ReturnRecord(id:m['id']?.toString()??'',date:DateTime.tryParse(m['date']?.toString()??'')??DateTime.now(),type:m['type']?.toString()??'PURCHASE_RETURN',partyName:m['partyName']?.toString()??'',sareeId:m['sareeId']?.toString()??'',sareeName:m['sareeName']?.toString()??'',sareeCode:m['sareeCode']?.toString()??'',quantity:(m['quantity'] as num?)?.toDouble()??0,amount:(m['amount'] as num?)?.toDouble()??0,gst:(m['gst'] as num?)?.toDouble()??0,notes:m['notes']?.toString()??'');
}
class ReturnStorage{static const key='ajanta_returns';static const collection='returns';static Future<List<ReturnRecord>> load()async{final maps=await CloudSyncService.loadMaps(collection:collection,localKey:key);return maps.map(ReturnRecord.fromJson).toList();}static Future<void>save(List<ReturnRecord> r)async=>CloudSyncService.saveMaps(collection:collection,localKey:key,items:r.map((x)=>x.toJson()).toList());static Future<void>delete(String id)async{final d=await load();d.removeWhere((x)=>x.id==id);await save(d);await CloudSyncService.delete(collection:collection,id:id);}}
class ReturnsPage extends StatefulWidget{const ReturnsPage({super.key});@override State<ReturnsPage> createState()=>_ReturnsPageState();}
class _ReturnsPageState extends State<ReturnsPage>{List<ReturnRecord> returns=[];List<Invoice> saleInvoices=[];bool loading=true;@override void initState(){super.initState();load();}Future<void>load()async{returns=await ReturnStorage.load();saleInvoices=await InvoiceStorage.load();if(mounted)setState(()=>loading=false);}
Future<void>addPurchaseReturn()async{final result=await Navigator.push<ReturnRecord>(context,MaterialPageRoute(builder:(_)=>const AddPurchaseReturnPage()));if(result!=null){final r=await ReturnStorage.load();r.add(result);await ReturnStorage.save(r);final inv=await InventoryStorage.load();final i=inv.indexWhere((s)=>s.id==result.sareeId);if(i!=-1){inv[i].stock-=result.quantity;if(inv[i].stock<0)inv[i].stock=0;await InventoryStorage.save(inv);}await load();}}
Future<void>deleteReturn(ReturnRecord r)async{final ok=await showDialog<bool>(context:context,builder:(_)=>AlertDialog(title:const Text('Permanent delete'),content:Text('Delete ${r.id}? Inventory will be increased back by ${_formatNumber(r.quantity)}.'),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('CANCEL')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('DELETE'))]));if(ok!=true)return;final inv=await InventoryStorage.load();final i=inv.indexWhere((s)=>s.id==r.sareeId);if(i!=-1){inv[i].stock+=r.quantity;await InventoryStorage.save(inv);}await ReturnStorage.delete(r.id);await load();}
@override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Returns')),body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(12),children:[const Text('Sales Returns',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:8),...saleInvoices.expand((inv)=>inv.items.where((x)=>x.priceCode=='RETURN').map((item)=>Card(child:ListTile(leading:const Icon(Icons.assignment_return),title:Text(item.sareeName),subtitle:Text('Invoice ${inv.number} • ${_dateText(inv.date)} • Qty ${_formatNumber(item.quantity)}'),trailing:Text('₹${_formatNumber(item.total)}'))))),const SizedBox(height:20),const Text('Purchase Returns',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:8),...returns.where((r)=>r.type=='PURCHASE_RETURN').map((r)=>Card(child:ListTile(leading:const Icon(Icons.undo),title:Text(r.sareeName,style:const TextStyle(fontWeight:FontWeight.bold)),subtitle:Text('${r.id}\nTrader: ${r.partyName}\nQty: ${_formatNumber(r.quantity)} • GST: ₹${_formatNumber(r.gst)}'),isThreeLine:true,trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:()=>deleteReturn(r)))))],),floatingActionButton:FloatingActionButton.extended(onPressed:addPurchaseReturn,icon:const Icon(Icons.undo),label:const Text('Purchase Return')));}
class AddPurchaseReturnPage extends StatefulWidget{const AddPurchaseReturnPage({super.key});@override State<AddPurchaseReturnPage> createState()=>_AddPurchaseReturnPageState();}
class _AddPurchaseReturnPageState extends State<AddPurchaseReturnPage>{List<Purchase> purchases=[];Purchase? selected;final qty=TextEditingController();final notes=TextEditingController();@override void initState(){super.initState();load();}Future<void>load()async{final p=await PurchaseStorage.load();if(mounted)setState(()=>purchases=p);}Future<void>save()async{if(selected==null)return;final q=double.tryParse(qty.text.trim());if(q==null||q<=0||q>selected!.quantity)return;final goods=q*selected!.purchasePrice;final r=ReturnRecord(id:'RET-${DateTime.now().microsecondsSinceEpoch}',date:DateTime.now(),type:'PURCHASE_RETURN',partyName:selected!.trader,sareeId:selected!.sareeId,sareeName:selected!.sareeName,sareeCode:selected!.sareeCode,quantity:q,amount:goods,gst:goods*0.05,notes:notes.text.trim());if(mounted)Navigator.pop(context,r);} @override void dispose(){qty.dispose();notes.dispose();super.dispose();}@override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Purchase Return')),body:ListView(padding:const EdgeInsets.all(16),children:[DropdownButtonFormField<Purchase>(value:selected,isExpanded:true,items:purchases.map((p)=>DropdownMenuItem(value:p,child:Text('${p.sareeName} • ${p.trader} • ${_formatNumber(p.quantity)}'))).toList(),onChanged:(v)=>setState(()=>selected=v),decoration:const InputDecoration(labelText:'Purchase')),const SizedBox(height:16),TextField(controller:qty,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Return Quantity')),const SizedBox(height:16),TextField(controller:notes,maxLines:3,decoration:const InputDecoration(labelText:'Notes')),const SizedBox(height:24),FilledButton(onPressed:save,child:const Text('SAVE RETURN'))]));}

// ============================================================
// REPORTS
// ============================================================

class ReportsPage extends StatefulWidget{const ReportsPage({super.key});@override State<ReportsPage> createState()=>_ReportsPageState();}
class _ReportsPageState extends State<ReportsPage>{List<Invoice> invoices=[];List<Purchase> purchases=[];List<Payment> payments=[];List<TraderPayment> traderPayments=[];List<CashbookEntry> cashbook=[];List<ReturnRecord> returns=[];bool loading=true;@override void initState(){super.initState();load();}Future<void>load()async{invoices=await InvoiceStorage.load();purchases=await PurchaseStorage.load();payments=await PaymentStorage.load();traderPayments=await TraderPaymentStorage.load();cashbook=await CashbookStorage.load();returns=await ReturnStorage.load();if(mounted)setState(()=>loading=false);}
String get summary {final sales=invoices.fold(0.0,(s,i)=>s+i.grandTotal);final gstSales=invoices.fold(0.0,(s,i)=>s+i.gst);final goodsPurch=purchases.fold(0.0,(s,p)=>s+p.total);final gstPurch=purchases.fold(0.0,(s,p)=>s+p.gstAmount);final paid=paysSum(payments);final tpaid=paysSumTrader(traderPayments);final expenses=cashbook.where((e)=>e.type=='Expense').fold(0.0,(s,e)=>s+e.amount);return 'Sales: ₹${_formatNumber(sales)}\nGST on sales: ₹${_formatNumber(gstSales)}\nPurchases: ₹${_formatNumber(goodsPurch)}\nGST on purchases: ₹${_formatNumber(gstPurch)}\nCustomer payments: ₹${_formatNumber(paid)}\nTrader payments: ₹${_formatNumber(tpaid)}\nCashbook expenses: ₹${_formatNumber(expenses)}\nPurchase returns: ${returns.where((r)=>r.type=='PURCHASE_RETURN').length}';}
double paysSum(List<Payment> l)=>l.fold(0.0,(s,p)=>s+p.amount);double paysSumTrader(List<TraderPayment> l)=>l.fold(0.0,(s,p)=>s+p.amount);
Future<void>exportExcel()async{final f=await ExcelService.createWorkbook();await FileShareService.shareFile(f,text:'Ajanta Saree Centre Excel export');}
@override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Reports'),actions:[IconButton(onPressed:exportExcel,icon:const Icon(Icons.table_view)),IconButton(onPressed:()=>PdfService.shareTextReport('ASC_Report',summary),icon:const Icon(Icons.picture_as_pdf))]),body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(16),children:[Card(child:Padding(padding:const EdgeInsets.all(16),child:Text(summary,style:const TextStyle(height:1.7)))),const SizedBox(height:12),FilledButton.icon(onPressed:load,icon:const Icon(Icons.refresh),label:const Text('Refresh'))]));}

// ============================================================
// BACKUP / RESTORE
// ============================================================

class BackupRestorePage extends StatefulWidget{const BackupRestorePage({super.key});@override State<BackupRestorePage> createState()=>_BackupRestorePageState();}
class _BackupRestorePageState extends State<BackupRestorePage>{bool working=false;
Future<Map<String,dynamic>> snapshot()async{return {'version':1,'createdAt':DateTime.now().toIso8601String(),'inventory':(await InventoryStorage.load()).map((x)=>x.toJson()).toList(),'purchases':(await PurchaseStorage.load()).map((x)=>x.toJson()).toList(),'invoices':(await InvoiceStorage.load()).map((x)=>x.toJson()).toList(),'payments':(await PaymentStorage.load()).map((x)=>x.toJson()).toList(),'traderPayments':(await TraderPaymentStorage.load()).map((x)=>x.toJson()).toList(),'customers':(await CustomerStorage.load()).map((x)=>x.toMap()).toList(),'cashbook':(await CashbookStorage.load()).map((x)=>x.toJson()).toList(),'returns':(await ReturnStorage.load()).map((x)=>x.toJson()).toList()};}
Future<void>backup()async{setState(()=>working=true);try{final data=jsonEncode(await snapshot());final f=await FileShareService.writeTempBytes('Ajanta_Saree_Centre_Backup_${DateTime.now().millisecondsSinceEpoch}.json',utf8.encode(data));await FileShareService.shareFile(f,text:'Ajanta Saree Centre backup');}finally{if(mounted)setState(()=>working=false);}}
Future<void> restore() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('RESTORE BACKUP'),
        content: const Text(
          'This will replace the local business dataset with the selected backup and upload the restored business records to Firestore. Customer login passwords are not included in backups.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('CONTINUE'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final pick = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (pick == null || pick.files.single.bytes == null) return;

    setState(() => working = true);
    try {
      final map = jsonDecode(
        utf8.decode(pick.files.single.bytes!),
      ) as Map<String, dynamic>;

      final inventory = (map['inventory'] as List? ?? [])
          .map((e) => Saree.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      await InventoryStorage.save(inventory);

      final purchases = (map['purchases'] as List? ?? [])
          .map((e) => Purchase.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      await PurchaseStorage.save(purchases);

      final invoices = <Invoice>[];
      for (final raw in (map['invoices'] as List? ?? [])) {
        final m = Map<String, dynamic>.from(raw);
        final items = (m['items'] as List? ?? []).map((x) {
          final item = Map<String, dynamic>.from(x);
          return InvoiceItem(
            sareeId: item['sareeId']?.toString() ?? '',
            sareeName: item['sareeName']?.toString() ?? '',
            sareeCode: item['sareeCode']?.toString() ?? '',
            priceCode: item['priceCode']?.toString() ?? '',
            quantity: (item['quantity'] as num?)?.toDouble() ?? 0,
            price: (item['price'] as num?)?.toDouble() ?? 0,
          );
        }).toList();
        invoices.add(
          Invoice(
            number: m['number']?.toString() ?? '',
            date: DateTime.tryParse(m['date']?.toString() ?? '') ?? DateTime.now(),
            customerId: m['customerId']?.toString() ?? '',
            customerName: m['customerName']?.toString() ?? '',
            items: items,
            subtotal: (m['subtotal'] as num?)?.toDouble() ?? 0,
            gst: (m['gst'] as num?)?.toDouble() ?? 0,
            grandTotal: (m['grandTotal'] as num?)?.toDouble() ?? 0,
            paid: (m['paid'] as num?)?.toDouble() ?? 0,
            outstanding: (m['outstanding'] as num?)?.toDouble() ?? 0,
          ),
        );
      }
      await InvoiceStorage.save(invoices);

      final payments = (map['payments'] as List? ?? [])
          .map((e) => Payment.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      await PaymentStorage.save(payments);

      final traderPayments = (map['traderPayments'] as List? ?? [])
          .map((e) => TraderPayment.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      await TraderPaymentStorage.save(traderPayments);

      for (final raw in (map['customers'] as List? ?? [])) {
        await CustomerStorage.save(
          Customer.fromMap(Map<String, dynamic>.from(raw)),
        );
      }

      final cashbook = (map['cashbook'] as List? ?? [])
          .map((e) => CashbookEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      await CashbookStorage.save(cashbook);

      final returns = (map['returns'] as List? ?? [])
          .map((e) => ReturnRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      await ReturnStorage.save(returns);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup restored successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => working = false);
    }
  }
@override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Backup / Restore')),body:ListView(padding:const EdgeInsets.all(16),children:[const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('Backup includes inventory, purchases, invoices, payments, trader payments, customers, cashbook and returns. Customer login passwords are never exported.'))),const SizedBox(height:16),FilledButton.icon(onPressed:working?null:backup,icon:const Icon(Icons.backup),label:const Text('CREATE BACKUP')),const SizedBox(height:12),OutlinedButton.icon(onPressed:working?null:restore,icon:const Icon(Icons.restore),label:const Text('RESTORE BACKUP')),if(working)...[const SizedBox(height:20),const Center(child:CircularProgressIndicator())]]));}

// ============================================================
// SETTINGS
// ============================================================

class SettingsPage extends StatelessWidget{const SettingsPage({super.key});@override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Settings')),body:ListView(children:[ListTile(leading:const Icon(Icons.cloud_done),title:const Text('Cloud database'),subtitle:const Text('Firestore + Firebase Authentication')),ListTile(leading:const Icon(Icons.percent),title:const Text('GST on sales'),subtitle:const Text('5%')),ListTile(leading:const Icon(Icons.percent),title:const Text('GST on purchases'),subtitle:const Text('5%')),ListTile(leading:const Icon(Icons.security),title:const Text('Customer access'),subtitle:const Text('Customer accounts can view only their own invoices, payments and profile.')),ListTile(leading:const Icon(Icons.info_outline),title:const Text('Ajanta Saree Centre'),subtitle:const Text('Satna (M.P.)'))]));}

// ============================================================
// MORE
// ============================================================

class MorePage extends StatelessWidget {
  const MorePage({super.key});
  Widget tile(BuildContext context, IconData icon, String title, Widget page)=>ListTile(leading:Icon(icon),title:Text(title),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>page)));
  @override Widget build(BuildContext context){return Scaffold(appBar:AppBar(title:const Text('More')),body:ListView(padding:const EdgeInsets.all(16),children:[
    tile(context,Icons.shopping_bag,'Purchases',const PurchasesPage()),
    tile(context,Icons.account_balance,'Trader Ledger',const TraderLedgerPage()),
    tile(context,Icons.assignment_return,'Returns',const ReturnsPage()),
    tile(context,Icons.account_balance_wallet,'Cashbook',const CashbookPage()),
    tile(context,Icons.bar_chart,'Reports',const ReportsPage()),
    tile(context,Icons.backup,'Backup / Restore',const BackupRestorePage()),
    tile(context,Icons.settings,'Settings',const SettingsPage()),
    const Divider(),
    ListTile(leading:const Icon(Icons.logout),title:const Text('Logout'),onTap:() async {final ok=await showDialog<bool>(context:context,builder:(_)=>AlertDialog(title:const Text('Logout?'),content:const Text('Your session will be ended on this device.'),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('CANCEL')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('LOGOUT'))])); if(ok==true){await SessionManager.logout();if(context.mounted)Navigator.pushAndRemoveUntil(context,MaterialPageRoute(builder:(_)=>const LoginPage()),(_)=>false);}}),
  ]));}
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
    await CashbookStorage.deleteBySource(payment.id);

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

class CustomerAccountDetailPage extends StatelessWidget {
  final Customer customer; final List<Invoice> invoices; final List<Payment> payments;
  const CustomerAccountDetailPage({super.key,required this.customer,required this.invoices,required this.payments});
  @override Widget build(BuildContext context){
    final inv=List<Invoice>.from(invoices)..sort((a,b)=>b.date.compareTo(a.date)); final pays=List<Payment>.from(payments)..sort((a,b)=>b.date.compareTo(a.date));
    final totalSales=inv.fold(0.0,(s,i)=>s+i.grandTotal); final totalPaid=pays.fold(0.0,(s,p)=>s+p.amount); final balance=totalSales-totalPaid;
    return Scaffold(appBar:AppBar(title:Text(customer.name,style:const TextStyle(fontWeight:FontWeight.bold))),body:ListView(padding:const EdgeInsets.all(16),children:[
      Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(customer.name,style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:6),Text('Customer ID: ${customer.id}'),if(customer.gstNumber.trim().isNotEmpty)Text('GST: ${customer.gstNumber}')]))),
      const SizedBox(height:12),Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(children:[_AccountAmountRow(label:'Total Sales',amount:totalSales),const Divider(),_AccountAmountRow(label:'Total Payments',amount:totalPaid),const Divider(),_AccountAmountRow(label:balance>=0?'Outstanding':'Customer Credit',amount:balance.abs(),bold:true)]))),
      const SizedBox(height:24),const Text('Invoices',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:8),
      if(inv.isEmpty)const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('No invoices found.'))),
      ...inv.map((invoice)=>Card(child:ListTile(leading:const Icon(Icons.receipt_long),title:Text(invoice.number,style:const TextStyle(fontWeight:FontWeight.bold)),subtitle:Text('${_dateText(invoice.date)}\nPaid: ₹${_formatNumber(invoice.paid)} • Due: ₹${_formatNumber(invoice.outstanding)}'),isThreeLine:true,trailing:IconButton(icon:const Icon(Icons.picture_as_pdf_outlined),onPressed:()=>PdfService.shareInvoice(invoice))))),
      const SizedBox(height:24),const Text('Payments',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:8),
      if(pays.isEmpty)const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('No payments found.'))),
      ...pays.map((payment)=>Card(child:ListTile(leading:const Icon(Icons.payments),title:Text(payment.id,style:const TextStyle(fontWeight:FontWeight.bold)),subtitle:Text('${_dateText(payment.date)}${payment.reference.isEmpty?'':'\nRef: ${payment.reference}'}'),trailing:Text('₹${_formatNumber(payment.amount)}',style:const TextStyle(fontWeight:FontWeight.bold))))),
    ]));
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
