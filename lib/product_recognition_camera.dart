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
  List<CameraDescription> cameras = const [];
  int activeCameraIndex = 0;
  String? error;
  bool recognizing = false, switchingCamera = false;

  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    try {
      cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception('No camera was found.');
      activeCameraIndex = cameras.indexWhere(
        (item) => item.lensDirection == CameraLensDirection.back,
      );
      if (activeCameraIndex < 0) activeCameraIndex = 0;
      await _startCamera(cameras[activeCameraIndex]);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> _startCamera(CameraDescription camera) async {
    final previous = controller;
    if (mounted) {
      setState(() {
        controller = null;
        error = null;
      });
    }
    await previous?.dispose();
    final next = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await next.initialize();
      if (!mounted) return next.dispose();
      setState(() => controller = next);
    } catch (e) {
      await next.dispose();
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> switchCamera() async {
    if (switchingCamera || cameras.length < 2) return;
    final currentDirection = cameras[activeCameraIndex].lensDirection;
    var nextIndex = cameras.indexWhere(
      (camera) =>
          camera.lensDirection != currentDirection &&
          (camera.lensDirection == CameraLensDirection.front ||
              camera.lensDirection == CameraLensDirection.back),
    );
    if (nextIndex < 0) nextIndex = (activeCameraIndex + 1) % cameras.length;
    setState(() => switchingCamera = true);
    activeCameraIndex = nextIndex;
    await _startCamera(cameras[activeCameraIndex]);
    if (mounted) setState(() => switchingCamera = false);
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
      if (query.isEmpty)
        throw Exception(
          'Smart Camera did not recognize a product. Try again with the label clearly visible.',
        );
      Navigator.pop(context, query);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        recognizing = false;
        error = 'Smart Camera did not recognize the product: $e';
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
    appBar: AppBar(
      title: const Text('Smart Product Camera'),
      actions: [
        if (cameras.length > 1)
          IconButton(
            tooltip: 'Switch front/rear camera',
            onPressed: recognizing || switchingCamera ? null : switchCamera,
            icon: const Icon(Icons.cameraswitch),
          ),
      ],
    ),
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
                'Place the product and visible label in the frame. Smart Camera will create a search; you choose the correct result manually.',
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
