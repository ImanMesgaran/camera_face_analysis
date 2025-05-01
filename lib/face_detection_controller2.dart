import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:camera_face_analysis/logic/extension_methods.dart';
import 'package:camera_face_analysis/logic/face_detector_painter.dart';
import 'package:camera_face_analysis/models/detected_face_model.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:path_provider/path_provider.dart';

class FaceDetectionController {
  // 1. Static private instance
  static final FaceDetectionController _instance =
      FaceDetectionController._internal();

  // 2. Private named constructor
  FaceDetectionController._internal();

  // 3. Factory constructor returns the singleton instance
  factory FaceDetectionController() => _instance;

  late CameraController cameraController;
  late final FaceDetector faceDetector;
  late StreamController<CameraImage> imageStreamController;
  // late StreamSubscription<CameraImage> _imageStreamSubscription;
  Timer? _faceHoldTimer;
  DateTime? _lastFaceCenteredTime;

  final ValueNotifier<double> envBrightness = ValueNotifier(0);
  final ValueNotifier<double> faceBrightness = ValueNotifier(0);
  final ValueNotifier<String> skinTone = ValueNotifier('Unknown');
  final ValueNotifier<double> acneLevel = ValueNotifier(0);
  final ValueNotifier<Rect?> faceRect = ValueNotifier(null);
  Function(XFile)? onImageCaptured;
  void Function(CameraImage image)? onImageAvailable;
  final ValueNotifier<CustomPainter?> facePainter = ValueNotifier(null);
  final ValueNotifier<CustomPaint?> customPaint = ValueNotifier(null);
  CustomPaint? customPainter;

  void setImageAvailableCallback(void Function(CameraImage image) callback) {
    onImageAvailable = callback;
  }

  Future<void> initialize() async {
    //imageStreamController = StreamController<CameraImage>.broadcast();

    /*
    _imageStreamSubscription = imageStreamController.stream.listen(
      _processCameraImage,
      onError: (e) => print('Stream error: $e'),
      cancelOnError: false,
    );
    */

    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
    );

