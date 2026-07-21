import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WindowsLocationConsent extends StatefulWidget {
  final Widget child;
  const WindowsLocationConsent({super.key, required this.child});

  @override
  State<WindowsLocationConsent> createState() => _WindowsLocationConsentState();
}

class _WindowsLocationConsentState extends State<WindowsLocationConsent> {
  bool loading = true;
  bool allowed = false;
  String? error;

  bool get applies => !kIsWeb && Platform.isWindows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!applies) {
      allowed = true;
    } else {
      final prefs = await SharedPreferences.getInstance();
      allowed = prefs.getBool('windows_location_consent') == true;
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _allow() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Turn on Windows Location Services, then try again.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied)
        permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception(
          'Location permission is required. Enable it in Windows Settings > Privacy & security > Location.',
        );
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('windows_location_consent', true);
      allowed = true;
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (allowed) return widget.child;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.location_on_outlined, size: 64),
                  const SizedBox(height: 14),
                  Text(
                    'Location permission required',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'The Windows POS uses location for delivery addresses, branch positioning, and delivery tracking. Your location is used only for these business features.',
                    textAlign: TextAlign.center,
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: loading ? null : _allow,
                    icon: const Icon(Icons.location_on),
                    label: Text(loading ? 'Checking…' : 'Allow location'),
                  ),
                  TextButton(
                    onPressed: Geolocator.openLocationSettings,
                    child: const Text('Open Windows location settings'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
