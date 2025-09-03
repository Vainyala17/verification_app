// Put this entire file in your project (replace your current file).
// Make sure pubspec.yaml contains the required packages and versions.
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data'; // <-- keep this one
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

class HomeScreen extends StatelessWidget {
  final List<CameraDescription> cameras;
  const HomeScreen({Key? key, required this.cameras}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient:
          LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.blue.shade400, Colors.blue.shade800]),
        ),
        child: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.face_retouching_natural, size: 100, color: Colors.white),
            SizedBox(height: 30),
            Text('Face Liveness Detection', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
            SizedBox(height: 20),
            Text('Verify your identity with face detection', style: TextStyle(fontSize: 16, color: Colors.white70), textAlign: TextAlign.center),
            SizedBox(height: 50),
            ElevatedButton(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => FaceDetectionScreen(cameras: cameras)));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.blue.shade800,
                padding: EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: Text('Click Here to Start', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ]),
        ),
      ),
    );
  }
}

class FaceDetectionScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const FaceDetectionScreen({Key? key, required this.cameras}) : super(key: key);

  @override
  _FaceDetectionScreenState createState() => _FaceDetectionScreenState();
}

class _FaceDetectionScreenState extends State<FaceDetectionScreen> {
  CameraController? _cameraController;
  FaceDetector? _faceDetector;
  bool _isDetecting = false;
  bool _isCameraInitialized = false;
  int _currentCameraIndex = 0;

  // Liveness detection states
  bool _faceDetected = false;
  bool _faceFittedInFrame = false;
  int _blinkCount = 0;
  bool _isBlinking = false;
  bool _livenessVerified = false;
  String _instructionText = "Position your face in the frame";

  // Face detection variables
  List<Face> _faces = [];
  bool _previousEyesOpen = true;

  @override
  void initState() {
    super.initState();
    _currentCameraIndex = _getFrontCameraIndex(); // choose front camera safely
    _initializeFaceDetector();
    _initializeCamera();
    _debugCameraInfo();
    _reinitializeFaceDetector();

  }

  Uint8List _yuv420toNV21(CameraImage image) {
    final int width = image.width;
    final int height = image.height;

    final yBuffer = image.planes[0].bytes;
    final uBuffer = image.planes[1].bytes;
    final vBuffer = image.planes[2].bytes;

    final uvRowStride = image.planes[1].bytesPerRow;
    final uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

    // NV21 size = Y + (Y/2)
    final nv21 = Uint8List(width * height + (width * height ~/ 2));

    // ✅ Copy Y directly
    nv21.setRange(0, width * height, yBuffer);

    int uvIndex = width * height;

    // ✅ Copy UV in VU order
    for (int row = 0; row < height ~/ 2; row++) {
      for (int col = 0; col < width ~/ 2; col++) {
        final uIndex = row * uvRowStride + col * uvPixelStride;
        final vIndex = row * uvRowStride + col * uvPixelStride;

        if (uvIndex + 1 >= nv21.length) break; // 🚨 Prevent overflow

        nv21[uvIndex++] = vBuffer[vIndex]; // V
        nv21[uvIndex++] = uBuffer[uIndex]; // U
      }
    }

    return nv21;
  }


  int _getFrontCameraIndex() {
    for (int i = 0; i < widget.cameras.length; i++) {
      if (widget.cameras[i].lensDirection == CameraLensDirection.front) return i;
    }
    return widget.cameras.isNotEmpty ? 0 : 0;
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) return;

