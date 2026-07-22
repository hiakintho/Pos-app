import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'app_loading_indicator.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'firebase_options.dart';
import 'models.dart';
import 'customer_support_page.dart';
import 'notification_inbox_page.dart';
import 'settings_screen.dart';
import 'account_security.dart';
import 'update_management.dart';

Set<String>? _knownRegisteredBusinesses;

void _notifyNewBusinessRegistrations(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> businesses,
) {
  final current = businesses.map((business) => business.id).toSet();
  if (_knownRegisteredBusinesses != null &&
      current.difference(_knownRegisteredBusinesses!).isNotEmpty) {
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.vibrate();
  }
  _knownRegisteredBusinesses = current;
}

class BusinessOwnerRegistrationPage extends StatefulWidget {
  const BusinessOwnerRegistrationPage({super.key});

  @override
  State<BusinessOwnerRegistrationPage> createState() =>
      _BusinessOwnerRegistrationPageState();
}

class _BusinessOwnerRegistrationPageState
    extends State<BusinessOwnerRegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _ownerName = TextEditingController();
  final _businessName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _branchName = TextEditingController(text: 'Main Branch');
  final _branchAddress = TextEditingController();
  final _paymentReference = TextEditingController();
  XFile? _profileImage;
  Uint8List? _profileBytes;
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in [
      _ownerName,
      _businessName,
      _email,
      _password,
      _branchName,
      _branchAddress,
      _paymentReference,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final credential = await auth.FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _email.text.trim(),
            password: _password.text,
          );
      final uid = credential.user!.uid;
      String? profileUrl;
      if (_profileImage != null) {
        final ref = FirebaseStorage.instance.ref('owner_profiles/$uid.jpg');
        await ref.putData(await _profileImage!.readAsBytes());
        profileUrl = await ref.getDownloadURL();
      }
      final firestore = FirebaseFirestore.instance;
      final businessRef = firestore.collection('businesses').doc();
      final branchRef = firestore.collection('branches').doc();
      final batch = firestore.batch();
      batch.set(businessRef, {
        'id': businessRef.id,
        'name': _businessName.text.trim(),
        'ownerId': uid,
        'ownerName': _ownerName.text.trim(),
        'ownerEmail': _email.text.trim(),
        'profileUrl': profileUrl,
        'paymentReference': _paymentReference.text.trim(),
        'approvalStatus': 'pending_payment_approval',
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(branchRef, {
        'id': branchRef.id,
        'businessId': businessRef.id,
        'name': _branchName.text.trim(),
        'address': _branchAddress.text.trim(),
        'managerId': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(firestore.collection('users').doc(uid), {
        'id': uid,
        'name': _ownerName.text.trim(),
        'email': _email.text.trim(),
        'role': UserRole.superAdmin,
        'businessId': businessRef.id,
        'branchId': branchRef.id,
        'profileUrl': profileUrl,
        'accountStatus': 'pending_payment_approval',
        'requiresEmailVerification': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Registration failed: $error')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Register your business')),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                InkWell(
                  onTap: _saving
                      ? null
                      : () async {
                          final image = await ImagePicker().pickImage(
                            source: ImageSource.gallery,
                            imageQuality: 75,
                            maxWidth: 800,
                          );
                          if (image != null && mounted) {
                            final bytes = await image.readAsBytes();
                            setState(() {
                              _profileImage = image;
                              _profileBytes = bytes;
                            });
                          }
                        },
                  child: CircleAvatar(
                    radius: 48,
                    backgroundImage: _profileBytes == null
                        ? null
                        : MemoryImage(_profileBytes!),
                    child: _profileBytes == null
                        ? const Icon(Icons.add_a_photo, size: 32)
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                _field(_ownerName, 'Owner full name'),
                _field(_businessName, 'Business name'),
                _field(_email, 'Email', type: TextInputType.emailAddress),
                _field(
                  _password,
                  'Password',
                  obscure: true,
                  minimum: 10,
                  strongPassword: true,
                ),
                _field(_branchName, 'Starting branch name'),
                _field(_branchAddress, 'Starting branch address'),
                _field(_paymentReference, 'Payment reference'),
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.verified_user),
                    title: Text('Approval required'),
                    subtitle: Text(
                      'A system owner must verify your payment before you can use the POS.',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _register,
                    child: Text(
                      _saving ? 'Registering…' : 'Submit registration',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? type,
    bool obscure = false,
    int minimum = 1,
    bool strongPassword = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      keyboardType: type,
      obscureText: obscure,
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        final requiredError = _required(value);
        if (requiredError != null) return requiredError;
        if (strongPassword) return strongPasswordError(value!);
        return value!.length < minimum
            ? 'Use at least $minimum characters'
            : null;
      },
    ),
  );
}

class BusinessApprovalPendingPage extends StatelessWidget {
  final String status;
  const BusinessApprovalPendingPage({super.key, required this.status});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Account approval'),
      actions: [
        IconButton(
          tooltip: 'System expenses',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const _SystemExpensesPage()),
          ),
          icon: const Icon(Icons.payments),
        ),
        IconButton(
          tooltip: 'Implementations and training',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const _BusinessServicesPage()),
          ),
          icon: const Icon(Icons.school),
        ),
        IconButton(
          onPressed: () => auth.FirebaseAuth.instance.signOut(),
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  status == 'rejected'
                      ? Icons.cancel
                      : status == 'expired'
                      ? Icons.event_busy
                      : Icons.hourglass_top,
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  status == 'rejected'
                      ? 'Registration not approved'
                      : status == 'expired'
                      ? 'Business subscription expired'
                      : 'Waiting for payment approval',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  status == 'rejected'
                      ? 'Contact the system owner to review your registration.'
                      : status == 'expired'
                      ? 'Contact the system owner to renew payment, expiry date, and feature access.'
                      : 'Your payment and business details must be approved before the POS becomes available.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class SystemOwnerPage extends StatefulWidget {
  final User user;
  final int initialSection;
  const SystemOwnerPage({
    super.key,
    required this.user,
    this.initialSection = 0,
  });

  @override
  State<SystemOwnerPage> createState() => _SystemOwnerPageState();
}

class _SystemOwnerPageState extends State<SystemOwnerPage> {
  late int _section = widget.initialSection;

  Future<void> _setApproval(
    DocumentReference<Map<String, dynamic>> business,
    Map<String, dynamic> data,
    String status,
  ) async {
    final ownerId = data['ownerId'] as String?;
    if (ownerId == null) return;
    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();
    batch.update(business, {
      'approvalStatus': status,
      'approvedBy': widget.user.id,
      'approvedAt': status == 'approved' ? FieldValue.serverTimestamp() : null,
    });
    batch.update(firestore.collection('users').doc(ownerId), {
      'accountStatus': status,
      'approvedBy': widget.user.id,
    });
    await batch.commit();
  }

  void _openSearch() => showSearch<void>(
    context: context,
    delegate: _SystemFeatureSearch(
      onSection: (section) => setState(() => _section = section),
      onHelp: _openHelpManagement,
      onProfile: _openProfileManagement,
    ),
  );

  void _openHelpManagement() => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => _BusinessHelpManagementPage(systemOwner: widget.user),
    ),
  );

  void _openProfileManagement() => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => _SystemOwnerProfilePage(user: widget.user),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 760;
    return Scaffold(
      drawer: mobile
          ? _SystemMobileDrawer(
              onSection: (value) => setState(() => _section = value),
              onSearch: _openSearch,
              onHelp: _openHelpManagement,
              onProfile: _openProfileManagement,
            )
          : null,
      appBar: AppBar(
        leading: mobile
            ? Builder(
                builder: (context) => IconButton(
                  tooltip: 'Menu',
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: const Icon(Icons.menu),
                ),
              )
            : null,
        title: const Text('System Owner'),
        actions: [
          if (!mobile)
            IconButton(
              tooltip: 'Search features',
              onPressed: _openSearch,
              icon: const Icon(Icons.search),
            ),
          if (!mobile)
            IconButton(
              tooltip: 'Business help management',
              onPressed: _openHelpManagement,
              icon: const Icon(Icons.support_agent),
            ),
          if (!mobile)
            IconButton(
              tooltip: 'Profile management',
              onPressed: _openProfileManagement,
              icon: const Icon(Icons.account_circle_outlined),
            ),
          NotificationBellButton(user: widget.user),
          IconButton(
            tooltip: 'Logout',
            onPressed: () => auth.FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Row(
        children: [
          if (!mobile)
            _SystemSidebar(
              user: widget.user,
              selectedIndex: _section,
              onSelected: (value) => setState(() => _section = value),
              onLogout: () => auth.FirebaseAuth.instance.signOut(),
              onExpenses: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const _SystemExpensesPage()),
              ),
              onServices: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const _BusinessServicesPage(),
                ),
              ),
              onSystemOwners: () => showDialog<void>(
                context: context,
                builder: (_) => const _AddSystemOwnerDialog(),
              ),
              onSupport: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      CustomerSupportPage(user: widget.user, systemOwner: true),
                ),
              ),
            ),
          if (!mobile) const VerticalDivider(width: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('businesses')
                  .snapshots(),
              builder: (context, snapshot) {
                if (_section == 3) {
                  return const _SystemExpensesPage(embedded: true);
                }
                if (_section == 4) {
                  return const _BusinessServicesPage(embedded: true);
                }
                if (_section == 5) {
                  return CustomerSupportPage(
                    user: widget.user,
                    systemOwner: true,
                    embedded: true,
                  );
                }
                if (_section == 6) {
                  return UpdateManagementPage(systemOwner: widget.user);
                }
                if (!snapshot.hasData) {
                  return const Center(child: ModernLoadingIndicator());
                }
                final businesses = snapshot.data!.docs;
                _notifyNewBusinessRegistrations(businesses);
                if (_section != 0 && businesses.isEmpty) {
                  return const Center(
                    child: Text('No business registrations.'),
                  );
                }
                return Align(
                  alignment: Alignment.topCenter,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_section == 0) const _SystemDashboardSummary(),
                        if (_section != 0)
                          Padding(
                            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _section == 1
                                    ? 'Business Owners'
                                    : 'Subscription Management',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        if (_section != 0)
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(16),
                            itemCount: businesses.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final business = businesses[index];
                              final data = business.data();
                              final status =
                                  data['approvalStatus'] as String? ??
                                  'approved';
                              return Card(
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundImage: data['profileUrl'] == null
                                        ? null
                                        : NetworkImage(data['profileUrl']),
                                    child: data['profileUrl'] == null
                                        ? const Icon(Icons.business)
                                        : null,
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(data['name'] ?? 'Business'),
                                      ),
                                      if (_section == 2)
                                        IconButton(
                                          tooltip:
                                              'Subscription, expiry and features',
                                          onPressed: () => showDialog<void>(
                                            context: context,
                                            builder: (_) =>
                                                _BusinessSubscriptionDialog(
                                                  business: business.reference,
                                                  data: data,
                                                  systemOwnerId: widget.user.id,
                                                ),
                                          ),
                                          icon: const Icon(Icons.tune),
                                        ),
                                    ],
                                  ),
                                  subtitle: Text(
                                    '${data['ownerName'] ?? 'Owner'} • ${data['ownerEmail'] ?? ''}\nPaid: Tsh ${data['amountPaid'] ?? 'Not set'} • ${status.replaceAll('_', ' ')}\nExpires: ${_subscriptionDate(data['subscriptionExpiresAt'])}',
                                  ),
                                  isThreeLine: true,
                                  trailing: status == 'pending_payment_approval'
                                      ? Wrap(
                                          spacing: 6,
                                          children: [
                                            IconButton(
                                              tooltip: 'Reject',
                                              onPressed: () => _setApproval(
                                                business.reference,
                                                data,
                                                'rejected',
                                              ),
                                              icon: const Icon(
                                                Icons.close,
                                                color: Colors.red,
                                              ),
                                            ),
                                            IconButton.filled(
                                              tooltip: 'Approve payment',
                                              onPressed: () => _setApproval(
                                                business.reference,
                                                data,
                                                'approved',
                                              ),
                                              icon: const Icon(Icons.check),
                                            ),
                                          ],
                                        )
                                      : Text(status),
                                ),
                              );
                            },
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
    );
  }
}

