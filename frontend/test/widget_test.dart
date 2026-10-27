import 'package:flutter_test/flutter_test.dart';
import 'package:ipo_tracker/core/models/ipo_model.dart';

void main() {
  test('Allotment status parser maps status strings accurately', () {
    expect(parseAllotmentStatus('ALLOTTED'), AllotmentStatusEnum.allotted);
    expect(parseAllotmentStatus('allotted'), AllotmentStatusEnum.allotted);
    expect(parseAllotmentStatus('NOT_ALLOTTED'), AllotmentStatusEnum.notAllotted);
    expect(parseAllotmentStatus('LOOKUP_FAILED'), AllotmentStatusEnum.lookupFailed);
    expect(parseAllotmentStatus('NOT_SUPPORTED'), AllotmentStatusEnum.notSupported);
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
  });
}
