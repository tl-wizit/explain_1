import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

// Save image to storage (different implementation for web and mobile)
Future<String> saveImageToStorage(String imagePath, Uint8List bytes) async {
  final timestamp = DateTime.now().toString();
  
  if (kIsWeb) {
    // For web, just store the bytes in SharedPreferences and use timestamp as path
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('image_$timestamp', base64Encode(bytes));
    return timestamp;
  } else {
    // For mobile, store in file system
    final directory = await getApplicationDocumentsDirectory();
    final fileName = path.basename(imagePath);
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  }
}

// Get image explanation from OpenAI API
Future<String> getExplanation(String imagePath, Uint8List fileBytes, String? apiKey) async {
  try {
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('OpenAI API key not configured');
    }

    final url = Uri.parse('https://api.openai.com/v1/chat/completions');

    // Convert image to base64
    String base64Image = base64Encode(fileBytes);

    // Create the request payload
    final payload = {
      'model': 'gpt-4o-mini',
      'messages': [
        {
          'role': 'system',
          'content': 'You are an assistant that explains the contents of images in French for 10-year-old children.'
        },
        {
          'role': 'user',
          'content': [
            {
              'type': 'text',
              'text': 'Décris ce que contient cette image comme si tu parlais à un enfant de 10 ans.'
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
      throw Exception('Error ${response.statusCode}: $responseBody');
    }
  } catch (e) {
    return 'Erreur lors de l\'analyse de l\'image: $e';
  }
}