class _SystemMobileDrawer extends StatelessWidget {
  final ValueChanged<int> onSection;
  final VoidCallback onSearch;
  final VoidCallback onHelp;
  final VoidCallback onProfile;
  const _SystemMobileDrawer({
    required this.onSection,
    required this.onSearch,
    required this.onHelp,
    required this.onProfile,
  });

  @override
  Widget build(BuildContext context) => Drawer(
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          const ListTile(
            leading: Icon(Icons.admin_panel_settings),
            title: Text(
              'System Owner',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(),
          ...[
            ('Dashboard', Icons.dashboard, 0),
            ('Business Owners', Icons.business, 1),
            ('Subscriptions', Icons.workspace_premium, 2),
            ('Expenses', Icons.payments, 3),
            ('Training & Implementation', Icons.school, 4),
            ('Customer Support', Icons.support_agent, 5),
            ('Update Management', Icons.system_update, 6),
          ].map(
            (item) => ListTile(
              leading: Icon(item.$2),
              title: Text(item.$1),
              onTap: () {
                Navigator.pop(context);
                onSection(item.$3);
              },
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.search),
            title: const Text('Search features'),
            onTap: () {
              Navigator.pop(context);
              onSearch();
            },
          ),
          ListTile(
            leading: const Icon(Icons.support_agent),
            title: const Text('Business Help Management'),
            onTap: () {
              Navigator.pop(context);
              onHelp();
            },
          ),
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: const Text('Profile Management'),
            onTap: () {
              Navigator.pop(context);
              onProfile();
            },
          ),
        ],
      ),
    ),
  );
}

