import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

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
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, usersSnapshot) =>
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('delivery_ratings')
                  .snapshots(),
              builder: (context, ratingSnapshot) {
                if (!usersSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
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
                      'No delivery users. Add them from User Management.',
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