    cameraController = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup:
          Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420,
    );

    await cameraController.initialize();
    faceDetector = FaceDetector(
      options: FaceDetectorOptions(enableContours: true, enableLandmarks: true),
    );

    imageStreamController = StreamController<CameraImage>.broadcast();
    cameraController.startImageStream((image) {
      imageStreamController.add(image);
    });

    //imageStreamController.stream.listen(_processCameraImage);

    // bool _isProcessing = false;
    // int _frameCount = 0;

    // imageStreamController.stream.listen((image) async {
    //   if (_isProcessing) return;

    //   if (_frameCount++ % 10 == 0) {
    //     await _processCameraImage(image);
    //     _isProcessing = false;
    //     //print('_processCameraImage');
    //   }
    // });

    /* 
    // Method 2
    bool _isProcessing = false;
    DateTime _lastFrameTime = DateTime.now();
    final Duration _minFrameInterval = Duration(milliseconds: 300);

    await cameraController.startImageStream((CameraImage image) async {
      final now = DateTime.now();
      if (_isProcessing || now.difference(_lastFrameTime) < _minFrameInterval) {
        return;
      }

      _isProcessing = true;
      _lastFrameTime = now;

      try {
        //imageStreamController.add(image);
        await _processCameraImage(image);
      } catch (e) {
        print("Error processing image: $e");
      } finally {
        _isProcessing = false;
      }
    });
    */

    bool _isProcessing = false;
    Duration minFrameInterval = Duration(milliseconds: 300);
    DateTime _lastFrameTime = DateTime.now();
    //Future.delayed(Duration(seconds: 10), () {
    imageStreamController.stream.listen(
      (image) async {
        final now = DateTime.now();
        if (_isProcessing ||
            now.difference(_lastFrameTime) > minFrameInterval) {
          _lastFrameTime = now;
          await processCameraImage(image);
          _isProcessing = false;
        }
      },
      onError: (value) {
        print('this is the on error: $value');
      },
      cancelOnError: false,
    );
    //});

    /*
    bool _isProcessing = false;
    DateTime _lastProcessedTime = DateTime.now();
    final Duration _minFrameInterval = Duration(
      milliseconds: 500,
    ); // adjust as needed

    
    _imageStreamSubscription = imageStreamController.stream.listen(
      (image) async {
        final now = DateTime.now();
        if (_isProcessing ||
            now.difference(_lastProcessedTime) < _minFrameInterval) {
          return;
        }

        _isProcessing = true;
        _lastProcessedTime = now;

        try {
          await _processCameraImage(image);
        } catch (e) {
          print("Error in _processCameraImage: $e");
        } finally {
          _isProcessing = false;
        }
      },
      onError: (value) {
        print('this is the on error: $value');
      },
      cancelOnError: false,
    );
    */
  }

  /*
  Future<void> initialize() async {
    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
    );

    cameraController = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup:
          Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.nv21,
    );

    await cameraController.initialize();

    faceDetector = FaceDetector(
      options: FaceDetectorOptions(enableContours: true, enableLandmarks: true),
    );

    DateTime _lastFrameTime = DateTime.now();
    Duration minFrameInterval = Duration(milliseconds: 300);

    await cameraController.startImageStream((image) {
      final now = DateTime.now();
      if (now.difference(_lastFrameTime) > minFrameInterval) {
        _lastFrameTime = now;
        _processCameraImage(image);
      }
    });
  }
  */

  void dispose() {
    cameraController.dispose();
    imageStreamController.close();
    faceDetector.close();
    print('_processCameraImage on close');
  }

  static Future<DetectedFace?> _detectFace({
    required InputImage? visionImage,
    required FaceDetectorMode performanceMode,
  }) async {
    if (visionImage == null) return null;
    final options = FaceDetectorOptions(
      enableLandmarks: true,
      enableTracking: true,
      performanceMode: performanceMode,
    );
    final faceDetector = FaceDetector(options: options);
    try {
      final List<Face> faces = await faceDetector.processImage(visionImage);
      final faceDetect = _extractFace(faces);
      return faceDetect;
    } catch (error) {
      debugPrint(error.toString());
      return null;
    }
  }

  Future<InputImage> loadImageFromAssets(String assetPath) async {
    final byteData = await rootBundle.load(assetPath);

    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/per_normal_face.jpg');

    await tempFile.writeAsBytes(byteData.buffer.asUint8List());

    return InputImage.fromFilePath(tempFile.path);
  }

  final orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  void updateFace(
    List<Face> faces,
    Size imageSize,
    InputImageRotation rotation,
    CameraLensDirection cameraLensDirection,
  ) {
    facePainter.value = FaceDetectorPainter(
      faces,
      imageSize,
      rotation,
      cameraLensDirection,
    );
  }

  Future<void> _processImage(
    InputImage inputImage,
    FaceDetector _faceDetector,
  ) async {
    final faces = await _faceDetector.processImage(inputImage);
    if (inputImage.metadata?.size != null &&
        inputImage.metadata?.rotation != null) {
      final painter = FaceDetectorPainter(
        faces,
        inputImage.metadata!.size,
        inputImage.metadata!.rotation,
        CameraLensDirection.front,
      );
      customPainter = CustomPaint(painter: painter);
    } else {
      String text = 'Faces found: ${faces.length}\n\n';
      for (final face in faces) {
        text += 'face: ${face.boundingBox}\n\n';
      }

      // TODO: set _customPaint to draw boundingRect on top of image
      customPainter = null;
    }
  }

  // Method 1
  bool _isProcessing = false;

  Future<void> processCameraImage(CameraImage image) async {
    if (_isProcessing) return;
    _isProcessing = true;

    print('_processCameraImage inside');

    try {
      final start = DateTime.now();

      final inputImage = await convertCameraImageToInputImage(
        image,
        cameraController.description,
      );

      // final faces = await faceDetector.processImage(inputImage);

      final _face = await _detectFace(
        performanceMode: FaceDetectorMode.accurate,
        visionImage: _inputImageFromCameraImage(
          image,
          cameraController,
          orientations,
        ),
      );

      final face = _face?.face ?? null;

      if (face != null) {
        // final face = faces.first;
        faceRect.value = face.boundingBox;

        updateFace(
          [face],
          inputImage.metadata!.size,
          inputImage.metadata!.rotation,
          CameraLensDirection.front,
        );

        final _imageFromCameraImage = await convertCameraImageToImage(image);

        final _convertedImage = _inputImageFromCameraImage(
          image,
          cameraController,
          orientations,
        );
        if (_convertedImage == null) return;

        final cropped = await _cropFaceFromCameraImage(image, face.boundingBox);

        //
        FaceDetector _faceDetector = FaceDetector(
          options: FaceDetectorOptions(
            enableContours: true,
            enableLandmarks: true,
          ),
        );
        _processImage(inputImage, _faceDetector);
        final painter = FaceDetectorPainter(
          [face],
          inputImage.metadata!.size,
          inputImage.metadata!.rotation,
          CameraLensDirection.front,
        );
        customPaint.value = CustomPaint(painter: painter);
        //

        if (cropped != null) {
          print('_processCameraImage inside');
          final brightness = await compute(_calculateBrightness, cropped);

          if (_imageFromCameraImage != null) {
            final environmentBrightness = await compute(
              _calculateBrightness,
              _imageFromCameraImage,
            );
            faceBrightness.value = brightness;
            envBrightness.value = environmentBrightness;
          }

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
                imageStreamController.add(image);
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
      _isProcessing = false;
    } finally {
      _isProcessing = false;
    }
  }

  static InputImage? _inputImageFromCameraImage(
    CameraImage image,
    CameraController? controller,
    Map<DeviceOrientation, int> orientations,
  ) {
    // get image rotation
    // it is used in android to convert the InputImage from Dart to Java
    // `rotation` is not used in iOS to convert the InputImage from Dart to Obj-C
    // in both platforms `rotation` and `camera.lensDirection` can be used to compensate `x` and `y` coordinates on a canvas
    final camera = controller!.description;
    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation =
          orientations[controller.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        // front-facing
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        // back-facing
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    if (rotation == null) return null;

    // get image format
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    // validate format depending on platform
    // only supported formats:
    // * bgra8888 for iOS
    if (format == null ||
        (Platform.isIOS && format != InputImageFormat.bgra8888))
      return null;
    if (image.planes.isEmpty) return null;

    final bytes =
        Platform.isAndroid
            ? image.getNv21Uint8List()
            : Uint8List.fromList(
              image.planes.fold(
                <int>[],
                (List<int> previousValue, element) =>
                    previousValue..addAll(element.bytes),
              ),
            );

    // compose InputImage using bytes
    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation, // used only in Android
        format: Platform.isIOS ? format : InputImageFormat.nv21,
        bytesPerRow: image.planes.first.bytesPerRow, // used only in iOS
      ),
    );
  }

  // Method 2
  /*
  bool _isProcessing = false;

  Future<void> _processCameraImage(CameraImage cameraImage) async {
    if (_isProcessing) return;

    _isProcessing = true;

    try {
      final result = await compute(_convertAndDetect, {
        'cameraImage': cameraImage,
        'platform': Platform.isIOS ? 'ios' : 'android',
      });

      final InputImage inputImage = result['inputImage'];
      final img.Image? converted = result['convertedImage'];

      if (converted != null) {
        // Do pixel manipulation here
      }

      final faces = await faceDetector.processImage(inputImage);
      if (faces.isNotEmpty) {
        debugPrint('Faces detected: ${faces.length}');
      }
    } catch (e) {
      debugPrint('Error in image processing: $e');
    } finally {
      _isProcessing = false;
    }
  }

  static Future<Map<String, dynamic>> _convertAndDetect(
    Map<String, dynamic> data,
  ) async {
    final CameraImage cameraImage = data['cameraImage'];
    final String platform = data['platform'];

    final inputImage = await convertCameraImageToInputImage(
      cameraImage,
      platform,
    );
    final converted = convertYUV420ToImage(
      cameraImage,
    ); // if needed for pixel ops

    return {'inputImage': inputImage, 'convertedImage': converted};
  }
  */

  // End of Method 2

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
      if (converted == null) return null;
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

  // Method 1
  /*
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
                  ? InputImageFormat.yuv_420_888
                  : InputImageFormat.bgra8888,
        );

        imgImage.setPixelRgba(x, y, color.red, color.green, color.blue, 255);
      }
    }

    return imgImage;
  }
  */

  // Method 2
  Future<img.Image?> _convertCameraImageToImage(CameraImage image) async {
    if (image.planes.length < 3) {
      print(
        "Unsupported format or corrupted image. Plane count: ${image.planes.length}",
      );
      return null;
    }

    final width = image.width;
    final height = image.height;
    final uvRowStride = image.planes[1].bytesPerRow;
    final uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

    final imgImage = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final uvIndex = uvPixelStride * (x ~/ 2) + uvRowStride * (y ~/ 2);
        final index = y * width + x;

        final yp = image.planes[0].bytes[index];
        final up =
            image.planes[1].bytes.length > uvIndex
                ? image.planes[1].bytes[uvIndex]
                : 128;
        final vp =
            image.planes[2].bytes.length > uvIndex
                ? image.planes[2].bytes[uvIndex]
                : 128;

        final color = convertToColor(
          y: yp,
          u: up,
          v: vp,
          format:
              Platform.isIOS
                  ? InputImageFormat.bgra8888
                  : InputImageFormat.nv21,
        );

        imgImage.setPixelRgba(x, y, color.red, color.green, color.blue, 255);
      }
    }

    return imgImage;
  }

  Future<img.Image?> convertCameraImageToImage(CameraImage cameraImage) async {
    final width = cameraImage.width;
    final height = cameraImage.height;

    if (Platform.isAndroid) {
      if (cameraImage.planes.length < 3) return null;

      final imgImage = img.Image(width: width, height: height);

      final Uint8List yPlane = cameraImage.planes[0].bytes;
      final Uint8List uPlane = cameraImage.planes[1].bytes;
      final Uint8List vPlane = cameraImage.planes[2].bytes;

      final int uvRowStride = cameraImage.planes[1].bytesPerRow;
      final int uvPixelStride = cameraImage.planes[1].bytesPerPixel!;

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int yIndex = y * cameraImage.planes[0].bytesPerRow + x;
          final int uvX = x ~/ 2;
          final int uvY = y ~/ 2;
          final int uvIndex = uvY * uvRowStride + uvX * uvPixelStride;

          final int yp = yPlane[yIndex];
          final int up = uPlane[uvIndex];
          final int vp = vPlane[uvIndex];

          final r = (yp + 1.403 * (vp - 128)).clamp(0, 255).toInt();
          final g =
              (yp - 0.344 * (up - 128) - 0.714 * (vp - 128))
                  .clamp(0, 255)
                  .toInt();
          final b = (yp + 1.770 * (up - 128)).clamp(0, 255).toInt();

          imgImage.setPixelRgba(x, y, r, g, b, 255);
        }
      }

      return imgImage;
    }

    if (Platform.isIOS) {
      // iOS typically uses BGRA format
      if (cameraImage.planes.length != 1) return null;

      final plane = cameraImage.planes[0];
      final bytes = plane.bytes;
      final rowStride = plane.bytesPerRow;
      final imgImage = img.Image(width: width, height: height);

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final index = y * rowStride + x * 4;
          final b = bytes[index];
          final g = bytes[index + 1];
          final r = bytes[index + 2];
          final a = bytes[index + 3];

          imgImage.setPixelRgba(x, y, r, g, b, a);
        }
      }

      return imgImage;
    }

    return null;
  }

  // Method 1
  /*
  Future<InputImage> convertCameraImageToInputImage(
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

    /*final metadata = InputImageMetadata(
      size: imageSize,
      rotation: imageRotation,
      format: inputImageFormat,
      bytesPerRow: image.planes[0].bytesPerRow,
    );*/

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotation.rotation0deg,
        // format: InputImageFormat.yuv420,
        // format:
        //     Platform.isAndroid
        //         ? InputImageFormat.nv21
        //         : InputImageFormatValue.fromRawValue(image.format.raw)!,
        format:
            Platform.isIOS ? InputImageFormat.bgra8888 : InputImageFormat.nv21,
        // format: InputImageFormatValue.fromRawValue(image.format.raw)!,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }
  */

  // Method 2
  Future<InputImage> convertCameraImageToInputImage(
    CameraImage image,
    CameraDescription camera,
  ) async {
    final WriteBuffer allBytes = WriteBuffer();
    for (final plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    // final bytes = allBytes.done().buffer.asUint8List();

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

    /*final metadata = InputImageMetadata(
      size: imageSize,
      rotation: imageRotation,
      format: inputImageFormat,
      bytesPerRow: image.planes[0].bytesPerRow,
    );*/

    final bytes =
        Platform.isAndroid
            ? image.getNv21Uint8List()
            : Uint8List.fromList(
              image.planes.fold(
                <int>[],
                (List<int> previousValue, element) =>
                    previousValue..addAll(element.bytes),
              ),
            );

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotation.rotation0deg,
        // format: InputImageFormat.yuv_420_888,
        // format: InputImageFormat.yuv420,
        // format:
        //     Platform.isAndroid
        //         ? InputImageFormat.yuv_420_888
        //         : InputImageFormat.bgra8888,
        format:
            Platform.isIOS
                ? InputImageFormatValue.fromRawValue(image.format.raw)!
                : InputImageFormat.nv21,
        // format: InputImageFormatValue.fromRawValue(image.format.raw)!,
        // format: InputImageFormat.yuv420,
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

  //
  // IMPORTED
  static _extractFace(List<Face> faces) {
    //List<Rect> rect = [];
    bool wellPositioned = faces.isNotEmpty;
    Face? detectedFace;

    for (Face face in faces) {
      // rect.add(face.boundingBox);
      detectedFace = face;

      // Head is rotated to the right rotY degrees
      if (face.headEulerAngleY! > 5 || face.headEulerAngleY! < -5) {
        wellPositioned = false;
      }

      // Head is tilted sideways rotZ degrees
      if (face.headEulerAngleZ! > 5 || face.headEulerAngleZ! < -5) {
        wellPositioned = false;
      }

      // If landmark detection was enabled with FaceDetectorOptions (mouth, ears,
      // eyes, cheeks, and nose available):
      final FaceLandmark? leftEar = face.landmarks[FaceLandmarkType.leftEar];
      final FaceLandmark? rightEar = face.landmarks[FaceLandmarkType.rightEar];
      final FaceLandmark? bottomMouth =
          face.landmarks[FaceLandmarkType.bottomMouth];
      final FaceLandmark? rightMouth =
          face.landmarks[FaceLandmarkType.rightMouth];
      final FaceLandmark? leftMouth =
          face.landmarks[FaceLandmarkType.leftMouth];
      final FaceLandmark? noseBase = face.landmarks[FaceLandmarkType.noseBase];
      if (leftEar == null ||
          rightEar == null ||
          bottomMouth == null ||
          rightMouth == null ||
          leftMouth == null ||
          noseBase == null) {
        wellPositioned = false;
      }

      if (face.leftEyeOpenProbability != null) {
        if (face.leftEyeOpenProbability! < 0.5) {
          wellPositioned = false;
        }
      }

      if (face.rightEyeOpenProbability != null) {
        if (face.rightEyeOpenProbability! < 0.5) {
          wellPositioned = false;
        }
      }

      if (wellPositioned) {
        break;
      }
    }

    return DetectedFace(wellPositioned: wellPositioned, face: detectedFace);
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
