import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'settings_page.dart';
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
  final Map<String, Uint8List> _imageCache = {};
  ImagePicker? _imagePicker;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _imagePicker = ImagePicker();
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
            (json.decode(history) as List)
                .map((item) => Map<String, String>.from(item as Map)));
        _imageHistory
            .sort((a, b) => b['timestamp']!.compareTo(a['timestamp']!));
      });

      // Load images from SharedPreferences
      for (var item in _imageHistory) {
        final imageData = prefs.getString('image_${item['path']}');
        if (imageData != null) {
          _imageCache[item['path']!] = base64Decode(imageData);
        }
      }
    }
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    _imageHistory.sort((a, b) => b['timestamp']!.compareTo(a['timestamp']!));
    await prefs.setString('imageHistory', json.encode(_imageHistory));
  }

  Future<String> _saveImageToStorage(String sourcePath, Uint8List bytes) async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = DateTime.now().toString();

    if (kIsWeb) {
      await prefs.setString('image_$timestamp', base64Encode(bytes));
      _imageCache[timestamp] = bytes;
      return timestamp;
    } else {
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'image_$timestamp${path.extension(sourcePath)}';
      final destinationPath = path.join(directory.path, fileName);

      await File(destinationPath).writeAsBytes(bytes);
      // Also cache in SharedPreferences for persistence
      await prefs.setString('image_$destinationPath', base64Encode(bytes));
      _imageCache[destinationPath] = bytes;
      return destinationPath;
    }
  }

  Future<void> _takePicture() async {
    try {
      debugPrint('Taking picture, is web: $kIsWeb');
      if (kIsWeb) {
        final picker = ImagePicker();
        debugPrint('Opening image picker on web');
        final XFile? image =
            await picker.pickImage(source: ImageSource.gallery);

        if (image != null) {
          debugPrint('Image selected, reading bytes');
          final bytes = await image.readAsBytes();
          debugPrint('Bytes read, saving to storage');
          final storagePath = await _saveImageToStorage(image.path, bytes);
          debugPrint('Getting explanation');
          final explanation =
              await _getExplanation('web_image', fileBytes: bytes);
          debugPrint('Explanation received');

          setState(() {
            _imageHistory.add({
              'path': storagePath,
              'timestamp': DateTime.now().toString().split('.')[0],
              'explanation': explanation,
            });
          });

          _saveHistory();
        } else {
          debugPrint('No image selected');
        }
      } else {
        // Ensure controller is initialized
        if (_controller == null || !_controller!.value.isInitialized) {
          debugPrint('Reinitializing camera controller');
          if (widget.camera != null) {
            _controller = CameraController(
              widget.camera!,
              ResolutionPreset.high,
            );
            _initializeControllerFuture = _controller?.initialize();
          }
        }

        // Wait for controller initialization
        if (_initializeControllerFuture != null) {
          await _initializeControllerFuture;
          final image = await _controller?.takePicture();
          if (image != null) {
            final bytes = await image.readAsBytes();
            final storagePath = await _saveImageToStorage(image.path, bytes);
            final explanation =
                await _getExplanation(storagePath, fileBytes: bytes);

            setState(() {
              _imageHistory.add({
                'path': storagePath,
                'timestamp': DateTime.now().toString().split('.')[0],
                'explanation': explanation,
              });
            });

            _saveHistory();
          }
        }
      }
    } catch (e, stackTrace) {
      debugPrint('Error taking picture: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  Future<void> _deleteImage(int index) async {
    final item = _imageHistory[index];
    final prefs = await SharedPreferences.getInstance();

    // Remove from SharedPreferences
    await prefs.remove('image_${item['path']}');

    if (!kIsWeb) {
      // Remove physical file on mobile
      final file = File(item['path']!);
      if (await file.exists()) {
        await file.delete();
      }
    }

    // Remove from cache
    _imageCache.remove(item['path']);

    setState(() {
      _imageHistory.removeAt(index);
    });
    _saveHistory();
  }

  Future<String> _getExplanation(String imagePath,
      {Uint8List? fileBytes}) async {
    setState(() {
      _isAnalyzing = true;
    });

    try {
      // Get API key from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final apiKey = prefs.getString('openai_api_key');

      if (apiKey == null || apiKey.isEmpty) {
        await showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Clé API manquante'),
              content: const Text(
                  'Veuillez configurer votre clé API OpenAI dans les paramètres.'),
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const SettingsPage()),
                    );
                  },
                  child: const Text('Aller aux paramètres'),
                ),
              ],
            );
          },
        );
        throw Exception('OpenAI API key not configured');
      }

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
            'content':
                'You are an assistant that explains the contents of images in French for 10-year-old children.'
          },
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text':
                    'Décris ce que contient cette image comme si tu parlais à un enfant de 10 ans.'
              },
              {
                'type': 'image_url',
                'image_url': {'url': 'data:image/jpeg;base64,$base64Image'}
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

  Future<void> _handleImageSelection({bool fromCamera = false}) async {
    try {
      debugPrint('Starting image selection, fromCamera: $fromCamera');
      setState(() {
        _isAnalyzing = true;
      });

      final XFile? image = await _imagePicker?.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 80, // Reduce image size
        maxWidth: 1920, // Limit max dimensions
        maxHeight: 1080,
      );

      if (image != null) {
        debugPrint('Image selected: ${image.path}');
        final bytes = await image.readAsBytes();
        debugPrint('Image bytes read, size: ${bytes.length}');

        final storagePath = await _saveImageToStorage(image.path, bytes);
        debugPrint('Image saved to storage: $storagePath');

        final explanation =
            await _getExplanation(storagePath, fileBytes: bytes);
        debugPrint('Got explanation');

        if (!mounted) return; // Check if widget is still mounted

        setState(() {
          _imageCache[storagePath] = bytes;
          _imageHistory.add({
            'path': storagePath,
            'timestamp': DateTime.now().toString().split('.')[0],
            'explanation': explanation,
          });
        });

        // Add this after setState
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }

        await _saveHistory();
        debugPrint('History saved');
      } else {
        debugPrint('No image selected');
      }
    } catch (e, stackTrace) {
      debugPrint('Error handling image selection: $e');
      debugPrint('Stack trace: $stackTrace');
    } finally {
      if (mounted) {
        // Check if widget is still mounted
        setState(() {
          _isAnalyzing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _controller?.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Explique-moi... v${Version.number} (${Version.build})'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
            },
          ),
        ],
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
                        controller: _scrollController,
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
                                    child: _imageCache.containsKey(item['path'])
                                        ? Image.memory(
                                            _imageCache[item['path']]!,
                                            fit: BoxFit.cover,
                                          )
                                        : kIsWeb
                                            ? const Center(
                                                child: Text(
                                                    'Image non disponible'),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['timestamp']!,
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
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
                                OverflowBar(
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        _isSpeaking
                                            ? Icons.stop
                                            : Icons.volume_up,
                                        color: theme.colorScheme.primary,
                                      ),
                                      onPressed: () =>
                                          _speak(item['explanation']!),
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
                            debugPrint('Camera button pressed');
                            if (kIsWeb) {
                              debugPrint('Web platform - using gallery');
                              await _handleImageSelection();
                            } else {
                              debugPrint('Mobile platform - showing options');
                              if (!mounted) return;
                              showModalBottomSheet<void>(
                                context: context,
                                builder: (BuildContext context) {
                                  return SafeArea(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        ListTile(
                                          leading: const Icon(Icons.camera_alt),
                                          title:
                                              const Text('Prendre une photo'),
                                          onTap: () {
                                            Navigator.pop(context);
                                            _handleImageSelection(
                                                fromCamera: true);
                                          },
                                        ),
                                        ListTile(
                                          leading:
                                              const Icon(Icons.photo_library),
                                          title:
                                              const Text('Choisir une image'),
                                          onTap: () {
                                            Navigator.pop(context);
                                            _handleImageSelection();
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
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
