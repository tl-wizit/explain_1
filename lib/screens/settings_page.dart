import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _apiKeyController = TextEditingController();
  static const String apiKeyPref = 'openai_api_key';
  bool _obscureText = true;

  final FlutterTts _flutterTts = FlutterTts();
  List<dynamic>? _voices;
  String? _selectedVoice;
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
    _loadApiKey();
    _loadVoices();
  }

  Future<void> _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKeyController.text = prefs.getString(apiKeyPref) ?? '';
    });
  }

  Future<void> _loadVoices() async {
    final prefs = await SharedPreferences.getInstance();
    String? savedVoice = prefs.getString('selected_voice');
    
    // Initialize TTS
    await _flutterTts.setLanguage('fr-FR');
    await _flutterTts.setSpeechRate(0.9);
    
    // Get available voices
    final voices = await _flutterTts.getVoices;
    debugPrint('Available voices in settings: $voices');
    
    // Set default voice if needed
    if (savedVoice == null && voices != null) {
      final frenchVoices = voices.where(
        (v) => (v['locale'] as String?)?.startsWith('fr') ?? false
      ).toList();
      
      if (frenchVoices.isNotEmpty) {
        savedVoice = frenchVoices.first['name'] as String;
        await prefs.setString('selected_voice', savedVoice);
        debugPrint('Set default voice in settings to: $savedVoice');
      }
    }
    
    // Apply current voice
    if (savedVoice != null) {
      await _flutterTts.setVoice({"name": savedVoice, "locale": "fr-FR"});
    }
    
    setState(() {
      _voices = voices;
      _selectedVoice = savedVoice;
    });
    debugPrint('Settings loaded with voice: $_selectedVoice');
  }

  Future<void> _testVoice() async {
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

    try {
      // Always set language and voice before speaking
      await _flutterTts.setLanguage('fr-FR');
      if (_selectedVoice != null) {
        await _flutterTts.setVoice({"name": _selectedVoice!, "locale": "fr-FR"});
      }
      
      _flutterTts.setCompletionHandler(() {
        if (mounted) {
          setState(() {
            _isSpeaking = false;
          });
        }
      });

      await _flutterTts.speak("Bonjour. Je suis la voix qui va t'expliquer les images");
    } catch (e) {
      debugPrint('TTS Error in settings: $e');
      setState(() {
        _isSpeaking = false;
      });
    }
  }

  Future<void> _onVoiceChanged(String? value) async {
    // Stop any ongoing speech
    if (_isSpeaking) {
      await _flutterTts.stop();
    }

    if (value == null) return;
    
    try {
      // Apply voice change
      await _flutterTts.setLanguage('fr-FR');
      await _flutterTts.setVoice({"name": value, "locale": "fr-FR"});
      
      // Save selection
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selected_voice', value);
      
      setState(() {
        _selectedVoice = value;
        _isSpeaking = false;
      });
      
      debugPrint('Voice changed and saved: $value');
    } catch (e) {
      debugPrint('Error changing voice: $e');
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          TextFormField(
            controller: _apiKeyController,
            decoration: InputDecoration(
              labelText: 'Clé API OpenAI',
              hintText: 'Entrez votre clé API OpenAI',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureText ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () {
                  setState(() {
                    _obscureText = !_obscureText;
                  });
                },
              ),
            ),
            obscureText: _obscureText,
            onChanged: (value) async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(apiKeyPref, value);
            },
          ),
          const SizedBox(height: 24),
          Text('Voix', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedVoice,
                  items: _voices
                      ?.where((v) =>
                          (v['locale'] as String?)?.startsWith('fr') ?? false)
                      .map((voice) => DropdownMenuItem<String>(
                            value: voice['name'] as String,
                            child: Text(voice['name'] as String),
                          ))
                      .toList(),
                  onChanged: _onVoiceChanged,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  hint: const Text('Sélectionnez une voix'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(_isSpeaking ? Icons.stop : Icons.play_arrow),
                onPressed: _testVoice,
                color: theme.colorScheme.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}