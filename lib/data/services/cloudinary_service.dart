import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class CloudinaryService {
  static const String _cloudName = 'divynstru';
  static const String _uploadPreset = 'qoima_unsigned';
  static const String _folder = 'qoima_products';

  static final String _uploadUrl =
      'https://api.cloudinary.com/v1_1/$_cloudName/image/upload';

  /// XFile (image_picker) арқылы жүктеу — iOS/Android екеуінде де жұмыс жасайды
  Future<String> uploadXFile(XFile xFile) async {
    final bytes = await xFile.readAsBytes(); // dart:io қажет емес
    return _upload(bytes, _resolveFileName(xFile.path));
  }

  /// Бірнеше XFile параллель жүктеу
  Future<List<String>> uploadMultiple(List<XFile> files) async {
    if (files.isEmpty) return [];
    return Future.wait(files.map(uploadXFile));
  }

  Future<String> _upload(List<int> bytes, String fileName) async {
    final request = http.MultipartRequest('POST', Uri.parse(_uploadUrl))
      ..fields['upload_preset'] = _uploadPreset
      ..fields['folder'] = _folder
      ..files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: fileName),
      );

    final streamedResponse = await request.send().timeout(
          const Duration(seconds: 60),
          onTimeout: () => throw CloudinaryException(
            'Время ожидания истекло. Проверьте интернет.',
          ),
        );

    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final url = json['secure_url'] as String?;
      if (url == null || url.isEmpty) {
        throw CloudinaryException('Cloudinary не вернул URL.');
      }
      return url;
    } else {
      final errorBody = jsonDecode(response.body) as Map<String, dynamic>?;
      final message = (errorBody?['error'] as Map?)?['message'] as String? ??
          'Неизвестная ошибка Cloudinary';
      throw CloudinaryException('Ошибка [${response.statusCode}]: $message');
    }
  }

  String _resolveFileName(String path) {
    final name = path.split('/').last.split('\\').last;
    return name.contains('.') ? name : '$name.jpg';
  }
}

class CloudinaryException implements Exception {
  final String message;
  const CloudinaryException(this.message);

  @override
  String toString() => 'CloudinaryException: $message';
}
