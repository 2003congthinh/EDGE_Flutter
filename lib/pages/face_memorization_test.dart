import 'dart:ffi' hide Size;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'package:flutter/src/rendering/custom_paint.dart';
import 'package:ultralytics_yolo/yolo.dart';

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
        modelVersion: "yolov11",
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

    try {
      final result = await vision.yoloOnFrame(
          bytesList: image.planes.map((plane) => plane.bytes).toList(),
          imageHeight: image.height,
          imageWidth: image.width,
          iouThreshold: 0.4,
          confThreshold: 0.4,
          classThreshold: 0.5
      );

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

class FacePainter extends CustomPainter {
  final List<dynamic> facesList;
  final Size cameraSize; // raw resolution of the camera frame

  FacePainter({required this.facesList, required this.cameraSize});

  @override
  void paint(Canvas canvas, Size size) {
    // calculate how much the camera image was stretched to fit the screen
    final double scaleX = size.width / cameraSize.width;
    final double scaleY = size.height / cameraSize.height;

    Paint p = Paint();
    p.color = Colors.red;
    p.style = PaintingStyle.stroke;
    p.strokeWidth = 4.0;

    for (var face in facesList) {
      // flutter_vision returns the bounding box as an array: [left, top, right, bottom]
      List<dynamic> box = face['box'];

      // Multiply the raw YOLO coordinates by the screen scale
      double left = box[0].toDouble() * scaleX;
      double top = (cameraSize.height - box[1].toDouble()) * scaleY;
      double right = box[2].toDouble() * scaleX;
      double bottom = (cameraSize.height - box[3].toDouble()) * scaleY;

      Rect rect = Rect.fromLTRB(left, top, right, bottom);
      canvas.drawRect(rect, p);

      // show the confidence score above the box
      TextSpan span = TextSpan(
        style: const TextStyle(color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold),
        text: "${(face['score'] * 100).toStringAsFixed(0)}%",
      );
      TextPainter tp = TextPainter(text: span, textAlign: TextAlign.left, textDirection: TextDirection.ltr);
      tp.layout();
      tp.paint(canvas, Offset(left, top - 20));
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true; // We want to repaint every time a new frame arrives
  }
}