import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/api_constants.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late final Dio dio;
  int _sessionRevision = 0;
  Future<void> _tokenWrites = Future.value();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  ApiClient._internal() {
    dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: ApiConstants.connectTimeout,
        receiveTimeout: ApiConstants.receiveTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final revision = _sessionRevision;
          final token = await getToken();
          if (revision != _sessionRevision) {
            return handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.cancel,
              ),
            );
          }
          options.extra['sessionRevision'] = revision;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onResponse: (response, handler) {
          if (response.requestOptions.extra['sessionRevision'] !=
              _sessionRevision) {
            return handler.reject(
              DioException(
                requestOptions: response.requestOptions,
                type: DioExceptionType.cancel,
              ),
            );
          }
          handler.next(response);
        },
        onError: (DioException e, handler) {
          return handler.next(e);
        },
      ),
    );
  }

  Future<void> saveToken(String token) async {
    _sessionRevision++;
    _tokenWrites = _tokenWrites.catchError((_) {}).then((_) => _storage.write(key: 'jwt_token', value: token));
    await _tokenWrites;
  }

  Future<String?> getToken() async {
    await _tokenWrites;
    return await _storage.read(key: 'jwt_token');
  }

  Future<void> clearToken() async {
    _sessionRevision++;
    _tokenWrites = _tokenWrites.catchError((_) {}).then((_) => _storage.delete(key: 'jwt_token'));
    await _tokenWrites;
  }
}
