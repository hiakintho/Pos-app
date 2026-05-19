import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'firebase_options.dart';
import 'login_page.dart';
import 'dashboard_screen.dart';
import 'pos_screen.dart';
import 'inventory_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'expenses_screen.dart';
import 'purchases_screen.dart';
import 'sales_management_screen.dart';
import 'models.dart';
import 'sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
  }

  // Start background sync
  SyncService().syncData();

  runApp(const RubenPOS());
}

class RubenPOS extends StatelessWidget {
  const RubenPOS({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'POS App',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 2),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  Future<User?> _loadUser(auth.User firebaseUser) async {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(firebaseUser.uid)
        .get();

    if (!userDoc.exists || userDoc.data() == null) return null;
    return User.fromMap({'id': firebaseUser.uid, ...userDoc.data()!});
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<auth.User?>(
      stream: auth.FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final firebaseUser = snapshot.data;
        if (firebaseUser == null) return const LoginPage();

        return FutureBuilder<User?>(
          future: _loadUser(firebaseUser),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final appUser = userSnapshot.data;
            if (appUser == null) {
              auth.FirebaseAuth.instance.signOut();
              return const LoginPage();
            }

            return MainNavigation(user: appUser);
          },
        );
      },
    );
  }
}

class MainNavigation extends StatefulWidget {
  final User user;
  const MainNavigation({super.key, required this.user});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  final GlobalKey<ScaffoldState> _shellKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = 0;

  Future<void> _logout() async {
    await auth.FirebaseAuth.instance.signOut();
  }

  void _openDrawer() {
    _shellKey.currentState?.openDrawer();
  }

  @override
  Widget build(BuildContext context) {
    bool isDesktop = MediaQuery.of(context).size.width > 900;

    return StreamBuilder<Map<String, bool>>(
      stream: _rolePermissionsStream(widget.user),
      builder: (context, snapshot) {
        final permissions = snapshot.data;
        final destinations = _navigationItems(permissions);
        final primaryDestinations = destinations
            .where((item) => item.showInPrimaryNavigation)
            .toList();

        if (_selectedIndex >= destinations.length) {
          _selectedIndex = 0;
        }

        if (destinations.isEmpty) {
          return const Scaffold(
            body: Center(child: Text('No features assigned to this role.')),
          );
        }

        return Scaffold(
          key: _shellKey,
          drawer: _AppDrawer(
            user: widget.user,
            selectedIndex: _selectedIndex,
            destinations: destinations,
            onDestinationSelected: (index) {
              Navigator.pop(context);
              setState(() => _selectedIndex = index);
            },
            onLogout: _logout,
          ),
          body: Row(
            children: [
              if (isDesktop)
                NavigationRail(
                  extended: true,
                  leading: const RubenLogo(fontSize: 24),
                  destinations: primaryDestinations
                      .map(
                        (item) => NavigationRailDestination(
                          icon: Icon(item.icon),
                          label: Text(item.label),
                        ),
                      )
                      .toList(),
                  selectedIndex: _primarySelectedIndex(
                    destinations,
                    primaryDestinations,
                  ),
                  onDestinationSelected: (index) {
                    final selected = primaryDestinations[index];
                    setState(
                      () => _selectedIndex = destinations.indexOf(selected),
                    );
                  },
                ),
              Expanded(child: destinations[_selectedIndex].screen),
            ],
          ),
          bottomNavigationBar: !isDesktop
              ? BottomNavigationBar(
                  currentIndex: _primarySelectedIndex(
                    destinations,
                    primaryDestinations,
                  ),
                  onTap: (index) {
                    final selected = primaryDestinations[index];
                    setState(
                      () => _selectedIndex = destinations.indexOf(selected),
                    );
                  },
                  type: BottomNavigationBarType.fixed,
                  items: primaryDestinations
                      .map(
                        (item) => BottomNavigationBarItem(
                          icon: Icon(item.icon),
                          label: item.label,
                        ),
                      )
                      .toList(),
                )
              : null,
        );
      },
    );
  }

  int _primarySelectedIndex(
    List<_NavigationItem> destinations,
    List<_NavigationItem> primaryDestinations,
  ) {
    final selected = destinations[_selectedIndex];
    final index = primaryDestinations.indexOf(selected);
    return index == -1 ? 0 : index;
  }

