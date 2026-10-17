import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

Future<String?> cropAndSaveFace({
  required String sourceImagePath,
  required List<dynamic> yoloBox,
  required String userId,
}) async {
  try {
    // Read the full image from disk and decode it
    final File sourceFile = File(sourceImagePath);
    final Uint8List bytes = await sourceFile.readAsBytes();
    final img.Image? fullImage = img.decodeImage(bytes);

    if (fullImage == null) {
      print("Failed to decode image.");
      return null;
    }

    // Extract YOLO coordinates
    int left = yoloBox[0].toInt();
    int top = yoloBox[1].toInt();
    int right = yoloBox[2].toInt();
    int bottom = yoloBox[3].toInt();

    // Safety Check: Ensure the crop area doesn't exceed the image boundaries
    int safeX = left.clamp(0, fullImage.width);
    int safeY = top.clamp(0, fullImage.height);
    int safeWidth = (right - left).clamp(0, fullImage.width - safeX);
    int safeHeight = (bottom - top).clamp(0, fullImage.height - safeY);

    // Perform the crop instantly in RAM
    img.Image croppedFace = img.copyCrop(
      fullImage,
      x: safeX,
      y: safeY,
      width: safeWidth,
      height: safeHeight,
    );

    // Optional: Standardize the size for recognition models (e.g., 112x112)
    img.Image resizedFace = img.copyResize(croppedFace, width: 112, height: 112);

    // Save to secure App Memory (Hidden from public gallery)
    final directory = await getApplicationDocumentsDirectory();
    final String fileName = '${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final String savedPath = '${directory.path}/$fileName';

    final File savedFile = File(savedPath);
    await savedFile.writeAsBytes(img.encodeJpg(resizedFace));

    print("✅ Face securely saved at: $savedPath");
    return savedPath;

  } catch (e) {
    print("❌ Error cropping and saving face: $e");
    return null;
  }
}