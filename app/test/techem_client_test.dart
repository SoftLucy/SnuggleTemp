import 'package:flutter_test/flutter_test.dart';
import 'package:snuggletemp/techem_client.dart';

void main() {
  test('parses escaped Techem heating records and sorts months', () {
    const html =
        r'\"period\":\"2026-09\",\"service\":\"HEATING\",\"unitOfMeasure\":\"KWH\",\"status\":\"FINAL\",\"amount\":123.4,\"quality\":1,\"revision\":2,\"createdAt\":\"2026-09-30T12:00:00Z\",\"mixedHeatingEquipment\":false'
        r' \"period\":\"2026-08\",\"service\":\"HEATING\",\"unitOfMeasure\":\"KWH\",\"status\":\"FINAL\",\"amount\":98.6,\"quality\":1,\"revision\":1,\"createdAt\":\"2026-08-31T12:00:00Z\",\"mixedHeatingEquipment\":false';

    final records = TechemClient.parseRecordsFromHtml(html);

    expect(records.map((record) => record.period), ['2026-08', '2026-09']);
    expect(records.map((record) => record.amountKwh), [98.6, 123.4]);
  });

  test('builds a month-specific history route', () {
    expect(
      TechemClient.heatingPageUri(
        now: DateTime(2026, 10, 25),
        routePrefix: '/consumptions/heating/',
      ).path,
      '/consumptions/heating/2026-09',
    );
    expect(
      TechemClient.routePrefixFromUri(
        Uri.parse('https://mieter.techem.de/consumptions/heating/2026-09'),
      ),
      '/consumptions/heating/',
    );
  });
}
