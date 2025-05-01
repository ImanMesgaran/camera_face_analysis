// // face_detection_controller.dart

// import 'dart:async';
// import 'dart:io';
// import 'dart:isolate';
// import 'dart:typed_data';
// import 'dart:ui' as ui;
// import 'package:camera/camera.dart';
// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
// import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// import 'package:image/image.dart' as img;
// import 'package:tflite_flutter/tflite_flutter.dart';
// import 'package:google_mlkit_commons/google_mlkit_commons.dart';
// import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

// class FaceDetectionControllerTemp {
//   late CameraController _cameraController;
//   final FaceDetector _faceDetector;
//   Interpreter? _acneInterpreter;
//   bool _isProcessing = false;
//   late List<CameraDescription> _cameras;
//   Function(Uint8List croppedFace)? onFaceCaptured;
//   int _stableCounter = 0;
//   final int _stableThreshold = 90; // about 3 seconds at 30fps

//   Face? _lastFace;
//   Rect? _lastFaceRect;
//   Size? _imageSize;

//   // double envBrightness = 0.0;
//   // double faceBrightness = 0.0;
//   // double acneLevel = 0.0;
//   // String skinTone = 'Unknown';

//   final ValueNotifier<Rect?> faceRect = ValueNotifier(null);
//   final ValueNotifier<double> envBrightness = ValueNotifier(0);
//   final ValueNotifier<double> faceBrightness = ValueNotifier(0);
//   final ValueNotifier<String> skinTone = ValueNotifier('Unknown');
//   final ValueNotifier<double> acneLevel = ValueNotifier(0);

//   Timer? _stableTimer;
//   bool _isFaceStable = false;
//   Function(File)? onImageCaptured;

//   CameraController get cameraController => _cameraController;

//   FaceDetectionControllerTemp()
//     : _faceDetector = FaceDetector(
//         options: FaceDetectorOptions(
//           performanceMode: FaceDetectorMode.fast,
//           enableContours: true,
//         ),
//       ) {
//     init();
//   }

//   void init() async {
//     await initialize();
//   }

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
//     await Future.delayed(const Duration(milliseconds: 100));
//     _cameraController.startImageStream(_processCameraImage);
//     //await _loadAcneModel();
//   }

//   Future<void> _loadAcneModel() async {
//     try {
//       _acneInterpreter = await Interpreter.fromAsset('acne_model.tflite');
//     } catch (e) {
//       debugPrint('Acne model load failed: $e');
//     }
//   }

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
//         envBrightness.value = results['env']!;
//         faceBrightness.value = results['face']!;
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
//     if (faceBrightness.value < 50) {
//       skinTone.value = 'Dark';
//     } else if (faceBrightness.value < 150) {
//       skinTone.value = 'Medium';
//     } else {
//       skinTone.value = 'Light';
//     }
//   }

//   Face? get currentFace => _lastFace;
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

// // face_detection_controller.dart

// // import 'dart:async';
// // import 'dart:io';
// // import 'dart:isolate';
// // import 'dart:math';
// // import 'dart:typed_data';

// // import 'package:camera/camera.dart';
// // import 'package:flutter/material.dart';
// // import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// // import 'package:image/image.dart' as img;

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
//   bool _hasCaptured = false;
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
//       ResolutionPreset.high,
//       imageFormatGroup:
//           Platform.isAndroid
//               ? ImageFormatGroup.yuv420
//               : ImageFormatGroup.bgra8888,
//     );

//     _faceDetector = FaceDetector(
//       options: FaceDetectorOptions(
//         enableContours: true,
//         enableClassification: true,
//         enableLandmarks: true,
//       ),
//     );

//     await _cameraController.initialize();
//     _cameraController.startImageStream(_processCameraImage);
//   }

//   void _processCameraImage(CameraImage image) async {
//     if (_isDetecting || !_cameraController.value.isInitialized) return;

//     _isDetecting = true;

//     try {
//       final inputImage = _getInputImageFromCameraImage(image);
//       final faces = await _faceDetector.processImage(inputImage);

//       if (faces.isNotEmpty) {
//         final face = faces.first;

//         faceRect.value = face.boundingBox;

//         _checkFaceStability(face.boundingBox);

//         await _calculateEnvBrightness(image);

//         final croppedFace = await _cropFaceFromCameraImage(
//           image,
//           face.boundingBox,
//         );

