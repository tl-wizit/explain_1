import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;

class TTSService {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isSpeaking = false;
  bool _isPaused = false;
  String _currentText = '';
  String? _selectedVoice;
  final VoidCallback _onStateChanged;

  TTSService({required VoidCallback onStateChanged}) : _onStateChanged = onStateChanged {
    _initTTS();
  }

  // Getters for external access
  bool get isSpeaking => _isSpeaking;
  bool get isPaused => _isPaused;
  String get currentText => _currentText;
  String? get selectedVoice => _selectedVoice;

  Future<void> _initTTS() async {
    await _flutterTts.setLanguage('fr-FR');
    await _flutterTts.setSpeechRate(0.9);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setVolume(1.0);

    // Set handlers
    _flutterTts.setErrorHandler((msg) {
      debugPrint('TTS Error: $msg');
      if (msg != 'interrupted') {
        _isSpeaking = false;
        _isPaused = false;
        _currentText = '';
        _onStateChanged();
      }
    });

    _flutterTts.setCompletionHandler(() {
      debugPrint('TTS Completed');
      _isSpeaking = false;
      _isPaused = false;
      _currentText = '';
      _onStateChanged();
    });

    // Load saved voice preference
    final prefs = await SharedPreferences.getInstance();
    await loadVoice(prefs.getString('selected_voice'));
  }

  // Load and apply voice - used both on init and when returning from settings
  Future<void> loadVoice(String? voiceName) async {
    final prefs = await SharedPreferences.getInstance();
    
    // If no voice specified, try to get saved voice or set default
    if (voiceName == null) {
      voiceName = prefs.getString('selected_voice');
      
      // If still null, set default voice
      if (voiceName == null) {
        final voices = await _flutterTts.getVoices;
        final frenchVoices = voices?.where(
          (v) => (v['locale'] as String?)?.startsWith('fr') ?? false
        ).toList();
        
        if (frenchVoices != null && frenchVoices.isNotEmpty) {
          voiceName = frenchVoices.first['name'] as String;
          await prefs.setString('selected_voice', voiceName);
          debugPrint('Setting default voice to: $voiceName');
        }
      }
    }
    
    if (voiceName != null) {
      try {
        // Explicitly configure language before setting voice
        await _flutterTts.setLanguage('fr-FR');
        await _flutterTts.setVoice({"name": voiceName, "locale": "fr-FR"});
        _selectedVoice = voiceName;
        debugPrint('TTS voice loaded: $_selectedVoice');
        _onStateChanged();
      } catch (e) {
        debugPrint('Error setting voice: $e');
      }
    }
  }

  // Speak, pause, resume - special handling for web
  Future<void> speak(String text) async {
    debugPrint('TTS Service - Speaking: $_isSpeaking, Paused: $_isPaused, Voice: $_selectedVoice, Text: ${text.substring(0, math.min(20, text.length))}...');
    
    try {
      if (_isSpeaking) {
        if (_isPaused) {
          // Resume playback - special handling for web
          _isPaused = false;
          _onStateChanged();
          
          if (kIsWeb) {
            // For web, we need to stop and restart with the saved text
            await _flutterTts.stop();
            
            // Wait a moment for the speech engine to reset
            await Future.delayed(const Duration(milliseconds: 200));
            
            // Explicitly configure voice again
            await _flutterTts.setLanguage('fr-FR');
            if (_selectedVoice != null) {
              await _flutterTts.setVoice({"name": _selectedVoice!, "locale": "fr-FR"});
            }
            await _flutterTts.setSpeechRate(0.9);
            
            // Start speaking from beginning
            debugPrint('Web TTS: Restarting speech');
            await _flutterTts.speak(_currentText);
          } else {
            // For mobile platforms that support resume
            await _flutterTts.speak(_currentText);
          }
        } else {
          // Pause playback
          _isPaused = true;
          _onStateChanged();
          
          if (kIsWeb) {
            // For web, stop speech synthesis
            debugPrint('Web TTS: Stopping speech');
            await _flutterTts.stop();
          } else {
            // For mobile platforms
            await _flutterTts.stop();
          }
        }
      } else {
        // Start new playback
        await _flutterTts.stop(); // Stop any ongoing speech
        
        _currentText = text;
        _isSpeaking = true;
        _isPaused = false;
        _onStateChanged();
        
        // Configure TTS
        await _flutterTts.setLanguage('fr-FR');
        if (_selectedVoice != null) {
          await _flutterTts.setVoice({"name": _selectedVoice!, "locale": "fr-FR"});
          debugPrint('Using voice: $_selectedVoice for new speech');
        } else {
          debugPrint('No voice selected, using default');
        }
        await _flutterTts.setSpeechRate(0.9);
        
        await _flutterTts.speak(text);
      }
    } catch (e) {
      debugPrint('TTS Service Error: $e');
      _isSpeaking = false;
      _isPaused = false;
      _currentText = '';
      _onStateChanged();
    }
  }
  
  // Stop TTS completely
  Future<void> stop() async {
    await _flutterTts.stop();
    _isSpeaking = false;
    _isPaused = false;
    _currentText = '';
    _onStateChanged();
  }
  
  // Check if the given text is currently playing
  bool isPlayingText(String text) {
    return _isSpeaking && _currentText == text;
  }
  
  // Dispose resources
  Future<void> dispose() async {
    await _flutterTts.stop();
  }
}