import 'dart:typed_data';

import 'package:camera_face_analysis/FaceCapturePage.dart';
import 'package:camera_face_analysis/face_detection_controller.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class FaceDetectionPage extends StatefulWidget {
  @override
  _FaceDetectionPageState createState() => _FaceDetectionPageState();
}

class _FaceDetectionPageState extends State<FaceDetectionPage> {
  late FaceDetectionController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        FaceDetectionController()
          ..onFaceCaptured = (Uint8List croppedFace) {
            // Handle the face capture logic here (e.g., showing the image or processing it)
            setState(() {
              // Optionally update the UI based on the captured face (croppedFace)
            });
          };

    // Initialize the face detection controller
    _controller.initialize().then((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
    _controller.dispose(); // Don't forget to dispose of the controller
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Face Detection')),
      body:
          _controller.cameraController.value.isInitialized
              ? Column(
                children: [
                  // Display the live camera feed
                  Expanded(child: CameraPreview(_controller.cameraController)),
                  // Display detected face details
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Text('Skin Tone: ${_controller.skinTone}'),
                        Text('Face Brightness: ${_controller.faceBrightness}'),
                        Text(
                          'Environment Brightness: ${_controller.envBrightness}',
                        ),
                        Text('Acne Level: ${_controller.acneLevel}'),
                      ],
                    ),
                  ),
                ],
              )
              : Center(child: CircularProgressIndicator()),
    );
  }
}
