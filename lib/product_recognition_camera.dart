import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'app_loading_indicator.dart';

import 'ai_service.dart';

class ProductRecognitionCamera extends StatefulWidget {
  final List<String> productNames;
  const ProductRecognitionCamera({super.key, required this.productNames});

  @override
  State<ProductRecognitionCamera> createState() =>
      _ProductRecognitionCameraState();
}

class _ProductRecognitionCameraState extends State<ProductRecognitionCamera> {
  CameraController? controller;
  String? error;
  bool recognizing = false;

  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception('No camera was found.');
      final camera =
          cameras
              .where((item) => item.lensDirection == CameraLensDirection.front)
              .firstOrNull ??
          cameras.first;
      final next = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await next.initialize();
      if (!mounted) return next.dispose();
      setState(() => controller = next);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> recognize() async {
    final camera = controller;
    if (camera == null || recognizing) return;
    setState(() => recognizing = true);
    try {
      final image = await camera.takePicture();
      final result = await AiService.instance.recognizeProduct(
        await image.readAsBytes(),
        mimeType: 'image/jpeg',
        productNames: widget.productNames,
      );
      final query =
          (result['searchQuery'] ??
                  result['productName'] ??
                  result['detectedText'] ??
                  '')
              .toString()
              .trim();
      if (!mounted) return;
      if (query.isEmpty) throw Exception('No product could be recognized.');
      Navigator.pop(context, query);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        recognizing = false;
        error = 'Could not recognize product: $e';
      });
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI Product Camera')),
    body: Column(
      children: [
        Expanded(
          child: controller == null
              ? Center(
                  child: error == null
                      ? const ModernLoadingIndicator()
                      : Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(error!, textAlign: TextAlign.center),
                        ),
                )
              : Center(
                  child: AspectRatio(
                    aspectRatio: controller!.value.aspectRatio,
                    child: CameraPreview(controller!),
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text(
                'Place the product and visible label in the frame. AI will convert the image into a product search; you choose the result manually.',
                textAlign: TextAlign.center,
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: controller == null || recognizing ? null : recognize,
                icon: recognizing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: ModernLoadingIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.camera_alt),
                label: Text(
                  recognizing ? 'Recognizing…' : 'Capture and recognize',
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
