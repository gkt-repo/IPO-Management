class ApiConstants {
  // Use localhost in dev, or your Oracle Cloud VM IP/domain in production
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:5000',
  );

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 15);

  // Auth endpoints
  static const String login = '/api/auth/login';
  static const String register = '/api/auth/register';
  static const String me = '/api/auth/me';

  // PAN endpoints
  static const String pan = '/api/pan';

  // IPO & Refresh endpoints
  static const String ipoList = '/api/ipo';
  static const String dashboard = '/api/ipo/dashboard';
  static const String refresh = '/api/ipo/refresh';
}
