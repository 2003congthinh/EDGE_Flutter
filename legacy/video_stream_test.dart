import 'dart:ffi' hide Size;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/src/rendering/custom_paint.dart';
import 'package:ultralytics_yolo/yolo.dart';

class VideoStreamTest extends StatefulWidget {
  const VideoStreamTest({super.key});

  @override
  State<VideoStreamTest> createState() => _VideoStreamTestState();
}

class _VideoStreamTestState extends State<VideoStreamTest> {
  CameraController? _controller;
  bool _isCameraInitialized = false;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  bool isLoading = false;
  ui.Image? uiImage;

  @override
  void initState() {
    super.initState();
    // We split "Setup" from "Start"
    _setupCameraSystem();
  }

  Future<void> _setupCameraSystem() async {
    var status = await Permission.camera.request();
    if (status.isDenied) return;

    _cameras = await availableCameras();

    if (_cameras.isNotEmpty) {
      // Find the front camera to start with
      _selectedCameraIndex = _cameras.indexWhere(
              (c) => c.lensDirection == CameraLensDirection.front
      );

      // If no front camera, just take the first one (Index 0)
      if (_selectedCameraIndex == -1) _selectedCameraIndex = 0;

      // Start the camera
      _initCameraController(_cameras[_selectedCameraIndex]);
    }
  }


  Future<void> _initCameraController(CameraDescription cameraDescription) async {
    // If a controller already exists, we MUST dispose it first to free the hardware
    if (_controller != null) {
      // STOP THE STREAM before disposing, or it will crash on switch
      if (_controller!.value.isStreamingImages) {
        await _controller!.stopImageStream();
      }
      await _controller!.dispose();
    }

    _controller = CameraController(
      cameraDescription,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await _controller!.initialize();
      if (!mounted) return;

      setState(() {
        _isCameraInitialized = true;
      });
    } catch (e) {
      debugPrint("Camera Error: $e");
    }
  }

  void _onSwitchCamera() {
    if (_cameras.length < 2) return;

    setState(() {
      _isCameraInitialized = false; // Show loader while switching
      // Cycle through the list (0 -> 1 -> 0)
      _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    });

    _initCameraController(_cameras[_selectedCameraIndex]);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized || _controller == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Aspect Ratio Fix (The Dome Fix)
    final size = MediaQuery.of(context).size;
    final deviceRatio = size.width / size.height;
    double scale = 1.0;

    // Calculate robust scale (handles both portrait and landscape properly)
    // inverse the controller ratio because the preview is usually landscape (w>h)
    // but the phone is portrait.
    final cameraAspectRatio = _controller!.value.aspectRatio;

    if (deviceRatio < 1.0) {
      // Portrait Mode
      scale = 1 / (cameraAspectRatio * deviceRatio);
    } else {
      // Landscape Mode
      scale = cameraAspectRatio / deviceRatio;
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Transform.scale(
            scale: scale,
            alignment: Alignment.center,
            child: Center(child: CameraPreview(_controller!)),
          ),

          // Back Button
          Positioned(
            top: 50,
            left: 20,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),

          // Switch Camera Button
          Positioned(
            bottom: 30,
            right: 20,
            child: FloatingActionButton(
              onPressed: _onSwitchCamera,
              backgroundColor: Colors.white24,
              child: const Icon(Icons.cameraswitch, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
