import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  await dotenv.load(fileName: ".env");
  WidgetsFlutterBinding.ensureInitialized();
  
  CameraDescription? firstCamera;
  if (!kIsWeb) {
    final cameras = await availableCameras();
    if (cameras.isNotEmpty) {
      firstCamera = cameras.first;
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
      title: 'Explain App',
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

class HomePage extends StatefulWidget {
  final CameraDescription? camera;

  const HomePage({super.key, required this.camera});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  final FlutterTts _flutterTts = FlutterTts();
  List<Map<String, String>> _imageHistory = [];
  bool _isAnalyzing = false;
  bool _isSpeaking = false;
  Map<String, Uint8List> _webImageBytes = {};

  @override
  void initState() {
    super.initState();
    if (widget.camera != null) {
      _controller = CameraController(
        widget.camera!,
        ResolutionPreset.high,
      );
      _initializeControllerFuture = _controller?.initialize();
    }
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getString('imageHistory');
    if (history != null) {
      setState(() {
        _imageHistory = List<Map<String, String>>.from(
          (json.decode(history) as List).map((item) => Map<String, String>.from(item as Map))
        );
        // Sort by timestamp, most recent first
        _imageHistory.sort((a, b) => b['timestamp']!.compareTo(a['timestamp']!));
      });
    }
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    // Sort before saving
    _imageHistory.sort((a, b) => b['timestamp']!.compareTo(a['timestamp']!));
    await prefs.setString('imageHistory', json.encode(_imageHistory));
  }

  Future<void> _takePicture() async {
    try {
      await _initializeControllerFuture;
      final image = await _controller?.takePicture();
      if (image != null) {
        final explanation = await _getExplanation(image.path);

        setState(() {
          _imageHistory.add({
            'path': image.path,
            'timestamp': DateTime.now().toString().split('.')[0], // Remove milliseconds
            'explanation': explanation,
          });
        });

        _saveHistory();
      }
    } catch (e) {
      print(e);
    }
  }

  Future<String> _getExplanation(String imagePath, {Uint8List? fileBytes}) async {
    setState(() {
      _isAnalyzing = true;
    });

    try {
      final apiKey = dotenv.env['OPENAI_API_KEY'] ?? '';
      final url = Uri.parse('https://api.openai.com/v1/chat/completions');

      // Get the image bytes
      final imageBytes = fileBytes ?? await File(imagePath).readAsBytes();

      // Convert image to base64
      String base64Image = base64Encode(imageBytes);

      // Create the request payload
      final payload = {
        'model': 'gpt-4o-mini',
        'messages': [
          {
            'role': 'system',
            'content': 'You are an assistant that explains images in French for 10-year-old children.'
          },
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text': 'Explique cette image comme si tu parlais à un enfant de 10 ans.'
              },
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:image/jpeg;base64,$base64Image'
                }
              }
            ]
          }
        ]
      };

      // Send the request
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json; charset=utf-8',
        },
        body: json.encode(payload),
      );

      // Ensure the response is decoded as UTF-8
      final responseBody = utf8.decode(response.bodyBytes);

      if (response.statusCode == 200) {
        final data = json.decode(responseBody);
        return data['choices'][0]['message']['content'];
      } else {
        log('Error response: ${response.statusCode} - $responseBody');
        await showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Erreur'),
              content: SelectableText(
                'Erreur lors de l\'analyse de l\'image.\nDétails: ${response.statusCode} - $responseBody',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
        return 'Erreur lors de l\'analyse de l\'image.';
      }
    } finally {
      setState(() {
        _isAnalyzing = false;
      });
    }
  }

  Future<void> _deleteImage(int index) async {
    setState(() {
      _imageHistory.removeAt(index);
    });
    _saveHistory();
  }

  Future<void> _speak(String text) async {
    if (_isSpeaking) {
      await _flutterTts.stop();
      setState(() {
        _isSpeaking = false;
      });
      return;
    }

    setState(() {
      _isSpeaking = true;
    });
    await _flutterTts.setLanguage('fr-FR');
    await _flutterTts.speak(text);
    
    _flutterTts.setCompletionHandler(() {
      setState(() {
        _isSpeaking = false;
      });
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Explain App'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: _imageHistory.isEmpty
                    ? Center(
                        child: Text(
                          'Prenez ou sélectionnez une photo pour commencer',
                          style: theme.textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        itemCount: _imageHistory.length,
                        itemBuilder: (context, index) {
                          final item = _imageHistory[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 8.0,
                            ),
                            elevation: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ClipRRect(
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(12),
                                  ),
                                  child: AspectRatio(
                                    aspectRatio: 16 / 9,
                                    child: kIsWeb
                                        ? Image.memory(
                                            _webImageBytes[item['path']] ?? Uint8List(0),
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) {
                                              log('Error loading image: $error');
                                              return const Center(
                                                child: Icon(Icons.error_outline, size: 48, color: Colors.red),
                                              );
                                            },
                                          )
                                        : Image.file(
                                            File(item['path']!),
                                            fit: BoxFit.cover,
                                          ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['timestamp']!,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.secondary,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        item['explanation']!,
                                        style: theme.textTheme.bodyLarge,
                                      ),
                                    ],
                                  ),
                                ),
                                ButtonBar(
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        _isSpeaking ? Icons.stop : Icons.volume_up,
                                        color: theme.colorScheme.primary,
                                      ),
                                      onPressed: () => _speak(item['explanation']!),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.delete,
                                        color: theme.colorScheme.error,
                                      ),
                                      onPressed: () => _deleteImage(index),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ElevatedButton.icon(
                    onPressed: _isAnalyzing
                        ? null
                        : () async {
                            log('Take photo button pressed');
                            final result = await FilePicker.platform.pickFiles(type: FileType.image);
                            if (result != null) {
                              if (kIsWeb) {
                                // Handle web platform
                                final bytes = result.files.single.bytes;
                                if (bytes != null) {
                                  log('File selected on web');
                                  final explanation = await _getExplanation('dummy_path', fileBytes: bytes);
                                  log('Explanation received: $explanation');

                                  final timestamp = DateTime.now().toString();
                                  setState(() {
                                    _webImageBytes[timestamp] = bytes;
                                    _imageHistory.add({
                                      'path': timestamp,
                                      'timestamp': timestamp,
                                      'explanation': explanation,
                                    });
                                  });

                                  log('Image history updated');
                                  _saveHistory();
                                }
                              } else {
                                // Handle native platforms
                                final filePath = result.files.single.path;
                                if (filePath != null) {
                                  log('File selected: $filePath');
                                  final explanation = await _getExplanation(filePath);
                                  log('Explanation received: $explanation');

                                  setState(() {
                                    _imageHistory.add({
                                      'path': filePath,
                                      'timestamp': DateTime.now().toString(),
                                      'explanation': explanation,
                                    });
                                  });

                                  log('Image history updated');
                                  _saveHistory();
                                }
                              }
                            } else {
                              log('No file selected');
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Prendre une photo'),
                  ),
                ),
              ),
            ],
          ),
          if (_isAnalyzing)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Analyse en cours...',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
