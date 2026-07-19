import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'firebase_options.dart';
import 'models.dart';
import 'notification_inbox_page.dart';
import 'pricing_settings_screen.dart';

const List<_FeatureDefinition> _systemFeatures = [
  _FeatureDefinition('dashboard', 'Dashboard', 'View business overview'),
  _FeatureDefinition('pos', 'POS', 'Sell products and complete checkout'),
  _FeatureDefinition('inventory', 'Inventory', 'View product stock'),
  _FeatureDefinition('add_product', 'Add Product', 'Create new products'),
  _FeatureDefinition('purchase_stock', 'Purchase Stock', 'Restock products'),
  _FeatureDefinition('expenses', 'Expenses', 'Manage business expenses'),
  _FeatureDefinition(
    'approve_expenses',
    'Approve Expenses',
    'Validate and approve business expenses',
  ),
  _FeatureDefinition('purchases', 'Purchases', 'Manage supplier purchases'),
  _FeatureDefinition(
    'manage_purchase_orders',
    'Manage Purchase Orders',
    'Create and update purchase orders',
  ),
  _FeatureDefinition(
    'approve_purchases',
    'Approve Purchases',
    'Approve supplier purchase orders',
  ),
  _FeatureDefinition(
    'receive_goods',
    'Receive Goods',
    'Receive purchases and update inventory',
  ),
  _FeatureDefinition(
    'verify_purchase_invoices',
    'Verify Purchase Invoices',
    'Validate supplier invoices',
  ),
  _FeatureDefinition(
    'branch_purchase_reports',
    'Branch Purchase Reports',
    'View purchase reporting across branches',
  ),
  _FeatureDefinition('sales_management', 'Sales', 'Manage sales records'),
  _FeatureDefinition(
    'online_sales',
    'Online Sales',
    'Manage marketplace orders and shipment tracking',
  ),
  _FeatureDefinition(
    'manage_sales_transactions',
    'Manage Sales Transactions',
    'Edit sales, returns, delivery, and payment status',
  ),
  _FeatureDefinition(
    'manage_discounts',
    'Discount Management',
    'Create and manage sales discounts',
  ),
  _FeatureDefinition(
    'manage_price_groups',
    'Price Group Management',
    'Create and manage price groups',
  ),
  _FeatureDefinition(
    'branch_sales_monitoring',
    'Branch Sales Monitoring',
    'View sales across business branches',
  ),
  _FeatureDefinition('reports', 'Reports', 'View reports and analytics'),
  _FeatureDefinition(
    'business_management',
    'Business Management',
    'Accounting, employees, assets, accounts and stock transfers',
  ),
  _FeatureDefinition('settings', 'Settings', 'Open administration settings'),
  _FeatureDefinition(
    'user_management',
    'User Management',
    'Add and edit staff',
  ),
  _FeatureDefinition(
    'role_management',
    'Role Management',
    'Create roles and permissions',
  ),
  _FeatureDefinition(
    'branch_management',
    'Branch Management',
    'Manage business locations',
  ),
];

