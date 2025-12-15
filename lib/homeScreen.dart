import 'dart:io';
import 'package:camera/camera.dart';
import 'package:emotion_recognition_app/service.dart'; // Ensure this matches your project structure
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  CameraController? _cameraController;
  Future<void>? _initializeControllerFuture;

  // New variables for camera management
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;

  String _detectedEmotion = 'No emotion detected yet';
  bool _isProcessing = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _checkPermissionsAndInitCamera();
  }

  Future<void> _checkPermissionsAndInitCamera() async {
    try {
      var status = await Permission.camera.status;
      if (!status.isGranted) {
        status = await Permission.camera.request();
        if (!status.isGranted) {
          setState(() {
            _detectedEmotion = 'Camera permission denied';
          });
          return;
        }
      }

      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _detectedEmotion = 'No cameras available';
        });
        return;
      }

      // Default to Front camera (if available) for emotion apps, or fallback to 0
      // Usually: 0 is Back, 1 is Front on mobile.
      // We try to find the front camera first for the default view.
      int initialIndex = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
      if (initialIndex == -1) initialIndex = 0; // Fallback to first camera if no front cam

      _selectedCameraIndex = initialIndex;

      await _initCamera(_cameras[_selectedCameraIndex]);

    } catch (e) {
      setState(() {
        _detectedEmotion = 'Error initializing camera: $e';
      });
    }
  }

  // Helper to initialize a specific camera description
  Future<void> _initCamera(CameraDescription cameraDescription) async {
    final prevController = _cameraController;

    // Dispose the old controller if it exists
    if (prevController != null) {
      await prevController.dispose();
    }

    _cameraController = CameraController(
      cameraDescription,
      ResolutionPreset.medium,
      enableAudio: false, // Audio not needed for photos
    );

    _initializeControllerFuture = _cameraController!.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  // Toggle between Front and Back cameras
  void _toggleCamera() {
    if (_cameras.length < 2) {
      _showResultDialog('Only one camera available.');
      return;
    }

    setState(() {
      // Logic: If current is Back, find Front. If current is Front, find Back.
      final lensDirection = _cameraController?.description.lensDirection;
      CameraLensDirection newDirection;

      if (lensDirection == CameraLensDirection.front) {
        newDirection = CameraLensDirection.back;
      } else {
        newDirection = CameraLensDirection.front;
      }

      final newIndex = _cameras.indexWhere((c) => c.lensDirection == newDirection);

      if (newIndex != -1) {
        _selectedCameraIndex = newIndex;
        _initCamera(_cameras[_selectedCameraIndex]);
      } else {
        // Fallback: just go to the next index in the list
        _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
        _initCamera(_cameras[_selectedCameraIndex]);
      }
    });
  }

  Future<void> _captureAndDetect() async {
    if (_isProcessing ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      print('Capture aborted.');
      return;
    }

    setState(() => _isProcessing = true);
    _showLoadingDialog();

    try {
      await _initializeControllerFuture;

      // Turn off flash for emotion detection to avoid glare
      await _cameraController!.setFlashMode(FlashMode.off);

      final image = await _cameraController!.takePicture();

      dynamic input;
      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        input = bytes;
        print('Web capture: ${bytes.length} bytes');
      } else {
        input = File(image.path);
        print('Mobile capture: ${image.path}');
      }

      // Call existing service
      final emotions = await EmotionService().detectEmotions(input);

      Navigator.pop(context); // close loading
      if (emotions.isEmpty) {
        _showResultDialog('No emotion detected.');
      } else {
        final topEmotion = emotions.entries
            .reduce((a, b) => a.value > b.value ? a : b)
            .key;
        final confidence = (emotions[topEmotion] * 100).toStringAsFixed(0);
        _showResultDialog('Detected: $topEmotion ($confidence%)');
      }
    } catch (e) {
      Navigator.pop(context);
      _showResultDialog('Error: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _uploadAndDetect() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() => _isProcessing = true);
    _showLoadingDialog();

    try {
      dynamic input;
      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        input = bytes;
        print('Web upload: ${bytes.length} bytes');
      } else {
        input = File(picked.path);
        print('Mobile upload: ${picked.path}');
      }

      final emotions = await EmotionService().detectEmotions(input);

      Navigator.pop(context);
      if (emotions.isEmpty) {
        _showResultDialog('No emotion detected.');
      } else {
        final topEmotion = emotions.entries
            .reduce((a, b) => a.value > b.value ? a : b)
            .key;
        final confidence = (emotions[topEmotion] * 100).toStringAsFixed(0);
        _showResultDialog('Detected: $topEmotion ($confidence%)');
      }
    } catch (e) {
      Navigator.pop(context);
      _showResultDialog('Error: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          Center(
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text("Detecting emotion...",
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
    );
  }

  void _showResultDialog(String message) {
    showDialog(
      context: context,
      builder: (_) =>
          AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Text("Detection Result"),
            content: Text(message, style: const TextStyle(fontSize: 16)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK"),
              )
            ],
          ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emotion Recognition', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        backgroundColor: Colors.deepPurple,
        //Action Button to Flip Camera
        actions: [
          IconButton(
            icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
            onPressed: _toggleCamera,
            tooltip: 'Switch Camera',
          ),
        ],
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: _cameraController == null
                ? const Center(child: Text('Initializing camera...'))
                : FutureBuilder(
              future: _initializeControllerFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                  return Center(
                    child: Stack(
                      children: [
                        // Helper to ensure camera ratio fits the screen
                        CameraPreview(_cameraController!),

                        // Face Guide Overlay
                        CustomPaint(
                          painter: FaceGuidePainter(),
                          child: Container(
                            color: Colors.transparent,
                            width: double.infinity,
                            height: double.infinity,
                            child: const Center(
                              child: Text(
                                "Align your face within the box",
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                } else {
                  return const Center(child: CircularProgressIndicator());
                }
              },
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.camera_alt, color: Colors.white,),
                  label: const Text('Capture & Detect', style: TextStyle(fontSize: 16, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isProcessing ? null : _captureAndDetect,
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.photo_library, color: Colors.white,),
                  label: const Text('Upload Picture', style: TextStyle(fontSize: 16, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isProcessing ? null : _uploadAndDetect,
                ),
                const SizedBox(height: 25),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FaceGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    // Optional: darken area outside the rectangle
    final overlayPaint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    final rectWidth = size.width * 0.7;
    final rectHeight = size.height * 0.5;
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: rectWidth,
      height: rectHeight,
    );

    // Draw dim overlay
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), overlayPaint);

    // Clear the rectangle area (to make it transparent)
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());
    canvas.drawRect(rect, Paint()..blendMode = BlendMode.clear);
    canvas.restore();

    // Draw white border around the clear rectangle
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}