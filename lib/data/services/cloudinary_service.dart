import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class CloudinaryService {
  static const String _cloudName = 'divynstru';
  static const String _uploadPreset = 'qoima_unsigned';
  static const String _folder = 'qoima_products';
  static const String _receiptsFolder = 'qoima_receipts';

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

  /// Чек жүктеу (XFile, тек фото) — бөлек қалтаға (`qoima_receipts`)
  Future<String> uploadReceipt(XFile xFile) async {
    final bytes = await xFile.readAsBytes();
    return _upload(bytes, _resolveFileName(xFile.path),
        folder: _receiptsFolder);
  }

  /// Чек жүктеу (bytes + атау) — PDF + фото. image/upload: PDF → image ретінде
  /// сақталады, `receiptPreviewUrl` арқылы pg_1,f_jpg трансформациясы қолданылады.
  Future<String> uploadReceiptBytes(List<int> bytes, String fileName) async {
    final request =
        http.MultipartRequest('POST', Uri.parse(_uploadUrl))
          ..fields['upload_preset'] = _uploadPreset
          ..fields['folder'] = _receiptsFolder
          ..files.add(http.MultipartFile.fromBytes('file', bytes,
              filename: fileName));
    final streamed = await request.send().timeout(
      const Duration(seconds: 60),
      onTimeout: () =>
          throw CloudinaryException('Время ожидания истекло. Проверьте интернет.'),
    );
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode == 200) {
      final url =
          (jsonDecode(resp.body) as Map<String, dynamic>)['secure_url']
              as String?;
      if (url == null || url.isEmpty) {
        throw CloudinaryException('Cloudinary не вернул URL.');
      }
      return url;
    }
    final errorBody =
        jsonDecode(resp.body) as Map<String, dynamic>?;
    final msg =
        (errorBody?['error'] as Map?)?['message'] as String? ??
            'Неизвестная ошибка';
    throw CloudinaryException('Ошибка [${resp.statusCode}]: $msg');
  }

  /// PDF чекті апп ІШІНДЕ inline көрсету үшін 1-бет JPG preview URL жасайды.
  /// Фото болса өзгертусіз қайтарады.
  static String receiptPreviewUrl(String url) {
    if (url.isEmpty) return url;
    if (!url.toLowerCase().contains('.pdf')) return url;
    return url
        .replaceFirst('/upload/', '/upload/pg_1,f_jpg,w_1000/')
        .replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '.jpg');
  }

  Future<String> _upload(List<int> bytes, String fileName,
      {String? folder}) async {
    final request = http.MultipartRequest('POST', Uri.parse(_uploadUrl))
      ..fields['upload_preset'] = _uploadPreset
      ..fields['folder'] = folder ?? _folder
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
