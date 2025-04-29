import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

class FaceDetectionController {
  late CameraController cameraController;
  late final FaceDetector faceDetector;
  late StreamController<CameraImage> _imageStreamController;
  late StreamSubscription<CameraImage> _imageStreamSubscription;
  Timer? _faceHoldTimer;
  DateTime? _lastFaceCenteredTime;

  final ValueNotifier<double> envBrightness = ValueNotifier(0);
  final ValueNotifier<double> faceBrightness = ValueNotifier(0);
  final ValueNotifier<String> skinTone = ValueNotifier('Unknown');
  final ValueNotifier<double> acneLevel = ValueNotifier(0);
  final ValueNotifier<Rect?> faceRect = ValueNotifier(null);
  Function(XFile)? onImageCaptured;

  Future<void> initialize() async {
    _imageStreamController = StreamController<CameraImage>.broadcast();

    _imageStreamSubscription = _imageStreamController.stream.listen(
      _processCameraImage,
      onError: (e) => print('Stream error: $e'),
      cancelOnError: false,
    );

    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
    );

    cameraController = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await cameraController.initialize();
    faceDetector = FaceDetector(
      options: FaceDetectorOptions(enableContours: true, enableLandmarks: true),
    );

    _imageStreamController = StreamController<CameraImage>.broadcast();
    cameraController.startImageStream((image) {
      _imageStreamController.add(image);
    });

    //_imageStreamController.stream.listen(_processCameraImage);

    // bool _isProcessing = false;
    // int _frameCount = 0;

    // _imageStreamController.stream.listen((image) async {
    //   if (_isProcessing) return;

    //   if (_frameCount++ % 10 == 0) {
    //     await _processCameraImage(image);
    //     _isProcessing = false;
    //     //print('_processCameraImage');
    //   }
    // });

    Duration minFrameInterval = Duration(milliseconds: 300);
    DateTime _lastFrameTime = DateTime.now();

