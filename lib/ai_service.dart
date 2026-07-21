import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';

class AiService {
  AiService._();
  static final instance = AiService._();
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Future<String> businessAdvice(Map<String, dynamic> context) async {
    final result = await _functions
        .httpsCallable('aiBusinessAdvice')
        .call<Map<String, dynamic>>({'context': context});
    return result.data['text']?.toString() ?? 'No advice available.';
  }

  Future<String> supportChat(
    String message,
    List<Map<String, String>> history,
  ) async {
    final result = await _functions
        .httpsCallable('aiSupportChat')
        .call<Map<String, dynamic>>({'message': message, 'history': history});
    return result.data['text']?.toString() ?? 'No response available.';
  }

  Future<Map<String, dynamic>> recognizeProduct(
    Uint8List bytes, {
    required String mimeType,
    required List<String> productNames,
  }) async {
    final result = await _functions
        .httpsCallable('recognizeProductImage')
        .call<Map<String, dynamic>>({
          'imageBase64': base64Encode(bytes),
          'mimeType': mimeType,
          'productNames': productNames,
        });
    return result.data;
  }
}
