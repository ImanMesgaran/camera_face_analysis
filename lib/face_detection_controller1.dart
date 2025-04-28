// // face_detection_controller.dart

// import 'dart:async';
// import 'dart:io';
// import 'dart:isolate';
// import 'dart:math';
// import 'dart:typed_data';

// import 'package:google_mlkit_commons/google_mlkit_commons.dart';

// import 'package:camera/camera.dart';
// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
// import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// import 'package:image/image.dart' as img;

// class FaceDetectionController {
//   final CameraLensDirection cameraLensDirection;
//   late CameraController _cameraController;
//   late FaceDetector _faceDetector;
//   bool _isDetecting = false;

//   final ValueNotifier<Rect?> faceRect = ValueNotifier(null);
//   final ValueNotifier<double> envBrightness = ValueNotifier(0);
//   final ValueNotifier<double> faceBrightness = ValueNotifier(0);
//   final ValueNotifier<String> skinTone = ValueNotifier('Unknown');
//   final ValueNotifier<double> acneLevel = ValueNotifier(0);

//   Timer? _stableTimer;
//   bool _isFaceStable = false;
//   Function(File)? onImageCaptured;

//   FaceDetectionController({
//     this.cameraLensDirection = CameraLensDirection.front,
//   });

//   CameraController get cameraController => _cameraController;

//   Future<void> initialize() async {
//     final cameras = await availableCameras();
//     final camera = cameras.firstWhere(
//       (c) => c.lensDirection == cameraLensDirection,
//     );

//     _cameraController = CameraController(
//       camera,
//       ResolutionPreset.medium,
//       enableAudio: false,
//     );

//     _faceDetector = FaceDetector(
//       options: FaceDetectorOptions(
//         enableContours: true,
//         enableClassification: true,
//       ),
//     );

//     await _cameraController.initialize();
//     _cameraController.startImageStream(_processCameraImage);
//   }

//   void _processCameraImage(CameraImage image) async {
//     if (_isDetecting) return;
//     _isDetecting = true;

//     try {
//       final inputImage = _getInputImageFromCameraImage(image);
//       final faces = await _faceDetector.processImage(inputImage);

//       if (faces.isNotEmpty) {
//         final face = faces.first;

//         faceRect.value = face.boundingBox;

//         _checkFaceStability(face.boundingBox);

//         _calculateEnvBrightness(image);

//         final croppedFace = await _cropFaceFromCameraImage(
//           image,
//           face.boundingBox,
//         );

//         _calculateFaceBrightnessAndAcne(croppedFace);
//       } else {
//         faceRect.value = null;
//         _stableTimer?.cancel();
//         _isFaceStable = false;
//       }
//     } catch (e) {
//       debugPrint('Face detection error: $e');
//     } finally {
//       _isDetecting = false;
//     }
//   }

//   InputImage _getInputImageFromCameraImage(CameraImage image) {
//     final WriteBuffer allBytes = WriteBuffer();
//     for (final Plane plane in image.planes) {
//       allBytes.putUint8List(plane.bytes);
//     }
//     final bytes = allBytes.done().buffer.asUint8List();

//     final Size imageSize = Size(
//       image.width.toDouble(),
//       image.height.toDouble(),
//     );

//     final inputImageFormat =
//         InputImageFormatMethods.fromRawValue(image.format.raw) ??
//         InputImageFormat.nv21;

//     final inputImage = InputImage.fromBytes(
//       bytes: bytes,
//       metadata: InputImageMetadata(
//         size: imageSize,
//         rotation: InputImageRotation.rotation0deg,
//         format: InputImageFormat.nv21,
//         bytesPerRow: image.planes[0].bytesPerRow,
//       ),
//     );

//     final planeData =
//         image.planes
//             .map(
//               (Plane plane) => InputImagePlaneMetadata(
//                 bytesPerRow: plane.bytesPerRow,
//                 height: plane.height,
//                 width: plane.width,
//               ),
//             )
//             .toList();

//     final imageRotation =
//         InputImageRotationMethods.fromRawValue(
//           _cameraController.description.sensorOrientation,
//         ) ??
//         InputImageRotation.rotation0deg;

//     final inputImageData = InputImageData(
//       size: imageSize,
//       imageRotation: imageRotation,
//       inputImageFormat: inputImageFormat,
//       planeData: planeData,
//     );

//     return InputImage.fromBytes(bytes: bytes, metadata: inputImageData);
//   }