class SettingsScreen extends StatefulWidget {
  final User user;
  final VoidCallback? onOpenMenu;
  final bool showLogout;
  const SettingsScreen({
    super.key,
    required this.user,
    this.onOpenMenu,
    this.showLogout = true,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final String _businessId;

  @override
  void initState() {
    super.initState();
    _businessId = _businessIdFor(widget.user);
    _seedAdministrationData();
  }

  Future<void> _seedAdministrationData() async {
    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();

    for (final feature in _systemFeatures) {
      batch.set(
        firestore.collection('features').doc(feature.id),
        feature.toMap(),
        SetOptions(merge: true),
      );
    }

    final ownerRole = _roleDocument(_businessId, UserRole.superAdmin);
    batch.set(ownerRole, {
      'roleId': UserRole.superAdmin,
      'displayName': 'Business Owner',
      'businessId': _businessId,
      'permissions': {for (final feature in _systemFeatures) feature.id: true},
      'isSystemRole': true,
    }, SetOptions(merge: true));

    final cashierRole = _roleDocument(_businessId, UserRole.cashier);
    batch.set(cashierRole, {
      'roleId': UserRole.cashier,
      'displayName': 'Cashier',
      'businessId': _businessId,
      'permissions': {
        'dashboard': true,
        'pos': true,
        'inventory': false,
        'add_product': false,
        'purchase_stock': false,
        'expenses': false,
        'approve_expenses': false,
        'purchases': false,
        'manage_purchase_orders': false,
        'approve_purchases': false,
        'receive_goods': false,
        'verify_purchase_invoices': false,
        'branch_purchase_reports': false,
        'sales_management': false,
        'online_sales': false,
        'manage_sales_transactions': false,
        'manage_discounts': false,
        'manage_price_groups': false,
        'branch_sales_monitoring': false,
        'reports': false,
        'settings': false,
        'user_management': false,
        'role_management': false,
        'branch_management': false,
      },
      'isSystemRole': true,
    }, SetOptions(merge: true));

    batch.set(_roleDocument(_businessId, UserRole.deliveryBoy), {
      'roleId': UserRole.deliveryBoy,
      'displayName': 'Delivery Boy',
      'businessId': _businessId,
      'permissions': {for (final feature in _systemFeatures) feature.id: false},
      'isSystemRole': true,
    }, SetOptions(merge: true));

    await batch.commit();
  }

  bool _isOwner() => widget.user.role == UserRole.superAdmin;

  @override
  Widget build(BuildContext context) {
    final isOwner = _isOwner();

    return Scaffold(
      appBar: AppBar(
        leading: widget.onOpenMenu == null
            ? null
            : IconButton(
                tooltip: 'Menu',
                onPressed: widget.onOpenMenu,
                icon: const Icon(Icons.menu),
              ),
        title: const Text('Settings & Administration'),
        actions: [NotificationBellButton(user: widget.user)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          ListTile(
            leading: const Icon(Icons.business),
            title: const Text('Business Scope'),
            subtitle: Text('Business ID: $_businessId'),
          ),
          _SubscriptionCountdownCard(businessId: _businessId),
          const Divider(),
          if (isOwner)
            _SettingsTile(
              icon: Icons.payments,
              title: 'Online Payment & Business',
              subtitle: 'Set business name, Lipa number, and payment policy',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      OnlineBusinessSettingsPage(businessId: _businessId),
                ),
              ),
            ),
          if (isOwner)
            _SettingsTile(
              icon: Icons.people,
              title: 'User Management',
              subtitle: 'Add staff, assign roles, and assign locations',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserManagementPage(
                    currentUser: widget.user,
                    businessId: _businessId,
                  ),
                ),
              ),
            ),
          if (isOwner)
            _SettingsTile(
              icon: Icons.category,
              title: 'Product Categories',
              subtitle: 'Create categories used by products and rules',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      CategoryManagementPage(businessId: _businessId),
                ),
              ),
            ),
          if (isOwner)
            _SettingsTile(
              icon: Icons.local_offer,
              title: 'Price Groups',
              subtitle: 'Create discounts, offers, and price increases',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      PriceGroupManagementPage(businessId: _businessId),
                ),
              ),
            ),
          if (isOwner)
            _SettingsTile(
              icon: Icons.receipt,
              title: 'Tax Management',
              subtitle: 'Apply tax by category, product, or price group',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      TaxManagementPage(businessId: _businessId),
                ),
              ),
            ),
          if (isOwner)
            _SettingsTile(
              icon: Icons.security,
              title: 'Role & Feature Management',
              subtitle: 'Create roles and choose accessible features',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      RoleManagementPage(businessId: _businessId),
                ),
              ),
            ),
          if (isOwner)
            _SettingsTile(
              icon: Icons.store,
              title: 'Branch Management',
              subtitle: 'Create and manage business locations',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      BranchManagementPage(businessId: _businessId),
                ),
              ),
            ),
          if (widget.showLogout) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout', style: TextStyle(color: Colors.red)),
              onTap: () async {
                await auth.FirebaseAuth.instance.signOut();
                if (!context.mounted) return;
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
            ),
          ],
        ],
      ),
    );
  }
}

class OnlineBusinessSettingsPage extends StatefulWidget {
  final String businessId;
  const OnlineBusinessSettingsPage({super.key, required this.businessId});

  @override
  State<OnlineBusinessSettingsPage> createState() =>
      _OnlineBusinessSettingsPageState();
}

