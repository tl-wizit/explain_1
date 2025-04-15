import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:explain_1/models/history_item.dart';
import 'package:explain_1/services/tts_service.dart';
import 'package:explain_1/utils/image_utils.dart';
import 'package:explain_1/screens/settings_page.dart';
import 'package:explain_1/version.dart';

class HomePage extends StatefulWidget {
  final CameraDescription? camera;

  const HomePage({super.key, this.camera});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final TTSService _ttsService;
  List<HistoryItem> _imageHistory = [];
  bool _isAnalyzing = false;
  final Map<String, Uint8List> _imageCache = {};
  final ImagePicker _imagePicker = ImagePicker();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _ttsService = TTSService(onStateChanged: () {
      if (mounted) setState(() {});
    });
    _loadHistory();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Check for voice changes when returning from settings page
    _checkForVoiceChanges();
  }

  Future<void> _checkForVoiceChanges() async {
    final prefs = await SharedPreferences.getInstance();
    final savedVoice = prefs.getString('selected_voice');
    
    // If the voice has changed, reload it in our TTS service
    if (savedVoice != null && savedVoice != _ttsService.selectedVoice) {
      debugPrint('Voice changed from ${_ttsService.selectedVoice} to $savedVoice, reloading...');
      await _ttsService.loadVoice(savedVoice);
    }
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getString('imageHistory');
    if (history != null) {
      try {
        final List<dynamic> historyList = json.decode(history);
        setState(() {
          _imageHistory = historyList
              .map((item) => HistoryItem.fromJson(Map<String, dynamic>.from(item)))
              .toList();
        });
        
        // Sort by timestamp (newest first)
        _imageHistory.sort((a, b) => b.timestamp.compareTo(a.timestamp));

        // Load images from SharedPreferences
        for (var item in _imageHistory) {
          final imageData = prefs.getString('image_${item.path}');
          if (imageData != null) {
            _imageCache[item.path] = base64Decode(imageData);
          }
        }
      } catch (e) {
        debugPrint('Error loading history: $e');
      }
    }
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Sort by timestamp (newest first)
      _imageHistory.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      await prefs.setString('imageHistory', json.encode(_imageHistory.map((e) => e.toJson()).toList()));
      debugPrint('History saved');
    } catch (e) {
      debugPrint('Error saving history: $e');
    }
  }

  Future<void> _deleteImage(int index) async {
    setState(() {
      _imageCache.remove(_imageHistory[index].path);
      _imageHistory.removeAt(index);
    });
    await _saveHistory();
  }

  Future<void> _handleImageSelection({bool fromCamera = false}) async {
    try {
      debugPrint('Starting image selection, fromCamera: $fromCamera');
      setState(() {
        _isAnalyzing = true;
      });

      final XFile? image = await _imagePicker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 80, // Reduce image size
        maxWidth: 1920, // Limit max dimensions
        maxHeight: 1080,
      );

      if (image != null) {
        debugPrint('Image selected: ${image.path}');
        final bytes = await image.readAsBytes();
        debugPrint('Image bytes read, size: ${bytes.length}');

        final storagePath = await saveImageToStorage(image.path, bytes);
        debugPrint('Image saved to storage: $storagePath');

        // Get API key for OpenAI
        final prefs = await SharedPreferences.getInstance();
        final apiKey = prefs.getString('openai_api_key');
        
        if (apiKey == null || apiKey.isEmpty) {
          if (!mounted) return;
          
          // Show dialog for missing API key
          await showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: const Text('Clé API manquante'),
                content: const Text('Veuillez configurer votre clé API OpenAI dans les paramètres.'),
                actions: <Widget>[
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const SettingsPage()),
                      );
                    },
                    child: const Text('Aller aux paramètres'),
                  ),
                ],
              );
            },
          );
          
          setState(() {
            _isAnalyzing = false;
          });
          return;
        }

        final explanation = await getExplanation(storagePath, bytes, apiKey);
        debugPrint('Got explanation');

        if (!mounted) return; // Check if widget is still mounted

        setState(() {
          _imageCache[storagePath] = bytes;
          _imageHistory.add(HistoryItem(
            path: storagePath,
            timestamp: DateTime.now().toString().split('.')[0],
            explanation: explanation,
          ));
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
      } else {
        debugPrint('No image selected');
      }
    } catch (e, stackTrace) {
      debugPrint('Error handling image selection: $e');
      debugPrint('Stack trace: $stackTrace');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _ttsService.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Explique-moi: v${Version.number} (${Version.build})'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              ).then((_) => _checkForVoiceChanges());
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
                          return _buildHistoryCard(theme, item, index);
                        },
                      ),
              ),
              _buildCameraButton(theme),
            ],
          ),
          if (_isAnalyzing) _buildLoadingOverlay(theme),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(ThemeData theme, HistoryItem item, int index) {
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
              child: _imageCache.containsKey(item.path)
                  ? Image.memory(
                      _imageCache[item.path]!,
                      fit: BoxFit.cover,
                    )
                  : kIsWeb
                      ? const Center(
                          child: Text('Image non disponible'),
                        )
                      : Image.file(
                          File(item.path),
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
                  item.timestamp,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.secondary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.explanation,
                  style: theme.textTheme.bodyLarge,
                ),
              ],
            ),
          ),
          OverflowBar(
            children: [
              IconButton(
                icon: Icon(
                  _ttsService.isPlayingText(item.explanation)
                      ? (_ttsService.isPaused ? Icons.play_arrow : Icons.pause)
                      : Icons.volume_up,
                  color: theme.colorScheme.primary,
                ),
                onPressed: () => _ttsService.speak(item.explanation),
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
  }

  Widget _buildCameraButton(ThemeData theme) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton.icon(
          onPressed: _isAnalyzing
              ? null
              : () async {
                  if (kIsWeb) {
                    await _handleImageSelection();
                  } else {
                    showModalBottomSheet(
                      context: context,
                      builder: (BuildContext context) {
                        return SafeArea(
                          child: Wrap(
                            children: <Widget>[
                              ListTile(
                                leading: const Icon(Icons.camera_alt),
                                title: const Text('Prendre une photo'),
                                onTap: () async {
                                  Navigator.pop(context);
                                  await _handleImageSelection(fromCamera: true);
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.photo_library),
                                title: const Text('Choisir une image'),
                                onTap: () async {
                                  Navigator.pop(context);
                                  await _handleImageSelection();
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
    );
  }

  Widget _buildLoadingOverlay(ThemeData theme) {
    return Container(
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
    );
  }
}