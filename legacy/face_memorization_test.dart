import 'dart:ffi' hide Size;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'package:ultralytics_yolo/yolo.dart';

import 'package:edge_device/helpers/FacePainter.dart';
import 'package:edge_device/helpers/CropAndSave.dart';

class FaceMemorizationTest extends StatefulWidget {
  const FaceMemorizationTest({super.key});

  @override 
  State<FaceMemorizationTest> createState() => _FaceMemorizationTestState();
}

class _FaceMemorizationTestState extends State<FaceMemorizationTest> {
  CameraController? _controller;
  bool _isCameraInitialized = false;
  FlutterVision vision = FlutterVision();

  // New variables for switching
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;

  bool _isProcessing = false;
  bool _isCapturingFace = false;
  YOLO? yolo;
  List<dynamic> results = [];
  // This is for safe disposing, camera is capturing 30 frames a second, there is almost certainly a frame already inside the native C++ background thread being processed when hit back.
  // That background thread tries to finish its math, reaches for the YOLO model in memory, realizes the memory has been wiped out, and triggers a fatal memory access error that kills the entire app.
  bool _isDisposing = false;
  bool isLoading = false;
  ui.Image? uiImage;
  double? w;
  double? h;

  @override
  void initState() {
    super.initState();
    _setupCameraSystem();
    loadYOLO();
  }

  Future<void> loadYOLO() async {
    setState(() => isLoading = true);

    await vision.loadYoloModel(
        labels: 'assets/labels.txt',
        modelPath: 'assets/yolo11.tflite',
        modelVersion: "yolov8",
        numThreads: 1,
        useGpu: false
    );
    setState(() => isLoading = false);
  }

  // get permissions and find all available cameras
  Future<void> _setupCameraSystem() async {
    var status = await Permission.camera.request();
    if (status.isDenied) return;

    _cameras = await availableCameras();

    if (_cameras.isNotEmpty) {
      // find the front camera
      _selectedCameraIndex = _cameras.indexWhere(
              (c) => c.lensDirection == CameraLensDirection.front
      );

      if (_selectedCameraIndex == -1) _selectedCameraIndex = 0;

      // start the camera
      _initCameraController(_cameras[_selectedCameraIndex]);
    }
  }

  void _processCameraFrame(CameraImage image) async {
    if (_isDisposing || _isProcessing) return;
    _isProcessing = true;

    // YOLO predicts
    try {
      final result = await vision.yoloOnFrame(
          bytesList: image.planes.map((plane) => plane.bytes).toList(),
          imageHeight: image.height,
          imageWidth: image.width,
          iouThreshold: 0.4,
          confThreshold: 0.4,
          classThreshold: 0.5
      );

      // Crop and save image
      // if (result.isNotEmpty) {
      //   var face = result[0];
      //   double confidence = face['score'];
      //
      //   // Trigger crop if YOLO is over 85% sure and we aren't already capturing
      //   if (confidence > 0.85) {
      //     try {
      //       // 1. Take a clean, high-res photo using the CameraController
      //       final XFile photo = await _controller!.takePicture();
      //
      //       // 2. Pass the photo path and the YOLO box to your backend function
      //       String? savedFacePath = await cropAndSaveFace(
      //         sourceImagePath: photo.path,
      //         yoloBox: face['box'],
      //         userId: "NewUser", // You can prompt the user for this name later
      //       );
      //
      //       if (savedFacePath != null) {
      //         print("Success! Proceed to recognition phase.");
      //       }
      //
      //     } catch (e) {
      //       print("Error capturing image: $e");
      //     } finally {
      //       // Unlock after 5 seconds to prevent spamming
      //       Future.delayed(const Duration(seconds: 5), () {
      //         if (mounted) _isCapturingFace = false;
      //       });
      //     }
      //   }
      // }

      if (mounted) {
        setState(() {
          results = result;
        });
      }
    } catch (e) {
      print("YOLO Error: $e");
    } finally {
      _isProcessing = false;
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
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await _controller!.initialize();
      if (!mounted) return;

      await _controller!.startImageStream((CameraImage image) {
        _processCameraFrame(image);
      });

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
      _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    });

    _initCameraController(_cameras[_selectedCameraIndex]);
  }

  @override
  void dispose() {
    _isDisposing = true;

    if (_controller != null && _controller!.value.isStreamingImages) {
      _controller!.stopImageStream();
    }
    _controller?.dispose();

    // give the native C++ thread 200ms to finish whatever frame it is currently holding before rip the model out of RAM.
    Future.delayed(const Duration(milliseconds: 200), () {
      vision.closeYoloModel();
    });

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

    final size = MediaQuery.of(context).size;
    final deviceRatio = size.width / size.height;
    double scale = 1.0;

    // inverse the controller ratio because the preview is usually landscape (w>h) but the phone is portrait.
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

          Transform.scale(
            scale: scale,
            alignment: Alignment.center,
            child: Center(
              child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Android camera sensors are natively landscape, but the plugin rotates them 90 degrees for portrait.
                    // must flip the width and height of the preview size to match the rotated tensor.
                    final double rawCameraWidth = _controller!.value.previewSize!.height;
                    final double rawCameraHeight = _controller!.value.previewSize!.width;

                    return CustomPaint(
                      size: Size(rawCameraWidth, rawCameraHeight),
                      painter: FacePainter(
                        facesList: results,
                        cameraSize: Size(rawCameraWidth, rawCameraHeight),
                      ),
                    );
                  }
              ),
            ),
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

