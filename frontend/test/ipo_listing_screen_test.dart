import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ipo_tracker/core/models/ipo_model.dart';
import 'package:ipo_tracker/providers/ipo_provider.dart';
import 'package:ipo_tracker/providers/pan_provider.dart';
import 'package:ipo_tracker/providers/refresh_job_provider.dart';
import 'package:ipo_tracker/screens/dashboard/dashboard_screen.dart';

class TestIpos extends IpoListNotifier {
  @override
  IpoListState build() {
    final now = DateTime.now().toUtc();
    IpoItemModel item(String name, String board, int open, int close) => IpoItemModel(
      id: name, name: name, slug: name, issueType: board,
      openDate: now.add(Duration(days: open)), closeDate: now.add(Duration(days: close)),
      registrar: 'KFINTECH', officialVerificationUrl: '', status: AllotmentStatusEnum.notApplied,
    );
    return IpoListState(isLoading: false, ipos: [
      item('Open Mainboard Company', 'MAINBOARD', -1, 1),
      item('Closed Mainboard Company', 'MAINBOARD', -5, -2),
      item('Upcoming Mainboard Company', 'MAINBOARD', 2, 5),
      item('Upcoming SME Company', 'SME', 2, 5),
    ]);
  }
  @override
  Future<void> fetchIposAndSummary({bool silent = false}) async {}
}

class TestPan extends PanNotifier {
  @override
  PanState build() => PanState(isLoading: false, hasPan: true);
  @override
  Future<void> fetchSavedPan() async {}
}

class TestRefresh extends RefreshJobNotifier {
  @override
  Future<void> triggerAppOpenRefresh() async {}
}

void main() {
  testWidgets('phone listing switches bidding tabs and preserves tab on board change', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ipoListProvider.overrideWith(TestIpos.new),
        panProvider.overrideWith(TestPan.new),
        refreshJobProvider.overrideWith(TestRefresh.new),
      ],
      child: const MaterialApp(home: DashboardScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Open Mainboard Company'), findsOneWidget);
    expect(find.text('Upcoming Mainboard Company'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Closed (1)'));
    await tester.tap(find.text('Closed (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Closed Mainboard Company'), findsOneWidget);
    expect(find.text('Open Mainboard Company'), findsNothing);

    await tester.tap(find.text('Upcoming (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Upcoming Mainboard Company'), findsOneWidget);
    expect(find.text('+ I have applied'), findsNothing);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SME').last);
    await tester.pumpAndSettle();
    expect(find.text('Upcoming SME Company'), findsOneWidget);
    expect(find.text('Upcoming Mainboard Company'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
