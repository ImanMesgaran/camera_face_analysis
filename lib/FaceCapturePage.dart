// // face_detection_controller.dart

// import 'dart:async';
// import 'dart:isolate';
// import 'dart:typed_data';
// import 'dart:ui' as ui;
// import 'package:camera/camera.dart';
// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
// import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// import 'package:image/image.dart' as img;
// import 'package:tflite_flutter/tflite_flutter.dart';

// class FaceDetectionController {
//   late CameraController _cameraController;
//   final FaceDetector _faceDetector;
//   Interpreter? _acneInterpreter;
//   bool _isProcessing = false;
//   late List<CameraDescription> _cameras;
//   Function(Uint8List croppedFace)? onFaceCaptured;
//   int _stableCounter = 0;
//   final int _stableThreshold = 90; // about 3 seconds at 30fps

//   double envBrightness = 0.0;
//   double faceBrightness = 0.0;
//   double acneLevel = 0.0;
//   String skinTone = 'Unknown';

//   Face? _lastFace;
//   Rect? _lastFaceRect;
//   Size? _imageSize;

//   FaceDetectionController()
//     : _faceDetector = FaceDetector(
//         options: FaceDetectorOptions(
//           performanceMode: FaceDetectorMode.fast,
//           enableContours: true,
//         ),
//       );

//   Future<void> initialize() async {
//     _cameras = await availableCameras();
//     final frontCamera = _cameras.firstWhere(
//       (camera) => camera.lensDirection == CameraLensDirection.front,
//     );

//     _cameraController = CameraController(
//       frontCamera,
//       ResolutionPreset.medium,
//       enableAudio: false,
//       imageFormatGroup: ImageFormatGroup.yuv420,
//     );

//     await _cameraController.initialize();
//     _cameraController.startImageStream(_processCameraImage);
//     await _loadAcneModel();
//   }

//   Future<void> _loadAcneModel() async {
//     try {
//       _acneInterpreter = await Interpreter.fromAsset('acne_model.tflite');
//     } catch (e) {
//       debugPrint('Acne model load failed: $e');
//     }
//   }

//   CameraController get cameraController => _cameraController;

//   void dispose() {
//     _faceDetector.close();
//     _cameraController.dispose();
//     _acneInterpreter?.close();
//   }

//   void _processCameraImage(CameraImage image) async {
//     if (_isProcessing) return;
//     _isProcessing = true;

//     final WriteBuffer allBytes = WriteBuffer();
//     for (Plane plane in image.planes) {
//       allBytes.putUint8List(plane.bytes);
//     }
//     final bytes = allBytes.done().buffer.asUint8List();

//     _imageSize = Size(image.width.toDouble(), image.height.toDouble());

//     final inputImage = InputImage.fromBytes(
//       bytes: bytes,
//       metadata: InputImageMetadata(
//         size: _imageSize!,
//         rotation: InputImageRotation.rotation0deg,
//         format: InputImageFormat.yuv_420_888,
//         bytesPerRow: image.planes[0].bytesPerRow,
//       ),
//     );

//     final faces = await _faceDetector.processImage(inputImage);

//     if (faces.isNotEmpty) {
//       final face = faces.first;
//       final boundingBox = face.boundingBox;

//       bool centered = _isFaceCentered(boundingBox, _imageSize!);

//       if (centered) {
//         _stableCounter++;
//         if (_stableCounter > _stableThreshold) {
//           await _capturePhoto(image, boundingBox);
//           _stableCounter = 0;
//         }
//       } else {
//         _stableCounter = 0;
//       }

//       _lastFace = face;
//       _lastFaceRect = boundingBox;

//       compute(_calculateBrightness, {
//         'image': image,
//         'boundingBox': boundingBox,
//       }).then((results) {
//         envBrightness = results['env']!;
//         faceBrightness = results['face']!;
//         _classifySkinTone();
//       });
//     } else {
//       _stableCounter = 0;
//       _lastFace = null;
//       _lastFaceRect = null;
//     }

//     _isProcessing = false;
//   }

