import 'dart:typed_data';

import 'package:camera_face_analysis/face_detection_controller.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class FaceDetectionPage extends StatefulWidget {
  @override
  _FaceDetectionPageState createState() => _FaceDetectionPageState();
}

class _FaceDetectionPageState extends State<FaceDetectionPage> {
  late FaceDetectionController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller =
        FaceDetectionController()
          ..onImageCaptured = (file) {
            // Handle captured image
          };

    _initializeController();
  }

  Future<void> _initializeController() async {
    await _controller.initialize();
    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Face Detection')),
      body:
          _isInitialized
              ? Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        CameraPreview(_controller.cameraController),
                        ValueListenableBuilder<Rect?>(
                          valueListenable: _controller.faceRect,
                          builder: (context, rect, child) {
                            if (rect == null) return SizedBox.shrink();
                            return Positioned(
                              left: rect.left,
                              top: rect.top,
                              width: rect.width,
                              height: rect.height,
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.green,
                                    width: 3,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        ValueListenableBuilder<String>(
                          valueListenable: _controller.skinTone,
                          builder:
                              (context, value, child) =>
                                  Text('Skin Tone: $value'),
                        ),
                        ValueListenableBuilder<double>(
                          valueListenable: _controller.faceBrightness,
                          builder:
                              (context, value, child) => Text(
                                'Face Brightness: ${value.toStringAsFixed(2)}',
                              ),
                        ),
                        ValueListenableBuilder<double>(
                          valueListenable: _controller.envBrightness,
                          builder:
                              (context, value, child) => Text(
                                'Environment Brightness: ${value.toStringAsFixed(2)}',
                              ),
                        ),
                        ValueListenableBuilder<double>(
                          valueListenable: _controller.acneLevel,
                          builder:
                              (context, value, child) => Text(
                                'Acne Level: ${value.toStringAsFixed(2)}%',
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
              : const Center(child: CircularProgressIndicator()),
    );
  }
}
