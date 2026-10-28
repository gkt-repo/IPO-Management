import 'package:flutter_test/flutter_test.dart';
import 'package:ipo_tracker/core/constants/api_constants.dart';

void main() {
  test('ApiConstants defines forgotPasswordHint endpoint correctly', () {
    expect(ApiConstants.forgotPasswordHint, '/api/auth/forgot-password-hint');
    expect(ApiConstants.register, '/api/auth/register');
    expect(ApiConstants.login, '/api/auth/login');
  });
}
