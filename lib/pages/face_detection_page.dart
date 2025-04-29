import 'dart:typed_data';

import 'package:camera_face_analysis/face_detection_controller.dart';
import 'package:camera_face_analysis/face_detection_controller2.dart';
import 'package:camera_face_analysis/logic/detector_view.dart';
import 'package:camera_face_analysis/logic/face_detector_painter.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceDetectionPage extends StatefulWidget {
  @override
  _FaceDetectionPageState createState() => _FaceDetectionPageState();
}

class _FaceDetectionPageState extends State<FaceDetectionPage> {
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(enableContours: true, enableLandmarks: true),
  );
  bool _canProcess = true;
  bool _isBusy = false;
  CustomPaint? _customPaint;
  String? _text;
  var _cameraLensDirection = CameraLensDirection.front;

  late FaceDetectionController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller =
        FaceDetectionController()
          ..onImageCaptured = (file) {
            // Handle captured image
            print('on captured image');
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
    _canProcess = false;
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Face Detection')),
      body:
          _isInitialized
              ? SingleChildScrollView(
                child: Column(
                  children: [
                    SizedBox(
                      height: 300,
                      width: MediaQuery.of(context).size.width,
                      child: DetectorView(
                        title: 'Face Detector',
                        customPaint: _customPaint,
                        text: _text,
                        onImage: _processImage,
                        initialCameraLensDirection: _cameraLensDirection,
                        onCameraLensDirectionChanged:
                            (value) => _cameraLensDirection = value,
                      ),
                    ),

                    /*Stack(
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
                    ),*/
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          /*FutureBuilder(
                            future: _controller.processCameraImage(image),
                            builder: (context, snapshot) {
                              return Container();
                            },
                          ),*/
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
                ),
              )
              : const Center(child: CircularProgressIndicator()),
    );
  }

  Future<void> _processImage(InputImage inputImage) async {
    if (!_canProcess) return;
    if (_isBusy) return;
    _isBusy = true;
    setState(() {
      _text = '';
    });
    final faces = await _faceDetector.processImage(inputImage);
    if (inputImage.metadata?.size != null &&
        inputImage.metadata?.rotation != null) {
      final painter = FaceDetectorPainter(
        faces,
        inputImage.metadata!.size,
        inputImage.metadata!.rotation,
        _cameraLensDirection,
      );
      _customPaint = CustomPaint(painter: painter);
    } else {
      String text = 'Faces found: ${faces.length}\n\n';
      for (final face in faces) {
        text += 'face: ${face.boundingBox}\n\n';
      }
      _text = text;
      // TODO: set _customPaint to draw boundingRect on top of image
      _customPaint = null;
    }
    _isBusy = false;
    if (mounted) {
      setState(() {});
    }
  }
}
