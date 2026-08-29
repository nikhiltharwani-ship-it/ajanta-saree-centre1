import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SharedPreferences.getInstance();
  runApp(const AjantaApp());
}

class AjantaApp extends StatelessWidget {
  const AjantaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ajanta Saree Centre',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.black,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const LoginPage(),
    );
  }
}

// ==================== LOGIN ====================

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool customerLogin = false;

  final idController = TextEditingController();
  final pinController = TextEditingController();

  void login() {
    if (idController.text.trim().isEmpty ||
        pinController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter ID and PIN')),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => HomePage(customer: customerLogin),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                children: [
                  const Icon(
                    Icons.storefront,
                    size: 70,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'AJANTA SAREE CENTRE',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text('Satna (M.P.)'),
                  const SizedBox(height: 30),

                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('Admin'),
                        icon: Icon(Icons.admin_panel_settings),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('Customer'),
                        icon: Icon(Icons.person),
                      ),
                    ],
                    selected: {customerLogin},
                    onSelectionChanged: (value) {
                      setState(() {
                        customerLogin = value.first;
                      });
                    },
                  ),

                  const SizedBox(height: 20),

                  TextField(
                    controller: idController,
                    decoration: InputDecoration(
                      labelText:
                          customerLogin ? 'Customer ID' : 'Admin ID',
                      prefixIcon: const Icon(Icons.person_outline),
                    ),
                  ),

                  const SizedBox(height: 12),

                  TextField(
                    controller: pinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'PIN',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: login,
                      child: const Padding(
                        padding: EdgeInsets.all(14),
                        child: Text(
                          'LOGIN',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    customerLogin
                        ? 'Customer access uses Customer ID + PIN.'
                        : 'Admin access for shop owners.',
                    style: const TextStyle(fontSize: 12),
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

// ==================== HOME ====================

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
            label: 'More',
          ),
        ],
      ),
    );
  }
}

// ==================== DASHBOARD ====================

class DashboardPage extends StatelessWidget {
  final bool customer;

  const DashboardPage({
    super.key,
    required this.customer,
  });

  Widget dashboardCard(String title, String value, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 25),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 5),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (customer) {
      return SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'MY ACCOUNT',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Text('Ajanta Saree Centre'),
            const SizedBox(height: 20),

            dashboardCard(
              'Outstanding',
              '₹0',
              Icons.account_balance_wallet_outlined,
            ),

            dashboardCard(
              'Total Purchases',
              '₹0',
              Icons.shopping_bag_outlined,
            ),

            dashboardCard(
              'Total Paid',
              '₹0',
              Icons.payments_outlined,
            ),

            const SizedBox(height: 10),

            const Card(
              child: ListTile(
                leading: Icon(Icons.receipt_long),
                title: Text('Purchase History'),
                subtitle: Text('Your previous bills will appear here.'),
              ),
            ),

            const Card(
              child: ListTile(
                leading: Icon(Icons.payment),
                title: Text('Payment History'),
                subtitle: Text('Your payments will appear here.'),
              ),
            ),

            const Card(
              child: ListTile(
                leading: Icon(Icons.description_outlined),
                title: Text('Account Statement'),
                subtitle: Text('View or share your statement.'),
              ),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'AJANTA SAREE CENTRE',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Text('Satna (M.P.)'),
          const SizedBox(height: 20),

          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.55,
            children: [
              dashboardCard(
                "Today's Sales",
                '₹0',
                Icons.receipt_long,
              ),
              dashboardCard(
                "Today's Purchases",
                '₹0',
                Icons.shopping_cart,
              ),
              dashboardCard(
                'Customer Due',
                '₹0',
                Icons.people,
              ),
              dashboardCard(
                'Trader Due',
                '₹0',
                Icons.store,
              ),
            ],
          ),

          const SizedBox(height: 15),

          const Card(
            child: ListTile(
              leading: Icon(Icons.warning_amber_outlined),
              title: Text('Low Stock'),
              subtitle: Text(
                'Low-stock products will appear here.',
              ),
            ),
          ),

          const SizedBox(height: 15),

          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sales Overview',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 30),
                  Center(
                    child: Text(
                      'Charts will appear as transactions are recorded.',
                    ),
                  ),
                  SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== SALES ====================

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final itemController = TextEditingController();
  final quantityController = TextEditingController(text: '1');
  final priceController = TextEditingController();

  String priceType = 'A';

  double get total {
    final quantity =
        double.tryParse(quantityController.text) ?? 0;
    final price =
        double.tryParse(priceController.text) ?? 0;

    return quantity * price;
  }

  Future<void> saveSale() async {
    if (itemController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter item name')),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    final count = prefs.getInt('sales_count') ?? 0;

    await prefs.setInt(
      'sales_count',
      count + 1,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sale saved successfully'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'NEW SALE',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 18),

          TextField(
            controller: itemController,
            decoration: const InputDecoration(
              labelText: 'Saree / Item',
              prefixIcon: Icon(Icons.inventory_2_outlined),
            ),
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: quantityController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantity',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: TextField(
                  controller: priceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Price ₹',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),

          const SizedBox(height: 15),

          const Text(
            'Price Type',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 8),

          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'A',
                label: Text('A'),
              ),
              ButtonSegment(
                value: 'B',
                label: Text('B'),
              ),
              ButtonSegment(
                value: 'C',
                label: Text('C'),
              ),
            ],
            selected: {priceType},
            onSelectionChanged: (value) {
              setState(() {
                priceType = value.first;
              });
            },
          ),

          const SizedBox(height: 18),

          Card(
            child: ListTile(
              title: const Text('Line Total'),
              trailing: Text(
                '₹${total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          FilledButton.icon(
            onPressed: saveSale,
            icon: const Icon(Icons.save),
            label: const Text('SAVE BILL'),
          ),

          const SizedBox(height: 8),

          OutlinedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('PDF generation will be added next.'),
                ),
              );
            },
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('SAVE & SHARE PDF'),
          ),
        ],
      ),
    );
  }
}

// ==================== INVENTORY ====================

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final nameController = TextEditingController();
  final price1Controller = TextEditingController();
  final price2Controller = TextEditingController();
  final price3Controller = TextEditingController();
  final stockController = TextEditingController(text: '0');

  Future<void> saveItem() async {
    if (nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter saree name/code'),
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    final count =
        prefs.getInt('product_count') ?? 0;

    await prefs.setInt(
      'product_count',
      count + 1,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Saree saved successfully'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'INVENTORY',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 15),

          TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Saree Name / Unique Code',
            ),
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: price1Controller,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Price 1 (A)',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: price2Controller,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Price 2 (B)',
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: price3Controller,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Price 3 (C)',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: stockController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Stock',
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 15),

          FilledButton.icon(
            onPressed: saveItem,
            icon: const Icon(Icons.add),
            label: const Text('ADD / SAVE ITEM'),
          ),

          const SizedBox(height: 20),

          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Inventory'),
              subtitle: Text(
                'Sales and purchases will automatically update stock in the completed database layer.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== ACCOUNTS ====================

class Accounts
