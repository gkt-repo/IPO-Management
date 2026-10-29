import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ipo_tracker/core/api/api_client.dart';
import 'package:ipo_tracker/providers/account_session_provider.dart';
import 'package:ipo_tracker/providers/auth_provider.dart';
import 'package:ipo_tracker/providers/ipo_provider.dart';
import 'package:ipo_tracker/providers/pan_provider.dart';
import 'package:ipo_tracker/providers/refresh_job_provider.dart';

class TestAuth extends AuthNotifier {
  @override
  AuthState build() => AuthState(isLoading: false, isAuthenticated: true);
}

final allotments = [
  {
    'id': 'ipo-a',
    'name': 'Account A allotment',
    'status': 'ALLOTTED',
    'allottedQuantity': 100,
  },
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late InterceptorsWrapper interceptor;
  late void Function(RequestOptions, RequestInterceptorHandler) respond;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'jwt_token': 'account-a-token',
      'cached_ipos_list:a': jsonEncode(allotments),
      'cached_ipos_list': jsonEncode(allotments),
      'cached_dashboard_summary': jsonEncode({
        'hasPan': true,
        'maskedPan': 'ABCDE****F',
      }),
    });
    respond = (options, handler) {
      if (options.path.endsWith('/login')) {
        handler.resolve(
          Response(
            requestOptions: options,
            data: {
              'accessToken': 'account-b-token',
              'user': {'id': 'b', 'email': 'b@example.test'},
            },
          ),
        );
      } else if (options.path.endsWith('/pan')) {
        handler.resolve(
          Response(
            requestOptions: options,
            data: {
              'hasPan': true,
              'pan': {
                'id': 'pan-a',
                'panMasked': 'ABCDE****F',
                'consentGiven': true,
              },
            },
          ),
        );
      } else {
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          ),
        );
      }
    };
    interceptor = InterceptorsWrapper(
      onRequest: (options, handler) => respond(options, handler),
    );
    ApiClient().dio.interceptors.add(interceptor);
    container = ProviderContainer(
      overrides: [authProvider.overrideWith(TestAuth.new)],
    );
    container.read(accountSessionProvider.notifier).changeUser('a');
  });
  tearDown(() {
    container.dispose();
    ApiClient().dio.interceptors.remove(interceptor);
  });

  test(
    'logout clears account state and the next login cannot use another account cache',
    () async {
      await container.read(ipoListProvider.notifier).fetchIposAndSummary();
      await container.read(panProvider.notifier).fetchSavedPan();
      expect(container.read(ipoListProvider).ipos.single.allottedQuantity, 100);
      expect(container.read(panProvider).hasPan, isTrue);
      await container.read(authProvider.notifier).logout();
      expect(container.read(ipoListProvider).ipos, isEmpty);
      expect(container.read(panProvider).pan, isNull);
      expect(container.read(refreshJobProvider).isRefreshing, isFalse);
      expect(
        await const FlutterSecureStorage().read(key: 'cached_ipos_list'),
        isNull,
      );
      expect(
        await const FlutterSecureStorage().read(key: 'cached_ipos_list:a'),
        isNull,
      );
      expect(
        await container
            .read(authProvider.notifier)
            .login('b@example.test', 'password'),
        isTrue,
      );
      await container.read(ipoListProvider.notifier).fetchIposAndSummary();
      expect(container.read(accountSessionProvider).userId, 'b');
      expect(container.read(ipoListProvider).ipos, isEmpty);
      expect(container.read(ipoListProvider).summary, isNull);
    },
  );

  test(
    'a late IPO response cannot repopulate state or write another account cache',
    () async {
      final started = Completer<void>();
      late RequestOptions pendingOptions;
      late RequestInterceptorHandler pendingHandler;
      respond = (options, handler) {
        pendingOptions = options;
        pendingHandler = handler;
        started.complete();
      };
      final fetch = container
          .read(ipoListProvider.notifier)
          .fetchIposAndSummary();
      await started.future;
      await container.read(authProvider.notifier).logout();
      container.read(accountSessionProvider.notifier).changeUser('b');
      pendingHandler.resolve(
        Response(requestOptions: pendingOptions, data: allotments),
      );
      await fetch;
      expect(container.read(ipoListProvider).ipos, isEmpty);
      expect(
        await const FlutterSecureStorage().read(key: 'cached_ipos_list:b'),
        isNull,
      );
      expect(
        await const FlutterSecureStorage().read(key: 'cached_ipos_list:a'),
        isNull,
      );
    },
  );

  test('late PAN and refresh responses are ignored after logout', () async {
    final requests = <String, (RequestOptions, RequestInterceptorHandler)>{};
    final started = Completer<void>();
    respond = (options, handler) {
      requests[options.path] = (options, handler);
      if (requests.length == 2) started.complete();
    };
    final pan = container.read(panProvider.notifier).fetchSavedPan();
    final refresh = container
        .read(refreshJobProvider.notifier)
        .triggerManualRefresh();
    await started.future;
    await container.read(authProvider.notifier).logout();
    for (final entry in requests.entries) {
      entry.value.$2.resolve(
        Response(
          requestOptions: entry.value.$1,
          data: entry.key.endsWith('/pan')
              ? {
                  'hasPan': true,
                  'pan': {'id': 'old-pan', 'panMasked': 'ABCDE****F'},
                }
              : {'jobId': 'old-job', 'status': 'QUEUED'},
        ),
      );
    }
    await Future.wait([pan, refresh]);
    expect(container.read(panProvider).pan, isNull);
    expect(container.read(refreshJobProvider).activeJobId, isNull);
    expect(container.read(refreshJobProvider).isRefreshing, isFalse);
  });

  test('legacy unscoped caches are never loaded for a new account', () async {
    container.read(accountSessionProvider.notifier).changeUser('b');
    await container.read(ipoListProvider.notifier).fetchIposAndSummary();
    expect(container.read(ipoListProvider).ipos, isEmpty);
  });
  test('a stale auth check cannot log out a newer session', () async {
    final started = Completer<void>();
    late RequestOptions oldOptions;
    late RequestInterceptorHandler oldHandler;
    final normalResponse = respond;
    respond = (options, handler) {
      if (options.path.endsWith('/me')) {
        oldOptions = options;
        oldHandler = handler;
        started.complete();
      } else {
        normalResponse(options, handler);
      }
    };
    final check = container.read(authProvider.notifier).checkAuth();
    await started.future;
    expect(await container.read(authProvider.notifier).login('b@example.test', 'password'), isTrue);
    oldHandler.reject(DioException(requestOptions: oldOptions, type: DioExceptionType.connectionError));
    await check;
    expect(container.read(authProvider).isAuthenticated, isTrue);
    expect(container.read(accountSessionProvider).userId, 'b');
    expect(await ApiClient().getToken(), 'account-b-token');
  });

}
