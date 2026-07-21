import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'app_loading_indicator.dart';

import 'models.dart';
import 'notification_inbox_page.dart';
import 'ai_service.dart';

class CustomerSupportPage extends StatelessWidget {
  final User user;
  final bool systemOwner;
  final VoidCallback? onOpenMenu;
  final bool embedded;
  final bool aiEnabled;

  const CustomerSupportPage({
    super.key,
    required this.user,
    this.systemOwner = false,
    this.onOpenMenu,
    this.embedded = false,
    this.aiEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('support_tickets')
        .snapshots();
    return Scaffold(
      appBar: embedded
          ? null
          : AppBar(
              leading: onOpenMenu == null
                  ? null
                  : IconButton(
                      onPressed: onOpenMenu,
                      icon: const Icon(Icons.menu),
                    ),
              title: Text(systemOwner ? 'Customer Support' : 'Support'),
              actions: [
                NotificationBellButton(user: user),
                if (!systemOwner && aiEnabled)
                  IconButton(
                    tooltip: 'Chat with AI support',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _AiSupportChatPage(user: user),
                      ),
                    ),
                    icon: const Icon(Icons.smart_toy),
                  ),
                if (systemOwner)
                  IconButton(
                    tooltip: 'Welcome message',
                    onPressed: () => _editWelcomeMessage(context),
                    icon: const Icon(Icons.waving_hand),
                  ),
              ],
            ),
      floatingActionButton: systemOwner
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _NewSupportTicketDialog(user: user),
              ),
              icon: const Icon(Icons.add_comment),
              label: const Text('New ticket'),
            ),
      body: Column(
        children: [
          const _SupportAvailabilityHeader(),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: ModernLoadingIndicator());
                }
                final tickets =
                    snapshot.data!.docs.where((doc) {
                      if (systemOwner) return true;
                      return doc.data()['businessId'] ==
                          (user.businessId ?? 'default_business');
                    }).toList()..sort(
                      (a, b) => _date(
                        b.data()['updatedAt'],
                      ).compareTo(_date(a.data()['updatedAt'])),
                    );
                if (tickets.isEmpty) {
                  return const Center(child: Text('No support tickets.'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  itemCount: tickets.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final ticket = tickets[index];
                    final data = ticket.data();
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Icon(
                            data['status'] == 'closed'
                                ? Icons.check
                                : Icons.support_agent,
                          ),
                        ),
                        title: Text(data['subject'] ?? 'Support request'),
                        subtitle: Text(
                          '${data['businessName'] ?? 'Business'} • ${data['priority'] ?? 'normal'} • ${data['status'] ?? 'open'}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _SupportConversationPage(
                              ticketId: ticket.id,
                              ticket: data,
                              user: user,
                              systemOwner: systemOwner,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editWelcomeMessage(BuildContext context) async {
    final controller = TextEditingController();
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Support welcome message'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'Message shown to business owners',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (save == true && controller.text.trim().isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('system_settings')
          .doc('support')
          .set({
            'welcomeMessage': controller.text.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    }
  }
}

class _AiSupportChatPage extends StatefulWidget {
  final User user;
  const _AiSupportChatPage({required this.user});

  @override
  State<_AiSupportChatPage> createState() => _AiSupportChatPageState();
}

class _AiSupportChatPageState extends State<_AiSupportChatPage> {
  final input = TextEditingController();
  final messages = <Map<String, String>>[
    {
      'role': 'model',
      'text':
          'Hello! I can explain how to use POS, stock, purchases, accounts, payroll, delivery, reports, permissions, and other system features. You can still open a human support ticket at any time.',
    },
  ];
  bool sending = false;

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || sending) return;
    setState(() {
      messages.add({'role': 'user', 'text': text});
      input.clear();
      sending = true;
    });
    try {
      final response = await AiService.instance.supportChat(text, messages);
      if (mounted) {
        setState(() => messages.add({'role': 'model', 'text': response}));
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => messages.add({
            'role': 'model',
            'text':
                'AI support is unavailable right now. Please create a human support ticket. ($e)',
          }),
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('AI System Support'),
      actions: [
        TextButton.icon(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => _NewSupportTicketDialog(user: widget.user),
          ),
          icon: const Icon(Icons.support_agent),
          label: const Text('Human support'),
        ),
      ],
    ),
    body: Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final message = messages[index];
              final userMessage = message['role'] == 'user';
              return Align(
                alignment: userMessage
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Card(
                  color: userMessage
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 650),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(message['text'] ?? ''),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (sending) const LinearProgressIndicator(),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    onSubmitted: (_) => send(),
                    decoration: const InputDecoration(
                      hintText: 'Ask how to use the system…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: sending ? null : send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _SupportAvailabilityHeader extends StatelessWidget {
  const _SupportAvailabilityHeader();
  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance
        .collection('system_settings')
        .doc('support')
        .snapshots(),
    builder: (context, messageSnapshot) =>
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .where('role', isEqualTo: UserRole.systemOwner)
              .snapshots(),
          builder: (context, userSnapshot) {
            final cutoff = DateTime.now().subtract(const Duration(minutes: 5));
            final online = (userSnapshot.data?.docs ?? const []).where((doc) {
              final seen = doc.data()['lastSeen'];
              return doc.data()['isOnline'] == true &&
                  seen is Timestamp &&
                  seen.toDate().isAfter(cutoff);
            }).length;
            return Card(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: ListTile(
                leading: const Icon(Icons.support_agent),
                title: Text(
                  messageSnapshot.data?.data()?['welcomeMessage'] ??
                      'Welcome to our support team. How can we help?',
                ),
                subtitle: Text(
                  online > 0
                      ? '$online support agent${online == 1 ? '' : 's'} online'
                      : 'Support is offline; leave a message.',
                ),
                trailing: Icon(
                  Icons.circle,
                  size: 12,
                  color: online > 0 ? Colors.green : Colors.grey,
                ),
              ),
            );
          },
        ),
  );
}

class _NewSupportTicketDialog extends StatefulWidget {
  final User user;
  const _NewSupportTicketDialog({required this.user});
  @override
  State<_NewSupportTicketDialog> createState() =>
      _NewSupportTicketDialogState();
}

class _NewSupportTicketDialogState extends State<_NewSupportTicketDialog> {
  final _subject = TextEditingController();
  final _message = TextEditingController();
  String _priority = 'normal';
  Future<void> _save() async {
    if (_subject.text.trim().isEmpty || _message.text.trim().isEmpty) return;
    final firestore = FirebaseFirestore.instance;
    final businessId = widget.user.businessId ?? 'default_business';
    final business = await firestore
        .collection('businesses')
        .doc(businessId)
        .get();
    final ticket = firestore.collection('support_tickets').doc();
    final message = ticket.collection('messages').doc();
    final batch = firestore.batch();
    batch.set(ticket, {
      'id': ticket.id,
      'businessId': businessId,
      'businessName': business.data()?['name'] ?? 'Business',
      'ownerId': widget.user.id,
      'subject': _subject.text.trim(),
      'priority': _priority,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(message, {
      'id': message.id,
      'senderId': widget.user.id,
      'senderName': widget.user.name,
      'senderRole': widget.user.role,
      'message': _message.text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New support ticket'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _subject,
            decoration: const InputDecoration(labelText: 'Subject'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _priority,
            items: const [
              'low',
              'normal',
              'high',
              'urgent',
            ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => setState(() => _priority = v!),
            decoration: const InputDecoration(labelText: 'Priority'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _message,
            minLines: 4,
            maxLines: 7,
            decoration: const InputDecoration(
              labelText: 'Describe the problem',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Send')),
    ],
  );
}

class _SupportConversationPage extends StatefulWidget {
  final String ticketId;
  final Map<String, dynamic> ticket;
  final User user;
  final bool systemOwner;
  const _SupportConversationPage({
    required this.ticketId,
    required this.ticket,
    required this.user,
    required this.systemOwner,
  });
  @override
  State<_SupportConversationPage> createState() =>
      _SupportConversationPageState();
}

class _SupportConversationPageState extends State<_SupportConversationPage> {
  final _message = TextEditingController();
  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty) return;
    _message.clear();
    final ticket = FirebaseFirestore.instance
        .collection('support_tickets')
        .doc(widget.ticketId);
    await ticket.collection('messages').add({
      'senderId': widget.user.id,
      'senderName': widget.user.name,
      'senderRole': widget.user.role,
      'message': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await ticket.update({
      'updatedAt': FieldValue.serverTimestamp(),
      if (widget.systemOwner) 'status': 'in_progress',
    });
  }

  Future<void> _close() => FirebaseFirestore.instance
      .collection('support_tickets')
      .doc(widget.ticketId)
      .update({'status': 'closed', 'updatedAt': FieldValue.serverTimestamp()});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.ticket['subject'] ?? 'Support'),
      actions: [
        if (widget.systemOwner)
          IconButton(
            tooltip: 'Close ticket',
            onPressed: _close,
            icon: const Icon(Icons.task_alt),
          ),
      ],
    ),
    body: Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('support_tickets')
                .doc(widget.ticketId)
                .collection('messages')
                .snapshots(),
            builder: (context, snapshot) {
              final messages = snapshot.data?.docs.toList() ?? [];
              messages.sort(
                (a, b) => _date(
                  a.data()['createdAt'],
                ).compareTo(_date(b.data()['createdAt'])),
              );
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: messages.length,
                itemBuilder: (_, index) {
                  final data = messages[index].data();
                  final mine = data['senderId'] == widget.user.id;
                  return Align(
                    alignment: mine
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Card(
                      color: mine
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data['senderName'] ?? 'User',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(data['message'] ?? ''),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _message,
                    decoration: const InputDecoration(
                      hintText: 'Write a message…',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

DateTime _date(dynamic value) => value is Timestamp
    ? value.toDate()
    : DateTime.fromMillisecondsSinceEpoch(0);