class _OnlineBusinessSettingsPageState
    extends State<OnlineBusinessSettingsPage> {
  final _businessName = TextEditingController();
  final _lipaNumber = TextEditingController();
  final _partialPercent = TextEditingController(text: '50');
  final _shippingFee = TextEditingController(text: '0');
  String _paymentTiming = 'before_order';
  String _paymentAmount = 'full';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    FirebaseFirestore.instance
        .collection('businesses')
        .doc(widget.businessId)
        .get()
        .then((doc) {
          final data = doc.data() ?? const <String, dynamic>{};
          _businessName.text = data['name'] as String? ?? '';
          _lipaNumber.text = data['lipaNumber'] as String? ?? '';
          _paymentTiming =
              data['onlinePaymentTiming'] as String? ?? 'before_order';
          _paymentAmount = data['onlinePaymentAmount'] as String? ?? 'full';
          _partialPercent.text =
              '${(data['onlinePartialPercent'] as num?) ?? 50}';
          _shippingFee.text = '${(data['shippingFee'] as num?) ?? 0}';
          if (mounted) setState(() => _loading = false);
        });
  }

  @override
  void dispose() {
    _businessName.dispose();
    _lipaNumber.dispose();
    _partialPercent.dispose();
    _shippingFee.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_businessName.text.trim().isEmpty || _lipaNumber.text.trim().isEmpty) {
      return;
    }
    setState(() => _loading = true);
    await FirebaseFirestore.instance
        .collection('businesses')
        .doc(widget.businessId)
        .set({
          'id': widget.businessId,
          'name': _businessName.text.trim(),
          'lipaNumber': _lipaNumber.text.trim(),
          'onlinePaymentTiming': _paymentTiming,
          'onlinePaymentAmount': _paymentAmount,
          'onlinePartialPercent':
              double.tryParse(_partialPercent.text.trim()) ?? 50,
          'shippingFee': double.tryParse(_shippingFee.text.trim()) ?? 0,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
    if (mounted) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Online business settings saved.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Online Payment & Business')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextField(
                controller: _businessName,
                decoration: const InputDecoration(labelText: 'Business name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _lipaNumber,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Lipa number'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _shippingFee,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Shipping fee (optional)',
                  prefixText: 'Tsh ',
                  helperText: 'Use 0 for free shipping',
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Customer payment timing',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              RadioListTile(
                value: 'before_order',
                groupValue: _paymentTiming,
                onChanged: (v) => setState(() => _paymentTiming = v!),
                title: const Text('Before order is placed'),
              ),
              RadioListTile(
                value: 'on_delivery',
                groupValue: _paymentTiming,
                onChanged: (v) => setState(() => _paymentTiming = v!),
                title: const Text('On delivery'),
              ),
              Text(
                'Required payment amount',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              RadioListTile(
                value: 'full',
                groupValue: _paymentAmount,
                onChanged: (v) => setState(() => _paymentAmount = v!),
                title: const Text('Full payment'),
              ),
              RadioListTile(
                value: 'partial',
                groupValue: _paymentAmount,
                onChanged: (v) => setState(() => _paymentAmount = v!),
                title: const Text('Partial payment'),
              ),
              if (_paymentAmount == 'partial') ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _partialPercent,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Partial payment percentage',
                    suffixText: '%',
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save),
                label: const Text('Save settings'),
              ),
            ],
          ),
  );
}

class UserManagementPage extends StatelessWidget {
  final User currentUser;
  final String businessId;

  const UserManagementPage({
    super.key,
    required this.currentUser,
    required this.businessId,
  });

  Stream<List<_RoleRecord>> _rolesStream() {
    return FirebaseFirestore.instance.collection('roles').snapshots().map((
      snapshot,
    ) {
      return snapshot.docs
          .map((doc) => _RoleRecord.fromDoc(doc))
          .where((role) => role.businessId == businessId)
          .toList()
        ..sort((a, b) => a.displayName.compareTo(b.displayName));
    });
  }

  Stream<List<Branch>> _branchesStream() {
    return FirebaseFirestore.instance.collection('branches').snapshots().map((
      snapshot,
    ) {
      return snapshot.docs
          .map((doc) => Branch.fromMap({'id': doc.id, ...doc.data()}))
          .where((branch) => (branch.businessId ?? businessId) == businessId)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    });
  }