//         await _calculateFaceBrightnessAndAcne(croppedFace);
//       } else {
//         faceRect.value = null;
//         _stableTimer?.cancel();
//         _isFaceStable = false;
//         _hasCaptured = false;
//       }
//     } catch (e, stackTrace) {
//       debugPrint('Face detection error: $e');
//       debugPrintStack(stackTrace: stackTrace);
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

//     return InputImage.fromBytes(
//       bytes: bytes,
//       metadata: InputImageMetadata(
//         size: Size(image.width.toDouble(), image.height.toDouble()),
//         rotation: _cameraRotation(),
//         format:
//             Platform.isAndroid
//                 ? InputImageFormat.nv21
//                 : InputImageFormat.bgra8888,
//         bytesPerRow: image.planes[0].bytesPerRow,
//       ),
//     );
//   }

//   InputImageRotation _cameraRotation() {
//     switch (_cameraController.description.sensorOrientation) {
//       case 90:
//         return InputImageRotation.rotation90deg;
//       case 270:
//         return InputImageRotation.rotation270deg;
//       case 180:
//         return InputImageRotation.rotation180deg;
//       default:
//         return InputImageRotation.rotation0deg;
//     }
//   }

//   void _checkFaceStability(Rect rect) {
//     final center = Offset(
//       rect.left + rect.width / 2,
//       rect.top + rect.height / 2,
//     );
//     final screenCenter = Offset(
//       _cameraController.value.previewSize!.height / 2,
//       _cameraController.value.previewSize!.width / 2,
//     );

//     final distance = (center - screenCenter).distance;

//     if (distance < 50) {
//       if (!_isFaceStable) {
//         _stableTimer = Timer(Duration(seconds: 2), _captureFace);
//         _isFaceStable = true;
//       }
//     } else {
//       _stableTimer?.cancel();
//       _isFaceStable = false;
//       _hasCaptured = false;
//     }
//   }

//   Future<void> _captureFace() async {
//     if (!_cameraController.value.isInitialized ||
//         !_cameraController.value.isStreamingImages)
//       return;
//     if (_hasCaptured) return;

//     final file = await _cameraController.takePicture();

//     _hasCaptured = true;

//     if (onImageCaptured != null) {
//       onImageCaptured!(File(file.path));
//     }
//   }

//   Future<void> _calculateEnvBrightness(CameraImage image) async {
//     final int totalY = image.planes[0].bytes.fold(0, (a, b) => a + b);
//     final double avgY = totalY / image.planes[0].bytes.length;

//     envBrightness.value = avgY;
//   }

//   Future<img.Image> _cropFaceFromCameraImage(
//     CameraImage image,
//     Rect boundingBox,
//   ) async {
//     final bytes = image.planes[0].bytes;

//     img.Image fullImage = img.Image.fromBytes(
//       width: image.width,
//       height: image.height,
//       bytes: bytes.buffer,
//       format: img.Format.uint8,
//     );

//     int x = boundingBox.left.toInt().clamp(0, fullImage.width - 1);
//     int y = boundingBox.top.toInt().clamp(0, fullImage.height - 1);
//     int w = boundingBox.width.toInt().clamp(1, fullImage.width - x);
//     int h = boundingBox.height.toInt().clamp(1, fullImage.height - y);

//     img.Image cropped = img.copyCrop(
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
//     int count = 0;

//     for (int y = 0; y < params.image.height; y++) {
//       for (int x = 0; x < params.image.width; x++) {
//         final pixel = params.image.getPixel(x, y);
//         final luminance = pixel.r; // Since image is luminance only

//         totalBrightness += luminance;
//         count++;
//       }
//     }

//     final avgBrightness = totalBrightness / count;

//     params.sendPort.send({
//       'brightness': avgBrightness,
//       'acne': 0, // acne detection disabled for now
//     });
//   }

//   String _classifySkinTone(double brightness) {
//     if (brightness > 220) return 'Very Light';
//     if (brightness > 170) return 'Light';
//     if (brightness > 120) return 'Medium';
//     if (brightness > 70) return 'Dark';
//     return 'Very Dark';
//   }

//   void dispose() {
//     _cameraController.dispose();
//     _faceDetector.close();
//     _stableTimer?.cancel();
//   }
// }

// class _BrightnessParams {
//   final img.Image image;
//   final SendPort sendPort;

//   _BrightnessParams(this.image, this.sendPort);
// }