    await Future.delayed(Duration(seconds: 3), () {
      _imageStreamController.stream.listen(
        (image) async {
          final now = DateTime.now();
          if (now.difference(_lastFrameTime) > minFrameInterval) {
            _lastFrameTime = now;
            await _processCameraImage(image);
          }
        },
        onError: (value) {
          print('this is the on error: $value');
        },
        cancelOnError: false,
      );
    });
  }

  void dispose() {
    cameraController.dispose();
    _imageStreamController.close();
    faceDetector.close();
    print('_processCameraImage on close');
  }

  Future<void> _processCameraImage(CameraImage image) async {
    print('_processCameraImage inside');

    try {
      final start = DateTime.now();

      final inputImage = await _convertCameraImageToInputImage(
        image,
        cameraController.description,
      );
      final faces = await faceDetector.processImage(inputImage);

      if (faces.isNotEmpty) {
        final face = faces.first;
        faceRect.value = face.boundingBox;

        final cropped = await _cropFaceFromCameraImage(image, face.boundingBox);

        if (cropped != null) {
          print('_processCameraImage inside');
          final brightness = await compute(_calculateBrightness, cropped);
          final environmentBrightness = await compute(
            _calculateBrightness,
            await _convertCameraImageToImage(image),
          );

          faceBrightness.value = brightness;
          envBrightness.value = environmentBrightness;

          skinTone.value = _classifySkinTone(brightness);
          acneLevel.value = await AcneDetector.process(cropped);
          _estimateAcneLevel(cropped);

          if (_isFaceCentered(face.boundingBox, image.width, image.height)) {
            _faceHoldTimer ??= Timer(Duration(seconds: 3), () async {
              if (cameraController.value.isStreamingImages) {
                await cameraController.stopImageStream();
              }
              final file = await cameraController.takePicture();
              onImageCaptured?.call(file);
              _faceHoldTimer?.cancel();
              _faceHoldTimer = null;

              await cameraController.startImageStream((image) {
                _imageStreamController.add(image);
              });
            });
          } else {
            print('_processCameraImage on no cropped face');
            _faceHoldTimer?.cancel();
            _faceHoldTimer = null;
          }
          final end = DateTime.now();
          print(
            'Frame processed in ${end.difference(start).inMilliseconds} ms',
          );
        }
      } else {
        print('_processCameraImage on no cropped face');
        faceRect.value = null;
        _faceHoldTimer?.cancel();
        _faceHoldTimer = null;
      }
    } catch (e) {
      debugPrint('Face detection error: $e');
    }
  }

  bool _isFaceCentered(Rect rect, int width, int height) {
    final centerX = width / 2;
    final centerY = height / 2;
    return rect.contains(Offset(centerX, centerY));
  }

  Future<img.Image?> _cropFaceFromCameraImage(
    CameraImage image,
    Rect boundingBox,
  ) async {
    try {
      final converted = await _convertCameraImageToImage(image);
      final left = boundingBox.left.toInt().clamp(0, converted.width - 1);
      final top = boundingBox.top.toInt().clamp(0, converted.height - 1);
      final width = boundingBox.width.toInt().clamp(1, converted.width - left);
      final height = boundingBox.height.toInt().clamp(
        1,
        converted.height - top,
      );

      return img.copyCrop(
        converted,
        x: left,
        y: top,
        width: width,
        height: height,
      );
    } catch (_) {
      return null;
    }
  }

  Future<img.Image> _convertCameraImageToImage(CameraImage image) async {
    final width = image.width;
    final height = image.height;
    final uvRowStride = image.planes[1].bytesPerRow;
    final uvPixelStride = image.planes[1].bytesPerPixel!;

    final imgImage = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final uvIndex = uvPixelStride * (x ~/ 2) + uvRowStride * (y ~/ 2);
        final index = y * width + x;

        final yp = image.planes[0].bytes[index];
        final up = image.planes[1].bytes[uvIndex];
        final vp = image.planes[2].bytes[uvIndex];

        // final color = _yuvToRgb(yp, up, vp);
        final color = convertToColor(
          y: yp,
          u: up,
          v: vp,
          format:
              Platform.isAndroid
                  ? InputImageFormat.nv21
                  : InputImageFormat.bgra8888,
        );

        imgImage.setPixelRgba(x, y, color.red, color.green, color.blue, 255);
      }
    }

    return imgImage;
  }

  Future<InputImage> _convertCameraImageToInputImage(
    CameraImage image,
    CameraDescription camera,
  ) async {
    final WriteBuffer allBytes = WriteBuffer();
    for (final plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final Size imageSize = Size(
      image.width.toDouble(),
      image.height.toDouble(),
    );

    final imageRotation =
        InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
        InputImageRotation.rotation0deg;

    final inputImageFormat =
        InputImageFormatValue.fromRawValue(image.format.raw) ??
        InputImageFormat.nv21;

    // final planeData =
    //     image.planes
    //         .map(
    //           (Plane plane) => InputImagePlaneMetadata(
    //             bytesPerRow: plane.bytesPerRow,
    //             height: plane.height,
    //             width: plane.width,
    //           ),
    //         )
    //         .toList();

    final metadata = InputImageMetadata(
      size: imageSize,
      rotation: imageRotation,
      format: inputImageFormat,
      bytesPerRow: image.planes[0].bytesPerRow,
    );

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotation.rotation0deg,
        // format: InputImageFormat.yuv420,
        format:
            Platform.isAndroid
                ? InputImageFormat.nv21
                : InputImageFormatValue.fromRawValue(image.format.raw)!,
        // format:
        //     Platform.isIOS ? InputImageFormat.bgra8888 : InputImageFormat.nv21,
        //format: InputImageFormatValue.fromRawValue(image.format.raw)!,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  Color convertToColor({
    required int y,
    required int u,
    required int v,
    required InputImageFormat format,
  }) {
    switch (format) {
      case InputImageFormat.nv21: // Android (YUV420)
        final r = (y + 1.4075 * (v - 128)).clamp(0, 255).toInt();
        final g =
            (y - 0.3455 * (u - 128) - 0.7169 * (v - 128)).clamp(0, 255).toInt();
        final b = (y + 1.7790 * (u - 128)).clamp(0, 255).toInt();
        return Color.fromARGB(255, r, g, b);

      case InputImageFormat.bgra8888: // iOS (already RGB in plane 0)
        // In this case, y, u, v are actually B, G, R
        return Color.fromARGB(255, v, u, y); // assuming y=blue, u=green, v=red

      default:
        throw UnsupportedError('Unsupported image format: $format');
    }
  }

  /*
  Color _yuvToRgb(int y, int u, int v) {
    final r = (y + 1.4075 * (v - 128)).clamp(0, 255).toInt();
    final g =
        (y - 0.3455 * (u - 128) - (0.7169 * (v - 128))).clamp(0, 255).toInt();
    final b = (y + 1.7790 * (u - 128)).clamp(0, 255).toInt();
    return Color.fromARGB(255, r, g, b);
  }
  */

  static double _calculateBrightness(img.Image image) {
    double total = 0;
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r;
        final g = pixel.g;
        final b = pixel.b;
        total += (r + g + b) / 3;
      }
    }
    return total / (image.width * image.height);
  }

  String _classifySkinTone(double brightness) {
    if (brightness > 200) return "Very Light";
    if (brightness > 150) return "Light";
    if (brightness > 100) return "Medium";
    if (brightness > 50) return "Dark";
    return "Very Dark";
  }

  double _estimateAcneLevel(img.Image faceImage) {
    int acnePixelCount = 0;
    int totalPixels = faceImage.width * faceImage.height;

    for (int y = 0; y < faceImage.height; y++) {
      for (int x = 0; x < faceImage.width; x++) {
        final pixel = faceImage.getPixel(x, y);
        final r = pixel.r;
        final g = pixel.g;
        final b = pixel.b;

        // Simple heuristic: detect reddish areas (inflamed skin)
        if (r > 130 && r > g + 20 && r > b + 20) {
          acnePixelCount++;
        }
      }
    }

    double acneRatio = acnePixelCount / totalPixels;
    return (acneRatio * 100).clamp(0, 100); // Return percentage estimate
  }
}

class AcneDetector {
  static Future<double> process(img.Image image) async {
    int acnePixelCount = 0;
    int totalPixelCount = image.width * image.height;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r;
        final g = pixel.g;
        final b = pixel.b;

        // Simple heuristic for red/pink tones common in acne
        if (r > 150 && g < 100 && b < 100) {
          acnePixelCount++;
        }
      }
    }

    return (acnePixelCount / totalPixelCount) * 100;
  }
}