//   bool _isFaceCentered(Rect faceRect, Size imageSize) {
//     final centerX = imageSize.width / 2;
//     final centerY = imageSize.height / 2;
//     final faceCenterX = faceRect.center.dx;
//     final faceCenterY = faceRect.center.dy;

//     const double tolerance = 50.0;

//     return (faceCenterX - centerX).abs() < tolerance &&
//         (faceCenterY - centerY).abs() < tolerance;
//   }

//   Future<void> _capturePhoto(CameraImage image, Rect boundingBox) async {
//     final croppedFace = await _cropFace(image, boundingBox);
//     if (croppedFace != null) {
//       // Here you could call TFLite model
//       onFaceCaptured?.call(croppedFace);
//     }
//   }

//   Future<Uint8List?> _cropFace(CameraImage image, Rect boundingBox) async {
//     try {
//       final width = image.width;
//       final height = image.height;

//       final img.Image converted = _convertYUV420toImage(image);

//       final faceImage = img.copyCrop(
//         converted,
//         x: boundingBox.left.toInt().clamp(0, width - 1),
//         y: boundingBox.top.toInt().clamp(0, height - 1),
//         width: boundingBox.width.toInt().clamp(
//           1,
//           width - boundingBox.left.toInt(),
//         ),
//         height: boundingBox.height.toInt().clamp(
//           1,
//           height - boundingBox.top.toInt(),
//         ),
//       );

//       return Uint8List.fromList(img.encodeJpg(faceImage));
//     } catch (e) {
//       debugPrint('Failed to crop face: $e');
//       return null;
//     }
//   }

//   img.Image _convertYUV420toImage(CameraImage image) {
//     final int width = image.width;
//     final int height = image.height;
//     final img.Image imgBuffer = img.Image(width: width, height: height);

//     for (int y = 0; y < height; y++) {
//       for (int x = 0; x < width; x++) {
//         final int uvIndex = (y ~/ 2) * (width ~/ 2) + (x ~/ 2);
//         final int index = y * width + x;

//         final yp = image.planes[0].bytes[index];
//         final up = image.planes[1].bytes[uvIndex];
//         final vp = image.planes[2].bytes[uvIndex];

//         final r = (yp + (1.370705 * (vp - 128))).clamp(0, 255).toInt();
//         final g =
//             (yp - (0.698001 * (vp - 128)) - (0.337633 * (up - 128)))
//                 .clamp(0, 255)
//                 .toInt();
//         final b = (yp + (1.732446 * (up - 128))).clamp(0, 255).toInt();

//         imgBuffer.setPixelRgb(x, y, r, g, b);
//       }
//     }

//     return imgBuffer;
//   }

//   void _classifySkinTone() {
//     if (faceBrightness < 50) {
//       skinTone = 'Dark';
//     } else if (faceBrightness < 150) {
//       skinTone = 'Medium';
//     } else {
//       skinTone = 'Light';
//     }
//   }

//   Face? get currentFace => _lastFace;
//   Rect? get faceRect => _lastFaceRect;
// }

// Future<Map<String, double>> _calculateBrightness(
//   Map<String, dynamic> args,
// ) async {
//   final CameraImage image = args['image'];
//   final Rect boundingBox = args['boundingBox'];

//   double totalEnvBrightness = 0;
//   int totalEnvPixels = 0;
//   double totalFaceBrightness = 0;
//   int totalFacePixels = 0;

//   final width = image.width;
//   final height = image.height;

//   for (int y = 0; y < height; y += 4) {
//     for (int x = 0; x < width; x += 4) {
//       final pixelIndex = y * width + x;
//       final yValue = image.planes[0].bytes[pixelIndex];

//       if (boundingBox.contains(Offset(x.toDouble(), y.toDouble()))) {
//         totalFaceBrightness += yValue;
//         totalFacePixels++;
//       } else {
//         totalEnvBrightness += yValue;
//         totalEnvPixels++;
//       }
//     }
//   }

//   return {
//     'env': totalEnvBrightness / totalEnvPixels,
//     'face': totalFaceBrightness / totalFacePixels,
//   };
// }
