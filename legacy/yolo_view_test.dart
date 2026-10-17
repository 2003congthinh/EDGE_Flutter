import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:ultralytics_yolo/yolo_view.dart';

class YoloViewTest extends StatefulWidget {
  const YoloViewTest({super.key});

  @override
  _YoloViewTestState createState() => _YoloViewTestState();
}

class _YoloViewTestState extends State<YoloViewTest> {
  YOLO? yolo;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    loadYOLO();
  }

  Future<void> loadYOLO() async {
    setState(() => isLoading = true);

    yolo = YOLO(
      modelPath: 'yolo11',
      task: YOLOTask.detect,
    );

    await yolo!.loadModel();
    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('YOLO Quick Demo')),
        body: Center(
          child: YOLOView(
            modelPath: 'yolo11',
            lensFacing: LensFacing.front,
            task: YOLOTask.detect,
            onResult: (results) {
              print('Detected ${results.length} objects');
              print('Detected object at ${results[0].boundingBox}');
            },
          )
        ),
      ),
    );
  }
}