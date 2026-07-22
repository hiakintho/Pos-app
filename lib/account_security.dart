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
