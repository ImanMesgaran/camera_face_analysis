import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:typed_data';

class CustomFaceDetectionView extends StatefulWidget {
  final void Function(CameraImage image) onImageAvailable;
  final CameraLensDirection initialDirection;
  final CameraController cameraController;
  // final ValueNotifier<CameraImage> onCameraImage;
  final CustomPaint? customPaint;
  final ValueNotifier<CustomPainter?> painter;

  CustomFaceDetectionView({
    required this.cameraController,
    required this.onImageAvailable,
    this.initialDirection = CameraLensDirection.front,
    // required this.onCameraImage,
    required this.customPaint,
    super.key,
    required this.painter,
  });

  @override
  State<CustomFaceDetectionView> createState() =>
      _CustomFaceDetectionViewState();
}

class _CustomFaceDetectionViewState extends State<CustomFaceDetectionView> {
  late List<CameraDescription> _cameras;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    _cameras = await availableCameras();
    final cam = _cameras.firstWhere(
      (c) => c.lensDirection == widget.initialDirection,
    );
    /*
    _controller = CameraController(
      cam,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    */

    // await widget.cameraController.initialize();
    // await widget.cameraController.startImageStream((CameraImage image) {
    //   widget.onImageAvailable(image);
    // });

    setState(() {
      _isInitialized = true;
    });
  }

  @override
  void dispose() {
    // _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return CameraPreview(widget.cameraController, child: widget.customPaint);
  }
}
