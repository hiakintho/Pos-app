import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/material.dart';

String? strongPasswordError(String password) {
  if (password.length < 10) return 'Use at least 10 characters';
  if (!RegExp(r'[A-Z]').hasMatch(password)) return 'Add an uppercase letter';
  if (!RegExp(r'[a-z]').hasMatch(password)) return 'Add a lowercase letter';
  if (!RegExp(r'[0-9]').hasMatch(password)) return 'Add a number';
  if (!RegExp(r'[^A-Za-z0-9]').hasMatch(password)) return 'Add a symbol';
  return null;
}

class EmailVerificationPage extends StatefulWidget {
  const EmailVerificationPage({super.key});

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  bool busy = false;

  Future<void> _send() async {
    setState(() => busy = true);
    try {
      await auth.FirebaseAuth.instance.currentUser?.sendEmailVerification();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Verification email sent. Open the link, then return here.',
            ),
          ),
        );
    } on auth.FirebaseAuthException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? 'Could not send verification email.'),
          ),
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _check() async {
    setState(() => busy = true);
    await auth.FirebaseAuth.instance.currentUser?.reload();
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      actions: [
        IconButton(
          tooltip: 'Logout',
          onPressed: () => auth.FirebaseAuth.instance.signOut(),
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.mark_email_read_outlined, size: 64),
                const SizedBox(height: 16),
                Text(
                  'Verify your email',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                Text(
                  'We sent a secure verification link to ${auth.FirebaseAuth.instance.currentUser?.email ?? 'your email'}. Firebase email authentication uses a verification link rather than a numeric OTP.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: busy ? null : _check,
                  child: const Text('I have verified my email'),
                ),
                TextButton(
                  onPressed: busy ? null : _send,
                  child: const Text('Resend verification email'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
