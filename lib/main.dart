import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'screens/home_page.dart';
import 'version.dart';

void main() async {
  print('DEBUG: App starting... Check console at chrome://inspect');
  WidgetsFlutterBinding.ensureInitialized();

  CameraDescription? firstCamera;
  if (!kIsWeb) {
    try {
      final cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        firstCamera = cameras.first;
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  runApp(MyApp(camera: firstCamera));
}

class MyApp extends StatelessWidget {
  final CameraDescription? camera;

  const MyApp({super.key, this.camera});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Explique-moi...',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red.shade400,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: HomePage(camera: camera),
    );
  }
}