class _SystemFeatureSearch extends SearchDelegate<void> {
  final ValueChanged<int> onSection;
  final VoidCallback onHelp;
  final VoidCallback onProfile;
  _SystemFeatureSearch({
    required this.onSection,
    required this.onHelp,
    required this.onProfile,
  });

  static const _features = <(String, IconData, int?)>[
    ('Dashboard', Icons.dashboard, 0),
    ('Business Owners', Icons.business, 1),
    ('Subscriptions', Icons.workspace_premium, 2),
    ('Expenses', Icons.payments, 3),
    ('Training & Implementation', Icons.school, 4),
    ('Customer Support', Icons.support_agent, 5),
    ('Update Management', Icons.system_update, 6),
    ('Business Help Management', Icons.manage_accounts, null),
    ('Profile Management', Icons.account_circle, null),
  ];

  @override
  List<Widget> buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear)),
  ];
  @override
  Widget buildLeading(BuildContext context) => IconButton(
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back),
  );
  @override
  Widget buildSuggestions(BuildContext context) => _results(context);
  @override
  Widget buildResults(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    final matches = _features
        .where((item) => item.$1.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return ListView.builder(
      itemCount: matches.length,
      itemBuilder: (_, index) {
        final item = matches[index];
        return ListTile(
          leading: Icon(item.$2),
          title: Text(item.$1),
          onTap: () {
            close(context, null);
            Future.microtask(() {
              if (item.$3 != null) {
                onSection(item.$3!);
              } else if (item.$1.startsWith('Business')) {
                onHelp();
              } else {
                onProfile();
              }
            });
          },
        );
      },
    );
  }
}

