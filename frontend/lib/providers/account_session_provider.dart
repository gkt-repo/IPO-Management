import 'package:flutter_riverpod/flutter_riverpod.dart';

// Object identity also distinguishes two logins to the same account, preventing
// a late response from a previous login from repopulating cleared state.
class AccountSession {
  final String? userId;
  AccountSession(this.userId);
}

class AccountSessionNotifier extends Notifier<AccountSession> {
  @override
  AccountSession build() => AccountSession(null);

  void changeUser(String? userId) => state = AccountSession(userId);
}

final accountSessionProvider =
    NotifierProvider<AccountSessionNotifier, AccountSession>(
      AccountSessionNotifier.new,
    );
