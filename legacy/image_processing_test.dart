import 'dart:ffi' hide Size;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/src/rendering/custom_paint.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class ImageProcessingTest extends StatefulWidget {
  const ImageProcessingTest({super.key});

  @override
  State<ImageProcessingTest> createState() => _ImageProcessingTestState();
}

class _ImageProcessingTestState extends State<ImageProcessingTest> {
  YOLO? yolo;
  File? selectedImage;
  List<dynamic> results = [];
  bool isLoading = false;
  ui.Image? uiImage;
  double? w;
  double? h;

  @override
  void initState() {
    super.initState();
    loadYOLO();
  }

  Future<void> loadYOLO() async {
    setState(() => isLoading = true);

    yolo = YOLO(
      // modelPath: 'assets/yolo11.tflite',
      modelPath: 'yolo11',
      task: YOLOTask.detect,
    );

    await yolo!.loadModel();
    setState(() => isLoading = false);
  }

  Future<void> pickAndDetect() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      setState(() {
        selectedImage = File(image.path);
        isLoading = true;
      });

      final imageBytes = await selectedImage!.readAsBytes();
      final decodedImage = await decodeImageFromList(imageBytes);
      final detectionResults = await yolo!.predict(imageBytes);

      setState(() {
        uiImage = decodedImage;
        w = decodedImage.width.toDouble();
        h = decodedImage.height.toDouble();
        results = detectionResults['boxes'] ?? [];
        // print("**************");
        // print(results);
        // print("**************");
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('YOLO Quick Demo')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (selectedImage != null)
                FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: w,
                    height: h,
                    child: CustomPaint(
                      painter: FacePainter(facesList: results, imageFile: uiImage),
                    ),
                  ),
                ),

              SizedBox(height: 20),

              if (isLoading)
                CircularProgressIndicator()
              else
                Text('Detected ${results.length} objects'),

              SizedBox(height: 20),

              ElevatedButton(
                onPressed: yolo != null ? pickAndDetect : null,
                child: Text('Pick Image & Detect'),
              ),

              SizedBox(height: 20),

              // Show detection results
              Expanded(
                child: ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final detection = results[index];
                    return ListTile(
                      title: Text(detection['class'] ?? 'Unknown'),
                      subtitle: Text(
                          'Confidence: ${(detection['confidence'] * 100).toStringAsFixed(1)}%'
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FacePainter extends CustomPainter {
  List<dynamic> facesList;
  ui.Image? imageFile;
  FacePainter({required this.facesList, @required this.imageFile});

  @override
  void paint(Canvas canvas, Size size){
    if(imageFile != null) {
      canvas.drawImage(imageFile!, Offset.zero, Paint());
    }

    Paint p = Paint();
    p.color = Colors.red;
    p.style = PaintingStyle.stroke;
    p.strokeWidth = 8;

    for (var i =0; i < facesList.length; i++){
      // print("*********************");
      // print(facesList[i]);
      // print("*********************");
      var face = facesList[i];

      double left = face['x1'].toDouble();
      double top = face['y1'].toDouble();
      double right = face['x2'].toDouble();
      double bottom = face['y2'].toDouble();

      Rect rect = Rect.fromLTRB(left, top, right, bottom);

      canvas.drawRect(rect, p);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }
}