class _BusinessHelpManagementPage extends StatefulWidget {
  final User systemOwner;
  const _BusinessHelpManagementPage({required this.systemOwner});
  @override
  State<_BusinessHelpManagementPage> createState() =>
      _BusinessHelpManagementPageState();
}

class _BusinessHelpManagementPageState
    extends State<_BusinessHelpManagementPage> {
  String? _businessId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Business Help Management')),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('businesses').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: ModernLoadingIndicator());
        }
        final businesses = snapshot.data!.docs;
        final selected = businesses
            .where((doc) => doc.id == _businessId)
            .firstOrNull;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: DropdownButtonFormField<String>(
                initialValue: _businessId,
                decoration: const InputDecoration(
                  labelText: 'Select business owner',
                  prefixIcon: Icon(Icons.business),
                ),
                items: businesses
                    .map(
                      (doc) => DropdownMenuItem(
                        value: doc.id,
                        child: Text(doc.data()['name'] ?? 'Business'),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _businessId = value),
              ),
            ),
            if (selected != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.pin),
                    label: const Text('Reset business owner PIN'),
                    onPressed: () async {
                      final ownerId = selected.data()['ownerId']?.toString();
                      if (ownerId == null || ownerId.isEmpty) return;
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(ownerId)
                          .set({
                            'pinResetRequestedAt': FieldValue.serverTimestamp(),
                            'pinResetRequestedBy': widget.systemOwner.id,
                          }, SetOptions(merge: true));
                      if (context.mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'PIN reset requested. The owner will create a new PIN on that device.',
                            ),
                          ),
                        );
                    },
                  ),
                ),
              ),
            if (selected == null)
              const Expanded(
                child: Center(
                  child: Text(
                    'Select a business to manage its users, roles, branches and settings.',
                  ),
                ),
              )
            else
              Expanded(
                child: SettingsScreen(
                  key: ValueKey(selected.id),
                  user: User(
                    id: widget.systemOwner.id,
                    name: widget.systemOwner.name,
                    email: widget.systemOwner.email,
                    role: UserRole.superAdmin,
                    businessId: selected.id,
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _SystemOwnerProfilePage extends StatefulWidget {
  final User user;
  const _SystemOwnerProfilePage({required this.user});
  @override
  State<_SystemOwnerProfilePage> createState() =>
      _SystemOwnerProfilePageState();
}

class _SystemOwnerProfilePageState extends State<_SystemOwnerProfilePage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _profileUrl = TextEditingController();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  bool _loaded = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _profileUrl.dispose();
    _currentPassword.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user.id)
        .update({
          'name': _name.text.trim(),
          'phone': _phone.text.trim(),
          'profileUrl': _profileUrl.text.trim(),
          'profileUpdatedAt': FieldValue.serverTimestamp(),
        });
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile updated.')));
    }
  }

  Future<void> _changePassword() async {
    final current = auth.FirebaseAuth.instance.currentUser;
    if (current == null || current.email == null) return;
    if (_currentPassword.text.isEmpty || _newPassword.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter the current password and a new password of at least 8 characters.',
          ),
        ),
      );
      return;
    }
    try {
      final credential = auth.EmailAuthProvider.credential(
        email: current.email!,
        password: _currentPassword.text,
      );
      await current.reauthenticateWithCredential(credential);
      await current.updatePassword(_newPassword.text);
      _currentPassword.clear();
      _newPassword.clear();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password changed successfully.')),
        );
    } on auth.FirebaseAuthException catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message ?? 'Could not change the password.'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Profile Management')),
    body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.id)
          .get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: ModernLoadingIndicator());
        }
        final data = snapshot.data!.data() ?? {};
        if (!_loaded) {
          _loaded = true;
          _name.text = data['name'] ?? widget.user.name;
          _phone.text = data['phone'] ?? '';
          _profileUrl.text = data['profileUrl'] ?? '';
        }
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: CircleAvatar(
                radius: 48,
                backgroundImage: _profileUrl.text.isEmpty
                    ? null
                    : NetworkImage(_profileUrl.text),
                child: _profileUrl.text.isEmpty
                    ? const Icon(Icons.person, size: 48)
                    : null,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Full name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: widget.user.email,
              enabled: false,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _profileUrl,
              decoration: const InputDecoration(
                labelText: 'Profile picture URL',
                prefixIcon: Icon(Icons.image_outlined),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Save profile'),
            ),
            const SizedBox(height: 28),
            Text(
              'Change password',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Confirm the current password to change it directly. An OTP is not required for an authenticated system owner.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _currentPassword,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Current password',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newPassword,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'New password (minimum 8 characters)',
                prefixIcon: Icon(Icons.password),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _changePassword,
              icon: const Icon(Icons.security),
              label: const Text('Change password'),
            ),
          ],
        );
      },
    ),
  );
}

class _SystemSidebar extends StatelessWidget {
  final User user;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Future<void> Function() onLogout;
  final VoidCallback onExpenses;
  final VoidCallback onServices;
  final VoidCallback onSystemOwners;
  final VoidCallback onSupport;

