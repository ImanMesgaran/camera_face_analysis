import 'dart:async';
import 'dart:typed_data';

import 'package:camera_face_analysis/face_detection_controller.dart';
import 'package:camera_face_analysis/face_detection_controller2.dart';
import 'package:camera_face_analysis/logic/detector_view.dart';
import 'package:camera_face_analysis/logic/face_detector_painter.dart';
import 'package:camera_face_analysis/pages/custom_face_detection_view.dart';
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
  final ValueNotifier<CustomPaint?> _customPaint = ValueNotifier(null);
  String? _text;
  var _cameraLensDirection = CameraLensDirection.front;

  late FaceDetectionController _faceDetectionController;
  bool _isInitialized = false;
  //late Future<void> _initializationFuture;

  @override
  void initState() {
    super.initState();
    _faceDetectionController =
        FaceDetectionController()
          ..onImageCaptured = (file) {
            // Handle captured image
            print('on captured image');
          };

    _initialize();
    //_initializeController();
    //_initializationFuture = _initialize();
    _faceDetectionController.imageStreamController =
        StreamController<CameraImage>.broadcast();

    _faceDetectionController.imageStreamController.stream.listen(
      (image) async {
        await _processCameraImage(image);
      },
      onError: (value) {
        print('this is the on error: $value');
      },
      cancelOnError: false,
    );
  }

  Future<void> _initialize() async {
    await Future.delayed(const Duration(milliseconds: 300));
    await _initializeController();
  }

  Future<void> _initializeController() async {
    await _faceDetectionController.initialize();
    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  @override
  void dispose() {
    _faceDetectionController.dispose();
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
                    /*
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
                    */

                    /*
                    FutureBuilder<void>(
                      future: _initializationFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        } else if (snapshot.hasError) {
                          return Center(
                            child: Text('Error: ${snapshot.error}'),
                          );
                        } else if (snapshot.hasData) {
                          return CustomFaceDetectionView(
                            onImageAvailable: _processCameraImage,
                            initialDirection: CameraLensDirection.front,
                          );
                        } else {
                          return Center(child: CircularProgressIndicator());
                        }
                      },
                    ),
                    */
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
                    /*
                    CustomFaceDetectionView(
                      cameraController:
                          _faceDetectionController.cameraController,
                      onImageAvailable: (image) async {
                        // _faceDetectionController.initialize();
                        _faceDetectionController.processCameraImage(image);
                        _processCameraImage(image);
                      },
                      customPaint: _customPaint,
                      painter: _faceDetectionController.facePainter,
                    ),
                    */
                    Stack(
                      //fit: StackFit.expand,
                      children: [
                        CameraPreview(
                          _faceDetectionController.cameraController,
                        ),
                        ValueListenableBuilder<CustomPainter?>(
                          valueListenable: _faceDetectionController.facePainter,
                          builder: (_, painter, __) {
                            return SizedBox(
                              height: 400,
                              width: double.infinity,
                              child: CustomPaint(painter: painter),
                            );
                          },
                        ),
                      ],
                    ),

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
                            valueListenable: _faceDetectionController.skinTone,
                            builder:
                                (context, value, child) =>
                                    Text('Skin Tone: $value'),
                          ),
                          ValueListenableBuilder<double>(
                            valueListenable:
                                _faceDetectionController.faceBrightness,
                            builder:
                                (context, value, child) => Text(
                                  'Face Brightness: ${value.toStringAsFixed(2)}',
                                ),
                          ),
                          ValueListenableBuilder<double>(
                            valueListenable:
                                _faceDetectionController.envBrightness,
                            builder:
                                (context, value, child) => Text(
                                  'Environment Brightness: ${value.toStringAsFixed(2)}',
                                ),
                          ),
                          ValueListenableBuilder<double>(
                            valueListenable: _faceDetectionController.acneLevel,
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

  Future<void> _processCameraImage(CameraImage cameraImage) async {
    if (!_canProcess) return;
    if (_isBusy) return;
    _isBusy = true;
    setState(() {
      _text = '';
    });
    final inputImage = await _faceDetectionController
        .convertCameraImageToInputImage(
          cameraImage,
          _faceDetectionController.cameraController.description,
        );

    final faces = await _faceDetector.processImage(inputImage);
    if (inputImage.metadata?.size != null &&
        inputImage.metadata?.rotation != null) {
      final painter = FaceDetectorPainter(
        faces,
        inputImage.metadata!.size,
        inputImage.metadata!.rotation,
        _cameraLensDirection,
      );

      setState(() {
        _customPaint.value = CustomPaint(painter: painter);
      });
    } else {
      String text = 'Faces found: ${faces.length}\n\n';
      for (final face in faces) {
        text += 'face: ${face.boundingBox}\n\n';
      }
      _text = text;
      // TODO: set _customPaint to draw boundingRect on top of image
      _customPaint.value = null;
    }
    _isBusy = false;
    if (mounted) {
      setState(() {});
    }
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
      _customPaint.value = CustomPaint(painter: painter);
    } else {
      String text = 'Faces found: ${faces.length}\n\n';
      for (final face in faces) {
        text += 'face: ${face.boundingBox}\n\n';
      }
      _text = text;
      // TODO: set _customPaint to draw boundingRect on top of image
      _customPaint.value = null;
    }
    _isBusy = false;
    if (mounted) {
      setState(() {});
    }
  }
}
