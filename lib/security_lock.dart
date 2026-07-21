import 'dart:convert';
import 'dart:io' show Platform;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_loading_indicator.dart';

class SecurityLock extends StatefulWidget {
  final String userId;
  final Widget child;
  const SecurityLock({super.key, required this.userId, required this.child});

  @override
  State<SecurityLock> createState() => _SecurityLockState();
}

class _SecurityLockState extends State<SecurityLock> {
  final pin = TextEditingController();
  final confirmPin = TextEditingController();
  final biometrics = LocalAuthentication();
  bool loading = true;
  bool locked = true;
  bool setup = false;
  String? error;
  late String pinKey;

  @override
  void initState() {
    super.initState();
    pinKey = 'security_pin_${widget.userId}';
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setup = prefs.getString(pinKey) == null;
    if (mounted) setState(() => loading = false);
    if (!setup) _useBiometric(silent: true);
  }

  String _hash(String value) =>
      sha256.convert(utf8.encode('${widget.userId}:$value')).toString();

  Future<void> _saveOrUnlock() async {
    final value = pin.text.trim();
    if (!RegExp(r'^\d{4}$').hasMatch(value)) {
      setState(() => error = 'Enter exactly four digits.');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (setup) {
      if (value != confirmPin.text.trim()) {
        setState(() => error = 'PIN confirmation does not match.');
        return;
      }
      await prefs.setString(pinKey, _hash(value));
      setup = false;
      locked = false;
    } else if (prefs.getString(pinKey) == _hash(value)) {
      locked = false;
    } else {
      error = 'Incorrect PIN.';
    }
    pin.clear();
    confirmPin.clear();
    if (mounted) setState(() {});
  }

  Future<void> _useBiometric({bool silent = false}) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      if (!await biometrics.canCheckBiometrics &&
          !await biometrics.isDeviceSupported())
        return;
      final ok = await biometrics.authenticate(
        localizedReason: 'Unlock the POS securely',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (ok && mounted) setState(() => locked = false);
    } on PlatformException catch (e) {
      if (!silent && mounted)
        setState(
          () => error = e.message ?? 'Fingerprint unlock is unavailable.',
        );
    }
  }

  @override
  void dispose() {
    pin.dispose();
    confirmPin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading)
      return const Scaffold(body: Center(child: ModernLoadingIndicator()));
    return Stack(
      children: [
        widget.child,
        if (!locked)
          Positioned(
            right: 18,
            bottom: 18,
            child: FloatingActionButton.small(
              heroTag: 'security-lock',
              tooltip: 'Lock screen',
              onPressed: () => setState(() => locked = true),
              child: const Icon(Icons.lock_outline),
            ),
          ),
        if (locked)
          Positioned.fill(
            child: Material(
              color: const Color(0xFF080808),
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 380),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                setup ? Icons.pin_outlined : Icons.lock,
                                size: 52,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                setup ? 'Create security PIN' : 'POS locked',
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                setup
                                    ? 'Choose a four-digit PIN for this account on this device.'
                                    : 'Your session remains signed in. Enter your PIN to continue.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 18),
                              TextField(
                                controller: pin,
                                autofocus: true,
                                obscureText: true,
                                maxLength: 4,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                onSubmitted: (_) => _saveOrUnlock(),
                                decoration: const InputDecoration(
                                  labelText: '4-digit PIN',
                                  counterText: '',
                                ),
                              ),
                              if (setup) ...[
                                const SizedBox(height: 12),
                                TextField(
                                  controller: confirmPin,
                                  obscureText: true,
                                  maxLength: 4,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  onSubmitted: (_) => _saveOrUnlock(),
                                  decoration: const InputDecoration(
                                    labelText: 'Confirm PIN',
                                    counterText: '',
                                  ),
                                ),
                              ],
                              if (error != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Text(
                                    error!,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: _saveOrUnlock,
                                  child: Text(setup ? 'Save PIN' : 'Unlock'),
                                ),
                              ),
                              if (!setup && !kIsWeb && Platform.isAndroid)
                                TextButton.icon(
                                  onPressed: _useBiometric,
                                  icon: const Icon(Icons.fingerprint),
                                  label: const Text('Use fingerprint'),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
