class ApiConstants {
  // Production Oracle VM endpoint by default
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://ipo.132-226-186-196.sslip.io',
  );

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 15);

  // Auth endpoints
  static const String login = '/api/auth/login';
  static const String register = '/api/auth/register';
  static const String forgotPasswordHint = '/api/auth/forgot-password-hint';
  static const String me = '/api/auth/me';

  // PAN endpoints
  static const String pan = '/api/pan';

  // IPO & Refresh endpoints
  static const String ipoList = '/api/ipo';
  static const String dashboard = '/api/ipo/dashboard';
  static const String refresh = '/api/ipo/refresh';
}