    // Request permission first
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() {
        _instructionText = "Camera permission required";
      });
      return;
    }

    // If index invalid, reset to 0
    if (_currentCameraIndex >= widget.cameras.length) _currentCameraIndex = 0;

    // Try different formats based on platform
    List<ImageFormatGroup> formats;
    if (Platform.isAndroid) {
      formats = [ImageFormatGroup.nv21, ImageFormatGroup.yuv420];
    } else {
      formats = [ImageFormatGroup.bgra8888];
    }

    bool initialized = false;
    for (final fmt in formats) {
      try {
        debugPrint('🔄 Trying camera format: $fmt');

        _cameraController = CameraController(
            widget.cameras[_currentCameraIndex],
            ResolutionPreset.medium,
            enableAudio: false,
            imageFormatGroup: fmt
        );

        await _cameraController!.initialize();

        // Test if this format will work with ML Kit by doing a simple test
        bool formatWorks = true; // Assume it works, we'll test during actual usage

        try {
          await _cameraController!.setFocusMode(FocusMode.auto);
        } catch (e) {
          debugPrint('⚠️ Could not set focus mode: $e');
        }

        initialized = true;
        debugPrint('✅ Camera initialized with format: $fmt (index=$_currentCameraIndex)');
        break;

      } catch (e) {
        debugPrint('❌ Init camera failed for format $fmt: $e');
        try {
          await _cameraController?.dispose();
        } catch (_) {}
      }
    }

    if (initialized && mounted) {
      setState(() {
        _isCameraInitialized = true;
      });
      // Small delay before starting image stream
      await Future.delayed(Duration(milliseconds: 500));
      _startImageStream();
    } else {
      debugPrint('❌ Failed to init camera with any tested format.');
      if (mounted) {
        setState(() => _instructionText = "Failed to initialize camera");
      }
    }
  }

  bool _testFormatCompatibility(CameraImage testImage) {
    try {
      final testInput = _convertCameraImage(testImage);
      if (testInput != null) {
        debugPrint('✅ Format compatibility test passed');
        return true;
      } else {
        debugPrint('❌ Format compatibility test failed - conversion returned null');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Format compatibility test failed with error: $e');
      return false;
    }
  }

  void _initializeFaceDetector() {
    try {
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableContours: false,
          enableClassification: true, // needed for eye open probabilities
          enableLandmarks: true, // enable if you want landmark fallback
          enableTracking: true,
          minFaceSize: 0.1,
          performanceMode: FaceDetectorMode.fast,
        ),
      );
    } catch (e) {
      debugPrint('Face detector init error: $e');
    }
  }