  const _SystemSidebar({
    required this.user,
    required this.selectedIndex,
    required this.onSelected,
    required this.onLogout,
    required this.onExpenses,
    required this.onServices,
    required this.onSystemOwners,
    required this.onSupport,
  });

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    return Container(
      width: compact ? 76 : 264,
      color: const Color(0xFF050505),
      padding: EdgeInsets.fromLTRB(compact ? 8 : 12, 16, compact ? 8 : 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
            child: compact
                ? const Icon(
                    Icons.point_of_sale,
                    color: Color(0xFF1DB954),
                    size: 30,
                  )
                : const Text(
                    'POS APP',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
          ),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF121212),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _item(
                    context,
                    Icons.dashboard,
                    'Dashboard',
                    selected: selectedIndex == 0,
                    onTap: () => onSelected(0),
                  ),
                  _item(
                    context,
                    Icons.business,
                    'Business Owners',
                    selected: selectedIndex == 1,
                    onTap: () => onSelected(1),
                  ),
                  _item(
                    context,
                    Icons.workspace_premium,
                    'Subscriptions',
                    selected: selectedIndex == 2,
                    onTap: () => onSelected(2),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Divider(height: 1),
                  ),
                  _item(
                    context,
                    Icons.payments,
                    'Expenses',
                    selected: selectedIndex == 3,
                    onTap: () => onSelected(3),
                  ),
                  _item(
                    context,
                    Icons.school,
                    'Training & Implementation',
                    selected: selectedIndex == 4,
                    onTap: () => onSelected(4),
                  ),
                  _item(
                    context,
                    Icons.admin_panel_settings,
                    'System Owners',
                    onTap: onSystemOwners,
                  ),
                  _item(
                    context,
                    Icons.support_agent,
                    'Customer Support',
                    selected: selectedIndex == 5,
                    onTap: () => onSelected(5),
                  ),
                  _item(
                    context,
                    Icons.system_update,
                    'Update Management',
                    selected: selectedIndex == 6,
                    onTap: () => onSelected(6),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF121212),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: EdgeInsets.all(compact ? 4 : 12),
              child: Row(
                children: [
                  if (!compact) ...[
                    CircleAvatar(
                      backgroundColor: const Color(0xFF1DB954),
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
                                ?.copyWith(color: const Color(0xFFB3B3B3)),
                          ),
                        ],
                      ),
                    ),
                  ],
                  IconButton(
                    tooltip: 'Logout',
                    onPressed: onLogout,
                    icon: const Icon(Icons.logout),
                    color: const Color(0xFFB3B3B3),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _item(
    BuildContext context,
    IconData icon,
    String label, {
    VoidCallback? onTap,
    bool selected = false,
  }) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: Material(
          color: selected ? const Color(0xFF2A2A2A) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: ListTile(
            dense: true,
            selected: selected,
            leading: Icon(
              icon,
              color: selected ? Colors.white : const Color(0xFFB3B3B3),
            ),
            title: compact
                ? null
                : Text(
                    label,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}

class _SystemDashboardSummary extends StatelessWidget {
  const _SystemDashboardSummary();

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance
        .collection('system_subscription_payments')
        .snapshots(),
    builder: (context, paymentsSnapshot) =>
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('system_expenses')
              .snapshots(),
          builder: (context, expensesSnapshot) =>
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('business_services')
                    .snapshots(),
                builder: (context, servicesSnapshot) {
                  final now = DateTime.now();
                  bool thisMonth(dynamic value) {
                    final date = value is Timestamp ? value.toDate() : null;
                    return date != null &&
                        date.year == now.year &&
                        date.month == now.month;
                  }

                  final revenue = (paymentsSnapshot.data?.docs ?? const [])
                      .where((doc) => thisMonth(doc.data()['paidAt']))
                      .fold<double>(
                        0,
                        (sum, doc) =>
                            sum +
                            ((doc.data()['amount'] as num?)?.toDouble() ?? 0),
                      );
                  final expenses = (expensesSnapshot.data?.docs ?? const [])
                      .where((doc) => thisMonth(doc.data()['incurredAt']))
                      .fold<double>(
                        0,
                        (sum, doc) =>
                            sum +
                            ((doc.data()['amount'] as num?)?.toDouble() ?? 0),
                      );
                  final services = servicesSnapshot.data?.docs ?? const [];
                  final serviceCosts = services
                      .where((doc) => thisMonth(doc.data()['serviceDate']))
                      .fold<double>(
                        0,
                        (sum, doc) =>
                            sum +
                            ((doc.data()['cost'] as num?)?.toDouble() ?? 0),
                      );
                  final implemented = services
                      .where(
                        (doc) =>
                            doc.data()['type'] == 'implementation' &&
                            doc.data()['status'] == 'completed',
                      )
                      .map((doc) => doc.data()['businessId'])
                      .toSet()
                      .length;
                  final trainings = services
                      .where(
                        (doc) =>
                            doc.data()['type'] == 'training' &&
                            doc.data()['status'] == 'completed',
                      )
                      .length;
                  final months = List.generate(6, (index) {
                    final offset = 5 - index;
                    return DateTime(now.year, now.month - offset, 1);
                  });
                  double monthlyTotal(
                    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
                    DateTime month,
                    String dateField,
                    String amountField,
                  ) => docs
                      .where((doc) {
                        final date = _timestamp(doc.data()[dateField]);
                        return date.year == month.year &&
                            date.month == month.month;
                      })
                      .fold<double>(
                        0,
                        (total, doc) =>
                            total +
                            ((doc.data()[amountField] as num?)?.toDouble() ??
                                0),
                      );
                  final paymentDocs = paymentsSnapshot.data?.docs ?? const [];
                  final expenseDocs = expensesSnapshot.data?.docs ?? const [];
                  final revenueSeries = months
                      .map(
                        (month) => monthlyTotal(
                          paymentDocs,
                          month,
                          'paidAt',
                          'amount',
                        ),
                      )
                      .toList();
                  final expenseSeries = months
                      .map(
                        (month) =>
                            monthlyTotal(
                              expenseDocs,
                              month,
                              'incurredAt',
                              'amount',
                            ) +
                            monthlyTotal(
                              services,
                              month,
                              'serviceDate',
                              'cost',
                            ),
                      )
                      .toList();
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _SystemMetric(
                              label: 'Monthly subscriptions',
                              value: _tsh(revenue),
                              icon: Icons.trending_up,
                            ),
                            _SystemMetric(
                              label: 'Monthly expenses',
                              value: _tsh(expenses + serviceCosts),
                              icon: Icons.trending_down,
                            ),
                            _SystemMetric(
                              label: 'Monthly profit',
                              value: _tsh(revenue - expenses - serviceCosts),
                              icon: Icons.account_balance,
                            ),
                            _SystemMetric(
                              label: 'Implemented',
                              value: '$implemented businesses',
                              icon: Icons.business_center,
                            ),
                            _SystemMetric(
                              label: 'Trainings',
                              value: '$trainings completed',
                              icon: Icons.school,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Live revenue and expenses',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Green: subscriptions • Red: expenses',
                                  style: TextStyle(color: Colors.grey),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  height: 190,
                                  child: CustomPaint(
                                    painter: _RevenueExpenseChartPainter(
                                      revenue: revenueSeries,
                                      expenses: expenseSeries,
                                      months: months,
                                    ),
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
        ),
  );
}

class _RevenueExpenseChartPainter extends CustomPainter {
  final List<double> revenue;
  final List<double> expenses;
  final List<DateTime> months;
  const _RevenueExpenseChartPainter({
    required this.revenue,
    required this.expenses,
    required this.months,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const left = 10.0;
    const bottom = 26.0;
    final chartHeight = size.height - bottom;
    final maxValue = [
      ...revenue,
      ...expenses,
    ].fold<double>(1, (max, value) => value > max ? value : max);
    final grid = Paint()
      ..color = const Color(0xFF333333)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = chartHeight * i / 4;
      canvas.drawLine(Offset(left, y), Offset(size.width, y), grid);
    }
    void drawSeries(List<double> values, Color color) {
      final path = Path();
      for (var i = 0; i < values.length; i++) {
        final x = left + (size.width - left) * i / (values.length - 1);
        final y = chartHeight - (values[i] / maxValue * (chartHeight - 8));
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
        canvas.drawCircle(Offset(x, y), 3.5, Paint()..color = color);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke,
      );
    }

    drawSeries(revenue, const Color(0xFF1DB954));
    drawSeries(expenses, Colors.redAccent);
    for (var i = 0; i < months.length; i++) {
      final x = left + (size.width - left) * i / (months.length - 1);
      final label = TextPainter(
        text: TextSpan(
          text: '${months[i].month}/${months[i].year.toString().substring(2)}',
          style: const TextStyle(color: Colors.grey, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(x - label.width / 2, chartHeight + 7));
    }
  }

  @override
  bool shouldRepaint(covariant _RevenueExpenseChartPainter oldDelegate) =>
      oldDelegate.revenue != revenue || oldDelegate.expenses != expenses;
}

class _SystemMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _SystemMetric({
    required this.label,
    required this.value,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 210,
    child: Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(label),
      ),
    ),
  );
}

class _SystemExpensesPage extends StatelessWidget {
  final bool embedded;
  const _SystemExpensesPage({this.embedded = false});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: embedded ? null : AppBar(title: const Text('System expenses')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => showDialog<void>(
        context: context,
        builder: (_) => const _SystemExpenseDialog(),
      ),
      icon: const Icon(Icons.add),
      label: const Text('Record expense'),
    ),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('system_expenses')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: ModernLoadingIndicator());
        }
        final docs = snapshot.data!.docs.toList()
          ..sort(
            (a, b) => _timestamp(
              b.data()['incurredAt'],
            ).compareTo(_timestamp(a.data()['incurredAt'])),
          );
        if (docs.isEmpty) {
          return const Center(child: Text('No system expenses recorded.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
          itemCount: docs.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (_, index) {
            final data = docs[index].data();
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
              title: Text(
                '${data['category'] ?? 'Expense'} • ${_tsh((data['amount'] as num?)?.toDouble() ?? 0)}',
              ),
              subtitle: Text(
                '${data['description'] ?? ''}\n${_shortDate(data['incurredAt'])}',
              ),
              isThreeLine: true,
            );
          },
        );
      },
    ),
  );
}

class _SystemExpenseDialog extends StatefulWidget {
  const _SystemExpenseDialog();
  @override
  State<_SystemExpenseDialog> createState() => _SystemExpenseDialogState();
}

class _SystemExpenseDialogState extends State<_SystemExpenseDialog> {
  final _amount = TextEditingController();
  final _description = TextEditingController();
  String _category = 'Maintenance';
  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) return;
    await FirebaseFirestore.instance.collection('system_expenses').add({
      'category': _category,
      'amount': amount,
      'description': _description.text.trim(),
      'incurredAt': FieldValue.serverTimestamp(),
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Record system expense'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _category,
            items:
                const [
                      'Maintenance',
                      'Customer support',
                      'Training',
                      'Travel',
                      'Hosting',
                      'Other',
                    ]
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
            onChanged: (value) => setState(() => _category = value!),
            decoration: const InputDecoration(labelText: 'Category'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Amount',
              prefixText: 'Tsh ',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _description,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}

class _BusinessServicesPage extends StatelessWidget {
  final bool embedded;
  const _BusinessServicesPage({this.embedded = false});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: embedded
        ? null
        : AppBar(title: const Text('Implementations & training')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => showDialog<void>(
        context: context,
        builder: (_) => const _BusinessServiceDialog(),
      ),
      icon: const Icon(Icons.add),
      label: const Text('Add record'),
    ),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('business_services')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: ModernLoadingIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Text('No implementation or training records.'),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
          itemCount: docs.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (_, index) {
            final data = docs[index].data();
            return ListTile(
              leading: CircleAvatar(
                child: Icon(
                  data['type'] == 'training'
                      ? Icons.school
                      : Icons.business_center,
                ),
              ),
              title: Text(
                '${data['businessName'] ?? 'Business'} • ${data['type'] ?? 'service'}',
              ),
              subtitle: Text(
                '${data['status'] ?? 'planned'} • ${_shortDate(data['serviceDate'])}\n${data['notes'] ?? ''}',
              ),
              isThreeLine: true,
              trailing: Text(
                'Fee ${_tsh((data['fee'] as num?)?.toDouble() ?? 0)}\nCost ${_tsh((data['cost'] as num?)?.toDouble() ?? 0)}',
                textAlign: TextAlign.end,
              ),
            );
          },
        );
      },
    ),
  );
}