  Stream<Map<String, bool>> _rolePermissionsStream(User user) {
    final businessId = user.businessId ?? 'default_business';
    final docId = '${businessId}_${user.role}';
    return Stream.fromFuture(
          FirebaseFirestore.instance.collection('roles').doc(docId).get(),
        )
        .asyncExpand((initial) {
          if (initial.exists) {
            return FirebaseFirestore.instance
                .collection('roles')
                .doc(docId)
                .snapshots();
          }

          return FirebaseFirestore.instance
              .collection('roles')
              .doc(user.role)
              .snapshots();
        })
        .map((doc) {
          final data = doc.data();
          if (data == null) {
            return {
              'dashboard': true,
              'pos': true,
              'inventory': true,
              'expenses': user.role == UserRole.superAdmin,
              'purchases': user.role == UserRole.superAdmin,
              'sales_management': user.role == UserRole.superAdmin,
              'reports': true,
              'settings': user.role == UserRole.superAdmin,
            };
          }
          return Map<String, bool>.from(data['permissions'] ?? {});
        });
  }

  List<_NavigationItem> _navigationItems(Map<String, bool>? permissions) {
    bool can(String featureId) {
      if (widget.user.role == UserRole.superAdmin) return true;
      if (permissions == null) return true;
      return permissions[featureId] == true;
    }

    return [
      if (can('dashboard'))
        _NavigationItem(
          label: 'Dashboard',
          icon: Icons.dashboard,
          screen: DashboardScreen(user: widget.user, onOpenMenu: _openDrawer),
          showInPrimaryNavigation: true,
        ),
      if (can('pos'))
        _NavigationItem(
          label: 'POS',
          icon: Icons.shopping_cart,
          screen: POSScreen(user: widget.user, onOpenMenu: _openDrawer),
          showInPrimaryNavigation: true,
        ),
      if (can('inventory'))
        _NavigationItem(
          label: 'Inventory',
          icon: Icons.inventory,
          screen: InventoryScreen(user: widget.user, onOpenMenu: _openDrawer),
          showInPrimaryNavigation: true,
        ),
      if (can('expenses'))
        _NavigationItem(
          label: 'Expenses',
          icon: Icons.payments,
          screen: ExpensesScreen(user: widget.user, onOpenMenu: _openDrawer),
        ),
      if (can('purchases'))
        _NavigationItem(
          label: 'Purchases',
          icon: Icons.local_shipping,
          screen: PurchasesScreen(user: widget.user, onOpenMenu: _openDrawer),
        ),
      if (can('sales_management'))
        _NavigationItem(
          label: 'Sales',
          icon: Icons.receipt_long,
          screen: SalesManagementScreen(
            user: widget.user,
            onOpenMenu: _openDrawer,
          ),
        ),
      if (can('reports'))
        _NavigationItem(
          label: 'Reports',
          icon: Icons.bar_chart,
          screen: ReportsScreen(user: widget.user, onOpenMenu: _openDrawer),
          showInPrimaryNavigation: true,
        ),
      if (can('settings'))
        _NavigationItem(
          label: 'Settings',
          icon: Icons.settings,
          screen: SettingsScreen(user: widget.user, onOpenMenu: _openDrawer),
          showInPrimaryNavigation: true,
        ),
    ];
  }
}

class _AppDrawer extends StatelessWidget {
  final User user;
  final int selectedIndex;
  final List<_NavigationItem> destinations;
  final ValueChanged<int> onDestinationSelected;
  final Future<void> Function() onLogout;

  const _AppDrawer({
    required this.user,
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    child: Text(
                      user.name.isEmpty ? '?' : user.name[0].toUpperCase(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          user.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: destinations.length,
                itemBuilder: (context, index) {
                  final item = destinations[index];
                  return ListTile(
                    selected: index == selectedIndex,
                    leading: Icon(item.icon),
                    title: Text(item.label),
                    onTap: () => onDestinationSelected(index),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                await onLogout();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _NavigationItem {
  final String label;
  final IconData icon;
  final Widget screen;
  final bool showInPrimaryNavigation;

  const _NavigationItem({
    required this.label,
    required this.icon,
    required this.screen,
    this.showInPrimaryNavigation = false,
  });
}

class RubenLogo extends StatelessWidget {
  final double fontSize;
  const RubenLogo({super.key, this.fontSize = 32});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        colors: [Colors.indigo, Colors.blueAccent],
      ).createShader(bounds),
      child: Text(
        'POS APP',
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}