// UPDATED _startImageStream with better error handling
  void _startImageStream() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    bool firstFrame = true;
    int failureCount = 0;
    const int maxFailures = 3;

    _cameraController!.startImageStream((CameraImage image) {
      if (firstFrame) {
        firstFrame = false;
        debugPrint('📸 First frame received: ${image.width}x${image.height}, format: ${image.format.group}, planes: ${image.planes.length}');

        // Test format compatibility on first frame
        if (!_testFormatCompatibility(image)) {
          debugPrint('❌ Format incompatible, stopping stream');
          try {
            _cameraController?.stopImageStream();
          } catch (e) {
            debugPrint('Error stopping image stream: $e');
          }
          if (mounted) {
            setState(() => _instructionText = "Camera format not supported");
          }
          return;
        }
      }

      if (!_isDetecting && !_livenessVerified && mounted) {
        _isDetecting = true;

        // Process with failure tracking
        Future.delayed(Duration(milliseconds: 100), () async {
          if (!mounted) {
            _isDetecting = false;
            return;
          }

          try {
            await _detectFaces(image);
            failureCount = 0; // Reset on success
          } catch (e) {
            failureCount++;
            debugPrint('Face detection failed (attempt $failureCount/$maxFailures): $e');

            if (failureCount >= maxFailures) {
              debugPrint('❌ Too many failures, stopping detection');
              try {
                _cameraController?.stopImageStream();
              } catch (_) {}
              if (mounted) {
                setState(() => _instructionText = "Detection failed - please restart");
              }
            }
          } finally {
            _isDetecting = false;
          }
        });
      }
    });
  }

  Future<void> _detectFaces(CameraImage image) async {
    try {
      final inputImage = _convertCameraImage(image);
      if (inputImage == null) {
        debugPrint('⚠️ convertCameraImage returned null - skipping frame');
        return;
      }

      final detectedFaces = await _faceDetector!.processImage(inputImage);

      if (mounted) {
        setState(() {
          _faces = detectedFaces;
        });
        _processFaceDetection(detectedFaces);
      }
    } catch (e, st) {
      debugPrint('❌ Face detection error: $e');
      // Don't log full stack trace unless needed for debugging
      rethrow; // Let the calling function handle the error counting
    } finally {
      _isDetecting = false;
    }
  }

  void _processFaceDetection(List<Face> detectedFaces) {
    if (detectedFaces.isEmpty) {
      setState(() {
        _faceDetected = false;
        _faceFittedInFrame = false;
        _instructionText = "Position your face in the frame";
      });
      return;
    }

    final face = detectedFaces.first;
    _faceDetected = true;

    final faceRect = face.boundingBox;
    if (_isFaceInFrame(faceRect)) {
      if (!_faceFittedInFrame) {
        setState(() {
          _faceFittedInFrame = true;
          _instructionText = "Great! Now blink your eyes 2 times";
        });
      }
      if (_faceFittedInFrame && !_livenessVerified) {
        _detectBlinking(face);
      }
    } else {
      setState(() {
        _faceFittedInFrame = false;
        _instructionText = "Fit your face into the frame";
      });
    }
  }

  bool _isFaceInFrame(Rect faceRect) {
    // Robust center / size check (values may need tweaking per device)
    final w = faceRect.width;
    final h = faceRect.height;
    final cx = faceRect.center.dx;
    final cy = faceRect.center.dy;
    return w > 80 && h > 80 && cx > 50 && cx < (MediaQuery.of(context).size.width - 50) && cy > 100 && cy < (MediaQuery.of(context).size.height - 200);
  }
  Future<void> _reinitializeFaceDetector() async {
    try {
      await _faceDetector?.close();
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableContours: false,
          enableClassification: true,
          enableLandmarks: false, // Try with landmarks OFF first
          enableTracking: false,  // Try with tracking OFF first
          minFaceSize: 0.15,
          performanceMode: FaceDetectorMode.accurate, // Try accurate mode
        ),
      );
      debugPrint("Face detector reinitialized");
    } catch (e) {
      debugPrint("Failed to reinitialize face detector: $e");
    }
  }

  double _calculateEAR(Face face) {
    // Get landmarks from the map
    final leftEye = face.landmarks[FaceLandmarkType.leftEye];
    final rightEye = face.landmarks[FaceLandmarkType.rightEye];

    if (leftEye == null || rightEye == null) return 1.0; // assume open

    final dx = (leftEye.position.x - rightEye.position.x).abs();
    final dy = (leftEye.position.y - rightEye.position.y).abs();

    // Smaller ratio means eyes are closing
    final ear = dy / dx;
    return ear;
  }



  void _detectBlinking(Face face) {
    final leftProb = face.leftEyeOpenProbability;
    final rightProb = face.rightEyeOpenProbability;

    bool eyesOpen;

    if (leftProb != null && rightProb != null) {
      // Use ML Kit’s classification
      final leftOpen = leftProb > 0.4;  // relaxed threshold
      final rightOpen = rightProb > 0.4;
      eyesOpen = leftOpen && rightOpen;
      debugPrint("👁 Prob: L=$leftProb R=$rightProb → eyesOpen=$eyesOpen");
    } else {
      // Fallback to EAR (eye aspect ratio) if classification missing
      eyesOpen = _calculateEAR(face) > 0.2;
      debugPrint("📏 EAR fallback → eyesOpen=$eyesOpen");
    }

    // Blink detection logic
    if (_previousEyesOpen && !eyesOpen) {
      // just closed
      _isBlinking = true;
      debugPrint("👁 Eyes closed");
    } else if (!_previousEyesOpen && eyesOpen && _isBlinking) {
      // just reopened → blink complete
      _isBlinking = false;
      _blinkCount++;
      debugPrint("✅ Blink detected! count=$_blinkCount");

      setState(() {
        if (_blinkCount >= 2) {
          _completeVerification();
        } else {
          _instructionText =
          "Blink ${2 - _blinkCount} more time${2 - _blinkCount == 1 ? '' : 's'}";
        }
      });
    }

    _previousEyesOpen = eyesOpen;
  }



  // Add this to your initState() method for debugging
  void _debugCameraInfo() {
    debugPrint('=== CAMERA DEBUG INFO ===');
    for (int i = 0; i < widget.cameras.length; i++) {
      final cam = widget.cameras[i];
      debugPrint('Camera $i: ${cam.lensDirection}, sensor: ${cam.sensorOrientation}');
    }
    debugPrint('Platform: ${Platform.isAndroid ? "Android" : "iOS"}');
    debugPrint('=========================');
  }

  void _completeVerification() {
    setState(() {
      _livenessVerified = true;
      _instructionText = "Successfully verified your liveness of face detection!";
    });

    try {
      _cameraController?.stopImageStream();
    } catch (_) {}
    Timer(Duration(seconds: 1), () => _showSuccessDialog());
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Row(children: [Icon(Icons.check_circle, color: Colors.green, size: 30), SizedBox(width: 10), Text('Verification Complete')]),
        content: Text('Your liveness of face detection has been successfully verified!'),
        actions: [TextButton(onPressed: () { Navigator.of(context).pop(); Navigator.of(context).pop(); }, child: Text('OK'))],
      ),
    );
  }

  // CORRECTED _convertCameraImage with better YUV420 handling
  InputImage? _convertCameraImage(CameraImage image) {
    try {
      final camera = widget.cameras[_currentCameraIndex];

      // Determine rotation
      InputImageRotation rotation = InputImageRotation.rotation0deg;
      switch (camera.sensorOrientation) {
        case 90:
          rotation = InputImageRotation.rotation90deg;
          break;
        case 180:
          rotation = InputImageRotation.rotation180deg;
          break;
        case 270:
          rotation = InputImageRotation.rotation270deg;
          break;
        default:
          rotation = InputImageRotation.rotation0deg;
      }

      // Determine format with STRICT validation
      InputImageFormat? format;

      if (Platform.isAndroid) {
        switch (image.format.group) {
          case ImageFormatGroup.nv21:
            format = InputImageFormat.nv21;
            break;
          case ImageFormatGroup.yuv420:
            format = InputImageFormat.yuv420;
            break;
          case ImageFormatGroup.bgra8888:
            format = InputImageFormat.bgra8888;
            break;
          default:
            debugPrint("❌ Unsupported Android format: ${image.format.group}");
            return null;
        }
      } else if (Platform.isIOS) {
        switch (image.format.group) {
          case ImageFormatGroup.bgra8888:
            format = InputImageFormat.bgra8888;
            break;
          default:
            debugPrint("❌ Unsupported iOS format: ${image.format.group}");
            return null;
        }
      }

      if (format == null) {
        debugPrint("❌ Could not determine input format for: ${image.format.group}");
        return null;
      }

      // Debug plane information
      debugPrint("🔍 Image details: ${image.width}x${image.height}, format: $format, planes: ${image.planes.length}");
      for (int i = 0; i < image.planes.length; i++) {
        final plane = image.planes[i];
        debugPrint("   Plane $i: ${plane.bytes.length} bytes, bytesPerRow: ${plane.bytesPerRow}");
      }


      // Collect bytes with CORRECTED format-specific handling
      Uint8List bytes;

      if (Platform.isAndroid) {
        if (format == InputImageFormat.nv21) {
          // NV21: Y plane + interleaved UV plane
          if (image.planes.length >= 2) {
            final yPlane = image.planes[0];
            final uvPlane = image.planes[1];

            bytes = Uint8List(yPlane.bytes.length + uvPlane.bytes.length);
            bytes.setRange(0, yPlane.bytes.length, yPlane.bytes);
            bytes.setRange(yPlane.bytes.length, bytes.length, uvPlane.bytes);
          } else {
            debugPrint("❌ NV21 format but insufficient planes: ${image.planes.length}");
            return null;
          }
        } else if (format == InputImageFormat.yuv420) {
          // Convert YUV420 to NV21 for ML Kit
          final nv21Bytes = _yuv420toNV21(image);
          bytes = nv21Bytes;
          format = InputImageFormat.nv21; // 👈 tell ML Kit it’s NV21

          debugPrint("📐 YUV420→NV21 conversion: total=${bytes.length}");
        }
        else if (format == InputImageFormat.bgra8888) {
          // BGRA8888 on Android
          if (image.planes.isNotEmpty) {
            bytes = Uint8List.fromList(image.planes[0].bytes);
          } else {
            debugPrint("❌ BGRA8888 format but no planes available");
            return null;
          }
        } else {
          debugPrint("❌ Unexpected format on Android: $format");
          return null;
        }
      } else {
        // iOS - BGRA8888 (single plane)
        if (image.planes.isNotEmpty) {
          bytes = Uint8List.fromList(image.planes[0].bytes);
        } else {
          debugPrint("❌ BGRA8888 format but no planes available");
          return null;
        }
      }

      // Build metadata with proper bytesPerRow
      final metadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.isNotEmpty ? image.planes[0].bytesPerRow : image.width,
      );

      debugPrint("✅ Final conversion: ${image.width}x${image.height}, format: $format, bytes: ${bytes.length}, bytesPerRow: ${metadata.bytesPerRow}");

      return InputImage.fromBytes(bytes: bytes, metadata: metadata);

    } catch (e, st) {
      debugPrint('❌ Error converting camera image: $e\n$st');
      return null;
    }
  }

  void _switchCamera() {
    if (widget.cameras.length > 1) {
      _currentCameraIndex = _currentCameraIndex == 0 ? 1 : 0;
      try {
        _cameraController?.dispose();
      } catch (_) {}
      _initializeCamera();
      setState(() {
        _faceDetected = false;
        _faceFittedInFrame = false;
        _blinkCount = 0;
        _livenessVerified = false;
        _instructionText = "Position your face in the frame";
      });
    }
  }

  @override
  void dispose() {
    try {
      _cameraController?.stopImageStream();
    } catch (_) {}
    _cameraController?.dispose();
    _faceDetector?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text('Face Liveness Detection'), backgroundColor: Colors.transparent, elevation: 0, actions: [IconButton(icon: Icon(Icons.switch_camera), onPressed: _switchCamera)]),
      body: _isCameraInitialized
          ? Stack(children: [
        CameraPreview(_cameraController!),
        CustomPaint(
          painter: FaceDetectionPainter(
            faces: _faces,
            imageSize: Size(_cameraController!.value.previewSize?.width ?? 1, _cameraController!.value.previewSize?.height ?? 1),
            faceFitted: _faceFittedInFrame,
          ),
          size: Size.infinite,
        ),
        Center(
          child: Container(
            width: 250,
            height: 300,
            decoration: BoxDecoration(
              border: Border.all(color: _faceFittedInFrame ? Colors.green : Colors.white, width: 3),
              borderRadius: BorderRadius.circular(125),
            ),
            child: _faceFittedInFrame ? Container(decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(125))) : null,
          ),
        ),
        Positioned(bottom: 100, left: 20, right: 20, child: _buildInstructionBox()),
        Positioned(top: 100, left: 20, right: 20, child: _buildStatusRow()),
      ])
          : Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(color: Colors.white), SizedBox(height: 20), Text('Initializing Camera...', style: TextStyle(color: Colors.white, fontSize: 16))])),
    );
  }

  Widget _buildInstructionBox() => Container(padding: EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)), child: Text(_instructionText, textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)));

  Widget _buildStatusRow() => Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
    _StatusIndicator(label: "Face Detected", isCompleted: _faceDetected),
    _StatusIndicator(label: "Face Fitted", isCompleted: _faceFittedInFrame),
    _StatusIndicator(label: "Blinks: $_blinkCount/2", isCompleted: _blinkCount >= 2),
  ]);
}

