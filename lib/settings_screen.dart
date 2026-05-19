import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'models.dart';
import 'pricing_settings_screen.dart';

const List<_FeatureDefinition> _systemFeatures = [
  _FeatureDefinition('dashboard', 'Dashboard', 'View business overview'),
  _FeatureDefinition('pos', 'POS', 'Sell products and complete checkout'),
  _FeatureDefinition('inventory', 'Inventory', 'View product stock'),
  _FeatureDefinition('add_product', 'Add Product', 'Create new products'),
  _FeatureDefinition('purchase_stock', 'Purchase Stock', 'Restock products'),
  _FeatureDefinition('expenses', 'Expenses', 'Manage business expenses'),
  _FeatureDefinition('purchases', 'Purchases', 'Manage supplier purchases'),
  _FeatureDefinition('sales_management', 'Sales', 'Manage sales records'),
  _FeatureDefinition('reports', 'Reports', 'View reports and analytics'),
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
  const SettingsScreen({super.key, required this.user, this.onOpenMenu});

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
        'purchases': false,
        'sales_management': false,
        'reports': false,
        'settings': false,
        'user_management': false,
        'role_management': false,
        'branch_management': false,
      },
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
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          ListTile(
            leading: const Icon(Icons.business),
            title: const Text('Business Scope'),
            subtitle: Text('Business ID: $_businessId'),
          ),
          const Divider(),
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
      ),
    );
  }
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
                        trailing: IconButton(
                          tooltip: 'Edit user',
                          icon: const Icon(Icons.edit),
                          onPressed: () =>
                              _openEditUser(context, user, roles, branches),
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
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.role?.displayName ?? '';
    _permissions = {
      for (final feature in _systemFeatures)
        feature.id: widget.role?.permissions[feature.id] ?? false,
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
          ..._systemFeatures.map((feature) {
            return SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(feature.name),
              subtitle: Text(feature.description),
              value: _permissions[feature.id] == true,
              onChanged: _isSaving
                  ? null
                  : (value) => setState(() => _permissions[feature.id] = value),
            );
          }),
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
