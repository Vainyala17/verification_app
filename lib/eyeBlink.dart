// import 'package:flutter/material.dart';
// import 'package:camera/camera.dart';
// import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// import 'dart:typed_data';
// class EyeBlinkScreen extends StatefulWidget {
//   final List<CameraDescription> cameras;
//   const EyeBlinkScreen({super.key, required this.cameras});
//
//   @override
//   State<EyeBlinkScreen> createState() => _EyeBlinkScreenState();
// }
//
// class _EyeBlinkScreenState extends State<EyeBlinkScreen> {
//   late CameraController _controller;
//   late FaceDetector _faceDetector;
//   bool _isDetecting = false;
//   bool _leftClosed = false;
//   bool _rightClosed = false;
//
//   @override
//   void initState() {
//     super.initState();
//     _initCamera();
//     _initDetector();
//   }
//
//   void _initDetector() {
//     final options = FaceDetectorOptions(
//       enableClassification: true, // 👈 Required for eye open probability
//       enableTracking: false,
//     );
//     _faceDetector = FaceDetector(options: options);
//   }
//
//   void _initCamera() {
//     _controller = CameraController(
//       widget.cameras[1], // use front camera
//       ResolutionPreset.low,
//       enableAudio: false,
//     );
//     _controller.initialize().then((_) {
//       if (!mounted) return;
//       _controller.startImageStream(_processCameraImage);
//       setState(() {});
//     });
//   }
//
//   Future<void> _processCameraImage(CameraImage image) async {
//     if (_isDetecting) return;
//     _isDetecting = true;
//
//     try {
//       // Convert camera image to InputImage
//       final WriteBuffer allBytes = WriteBuffer();
//       for (final Plane plane in image.planes) {
//         allBytes.putUint8List(plane.bytes);
//       }
//       final bytes = allBytes.done().buffer.asUint8List();
//
//       final inputImage = InputImage.fromBytes(
//         bytes: bytes,
//         metadata: InputImageMetadata(
//           size: Size(image.width.toDouble(), image.height.toDouble()),
//           rotation: InputImageRotation.rotation0deg,
//           format: InputImageFormat.yuv420,
//           bytesPerRow: image.planes.first.bytesPerRow,
//         ),
//       );
//
//       // Detect faces
//       final faces = await _faceDetector.processImage(inputImage);
//
//       for (Face face in faces) {
//         final leftProb = face.leftEyeOpenProbability ?? -1;
//         final rightProb = face.rightEyeOpenProbability ?? -1;
//
//         if (leftProb >= 0) {
//           if (leftProb < 0.3 && !_leftClosed) {
//             _leftClosed = true;
//             debugPrint("👁 Left eye closed");
//           } else if (leftProb > 0.7 && _leftClosed) {
//             _leftClosed = false;
//             debugPrint("✅ Left eye blink detected!");
//           }
//         }
//
//         if (rightProb >= 0) {
//           if (rightProb < 0.3 && !_rightClosed) {
//             _rightClosed = true;
//             debugPrint("👁 Right eye closed");
//           } else if (rightProb > 0.7 && _rightClosed) {
//             _rightClosed = false;
//             debugPrint("✅ Right eye blink detected!");
//           }
//         }
//       }
//     } catch (e) {
//       debugPrint("❌ Error: $e");
//     } finally {
//       _isDetecting = false;
//     }
//   }
//
//   @override
//   void dispose() {
//     _controller.dispose();
//     _faceDetector.close();
//     super.dispose();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     if (!_controller.value.isInitialized) {
//       return const Center(child: CircularProgressIndicator());
//     }
//     return CameraPreview(_controller);
//   }
// }