  Stream<List<User>> _usersStream() {
    return FirebaseFirestore.instance.collection('users').snapshots().map((
      snapshot,
    ) {
      return snapshot.docs
          .map((doc) => User.fromMap({'id': doc.id, ...doc.data()}))
          .where((user) => _businessIdFor(user) == businessId)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    });
  }

  void _openAddUser(
    BuildContext context,
    List<_RoleRecord> roles,
    List<Branch> branches,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AddUserSheet(
        businessId: businessId,
        roles: roles,
        branches: branches,
      ),
    );
  }

  void _openEditUser(
    BuildContext context,
    User user,
    List<_RoleRecord> roles,
    List<Branch> branches,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _EditUserSheet(
        user: user,
        businessId: businessId,
        roles: roles,
        branches: branches,
      ),
    );
  }

  Future<void> _deleteUser(BuildContext context, User user) async {
    if (user.id == currentUser.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You cannot delete your own account.')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove user?'),
        content: Text(
          '${user.name} will immediately lose access to this application.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await FirebaseFirestore.instance.collection('users').doc(user.id).delete();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('User access removed.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<_RoleRecord>>(
      stream: _rolesStream(),
      builder: (context, roleSnapshot) {
        return StreamBuilder<List<Branch>>(
          stream: _branchesStream(),
          builder: (context, branchSnapshot) {
            final roles = roleSnapshot.data ?? [];
            final branches = branchSnapshot.data ?? [];

            return Scaffold(
              appBar: AppBar(title: const Text('User Management')),
              body: StreamBuilder<List<User>>(
                stream: _usersStream(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final users = snapshot.data!;
                  if (users.isEmpty) {
                    return const Center(
                      child: Text('No users in this business yet.'),
                    );
                  }

                  return ListView.separated(
                    itemCount: users.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final user = users[index];
                      final roleName = roles
                          .where((role) => role.roleId == user.role)
                          .map((role) => role.displayName)
                          .firstOrNull;
                      final branchName = branches
                          .where((branch) => branch.id == user.branchId)
                          .map((branch) => branch.name)
                          .firstOrNull;

                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            user.name.isEmpty
                                ? '?'
                                : user.name[0].toUpperCase(),
                          ),
                        ),
                        title: Text(user.name),
                        subtitle: Text(
                          '${roleName ?? user.role} | ${branchName ?? 'All branches'}',
                        ),
                        trailing: Wrap(
                          spacing: 2,
                          children: [
                            IconButton(
                              tooltip: 'Edit user',
                              icon: const Icon(Icons.edit),
                              onPressed: () =>
                                  _openEditUser(context, user, roles, branches),
                            ),
                            IconButton(
                              tooltip: 'Remove user',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: user.id == currentUser.id
                                  ? null
                                  : () => _deleteUser(context, user),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
              floatingActionButton: FloatingActionButton.extended(
                onPressed: roles.isEmpty
                    ? null
                    : () => _openAddUser(context, roles, branches),
                icon: const Icon(Icons.person_add),
                label: const Text('Add User'),
              ),
            );
          },
        );
      },
    );
  }
}

class RoleManagementPage extends StatefulWidget {
  final String businessId;
  const RoleManagementPage({super.key, required this.businessId});

  @override
  State<RoleManagementPage> createState() => _RoleManagementPageState();
}

class _RoleManagementPageState extends State<RoleManagementPage> {
  Stream<List<_RoleRecord>> _rolesStream() {
    return FirebaseFirestore.instance.collection('roles').snapshots().map((
      snapshot,
    ) {
      return snapshot.docs
          .map((doc) => _RoleRecord.fromDoc(doc))
          .where((role) => role.businessId == widget.businessId)
          .toList()
        ..sort((a, b) => a.displayName.compareTo(b.displayName));
    });
  }

  Future<void> _openRoleSheet({_RoleRecord? role}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _RoleEditorSheet(businessId: widget.businessId, role: role),
    );
  }

  Future<void> _deleteRole(_RoleRecord role) async {
    if (role.isSystemRole) return;
    await FirebaseFirestore.instance
        .collection('roles')
        .doc(role.docId)
        .delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Role & Feature Management')),
      body: StreamBuilder<List<_RoleRecord>>(
        stream: _rolesStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final roles = snapshot.data!;
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: roles.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final role = roles[index];
              final enabledCount = _systemFeatures
                  .where((feature) => role.permissions[feature.id] == true)
                  .length;

              return ExpansionTile(
                leading: const Icon(Icons.security),
                title: Text(role.displayName),
                subtitle: Text(
                  '$enabledCount of ${_systemFeatures.length} features enabled',
                ),
                children: [
                  ..._systemFeatures.map((feature) {
                    final enabled = role.permissions[feature.id] == true;
                    return SwitchListTile(
                      title: Text(feature.name),
                      subtitle: Text(feature.description),
                      value: enabled,
                      onChanged: (value) async {
                        final updated = Map<String, bool>.from(
                          role.permissions,
                        );
                        updated[feature.id] = value;
                        for (final operation in const [
                          'create',
                          'read',
                          'update',
                          'delete',
                        ]) {
                          updated['${feature.id}.$operation'] = value;
                        }
                        await FirebaseFirestore.instance
                            .collection('roles')
                            .doc(role.docId)
                            .update({'permissions': updated});
                      },
                    );
                  }),
                  OverflowBar(
                    alignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => _openRoleSheet(role: role),
                        icon: const Icon(Icons.edit),
                        label: const Text('Edit Role'),
                      ),
                      if (!role.isSystemRole)
                        TextButton.icon(
                          onPressed: () => _deleteRole(role),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete'),
                        ),
                    ],
                  ),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openRoleSheet,
        icon: const Icon(Icons.add_moderator),
        label: const Text('New Role'),
      ),
    );
  }
}

class BranchManagementPage extends StatelessWidget {
  final String businessId;
  const BranchManagementPage({super.key, required this.businessId});

  Stream<List<Branch>> _branchesStream() {
    return FirebaseFirestore.instance.collection('branches').snapshots().map((
      snapshot,
    ) {
      return snapshot.docs
          .map((doc) => Branch.fromMap({'id': doc.id, ...doc.data()}))
          .where((branch) => (branch.businessId ?? businessId) == businessId)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    });
  }

  void _openBranchSheet(BuildContext context, {Branch? branch}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _BranchEditorSheet(businessId: businessId, branch: branch),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Branch Management')),
      body: StreamBuilder<List<Branch>>(
        stream: _branchesStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final branches = snapshot.data!;
          if (branches.isEmpty) {
            return const Center(child: Text('No branches yet.'));
          }

          return ListView.separated(
            itemCount: branches.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final branch = branches[index];
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.store)),
                title: Text(branch.name),
                subtitle: Text(
                  branch.address.isEmpty ? 'No address' : branch.address,
                ),
                trailing: IconButton(
                  tooltip: 'Edit branch',
                  icon: const Icon(Icons.edit),
                  onPressed: () => _openBranchSheet(context, branch: branch),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openBranchSheet(context),
        icon: const Icon(Icons.add_business),
        label: const Text('Add Branch'),
      ),
    );
  }
}

class _AddUserSheet extends StatefulWidget {
  final String businessId;
  final List<_RoleRecord> roles;
  final List<Branch> branches;

  const _AddUserSheet({
    required this.businessId,
    required this.roles,
    required this.branches,
  });

  @override
  State<_AddUserSheet> createState() => _AddUserSheetState();
}

class _AddUserSheetState extends State<_AddUserSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  late String _selectedRole;
  String? _selectedBranch;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedRole = widget.roles.any((role) => role.roleId == UserRole.cashier)
        ? UserRole.cashier
        : widget.roles.first.roleId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _saveUser() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    FirebaseApp? secondaryApp;
    try {
      secondaryApp = await Firebase.initializeApp(
        name: 'staff_creation_${DateTime.now().microsecondsSinceEpoch}',
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final secondaryAuth = auth.FirebaseAuth.instanceFor(app: secondaryApp);
      final credential = await secondaryAuth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final newUser = User(
        id: credential.user!.uid,
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        role: _selectedRole,
        branchId: _selectedBranch,
        businessId: widget.businessId,
      );

      await FirebaseFirestore.instance.collection('users').doc(newUser.id).set({
        ...newUser.toMap(),
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await secondaryAuth.signOut();

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User added to this business.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not add user: $e')));
    } finally {
      await secondaryApp?.delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: 'Add User',
      isSaving: _isSaving,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _textField(_nameController, 'Full name'),
            const SizedBox(height: 12),
            _textField(
              _emailController,
              'Email',
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            _textField(
              _passwordController,
              'Temporary password',
              obscureText: true,
            ),
            const SizedBox(height: 12),
            _roleDropdown(),
            const SizedBox(height: 12),
            _branchDropdown(),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _saveUser,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_add),
                label: Text(_isSaving ? 'Saving...' : 'Add User'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roleDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedRole,
      decoration: const InputDecoration(
        labelText: 'Role',
        border: OutlineInputBorder(),
      ),
      items: widget.roles
          .map(
            (role) => DropdownMenuItem(
              value: role.roleId,
              child: Text(role.displayName),
            ),
          )
          .toList(),
      onChanged: _isSaving
          ? null
          : (value) => setState(() => _selectedRole = value!),
    );
  }

  Widget _branchDropdown() {
    return DropdownButtonFormField<String?>(
      initialValue: _selectedBranch,
      decoration: const InputDecoration(
        labelText: 'Business location',
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('All branches')),
        ...widget.branches.map((branch) {
          return DropdownMenuItem(value: branch.id, child: Text(branch.name));
        }),
      ],
      onChanged: _isSaving
          ? null
          : (value) => setState(() => _selectedBranch = value),
    );
  }
}

class _EditUserSheet extends StatefulWidget {
  final User user;
  final String businessId;
  final List<_RoleRecord> roles;
  final List<Branch> branches;

  const _EditUserSheet({
    required this.user,
    required this.businessId,
    required this.roles,
    required this.branches,
  });

  @override
  State<_EditUserSheet> createState() => _EditUserSheetState();
}

class _EditUserSheetState extends State<_EditUserSheet> {
  late String _selectedRole;
  String? _selectedBranch;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedRole = widget.user.role;
    _selectedBranch = widget.user.branchId;
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user.id)
        .update({
          'role': _selectedRole,
          'branchId': _selectedBranch,
          'businessId': widget.businessId,
          'updatedAt': FieldValue.serverTimestamp(),
        });

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: 'Edit User',
      isSaving: _isSaving,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(widget.user.name),
            subtitle: Text(widget.user.email),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue:
                widget.roles.any((role) => role.roleId == _selectedRole)
                ? _selectedRole
                : widget.roles.first.roleId,
            decoration: const InputDecoration(
              labelText: 'Role',
              border: OutlineInputBorder(),
            ),
            items: widget.roles
                .map(
                  (role) => DropdownMenuItem(
                    value: role.roleId,
                    child: Text(role.displayName),
                  ),
                )
                .toList(),
            onChanged: _isSaving
                ? null
                : (value) => setState(() => _selectedRole = value!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _selectedBranch,
            decoration: const InputDecoration(
              labelText: 'Business location',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('All branches')),
              ...widget.branches.map((branch) {
                return DropdownMenuItem(
                  value: branch.id,
                  child: Text(branch.name),
                );
              }),
            ],
            onChanged: _isSaving
                ? null
                : (value) => setState(() => _selectedBranch = value),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: const Icon(Icons.save),
              label: const Text('Save Changes'),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleEditorSheet extends StatefulWidget {
  final String businessId;
  final _RoleRecord? role;

  const _RoleEditorSheet({required this.businessId, this.role});

  @override
  State<_RoleEditorSheet> createState() => _RoleEditorSheetState();
}

class _RoleEditorSheetState extends State<_RoleEditorSheet> {
  final _nameController = TextEditingController();
  late Map<String, bool> _permissions;
  late Map<String, Map<String, bool>> _crudPermissions;
  bool _isSaving = false;
  static const _operations = ['create', 'read', 'update', 'delete'];

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.role?.displayName ?? '';
    _permissions = {
      for (final feature in _systemFeatures)
        feature.id: widget.role?.permissions[feature.id] ?? false,
    };
    _crudPermissions = {
      for (final feature in _systemFeatures)
        feature.id: {
          for (final operation in _operations)
            operation:
                widget.role?.permissions['${feature.id}.$operation'] ??
                widget.role?.permissions[feature.id] ??
                false,
        },
    };
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isSaving = true);
    final firestore = FirebaseFirestore.instance;
    final roleId = widget.role?.roleId ?? _slug(name);
    final docId = widget.role?.docId ?? _roleDocId(widget.businessId, roleId);

    for (final feature in _systemFeatures) {
      final access = _crudPermissions[feature.id]!;
      _permissions[feature.id] = access.values.any((allowed) => allowed);
      for (final operation in _operations) {
        _permissions['${feature.id}.$operation'] = access[operation] == true;
      }
    }

    await firestore.collection('roles').doc(docId).set({
      'roleId': roleId,
      'displayName': name,
      'businessId': widget.businessId,
      'permissions': _permissions,
      'isSystemRole': widget.role?.isSystemRole ?? false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<_FeatureDefinition>>{};
    for (final feature in _systemFeatures) {
      groups.putIfAbsent(_featureGroup(feature.id), () => []).add(feature);
    }
    return _SheetScaffold(
      title: widget.role == null ? 'Create Role' : 'Edit Role',
      isSaving: _isSaving,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Role name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Feature access by CRUD operation',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          ...groups.entries.map(
            (group) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ExpansionTile(
                initiallyExpanded: group.key == 'Sales & Orders',
                leading: Icon(_featureGroupIcon(group.key)),
                title: Text(group.key),
                subtitle: Text('${group.value.length} features'),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _operations.map((operation) {
                        final allAllowed = group.value.every(
                          (feature) =>
                              _crudPermissions[feature.id]![operation] == true,
                        );
                        return FilterChip(
                          selected: allAllowed,
                          label: Text('All ${_operationLabel(operation)}'),
                          onSelected: _isSaving
                              ? null
                              : (value) => setState(() {
                                  for (final feature in group.value) {
                                    _crudPermissions[feature.id]![operation] =
                                        value;
                                  }
                                }),
                        );
                      }).toList(),
                    ),
                  ),
                  const Divider(height: 1),
                  ...group.value.map(
                    (feature) => Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            feature.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            feature.description,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            children: _operations.map((operation) {
                              return FilterChip(
                                selected:
                                    _crudPermissions[feature.id]![operation] ==
                                    true,
                                label: Text(_operationLabel(operation)),
                                onSelected: _isSaving
                                    ? null
                                    : (value) => setState(
                                        () =>
                                            _crudPermissions[feature
                                                    .id]![operation] =
                                                value,
                                      ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: const Icon(Icons.save),
              label: const Text('Save Role'),
            ),
          ),
        ],
      ),
    );
  }
}

class _BranchEditorSheet extends StatefulWidget {
  final String businessId;
  final Branch? branch;

  const _BranchEditorSheet({required this.businessId, this.branch});

  @override
  State<_BranchEditorSheet> createState() => _BranchEditorSheetState();
}

class _BranchEditorSheetState extends State<_BranchEditorSheet> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isSaving = false;
  GeoPoint? _location;

  Future<void> _pinGps() async {
    if (!await Geolocator.isLocationServiceEnabled()) return;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      return;
    }
    final position = await Geolocator.getCurrentPosition();
    if (mounted) {
      setState(
        () => _location = GeoPoint(position.latitude, position.longitude),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.branch?.name ?? '';
    _addressController.text = widget.branch?.address ?? '';
    _phoneController.text = widget.branch?.phone ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isSaving = true);
    final firestore = FirebaseFirestore.instance;
    final ref = widget.branch == null
        ? firestore.collection('branches').doc()
        : firestore.collection('branches').doc(widget.branch!.id);

    await ref.set({
      'id': ref.id,
      'businessId': widget.businessId,
      'name': name,
      'address': _addressController.text.trim(),
      'phone': _phoneController.text.trim(),
      'managerId': widget.branch?.managerId ?? '',
      if (_location != null) 'location': _location,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: widget.branch == null ? 'Add Branch' : 'Edit Branch',
      isSaving: _isSaving,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _textField(_nameController, 'Branch name'),
          const SizedBox(height: 12),
          _textField(_addressController, 'Address', required: false),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _isSaving ? null : _pinGps,
              icon: const Icon(Icons.pin_drop),
              label: Text(
                _location == null
                    ? 'Pin optional GPS location'
                    : 'GPS location pinned',
              ),
            ),
          ),
          const SizedBox(height: 12),
          _textField(_phoneController, 'Phone', required: false),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: const Icon(Icons.save),
              label: const Text('Save Branch'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionCountdownCard extends StatelessWidget {
  final String businessId;
  const _SubscriptionCountdownCard({required this.businessId});
  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('businesses')
            .doc(businessId)
            .snapshots(),
        builder: (context, snapshot) {
          final value = snapshot.data?.data()?['subscriptionExpiresAt'];
          if (value is! Timestamp) return const SizedBox.shrink();
          final expiry = value.toDate();
          final days = expiry.difference(DateTime.now()).inDays + 1;
          return Card(
            child: ListTile(
              leading: Icon(
                days <= 7 ? Icons.warning_amber : Icons.event_available,
                color: days <= 7 ? Colors.orange : null,
              ),
              title: Text(
                days > 0
                    ? '$days subscription days remaining'
                    : 'Subscription expired',
              ),
              subtitle: Text(
                'Expires ${expiry.day}/${expiry.month}/${expiry.year}',
              ),
            ),
          );
        },
      );
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _SheetScaffold extends StatelessWidget {
  final String title;
  final bool isSaving;
  final Widget child;

  const _SheetScaffold({
    required this.title,
    required this.isSaving,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: isSaving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureDefinition {
  final String id;
  final String name;
  final String description;

  const _FeatureDefinition(this.id, this.name, this.description);

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'description': description,
  };
}

String _operationLabel(String operation) => switch (operation) {
  'create' => 'Create',
  'read' => 'Read',
  'update' => 'Update',
  'delete' => 'Delete',
  _ => operation,
};

String _featureGroup(String featureId) {
  if ({
    'dashboard',
    'reports',
    'branch_purchase_reports',
    'branch_sales_monitoring',
  }.contains(featureId)) {
    return 'Dashboard & Reports';
  }
  if ({
    'pos',
    'sales_management',
    'online_sales',
    'manage_sales_transactions',
    'manage_discounts',
    'manage_price_groups',
  }.contains(featureId)) {
    return 'Sales & Orders';
  }
  if ({'inventory', 'add_product', 'purchase_stock'}.contains(featureId)) {
    return 'Products & Inventory';
  }
  if ({
    'purchases',
    'manage_purchase_orders',
    'approve_purchases',
    'receive_goods',
    'verify_purchase_invoices',
  }.contains(featureId)) {
    return 'Purchases & Suppliers';
  }
  if ({'expenses', 'approve_expenses'}.contains(featureId)) {
    return 'Expenses & Finance';
  }
  return 'Administration';
}

IconData _featureGroupIcon(String group) => switch (group) {
  'Dashboard & Reports' => Icons.analytics,
  'Sales & Orders' => Icons.shopping_bag,
  'Products & Inventory' => Icons.inventory_2,
  'Purchases & Suppliers' => Icons.local_shipping,
  'Expenses & Finance' => Icons.account_balance_wallet,
  _ => Icons.admin_panel_settings,
};

class _RoleRecord {
  final String docId;
  final String roleId;
  final String displayName;
  final String businessId;
  final Map<String, bool> permissions;
  final bool isSystemRole;

  const _RoleRecord({
    required this.docId,
    required this.roleId,
    required this.displayName,
    required this.businessId,
    required this.permissions,
    required this.isSystemRole,
  });

  factory _RoleRecord.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return _RoleRecord(
      docId: doc.id,
      roleId: data['roleId'] as String? ?? doc.id,
      displayName: data['displayName'] as String? ?? doc.id,
      businessId: data['businessId'] as String? ?? 'default_business',
      permissions: Map<String, bool>.from(data['permissions'] ?? {}),
      isSystemRole: data['isSystemRole'] == true,
    );
  }
}

Widget _textField(
  TextEditingController controller,
  String label, {
  bool obscureText = false,
  bool required = true,
  TextInputType? keyboardType,
}) {
  return TextFormField(
    controller: controller,
    obscureText: obscureText,
    keyboardType: keyboardType,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    validator: required
        ? (value) {
            if (value == null || value.trim().isEmpty) return 'Required';
            return null;
          }
        : null,
  );
}

String _businessIdFor(User user) => user.businessId ?? 'default_business';

String _slug(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

String _roleDocId(String businessId, String roleId) => '${businessId}_$roleId';

DocumentReference<Map<String, dynamic>> _roleDocument(
  String businessId,
  String roleId,
) {
  return FirebaseFirestore.instance
      .collection('roles')
      .doc(_roleDocId(businessId, roleId));
}
