# Edge Security: Local Real-Time Facial Recognition

A fully offline, privacy-first Flutter application for edge devices that performs real-time face detection and recognition. Built for physical access control and security checks, this system leverages a custom YOLO11 detection model and TensorFlow Lite to process live camera feeds entirely on-device with zero internet reliance.
**Progress:** image cropping

```mermaid
graph LR
A(facial detection on camera frame) --> B(image cropping) --> C(facial recognition) --> D(face registration) --> E(facial security function) --> F(app media browse functions)
```

## Features

* **100% Offline Processing:** No cloud APIs or data transmission. All processing happens on the edge.
* **Custom YOLO11 Integration:** Uses a custom-trained YOLO11 model parsed through the YOLOv8 engine architecture.
* **Dynamic Coordinate Mapping:** Auto)matically handles front-facing camera mirroring and resolution scaling to map bounding boxes perfectly to the UI.
* **Memory Safe:** Includes a custom disposal pipeline to prevent C++ memory leaks and segmentation faults (SIGSEGV) during screen transitions.

## Prerequisites

* **Flutter SDK:** `>=3.0.0`
* **Device:** A physical Android phone.
* **Target OS:** Android 8.0 (API 26) or higher.

## Setup & Installation

### Clone & Install
```bash
git clone [https://github.com/2003congthinh/EDGE_Flutter.git](https://github.com/2003congthinh/EDGE_Flutter.git)
cd EDGE_Flutter
flutter clean
flutter pub get