import 'package:camera_face_analysis/face_detection_controller.dart';
import 'package:camera_face_analysis/pages/face_detection_page.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: Scaffold(body: FaceDetectionPage()));
  }
}
