import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class EmotionService {
  // API URL
  static const String apiUrl = 'https://api-us.faceplusplus.com/facepp/v3/detect';

  // API KEY
  static const String apiKey = '';
  static const String apiSecret = '';

  Future<Map<String, dynamic>> detectEmotions(dynamic input) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse(apiUrl));

      // Auth in the body, not headers
      request.fields['api_key'] = apiKey;
      request.fields['api_secret'] = apiSecret;
      request.fields['return_attributes'] = 'emotion'; // Request emotion data explicitly

      // Handle Image File
      if (kIsWeb) {
        if (input is List<int>) {
          request.files.add(http.MultipartFile.fromBytes(
            'image_file', // Face++ expects 'image_file'
            input,
            filename: 'upload.jpg',
            contentType: MediaType('image', 'jpeg'),
          ));
        }
      } else {
        if (input is io.File) {
          request.files.add(await http.MultipartFile.fromPath(
            'image_file',
            input.path,
            contentType: MediaType('image', 'jpeg'),
          ));
        }
      }

      print('Sending request to Face++...');
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      print('Status: ${response.statusCode}');
      print('Body: ${response.body}');

      if (response.statusCode == 200) {
        var jsonResponse = jsonDecode(response.body);

        // Check if faces were detected
        if (jsonResponse['faces'] == null || (jsonResponse['faces'] as List).isEmpty) {
          return {}; // No face detected
        }

        //returns emotions inside 'attributes' -> 'emotion'
        var face = jsonResponse['faces'][0];
        var emotions = face['attributes']['emotion'];

        // Convert values
        return Map<String, dynamic>.from(emotions.map(
              (k, v) => MapEntry(k, (v as num).toDouble()),
        ));
      } else {
        throw Exception('API Error: ${response.body}');
      }
    } catch (e) {
      print('Error: $e');
      rethrow;
    }
  }
}