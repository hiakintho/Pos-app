import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'customer_marketplace.dart';
import 'system_administration.dart';
import 'customer_support_page.dart';
import 'notification_inbox_page.dart';
import 'notification_service.dart';
import 'delivery_management_page.dart';

const Color _spotifyGreen = Color(0xFF1DB954);
const Color _spotifyBlack = Color(0xFF050505);
const Color _spotifyPanel = Color(0xFF121212);
const Color _spotifyElevated = Color(0xFF181818);
const Color _spotifyCard = Color(0xFF242424);
const Color _spotifyMutedText = Color(0xFFB3B3B3);

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
    final darkScheme = ColorScheme.fromSeed(
      seedColor: _spotifyGreen,
      brightness: Brightness.dark,
      primary: _spotifyGreen,
      surface: _spotifyPanel,
      surfaceContainerHighest: _spotifyCard,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'POS App',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: darkScheme,
        scaffoldBackgroundColor: _spotifyBlack,
        canvasColor: _spotifyBlack,
        cardTheme: const CardThemeData(
          color: _spotifyElevated,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          backgroundColor: _spotifyBlack,
          foregroundColor: Colors.white,
        ),
        drawerTheme: const DrawerThemeData(backgroundColor: _spotifyPanel),
        dividerTheme: const DividerThemeData(color: Color(0xFF2A2A2A)),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _spotifyGreen,
            foregroundColor: Colors.black,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _spotifyElevated,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF303030)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _spotifyGreen, width: 1.5),
          ),
        ),
        listTileTheme: const ListTileThemeData(
          iconColor: _spotifyMutedText,
          textColor: Colors.white,
          selectedColor: Colors.white,
          selectedTileColor: Color(0xFF2A2A2A),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: _spotifyPanel,
          indicatorColor: _spotifyGreen,
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: _spotifyPanel,
          selectedItemColor: _spotifyGreen,
          unselectedItemColor: _spotifyMutedText,
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
            NotificationService.register(appUser.id);

            if (appUser.role == UserRole.customer) {
              return CustomerMarketplace(customer: appUser);
            }
            if (appUser.role == UserRole.deliveryBoy) {
              return DeliveryOrdersPage(user: appUser);
            }
            if (appUser.role == UserRole.systemOwner) {
              return SystemOwnerPage(user: appUser);
            }
            if (appUser.role == UserRole.superAdmin) {
              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(appUser.id)
                    .snapshots(),
                builder: (context, approvalSnapshot) {
                  if (!approvalSnapshot.hasData) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final status =
                      approvalSnapshot.data!.data()?['accountStatus']
                          as String? ??
                      'approved';
                  if (status != 'approved') {
                    return BusinessApprovalPendingPage(status: status);
                  }
                  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('businesses')
                        .doc(appUser.businessId ?? 'default_business')
                        .snapshots(),
                    builder: (context, businessSnapshot) {
                      if (!businessSnapshot.hasData) {
                        return const Scaffold(
                          body: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final expiry = businessSnapshot.data!
                          .data()?['subscriptionExpiresAt'];
                      final expiryDate = expiry is Timestamp
                          ? expiry.toDate()
                          : null;
                      if (expiryDate != null &&
                          expiryDate.isBefore(DateTime.now())) {
                        return const BusinessApprovalPendingPage(
                          status: 'expired',
                        );
                      }
                      return MainNavigation(
                        key: ValueKey(
                          '${businessSnapshot.data!.data()?['allowedFeatures']}-${businessSnapshot.data!.data()?['subscriptionExpiresAt']}',
                        ),
                        user: appUser,
                      );
                    },
                  );
                },
              );
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
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _orderAlerts;
  Set<String>? _knownOrders;

  @override
  void initState() {
    super.initState();
    if (widget.user.role == UserRole.superAdmin) {
      final businessId = widget.user.businessId ?? 'default_business';
      _orderAlerts = FirebaseFirestore.instance
          .collection('customer_orders')
          .snapshots()
          .listen((snapshot) {
            final current = snapshot.docs
                .where(
                  (doc) => (doc.data()['shopIds'] as List? ?? const [])
                      .contains(businessId),
                )
                .map((doc) => doc.id)
                .toSet();
            if (_knownOrders != null &&
                current.difference(_knownOrders!).isNotEmpty) {
              SystemSound.play(SystemSoundType.alert);
              HapticFeedback.vibrate();
            }
            _knownOrders = current;
          });
    }
  }

  @override
  void dispose() {
    _orderAlerts?.cancel();
    super.dispose();
  }

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
                _DesktopSidebar(
                  user: widget.user,
                  selectedIndex: _selectedIndex,
                  destinations: destinations,
                  onDestinationSelected: (index) {
                    setState(() => _selectedIndex = index);
                  },
                  onLogout: _logout,
                ),
              Expanded(
                child: ColoredBox(
                  color: _spotifyBlack,
                  child: destinations[_selectedIndex].screen,
                ),
              ),
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
    final roleStream =
        Stream.fromFuture(
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
                  'online_sales': user.role == UserRole.superAdmin,
                  'reports': true,
                  'settings': user.role == UserRole.superAdmin,
                };
              }
              return Map<String, bool>.from(data['permissions'] ?? {});
            });
    return roleStream.asyncMap((permissions) async {
      final business = await FirebaseFirestore.instance
          .collection('businesses')
          .doc(businessId)
          .get();
      final allowed = (business.data()?['allowedFeatures'] as List?)
          ?.map((item) => item.toString())
          .toSet();
      if (allowed == null) return permissions;
      return {
        for (final entry in permissions.entries)
          entry.key:
              entry.value &&
              allowed.contains(_subscriptionParent(entry.key.split('.').first)),
      };
    });
  }

  List<_NavigationItem> _navigationItems(Map<String, bool>? permissions) {
    bool can(String featureId) {
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
      if (can('online_sales'))
        _NavigationItem(
          label: 'Online Sales',
          icon: Icons.shopping_bag_outlined,
          screen: CustomerOrderManagementPage(
            user: widget.user,
            onOpenMenu: _openDrawer,
          ),
          showInPrimaryNavigation: true,
        ),
      if (widget.user.role == UserRole.superAdmin)
        _NavigationItem(
          label: 'Delivery Team',
          icon: Icons.delivery_dining,
          screen: DeliveryBoyManagementPage(
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
      _NavigationItem(
        label: 'Support',
        icon: Icons.support_agent,
        screen: CustomerSupportPage(user: widget.user, onOpenMenu: _openDrawer),
      ),
      _NavigationItem(
        label: 'Notifications',
        icon: Icons.notifications_outlined,
        screen: NotificationInboxPage(user: widget.user),
      ),
    ];
  }
}

String _subscriptionParent(String featureId) => switch (featureId) {
  'add_product' || 'purchase_stock' => 'inventory',
  'approve_expenses' => 'expenses',
  'manage_purchase_orders' ||
  'approve_purchases' ||
  'receive_goods' ||
  'verify_purchase_invoices' ||
  'branch_purchase_reports' => 'purchases',
  'manage_sales_transactions' ||
  'manage_discounts' ||
  'manage_price_groups' ||
  'branch_sales_monitoring' => 'sales_management',
  'user_management' || 'role_management' || 'branch_management' => 'settings',
  _ => featureId,
};

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

class _DesktopSidebar extends StatelessWidget {
  final User user;
  final int selectedIndex;
  final List<_NavigationItem> destinations;
  final ValueChanged<int> onDestinationSelected;
  final Future<void> Function() onLogout;

  const _DesktopSidebar({
    required this.user,
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 264,
      color: _spotifyBlack,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 4, 12, 18),
            child: RubenLogo(fontSize: 24),
          ),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _spotifyPanel,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: destinations.length,
                separatorBuilder: (context, index) {
                  final current = destinations[index];
                  final next = destinations[index + 1];
                  if (current.showInPrimaryNavigation &&
                      !next.showInPrimaryNavigation) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Divider(height: 1),
                    );
                  }
                  return const SizedBox(height: 2);
                },
                itemBuilder: (context, index) {
                  final item = destinations[index];
                  final selected = index == selectedIndex;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: _SidebarTile(
                      item: item,
                      selected: selected,
                      onTap: () => onDestinationSelected(index),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: _spotifyPanel,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _spotifyGreen,
                    foregroundColor: Colors.black,
                    child: Text(
                      user.name.isEmpty ? '?' : user.name[0].toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          user.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          user.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: _spotifyMutedText),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Logout',
                    onPressed: onLogout,
                    icon: const Icon(Icons.logout),
                    color: _spotifyMutedText,
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

class _SidebarTile extends StatelessWidget {
  final _NavigationItem item;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF2A2A2A) : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(
                item.icon,
                size: 22,
                color: selected ? _spotifyGreen : _spotifyMutedText,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : _spotifyMutedText,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: fontSize + 2,
          height: fontSize + 2,
          decoration: const BoxDecoration(
            color: _spotifyGreen,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.point_of_sale, color: Colors.black, size: 18),
        ),
        const SizedBox(width: 10),
        Text(
          'POS APP',
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}
