import 'dart:io';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NotificationService {
  static String? _activeUser;
  static Timer? _presenceTimer;

  static Future<void> register(String userId) async {
    if (_activeUser == userId) return;
    if (!kIsWeb &&
        !(Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
      return;
    }
    _activeUser = userId;
    await FirebaseFirestore.instance.collection('users').doc(userId).set({
      'isOnline': true,
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _presenceTimer?.cancel();
    _presenceTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      FirebaseFirestore.instance.collection('users').doc(userId).set({
        'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    final token = await messaging.getToken();
    if (token != null) await _saveToken(userId, token);
    messaging.onTokenRefresh.listen((token) => _saveToken(userId, token));
    FirebaseMessaging.onMessage.listen((message) {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.vibrate();
    });
  }

  static Future<void> _saveToken(String userId, String token) =>
      FirebaseFirestore.instance.collection('users').doc(userId).set({
        'fcmTokens': FieldValue.arrayUnion([token]),
        'notificationsEnabled': true,
      }, SetOptions(merge: true));
}
