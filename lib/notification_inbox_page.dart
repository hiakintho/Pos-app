import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'app_loading_indicator.dart';

import 'models.dart';
import 'customer_marketplace.dart';
import 'customer_support_page.dart';
import 'system_administration.dart';

class NotificationInboxPage extends StatelessWidget {
  final User user;
  const NotificationInboxPage({super.key, required this.user});

  Future<void> _markAllRead() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('notifications')
        .where('recipientId', isEqualTo: user.id)
        .get();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snapshot.docs.where(
      (doc) => doc.data()['read'] != true,
    )) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }

  Future<void> _openNotification(
    BuildContext context,
    DocumentReference<Map<String, dynamic>> reference,
    Map<String, dynamic> notification,
  ) async {
    await reference.update({'read': true});
    if (!context.mounted) return;
    final type = notification['type'] as String? ?? '';
    final Widget? destination = switch (type) {
      'new_business' => SystemOwnerPage(user: user, initialSection: 1),
      'new_order' => CustomerOrderManagementPage(user: user),
      'delivery_assignment' => DeliveryOrdersPage(user: user),
      'support_message' => CustomerSupportPage(
        user: user,
        systemOwner: user.role == UserRole.systemOwner,
      ),
      _ => null,
    };
    if (destination != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => destination),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Notifications'),
      actions: [
        IconButton(
          tooltip: 'Mark all read',
          onPressed: _markAllRead,
          icon: const Icon(Icons.done_all),
        ),
      ],
    ),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('recipientId', isEqualTo: user.id)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: ModernLoadingIndicator());
        }
        final docs = snapshot.data!.docs.toList()
          ..sort(
            (a, b) => _date(
              b.data()['createdAt'],
            ).compareTo(_date(a.data()['createdAt'])),
          );
        if (docs.isEmpty) {
          return const Center(child: Text('No notifications yet.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (_, index) {
            final doc = docs[index];
            final data = doc.data();
            return ListTile(
              leading: CircleAvatar(
                child: Icon(
                  data['read'] == true
                      ? Icons.notifications_none
                      : Icons.notifications_active,
                ),
              ),
              title: Text(
                data['title'] ?? 'Notification',
                style: TextStyle(
                  fontWeight: data['read'] == true
                      ? FontWeight.normal
                      : FontWeight.bold,
                ),
              ),
              subtitle: Text(data['body'] ?? ''),
              onTap: () => _openNotification(context, doc.reference, data),
            );
          },
        );
      },
    ),
  );
}

class NotificationBellButton extends StatelessWidget {
  final User user;
  const NotificationBellButton({super.key, required this.user});
  @override
  Widget build(BuildContext context) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('notifications')
            .where('recipientId', isEqualTo: user.id)
            .snapshots(),
        builder: (context, snapshot) {
          final unread =
              snapshot.data?.docs
                  .where((doc) => doc.data()['read'] != true)
                  .length ??
              0;
          return IconButton(
            tooltip: 'Notifications',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NotificationInboxPage(user: user),
              ),
            ),
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.notifications_outlined),
            ),
          );
        },
      );
}

DateTime _date(dynamic value) => value is Timestamp
    ? value.toDate()
    : DateTime.fromMillisecondsSinceEpoch(0);