//   void _checkFaceStability(Rect rect) {
//     final center = Offset(
//       rect.left + rect.width / 2,
//       rect.top + rect.height / 2,
//     );
//     final screenCenter = Offset(
//       _cameraController.value.previewSize!.width / 2,
//       _cameraController.value.previewSize!.height / 2,
//     );

//     final distance = (center - screenCenter).distance;

//     if (distance < 50) {
//       if (!_isFaceStable) {
//         _stableTimer = Timer(Duration(seconds: 3), _captureFace);
//         _isFaceStable = true;
//       }
//     } else {
//       _stableTimer?.cancel();
//       _isFaceStable = false;
//     }
//   }

//   Future<void> _captureFace() async {
//     if (!_cameraController.value.isInitialized ||
//         !_cameraController.value.isStreamingImages)
//       return;

//     final file = await _cameraController.takePicture();

//     if (onImageCaptured != null) {
//       onImageCaptured!(File(file.path));
//     }
//   }

//   Future<void> _calculateEnvBrightness(CameraImage image) async {
//     final BigInt totalY = image.planes[0].bytes.fold<BigInt>(
//       BigInt.zero,
//       (sum, byte) => sum + BigInt.from(byte),
//     );
//     final double avgY = totalY.toDouble() / image.planes[0].bytes.length;

//     envBrightness.value = avgY / 255.0;
//   }

//   Future<img.Image> _cropFaceFromCameraImage(
//     CameraImage image,
//     Rect boundingBox,
//   ) async {
//     final WriteBuffer allBytes = WriteBuffer();
//     for (final Plane plane in image.planes) {
//       allBytes.putUint8List(plane.bytes);
//     }
//     final bytes = allBytes.done().buffer.asUint8List();

//     final img.Image? fullImage = img.decodeImage(bytes);
//     if (fullImage == null) {
//       throw Exception('Failed to decode image');
//     }

//     final int x = boundingBox.left.toInt().clamp(0, fullImage.width - 1);
//     final int y = boundingBox.top.toInt().clamp(0, fullImage.height - 1);
//     final int w = boundingBox.width.toInt().clamp(1, fullImage.width - x);
//     final int h = boundingBox.height.toInt().clamp(1, fullImage.height - y);

//     final img.Image cropped = img.copyCrop(
//       fullImage,
//       x: x,
//       y: y,
//       width: w,
//       height: h,
//     );
//     return cropped;
//   }

//   Future<void> _calculateFaceBrightnessAndAcne(img.Image cropped) async {
//     final ReceivePort receivePort = ReceivePort();

//     await Isolate.spawn<_BrightnessParams>(
//       _brightnessIsolate,
//       _BrightnessParams(cropped, receivePort.sendPort),
//     );

//     final results = await receivePort.first as Map<String, double>;

//     faceBrightness.value = results['brightness'] ?? 0;

//     skinTone.value = _classifySkinTone(faceBrightness.value);

//     acneLevel.value = results['acne'] ?? 0;
//   }

//   static void _brightnessIsolate(_BrightnessParams params) {
//     double totalBrightness = 0;
//     int acnePoints = 0;
//     int count = 0;

//     for (int y = 0; y < params.image.height; y++) {
//       for (int x = 0; x < params.image.width; x++) {
//         final pixel = params.image.getPixel(x, y);
//         // Read r, g, b directly
//         final r = pixel.r;
//         final g = pixel.g;
//         final b = pixel.b;

//         final brightness = (r + g + b) / 3;

//         if ((r - g).abs() > 30 && (r - b).abs() > 30) {
//           acnePoints++;
//         }

//         totalBrightness += brightness;
//         count++;
//       }
//     }

//     final avgBrightness = totalBrightness / count;
//     final acnePercentage = (acnePoints / count) * 100;

//     params.sendPort.send({
//       'brightness': avgBrightness / 255.0,
//       'acne': acnePercentage,
//     });
//   }

//   String _classifySkinTone(double brightness) {
//     if (brightness > 200) return 'Very Light';
//     if (brightness > 150) return 'Light';
//     if (brightness > 100) return 'Medium';
//     if (brightness > 50) return 'Dark';
//     return 'Very Dark';
//   }

//   void dispose() {
//     _cameraController.dispose();
//     _faceDetector.close();
//     _stableTimer?.cancel();
//     faceRect.dispose();
//     envBrightness.dispose();
//     faceBrightness.dispose();
//     skinTone.dispose();
//     acneLevel.dispose();
//   }
// }

// class _BrightnessParams {
//   final img.Image image;
//   final SendPort sendPort;

//   _BrightnessParams(this.image, this.sendPort);
// }