class _StatusIndicator extends StatelessWidget {
  final String label;
  final bool isCompleted;
  const _StatusIndicator({required this.label, required this.isCompleted});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: isCompleted ? Colors.green : Colors.red, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}

class FaceDetectionPainter extends CustomPainter {
  final List<Face> faces;
  final Size imageSize;
  final bool faceFitted;
  FaceDetectionPainter({required this.faces, required this.imageSize, required this.faceFitted});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint facePaint = Paint()..color = Colors.green..style = PaintingStyle.stroke..strokeWidth = 2.0;
    final Paint landmarkPaint = Paint()..color = Colors.red..style = PaintingStyle.fill..strokeWidth = 2.0;

    // safe scaling factors
    final double scaleX = imageSize.width > 0 ? size.width / imageSize.width : 1.0;
    final double scaleY = imageSize.height > 0 ? size.height / imageSize.height : 1.0;

    for (final face in faces) {
      final Rect rect = Rect.fromLTRB(face.boundingBox.left * scaleX, face.boundingBox.top * scaleY, face.boundingBox.right * scaleX, face.boundingBox.bottom * scaleY);
      canvas.drawRect(rect, facePaint);

      for (final lm in face.landmarks.values) {
        if (lm == null) continue;
        final dynamic p = lm.position; // might be Point<int> or Offset
        double px = 0, py = 0;
        if (p is Point) {
          px = p.x.toDouble();
          py = p.y.toDouble();
        } else if (p is Offset) {
          px = p.dx;
          py = p.dy;
        } else {
          // fallback: try toString parse (unlikely)
          continue;
        }
        final Offset scaled = Offset(px * scaleX, py * scaleY);
        canvas.drawCircle(scaled, 3.0, landmarkPaint);
      }
    }
  }

  @override
  bool shouldRepaint(FaceDetectionPainter oldDelegate) => oldDelegate.faces != faces || oldDelegate.faceFitted != faceFitted;
}