class _BusinessServiceDialog extends StatefulWidget {
  const _BusinessServiceDialog();
  @override
  State<_BusinessServiceDialog> createState() => _BusinessServiceDialogState();
}

class _BusinessServiceDialogState extends State<_BusinessServiceDialog> {
  String? _businessId;
  String _type = 'implementation';
  String _status = 'planned';
  final _fee = TextEditingController(text: '0');
  final _cost = TextEditingController(text: '0');
  final _notes = TextEditingController();
  Future<void> _save(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> businesses,
  ) async {
    final business = businesses
        .where((doc) => doc.id == _businessId)
        .firstOrNull;
    if (business == null) return;
    await FirebaseFirestore.instance.collection('business_services').add({
      'businessId': business.id,
      'businessName': business.data()['name'] ?? 'Business',
      'type': _type,
      'status': _status,
      'fee': double.tryParse(_fee.text) ?? 0,
      'cost': double.tryParse(_cost.text) ?? 0,
      'notes': _notes.text.trim(),
      'serviceDate': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
    future: FirebaseFirestore.instance.collection('businesses').get(),
    builder: (context, snapshot) {
      final businesses = snapshot.data?.docs ?? [];
      return AlertDialog(
        title: const Text('Implementation or training record'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _businessId,
                items: businesses
                    .map(
                      (doc) => DropdownMenuItem(
                        value: doc.id,
                        child: Text(doc.data()['name'] ?? 'Business'),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _businessId = value),
                decoration: const InputDecoration(
                  labelText: 'Business customer',
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _type,
                items: const [
                  DropdownMenuItem(
                    value: 'implementation',
                    child: Text('System implementation'),
                  ),
                  DropdownMenuItem(value: 'training', child: Text('Training')),
                ],
                onChanged: (value) => setState(() => _type = value!),
                decoration: const InputDecoration(labelText: 'Service'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _status,
                items:
                    const ['planned', 'in_progress', 'completed', 'cancelled']
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                onChanged: (value) => setState(() => _status = value!),
                decoration: const InputDecoration(labelText: 'Status'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _fee,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Fee charged',
                  prefixText: 'Tsh ',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _cost,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Service expense/cost',
                  prefixText: 'Tsh ',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: businesses.isEmpty ? null : () => _save(businesses),
            child: const Text('Save'),
          ),
        ],
      );
    },
  );
}

DateTime _timestamp(dynamic value) => value is Timestamp
    ? value.toDate()
    : DateTime.fromMillisecondsSinceEpoch(0);
String _shortDate(dynamic value) {
  final date = _timestamp(value);
  return '${date.day}/${date.month}/${date.year}';
}

String _tsh(double value) => 'Tsh ${value.toStringAsFixed(0)}';

const _subscriptionFeatures = <String, String>{
  'dashboard': 'Dashboard',
  'pos': 'POS sales',
  'inventory': 'Inventory',
  'expenses': 'Expenses',
  'purchases': 'Purchases',
  'sales_management': 'Sales management',
  'online_sales': 'Online sales and delivery',
  'reports': 'Reports and analytics',
  'settings': 'Settings and administration',
};

String _subscriptionDate(dynamic value) {
  if (value is! Timestamp) return 'No expiry set';
  final date = value.toDate();
  return '${date.day}/${date.month}/${date.year}';
}

class _BusinessSubscriptionDialog extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> business;
  final Map<String, dynamic> data;
  final String systemOwnerId;

  const _BusinessSubscriptionDialog({
    required this.business,
    required this.data,
    required this.systemOwnerId,
  });

  @override
  State<_BusinessSubscriptionDialog> createState() =>
      _BusinessSubscriptionDialogState();
}

class _BusinessSubscriptionDialogState
    extends State<_BusinessSubscriptionDialog> {
  late final TextEditingController _amount;
  late DateTime _expiry;
  late Set<String> _allowed;
  bool _saving = false;
  bool _recordPayment = true;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: '${(widget.data['amountPaid'] as num?) ?? ''}',
    );
    final storedExpiry = widget.data['subscriptionExpiresAt'];
    _expiry = storedExpiry is Timestamp
        ? storedExpiry.toDate()
        : DateTime.now().add(const Duration(days: 30));
    final stored = widget.data['allowedFeatures'] as List?;
    _allowed = stored == null
        ? _subscriptionFeatures.keys.toSet()
        : stored.map((item) => item.toString()).toSet();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiry.isBefore(DateTime.now()) ? DateTime.now() : _expiry,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null && mounted) setState(() => _expiry = picked);
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount < 0 || _allowed.isEmpty) return;
    setState(() => _saving = true);
    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();
    batch.update(widget.business, {
      'amountPaid': amount,
      'subscriptionExpiresAt': Timestamp.fromDate(
        DateTime(_expiry.year, _expiry.month, _expiry.day, 23, 59, 59),
      ),
      'allowedFeatures': _allowed.toList()..sort(),
      'subscriptionUpdatedBy': widget.systemOwnerId,
      'subscriptionUpdatedAt': FieldValue.serverTimestamp(),
    });
    if (_recordPayment && amount > 0) {
      final payment = firestore
          .collection('system_subscription_payments')
          .doc();
      batch.set(payment, {
        'id': payment.id,
        'businessId': widget.business.id,
        'businessName': widget.data['name'] ?? 'Business',
        'amount': amount,
        'features': _allowed.toList()..sort(),
        'expiresAt': Timestamp.fromDate(_expiry),
        'recordedBy': widget.systemOwnerId,
        'paidAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.data['name'] ?? 'Business'} subscription'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount paid',
                prefixText: 'Tsh ',
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _recordPayment,
              title: const Text('Record this amount as subscription income'),
              subtitle: const Text(
                'Turn off when only changing features or expiry.',
              ),
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _recordPayment = value == true),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: const Text('Subscription expiry date'),
              subtitle: Text(_subscriptionDate(Timestamp.fromDate(_expiry))),
              trailing: const Icon(Icons.edit_calendar),
              onTap: _saving ? null : _pickExpiry,
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Features included in payment',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => setState(
                          () => _allowed = _subscriptionFeatures.keys.toSet(),
                        ),
                  child: const Text('Select all'),
                ),
              ],
            ),
            ..._subscriptionFeatures.entries.map(
              (feature) => CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _allowed.contains(feature.key),
                title: Text(feature.value),
                onChanged: _saving
                    ? null
                    : (value) => setState(() {
                        if (value == true) {
                          _allowed.add(feature.key);
                        } else {
                          _allowed.remove(feature.key);
                        }
                      }),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton.icon(
        onPressed: _saving ? null : _save,
        icon: const Icon(Icons.save),
        label: const Text('Save subscription'),
      ),
    ],
  );
}

