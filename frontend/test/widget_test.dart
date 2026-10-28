import 'package:flutter_test/flutter_test.dart';
import 'package:ipo_tracker/core/models/ipo_model.dart';
import 'package:ipo_tracker/providers/ipo_provider.dart';

void main() {
  test('Allotment status parser maps status strings accurately', () {
    expect(parseAllotmentStatus('ALLOTTED'), AllotmentStatusEnum.allotted);
    expect(parseAllotmentStatus('allotted'), AllotmentStatusEnum.allotted);
    expect(parseAllotmentStatus('NOT_ALLOTTED'), AllotmentStatusEnum.notAllotted);
    expect(parseAllotmentStatus('LOOKUP_FAILED'), AllotmentStatusEnum.lookupFailed);
    expect(parseAllotmentStatus('NOT_SUPPORTED'), AllotmentStatusEnum.notSupported);
    expect(parseAllotmentStatus('NOT_APPLIED'), AllotmentStatusEnum.notApplied);
    expect(parseAllotmentStatus('PENDING'), AllotmentStatusEnum.pending);
    expect(parseAllotmentStatus(null), AllotmentStatusEnum.pending);
  });

  test('IpoItemModel parses JSON response accurately', () {
    final json = {
      'id': 'ipo-1',
      'externalId': '11968',
      'name': 'Paras Healthcare Limited',
      'slug': 'paras-healthcare-limited',
      'issueType': 'MAINBOARD',
      'openDate': '2026-09-10T00:00:00.000Z',
      'closeDate': '2026-09-12T00:00:00.000Z',
      'priceBand': '₹650 - ₹693',
      'lotSize': 21,
      'listingPrice': 720.0,
      'registrar': 'MUFG_INTIME',
      'officialVerificationUrl': 'https://in.mpms.mufg.com/Initial_Offer/IPO.aspx',
      'status': 'ALLOTTED',
      'allottedQuantity': 21,
      'lastCheckedAt': '2026-09-15T12:00:00.000Z',
    };

    final model = IpoItemModel.fromJson(json);
    expect(model.id, 'ipo-1');
    expect(model.name, 'Paras Healthcare Limited');
    expect(model.status, AllotmentStatusEnum.allotted);
    expect(model.allottedQuantity, 21);
    expect(model.registrar, 'MUFG_INTIME');
    expect(model.effectiveIssuePrice, 693.0);
    expect(model.effectiveListingPrice, 720.0);
    expect(model.gainPerShare, 27.0);
    expect(model.totalProfit, 27.0 * 21);
    expect(model.totalInvested, 693.0 * 21);
    expect(model.totalCurrentValue, 720.0 * 21);
  });

  test('IpoItemModel correctly calculates profit with explicit issue and listing prices', () {
    final json = {
      'id': 'ipo-custom',
      'name': 'Custom IPO Tech',
      'slug': 'custom-ipo-tech',
      'issueType': 'MAINBOARD',
      'registrar': 'KFINTECH',
      'officialVerificationUrl': 'https://ipostatus.kfintech.com/',
      'status': 'ALLOTTED',
      'allottedQuantity': 50,
      'issuePrice': 200.0,
      'listingPrice': 260.0,
    };

    final model = IpoItemModel.fromJson(json);
    expect(model.effectiveIssuePrice, 200.0);
    expect(model.effectiveListingPrice, 260.0);
    expect(model.gainPerShare, 60.0);
    expect(model.gainPercentage, 30.0);
    expect(model.totalProfit, 3000.0); // 60 * 50
    expect(model.totalInvested, 10000.0); // 200 * 50
    expect(model.totalCurrentValue, 13000.0); // 260 * 50
  });

  test('Jio Platforms IPO correctly parses price band ₹1,065 - ₹1,119 and calculates 12 shares allotment profit', () {
    final json = {
      'id': 'ipo-jio',
      'externalId': '78061126051',
      'name': 'Jio Platforms Limited',
      'slug': 'jio-platforms-limited',
      'issueType': 'MAINBOARD',
      'registrar': 'KFINTECH',
      'officialVerificationUrl': 'https://ipostatus.kfintech.com/',
      'status': 'ALLOTTED',
      'allottedQuantity': 12,
      'priceBand': '₹1,065 - ₹1,119',
      'lotSize': 12,
      'issuePrice': 1119.0,
      'listingPrice': 1358.0,
    };

    final model = IpoItemModel.fromJson(json);
    expect(model.priceBand, '₹1,065 - ₹1,119');
    expect(model.lotSize, 12);
    expect(model.allottedQuantity, 12);
    expect(model.effectiveIssuePrice, 1119.0);
    expect(model.effectiveListingPrice, 1358.0);
    expect(model.gainPerShare, 239.0);
    expect(model.gainPercentage! >= 21.35 && model.gainPercentage! <= 21.37, true);
    expect(model.totalProfit, 239.0 * 12); // 2868.0
    expect(model.totalInvested, 1119.0 * 12); // 13428.0
    expect(model.totalCurrentValue, 1358.0 * 12); // 16296.0
  });

  test('IpoListState correctly aggregates total allotted profit across portfolio', () {
    final ipo1 = IpoItemModel(
      id: 'ipo-1',
      name: 'Alpha Ltd',
      slug: 'alpha-ltd',
      issueType: 'MAINBOARD',
      registrar: 'KFINTECH',
      officialVerificationUrl: '',
      status: AllotmentStatusEnum.allotted,
      allottedQuantity: 20,
      issuePrice: 100.0,
      listingPrice: 150.0,
    );

    final ipo2 = IpoItemModel(
      id: 'ipo-2',
      name: 'Beta Ltd',
      slug: 'beta-ltd',
      issueType: 'MAINBOARD',
      registrar: 'MUFG_INTIME',
      officialVerificationUrl: '',
      status: AllotmentStatusEnum.allotted,
      allottedQuantity: 30,
      issuePrice: 200.0,
      listingPrice: 250.0,
    );

    final ipo3 = IpoItemModel(
      id: 'ipo-3',
      name: 'Gamma Ltd',
      slug: 'gamma-ltd',
      issueType: 'MAINBOARD',
      registrar: 'BIGSHARE',
      officialVerificationUrl: '',
      status: AllotmentStatusEnum.notAllotted,
      allottedQuantity: null,
      issuePrice: 300.0,
      listingPrice: 350.0,
    );

    final state = IpoListState(
      isLoading: false,
      ipos: [ipo1, ipo2, ipo3],
      selectedStatusFilter: 'ALLOTTED',
      selectedLifecycle: IpoLifecycle.closed,
    );

    expect(state.allottedIpos.length, 2);
    expect(state.filteredIpos.length, 2);
    expect(state.filteredIpos.map((i) => i.name).toList(), ['Alpha Ltd', 'Beta Ltd']);

    // Profit IPO 1: (150 - 100) * 20 = 1,000
    // Profit IPO 2: (250 - 200) * 30 = 1,500
    // Total profit: 2,500
    expect(state.totalAllottedProfit, 2500.0);

    // Invested IPO 1: 100 * 20 = 2,000
    // Invested IPO 2: 200 * 30 = 6,000
    // Total invested: 8,000
    expect(state.totalAllottedInvested, 8000.0);

    // Listed Value: 3,000 + 7,500 = 10,500
    expect(state.totalAllottedValue, 10500.0);
    expect(state.totalAllottedShares, 50);

    // Return: (2,500 / 8,000) * 100 = 31.25%
    expect(state.totalAllottedReturnPercentage, 31.25);
  });

  test('IpoListState sorts filtered IPOs with latest date at the top and defaults to MAINBOARD', () {
    final olderIpo = IpoItemModel(
      id: 'ipo-older',
      name: 'Older Mainboard Ltd',
      slug: 'older-mainboard-ltd',
      issueType: 'MAINBOARD',
      registrar: 'KFINTECH',
      officialVerificationUrl: '',
      status: AllotmentStatusEnum.pending,
      listingDate: DateTime.parse('2026-10-10'),
    );

    final newerIpo = IpoItemModel(
      id: 'ipo-newer',
      name: 'Newer Mainboard Ltd',
      slug: 'newer-mainboard-ltd',
      issueType: 'MAINBOARD',
      registrar: 'KFINTECH',
      officialVerificationUrl: '',
      status: AllotmentStatusEnum.allotted,
      listingDate: DateTime.parse('2026-10-28'),
    );

    final smeIpo = IpoItemModel(
      id: 'ipo-sme',
      name: 'SME Tech Ltd',
      slug: 'sme-tech-ltd',
      issueType: 'SME',
      registrar: 'KFINTECH',
      officialVerificationUrl: '',
      status: AllotmentStatusEnum.pending,
      listingDate: DateTime.parse('2026-10-25'),
    );

    final state = IpoListState(
      isLoading: false,
      ipos: [olderIpo, newerIpo, smeIpo],
      selectedLifecycle: IpoLifecycle.closed,
    );

    // Default tab is MAINBOARD
    expect(state.selectedIssueType, 'MAINBOARD');
    expect(state.filteredIposAt(DateTime.utc(2026, 10, 29)).length, 2);

    // Latest IPO (Oct 28) must be first, older (Oct 10) second
    expect(state.filteredIposAt(DateTime.utc(2026, 10, 29)).first.name, 'Newer Mainboard Ltd');
    expect(state.filteredIposAt(DateTime.utc(2026, 10, 29)).last.name, 'Older Mainboard Ltd');

    final smeState = state.copyWith(selectedIssueType: 'SME');
    expect(smeState.filteredIposAt(DateTime.utc(2026, 10, 29)).map((i) => i.name).toList(), ['SME Tech Ltd']);
  });

  test('IpoItemModel isUpcoming detects upcoming status correctly', () {
    final now = DateTime.now();

    final pastIpo = IpoItemModel(
      id: 'past-ipo',
      name: 'Past IPO',
      slug: 'past-ipo',
      issueType: 'MAINBOARD',
      registrar: 'KFINTECH',
      officialVerificationUrl: '',
      status: AllotmentStatusEnum.notAllotted,
      listingDate: now.subtract(const Duration(days: 5)),
      listingPrice: 120.0,
    );
    expect(pastIpo.isUpcoming, false);

    final futureOpenIpo = IpoItemModel(
      id: 'future-open',
      name: 'Future Open IPO',
      slug: 'future-open',
      issueType: 'MAINBOARD',
      registrar: 'KFINTECH',
      officialVerificationUrl: '',
      status: AllotmentStatusEnum.notApplied,
      openDate: now.add(const Duration(days: 7)),
      closeDate: now.add(const Duration(days: 10)),
    );
    expect(futureOpenIpo.isUpcoming, true);

    final explicitIpo = IpoItemModel(
      id: 'explicit-ipo',
      name: 'Explicit Upcoming IPO',
      slug: 'explicit-ipo',
      issueType: 'SME',
      registrar: 'MUFG_INTIME',
      officialVerificationUrl: '',
      status: AllotmentStatusEnum.notApplied,
      isUpcomingExplicit: true,
    );
    expect(explicitIpo.isUpcoming, false);
    expect(explicitIpo.lifecycle, IpoLifecycle.unknown);
  });

  test('IpoListState filters and sorts UPCOMING IPOs with soonest first', () {
    final now = DateTime.now();

    final pastIpo = IpoItemModel(
      id: 'past-ipo',
      name: 'Past Mainboard Ltd',
      slug: 'past-mainboard-ltd',
      issueType: 'MAINBOARD',
      registrar: 'KFINTECH',
      officialVerificationUrl: '',
      status: AllotmentStatusEnum.notAllotted,
      listingDate: now.subtract(const Duration(days: 2)),
      listingPrice: 100.0,
    );

    final soonUpcoming = IpoItemModel(
      id: 'soon-ipo',
      name: 'Opening Soon Ltd',
      slug: 'opening-soon-ltd',
      issueType: 'MAINBOARD',
      registrar: 'KFINTECH',
      officialVerificationUrl: '',
      status: AllotmentStatusEnum.notApplied,
      openDate: now.add(const Duration(days: 3)),
      closeDate: now.add(const Duration(days: 6)),
      allotmentDate: now.add(const Duration(days: 7)),
    );

    final laterUpcoming = IpoItemModel(
      id: 'later-ipo',
      name: 'Opening Later SME Ltd',
      slug: 'opening-later-sme-ltd',
      issueType: 'SME',
      registrar: 'MUFG_INTIME',
      officialVerificationUrl: '',
      status: AllotmentStatusEnum.notApplied,
      openDate: now.add(const Duration(days: 12)),
      closeDate: now.add(const Duration(days: 15)),
      allotmentDate: now.add(const Duration(days: 18)),
    );

    final state = IpoListState(
      isLoading: false,
      ipos: [pastIpo, laterUpcoming, soonUpcoming],
      selectedIssueType: 'MAINBOARD',
      selectedLifecycle: IpoLifecycle.upcoming,
    );

    expect(state.filteredIpos.map((i) => i.name).toList(), ['Opening Soon Ltd']);
    expect(state.copyWith(selectedIssueType: 'SME').filteredIpos.map((i) => i.name).toList(), ['Opening Later SME Ltd']);
  });
}
