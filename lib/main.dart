import 'dart:typed_data';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Nhận diện khuôn mặt',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
      home: const FaceDetectionPage(),
    );
  }
}

class FaceDetectionPage extends StatefulWidget {
  const FaceDetectionPage({super.key});

  @override
  State<FaceDetectionPage> createState() =>
      _FaceDetectionPageState();
}

class _FaceDetectionPageState extends State<FaceDetectionPage> {
  CameraController? controller;

  final FaceDetector detector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableLandmarks: true,
      enableContours: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.fast,
    ),
  );

  bool detecting = false;
  bool takingPicture = false;

  int faceCount = 0;
  List<Face> faces = [];

  String? photoPath;

  @override
  void initState() {
    super.initState();
    startCamera();
  }

  // =========================
  // CAMERA
  // =========================

  Future<void> startCamera() async {
    if (cameras.isEmpty) return;

    controller = CameraController(
      cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );

    await controller!.initialize();

    if (!mounted) return;

    setState(() {});

    startStream();
  }

  // =========================
  // CAMERA STREAM
  // =========================

  Future<void> startStream() async {
    if (controller == null) return;

    if (controller!.value.isStreamingImages) {
      return;
    }

    await controller!.startImageStream(
      (CameraImage image) {
        if (detecting || takingPicture) return;

        detecting = true;

        detectFaces(image).whenComplete(() {
          detecting = false;
        });
      },
    );
  }

  // =========================
  // NHẬN DIỆN REALTIME
  // =========================

  Future<void> detectFaces(CameraImage image) async {
    try {
      final inputImage = convertImage(image);

      if (inputImage == null) return;

      final result =
          await detector.processImage(inputImage);

      if (!mounted) return;

      setState(() {
        faces = result;
        faceCount = result.length;
      });
    } catch (e) {
      debugPrint('Lỗi nhận diện: $e');
    }
  }

  // =========================
  // CHUYỂN ẢNH CAMERA
  // =========================

  InputImage? convertImage(CameraImage image) {
    if (image.planes.isEmpty) {
      return null;
    }

    final camera = controller!.description;

    final rotation =
        InputImageRotationValue.fromRawValue(
      camera.sensorOrientation,
    );

    if (rotation == null) return null;

    final bytes = Uint8List.fromList(
      image.planes.first.bytes,
    );

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(
          image.width.toDouble(),
          image.height.toDouble(),
        ),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow:
            image.planes.first.bytesPerRow,
      ),
    );
  }

  // =========================
  // CHỤP ẢNH
  // =========================

  Future<void> takePhoto() async {
    if (controller == null ||
        !controller!.value.isInitialized ||
        takingPicture) {
      return;
    }

    setState(() {
      takingPicture = true;
    });

    try {
      // Dừng camera stream
      if (controller!.value.isStreamingImages) {
        await controller!.stopImageStream();
      }

      // Chụp ảnh
      final XFile photo =
          await controller!.takePicture();

      photoPath = photo.path;

      // Phân tích ảnh
      final result =
          await detector.processImage(
        InputImage.fromFilePath(photo.path),
      );

      if (!mounted) return;

      setState(() {
        faces = result;
        faceCount = result.length;
      });

      // Hiện kết quả
      showAnalysis(result);

    } catch (e) {
      debugPrint('Lỗi chụp ảnh: $e');
    }

    // Mở camera realtime lại
    if (mounted) {
      await startStream();

      setState(() {
        takingPicture = false;
      });
    }
  }

  // =========================
  // HIỆN KẾT QUẢ PHÂN TÍCH
  // =========================

  void showAnalysis(List<Face> result) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [

                const Text(
                  'KẾT QUẢ PHÂN TÍCH',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 15),

                if (photoPath != null)
                  ClipRRect(
                    borderRadius:
                        BorderRadius.circular(15),
                    child: Image.file(
                      File(photoPath!),
                      height: 220,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),

                const SizedBox(height: 15),

                Text(
                  'Số khuôn mặt: ${result.length}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 10),

                if (result.isEmpty)
                  const Text(
                    'Không phát hiện khuôn mặt.',
                    style: TextStyle(fontSize: 16),
                  ),

                for (int i = 0;
                    i < result.length;
                    i++)
                  buildFaceResult(
                    i,
                    result[i],
                  ),

                const SizedBox(height: 15),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text('ĐÓNG'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // =========================
  // THÔNG TIN KHUÔN MẶT
  // =========================

  Widget buildFaceResult(
    int index,
    Face face,
  ) {
    String smile = 'Không xác định';
    String leftEye = 'Không xác định';
    String rightEye = 'Không xác định';

    if (face.smilingProbability != null) {
      smile =
          '${(face.smilingProbability! * 100).toStringAsFixed(0)}%'
          ' ${face.smilingProbability! >= 0.5 ? '(Đang cười)' : '(Không cười)'}';
    }

    if (face.leftEyeOpenProbability != null) {
      leftEye =
          '${(face.leftEyeOpenProbability! * 100).toStringAsFixed(0)}%'
          ' ${face.leftEyeOpenProbability! >= 0.5 ? '(Mở)' : '(Nhắm)'}';
    }

    if (face.rightEyeOpenProbability != null) {
      rightEye =
          '${(face.rightEyeOpenProbability! * 100).toStringAsFixed(0)}%'
          ' ${face.rightEyeOpenProbability! >= 0.5 ? '(Mở)' : '(Nhắm)'}';
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            '👤 Khuôn mặt ${index + 1}',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 5),

          Text('👁 Mắt trái: $leftEye'),

          Text('👁 Mắt phải: $rightEye'),

          Text('🙂 Nụ cười: $smile'),
        ],
      ),
    );
  }

  // =========================
  // VẼ KHUNG KHUÔN MẶT
  // =========================

  Widget faceBoxes() {
    if (controller == null ||
        !controller!.value.isInitialized ||
        faces.isEmpty) {
      return const SizedBox();
    }

    final previewSize =
        controller!.value.previewSize;

    if (previewSize == null) {
      return const SizedBox();
    }

    return Positioned.fill(
      child: CustomPaint(
        painter: FacePainter(
          faces: faces,
          imageSize: previewSize,
        ),
      ),
    );
  }

  @override
  void dispose() {
    controller?.dispose();
    detector.close();
    super.dispose();
  }

  // =========================
  // GIAO DIỆN
  // =========================

  @override
  Widget build(BuildContext context) {
    if (controller == null ||
        !controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Nhận diện khuôn mặt',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),

      body: Stack(
        children: [

          // CAMERA
          Positioned.fill(
            child: CameraPreview(controller!),
          ),

          // KHUNG KHUÔN MẶT
          faceBoxes(),

          // SỐ KHUÔN MẶT
          Positioned(
            top: 15,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.75),
                borderRadius:
                    BorderRadius.circular(15),
              ),
              child: Text(
                'Số khuôn mặt: $faceCount',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          // NÚT CHỤP ẢNH
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: SizedBox(
              height: 60,
              child: ElevatedButton.icon(
                onPressed:
                    takingPicture ? null : takePhoto,
                icon: takingPicture
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.camera_alt,
                        size: 30,
                      ),
                label: Text(
                  takingPicture
                      ? 'ĐANG PHÂN TÍCH...'
                      : 'CHỤP & PHÂN TÍCH',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =========================
// VẼ KHUNG
// =========================

class FacePainter extends CustomPainter {
  final List<Face> faces;
  final Size imageSize;

  FacePainter({
    required this.faces,
    required this.imageSize,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final paint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    for (final face in faces) {
      final box = face.boundingBox;

      final scaleX =
          size.width / imageSize.height;

      final scaleY =
          size.height / imageSize.width;

      final rect = Rect.fromLTRB(
        box.left * scaleX,
        box.top * scaleY,
        box.right * scaleX,
        box.bottom * scaleY,
      );

      canvas.drawRect(
        rect,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(
    covariant FacePainter oldDelegate,
  ) {
    return true;
  }
}