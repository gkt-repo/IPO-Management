import 'package:flutter_test/flutter_test.dart';
import 'package:ipo_tracker/core/models/ipo_model.dart';
import 'package:ipo_tracker/providers/ipo_provider.dart';

IpoItemModel issue({String id = 'test', String board = 'MAINBOARD', String? open = '2026-10-26', String? close = '2026-10-28'}) => IpoItemModel.fromJson({
  'id': id, 'name': id, 'slug': id, 'issueType': board,
  'openDate': open, 'closeDate': close, 'allotmentDate': '2026-11-01',
  'isUpcoming': true, 'status': 'NOT_APPLIED',
});

void main() {
  test('IST bidding boundaries override stale cached Upcoming flag', () {
    final ipo = issue();
    for (final entry in {
      '2026-10-26T04:29:59.999Z': IpoLifecycle.upcoming,
      '2026-10-26T04:30:00Z': IpoLifecycle.open,
      '2026-10-28T11:29:59.999Z': IpoLifecycle.open,
      '2026-10-28T11:30:00Z': IpoLifecycle.closed,
      '2026-10-29T00:00:00Z': IpoLifecycle.closed,
    }.entries) {
      expect(ipo.lifecycleAt(DateTime.parse(entry.key)), entry.value);
    }
  });

  test('SME closes at 4 PM IST and respects explicit extended times', () {
    final now = DateTime.parse('2026-10-28T10:30:00Z');
    expect(issue(board: 'SME').lifecycleAt(now), IpoLifecycle.closed);
    expect(issue().lifecycleAt(now), IpoLifecycle.open);
    expect(issue(board: 'SME', close: '2026-10-28T18:00:00+05:30').lifecycleAt(now), IpoLifecycle.open);
  });

  test('API timestamp overrides are retained when updating applied status', () {
    final ipo = IpoItemModel.fromJson({
      'id': 'extended', 'name': 'Extended', 'slug': 'extended',
      'openDate': '2026-10-26', 'closeDate': '2026-10-28',
      'biddingClosesAt': '2026-10-28T19:00:00+05:30',
    }).copyWith(hasApplied: true);
    expect(ipo.lifecycleAt(DateTime.parse('2026-10-28T12:00:00Z')), IpoLifecycle.open);
    expect(ipo.lifecycleAt(DateTime.parse('2026-10-28T13:30:00Z')), IpoLifecycle.closed);
  });

  test('missing and inverted schedules stay unknown', () {
    final now = DateTime.parse('2026-10-28T08:00:00Z');
    expect(issue(open: null, close: null).lifecycleAt(now), IpoLifecycle.unknown);
    expect(issue(open: null).lifecycleAt(now), IpoLifecycle.unknown);
    expect(issue(close: null).lifecycleAt(now), IpoLifecycle.unknown);
    expect(issue(close: '2026-10-25').lifecycleAt(now), IpoLifecycle.unknown);
  });

  test('three tabs partition each board; opening and closing order is useful', () {
    final now = DateTime.parse('2026-10-28T08:00:00Z');
    final state = IpoListState(isLoading: false, ipos: [
      issue(id: 'open-later', close: '2026-10-29'),
      issue(id: 'open-soon'),
      issue(id: 'closed-old', open: '2026-10-01', close: '2026-10-04'),
      issue(id: 'closed-recent', open: '2026-10-20', close: '2026-10-23'),
      issue(id: 'upcoming-later', open: '2026-11-05', close: '2026-11-08'),
      issue(id: 'upcoming-soon', open: '2026-11-01', close: '2026-11-04'),
      issue(id: 'sme', board: 'SME'),
      issue(id: 'undated', open: null, close: null),
    ]);
    List<String> ids(IpoListState s) => s.filteredIposAt(now).map((ipo) => ipo.id).toList();
    expect(ids(state), ['open-soon', 'open-later']);
    expect(ids(state.copyWith(selectedLifecycle: IpoLifecycle.closed)), ['closed-recent', 'closed-old']);
    expect(ids(state.copyWith(selectedLifecycle: IpoLifecycle.upcoming)), ['upcoming-soon', 'upcoming-later']);
    expect(ids(state.copyWith(selectedIssueType: 'SME')), ['sme']);
    expect(ids(state.copyWith(searchQuery: ' soon ')), ['open-soon']);
  });

  test('company names cannot manufacture prices or lot sizes', () {
    final ipo = IpoItemModel.fromJson({'id': 'jio', 'name': 'Jio Platforms', 'slug': 'jio-platforms'});
    expect(ipo.priceBand, isNull);
    expect(ipo.lotSize, isNull);
    expect(ipo.effectiveIssuePrice, isNull);
    expect(ipo.effectiveListingPrice, isNull);
  });
}
