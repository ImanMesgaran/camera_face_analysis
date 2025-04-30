import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:typed_data';

class CustomFaceDetectionView extends StatefulWidget {
  final void Function(CameraImage image) onImageAvailable;
  final CameraLensDirection initialDirection;

  const CustomFaceDetectionView({
    required this.onImageAvailable,
    this.initialDirection = CameraLensDirection.front,
    super.key,
  });

  @override
  State<CustomFaceDetectionView> createState() =>
      _CustomFaceDetectionViewState();
}

class _CustomFaceDetectionViewState extends State<CustomFaceDetectionView> {
  CameraController? _controller;
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
    _controller = CameraController(
      cam,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _controller!.initialize();
    await _controller!.startImageStream((CameraImage image) {
      widget.onImageAvailable(image);
    });

    setState(() {
      _isInitialized = true;
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return CameraPreview(_controller!);
  }
}
