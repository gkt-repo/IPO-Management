import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('PopScope navigates back to first screen when navigated via push()', (tester) async {
    final router = GoRouter(
      initialLocation: '/first',
      routes: [
        GoRoute(
          path: '/first',
          builder: (context, state) => const Scaffold(body: Text('FirstScreen')),
        ),
        GoRoute(
          path: '/second',
          builder: (context, state) {
            return PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) return;
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/first');
                }
              },
              child: const Scaffold(body: Text('SecondScreen')),
            );
          },
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    expect(find.text('FirstScreen'), findsOneWidget);

    router.push('/second');
    await tester.pumpAndSettle();
    expect(find.text('SecondScreen'), findsOneWidget);

    final popped = await WidgetsBinding.instance.handlePopRoute();
    expect(popped, isTrue);
    await tester.pumpAndSettle();

    expect(find.text('FirstScreen'), findsOneWidget);
    expect(find.text('SecondScreen'), findsNothing);
  });

  testWidgets('PopScope navigates back to first screen when navigated via go()', (tester) async {
    final router = GoRouter(
      initialLocation: '/first',
      routes: [
        GoRoute(
          path: '/first',
          builder: (context, state) => const Scaffold(body: Text('FirstScreen')),
        ),
        GoRoute(
          path: '/second',
          builder: (context, state) {
            return PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) return;
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/first');
                }
              },
              child: const Scaffold(body: Text('SecondScreen')),
            );
          },
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    expect(find.text('FirstScreen'), findsOneWidget);

    router.go('/second');
    await tester.pumpAndSettle();
    expect(find.text('SecondScreen'), findsOneWidget);

    final popped = await WidgetsBinding.instance.handlePopRoute();
    expect(popped, isTrue);
    await tester.pumpAndSettle();

    expect(find.text('FirstScreen'), findsOneWidget);
    expect(find.text('SecondScreen'), findsNothing);
  });
}
