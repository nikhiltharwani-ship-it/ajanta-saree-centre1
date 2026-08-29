import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SharedPreferences.getInstance();
  runApp(const AjantaApp());
}

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
      ),
      home: const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final id = TextEditingController();
  final pin = TextEditingController();
  bool customer = false;

  void login() {
    if (id.text.trim().isEmpty || pin.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter ID and PIN')),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => HomePage(customer: customer),
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
            child: Column(
              children: [
                const Icon(Icons.storefront, size: 70),
                const SizedBox(height: 15),
                const Text(
                  'AJANTA SAREE CENTRE',
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
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('Customer'),
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
                  controller: id,
                  decoration: InputDecoration(
                    labelText:
                        customer ? 'Customer ID' : 'Admin ID',
                  ),
                ),

                const SizedBox(height: 12),

                TextField(
                  controller: pin,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'PIN',
                  ),
                ),

                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: login,
                    child: const Text('LOGIN'),
                  ),
                ),

                const SizedBox(height: 12),

                const Text(
                  'No OTP authentication',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
  int index = 0;

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
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) {
          setState(() {
            index = value;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Sales',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            label: 'Stock',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
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
            customer ? 'MY ACCOUNT' : 'AJANTA SAREE CENTRE',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Text('Satna (M.P.)'),
          const SizedBox(height: 20),

          Card(
            child: ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text("Today's Sales"),
              trailing: const Text(
                '₹0',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          Card(
            child: ListTile(
              leading: const Icon(Icons.shopping_cart),
              title: const Text("Today's Purchases"),
              trailing: const Text(
                '₹0',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          Card(
            child: ListTile(
              leading: const Icon(Icons.people),
              title: const Text('Customer Due'),
              trailing: const Text(
                '₹0',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          Card(
            child: ListTile(
              leading: const Icon(Icons.store),
              title: const Text('Trader Due'),
              trailing: const Text(
                '₹0',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SalesPage extends StatelessWidget {
  const SalesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: Center(
        child: Text(
          'SALES\n\nInvoice module',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22),
        ),
      ),
    );
  }
}

class InventoryPage extends StatelessWidget {
  const InventoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: Center(
        child: Text(
          'INVENTORY\n\nSaree database\nPrice 1 (A)\nPrice 2 (B)\nPrice 3 (C)',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22),
        ),
      ),
    );
  }
}

class AccountsPage extends StatelessWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: Center(
        child: Text(
          'ACCOUNTS\n\nCustomers\nTraders / Suppliers\nPayments\nOutstanding',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22),
        ),
      ),
    );
  }
}

class MorePage extends StatelessWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: Center(
        child: Text(
          'MORE\n\nPurchases\nReturns\nCashbook\nReports\nBackup / Restore\nSettings',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22),
        ),
      ),
    );
  }
}
