import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'app_loading_indicator.dart';

import 'firebase_options.dart';
import 'models.dart';
import 'notification_inbox_page.dart';

class DeliveryBoyManagementPage extends StatelessWidget {
  final User user;
  final VoidCallback? onOpenMenu;
  const DeliveryBoyManagementPage({
    super.key,
    required this.user,
    this.onOpenMenu,
  });

  Future<void> _addDeliveryBoy(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _AddDeliveryBoyDialog(
        businessId: user.businessId ?? 'default_business',
        branchId: user.branchId,
      ),
    );
  }

  Future<void> _announce(
    BuildContext context,
    String driverId,
    String name,
  ) async {
    final controller = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Announcement to $name'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(labelText: 'Message'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (send != true || controller.text.trim().isEmpty) return;
    await FirebaseFirestore.instance.collection('notifications').add({
      'recipientId': driverId,
      'title': 'Owner announcement',
      'body': controller.text.trim(),
      'type': 'announcement',
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final businessId = user.businessId ?? 'default_business';
    return Scaffold(
      appBar: AppBar(
        leading: onOpenMenu == null
            ? null
            : IconButton(onPressed: onOpenMenu, icon: const Icon(Icons.menu)),
        title: const Text('Delivery Team'),
        actions: [NotificationBellButton(user: user)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addDeliveryBoy(context),
        icon: const Icon(Icons.person_add),
        label: const Text('Add delivery person'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, usersSnapshot) =>
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('delivery_ratings')
                  .snapshots(),
              builder: (context, ratingSnapshot) {
                if (!usersSnapshot.hasData) {
                  return const Center(child: ModernLoadingIndicator());
                }
                final drivers = usersSnapshot.data!.docs
                    .where(
                      (doc) =>
                          doc.data()['businessId'] == businessId &&
                          doc.data()['role'] == UserRole.deliveryBoy,
                    )
                    .toList();
                if (drivers.isEmpty) {
                  return const Center(
                    child: Text(
                      'No delivery users yet. Use Add delivery person.',
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: drivers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final driver = drivers[index];
                    final data = driver.data();
                    final ratings = (ratingSnapshot.data?.docs ?? const [])
                        .where(
                          (doc) => doc.data()['deliveryBoyId'] == driver.id,
                        )
                        .toList();
                    final average = ratings.isEmpty
                        ? 0.0
                        : ratings.fold<double>(
                                0,
                                (total, doc) =>
                                    total +
                                    ((doc.data()['rating'] as num?)
                                            ?.toDouble() ??
                                        0),
                              ) /
                              ratings.length;
                    return Card(
                      child: ExpansionTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.delivery_dining),
                        ),
                        title: Text(data['name'] ?? 'Delivery person'),
                        subtitle: Text(
                          '${data['deliveryAvailable'] == false ? 'Assigned / unavailable' : 'Available'} • Rating ${average.toStringAsFixed(1)} (${ratings.length})',
                        ),
                        trailing: IconButton(
                          tooltip: 'Send announcement',
                          onPressed: () => _announce(
                            context,
                            driver.id,
                            data['name'] ?? 'driver',
                          ),
                          icon: const Icon(Icons.campaign),
                        ),
                        children: ratings
                            .map(
                              (rating) => ListTile(
                                leading: const Icon(
                                  Icons.star,
                                  color: Colors.amber,
                                ),
                                title: Text('${rating.data()['rating']} stars'),
                                subtitle: Text(rating.data()['comment'] ?? ''),
                              ),
                            )
                            .toList(),
                      ),
                    );
                  },
                );
              },
            ),
      ),
    );
  }
}

class _AddDeliveryBoyDialog extends StatefulWidget {
  final String businessId;
  final String? branchId;
  const _AddDeliveryBoyDialog({required this.businessId, this.branchId});

  @override
  State<_AddDeliveryBoyDialog> createState() => _AddDeliveryBoyDialogState();
}

class _AddDeliveryBoyDialogState extends State<_AddDeliveryBoyDialog> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final phone = TextEditingController();
  final vehicle = TextEditingController();
  bool saving = false;

  @override
  void dispose() {
    for (final controller in [name, email, password, phone, vehicle]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => saving = true);
    FirebaseApp? secondaryApp;
    try {
      secondaryApp = await Firebase.initializeApp(
        name: 'delivery_creation_${DateTime.now().microsecondsSinceEpoch}',
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final secondaryAuth = auth.FirebaseAuth.instanceFor(app: secondaryApp);
      final credential = await secondaryAuth.createUserWithEmailAndPassword(
        email: email.text.trim(),
        password: password.text,
      );
      await FirebaseFirestore.instance
          .collection('users')
          .doc(credential.user!.uid)
          .set({
            'id': credential.user!.uid,
            'name': name.text.trim(),
            'email': email.text.trim(),
            'phone': phone.text.trim(),
            'vehicle': vehicle.text.trim(),
            'role': UserRole.deliveryBoy,
            'businessId': widget.businessId,
            'branchId': widget.branchId,
            'deliveryAvailable': true,
            'isActive': true,
            'createdAt': FieldValue.serverTimestamp(),
          });
      await secondaryAuth.signOut();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Delivery person added.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add delivery person: $e')),
      );
    } finally {
      await secondaryApp?.delete();
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add delivery person'),
    content: SizedBox(
      width: 460,
      child: Form(
        key: formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(name, 'Full name'),
              _field(email, 'Email', emailField: true),
              _field(password, 'Temporary password', passwordField: true),
              _field(phone, 'Phone number'),
              _field(vehicle, 'Vehicle / plate number', required: false),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: saving ? null : save,
        child: Text(saving ? 'Adding...' : 'Add'),
      ),
    ],
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = true,
    bool emailField = false,
    bool passwordField = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      obscureText: passwordField,
      keyboardType: emailField ? TextInputType.emailAddress : null,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: (value) {
        if (required && (value == null || value.trim().isEmpty)) {
          return '$label is required';
        }
        if (passwordField && (value?.length ?? 0) < 6) {
          return 'Use at least 6 characters';
        }
        return null;
      },
    ),
  );
}
