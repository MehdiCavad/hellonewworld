import 'package:dio/dio.dart';

import 'models.dart';

/// Base URL of the Rankd API. Override at build time:
/// `flutter run --dart-define=RANKD_API=https://rankd.example.com`
/// (the Android emulator reaches the host machine at http://10.0.2.2:5080).
const String apiBaseUrl = String.fromEnvironment('RANKD_API', defaultValue: 'http://localhost:5080');

const String appVersion = '2.0.0';

/// Thin client for the anonymous Rankd API. Device-scoped calls carry the
/// random device id created on first launch.
class ApiClient {
  ApiClient({required this.deviceId, required this.platform, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: '$apiBaseUrl/api/v1',
              connectTimeout: const Duration(seconds: 4),
              receiveTimeout: const Duration(seconds: 8),
              headers: {'X-Rankd-Version': appVersion},
            ));

  final Dio _dio;
  final String deviceId;
  final String platform;

  Options get _device => Options(headers: {'X-Rankd-Device': deviceId, 'X-Rankd-Platform': platform});

  Future<List<Topic>> topics() async {
    final r = await _dio.get<List<dynamic>>('/topics');
    return [for (final t in r.data!) Topic.fromJson(t as Map<String, dynamic>)];
  }

  Future<List<Level>> levels() async {
    final r = await _dio.get<List<dynamic>>('/levels');
    return [for (final l in r.data!) Level.fromJson(l as Map<String, dynamic>)];
  }

  Future<List<Item>> topicItems(String slug) async {
    final r = await _dio.get<Map<String, dynamic>>('/topics/$slug');
    return [for (final i in r.data!['items'] as List) Item.fromJson(i as Map<String, dynamic>)];
  }

  Future<GlobalRanking> globalRanking(String slug, {int take = 100}) async {
    final r = await _dio.get<Map<String, dynamic>>('/topics/$slug/global-ranking', queryParameters: {'take': take});
    return GlobalRanking.fromJson(r.data!);
  }

  Future<List<Attribution>> attributions() async {
    final r = await _dio.get<List<dynamic>>('/attributions');
    return [for (final a in r.data!) Attribution.fromJson(a as Map<String, dynamic>)];
  }

  Future<void> putSession(String id, Map<String, dynamic> body) =>
      _dio.put<void>('/sessions/$id', data: body, options: _device);

  Future<void> deleteMyData() => _dio.delete<void>('/devices/me', options: _device);
}