class _AddSystemOwnerDialog extends StatefulWidget {
  const _AddSystemOwnerDialog();

  @override
  State<_AddSystemOwnerDialog> createState() => _AddSystemOwnerDialogState();
}

class _AddSystemOwnerDialogState extends State<_AddSystemOwnerDialog> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _saving = false;

  Future<void> _save() async {
    if (_name.text.trim().isEmpty ||
        _email.text.trim().isEmpty ||
        _password.text.length < 6) {
      return;
    }
    setState(() => _saving = true);
    FirebaseApp? secondary;
    try {
      secondary = await Firebase.initializeApp(
        name: 'system_owner_${DateTime.now().microsecondsSinceEpoch}',
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final credential = await auth.FirebaseAuth.instanceFor(app: secondary)
          .createUserWithEmailAndPassword(
            email: _email.text.trim(),
            password: _password.text,
          );
      await FirebaseFirestore.instance
          .collection('users')
          .doc(credential.user!.uid)
          .set({
            'id': credential.user!.uid,
            'name': _name.text.trim(),
            'email': _email.text.trim(),
            'role': UserRole.systemOwner,
            'accountStatus': 'approved',
            'createdAt': FieldValue.serverTimestamp(),
          });
      if (mounted) Navigator.pop(context);
    } finally {
      await secondary?.delete();
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Register system owner'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Full name'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _email,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: const Text('Create'),
      ),
    ],
  );
}
