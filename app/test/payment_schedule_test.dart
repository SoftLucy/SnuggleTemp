import 'package:flutter_test/flutter_test.dart';
import 'package:snuggletemp/main.dart';

void main() {
  test('January and April advance changes total the annual payments', () {
    final schedule = [PaymentChange(1, 100), PaymentChange(4, 150)];
    expect(scheduledPaymentForMonth(schedule, 1), 100);
    expect(scheduledPaymentForMonth(schedule, 3), 100);
    expect(scheduledPaymentForMonth(schedule, 4), 150);
    expect(scheduledPaymentForMonth(schedule, 12), 150);
    expect(scheduledAnnualTotal(schedule), 1650);
  });

  test('a later payment change only affects that month onward', () {
    final schedule = [
      PaymentChange(1, 100),
      PaymentChange(4, 150),
      PaymentChange(10, 160),
    ];
    expect(scheduledAnnualTotal(schedule), 1680);
    expect(scheduledPaymentForMonth(schedule, 9), 150);
    expect(scheduledPaymentForMonth(schedule, 10), 160);
  });

  test(
    'break-even and €100-buffer kWh ceilings use the scheduled advances',
    () {
      const otherCosts = 500.0;
      const fixedHeating = 100.0;
      const variableHeating = 900.0;
      const referenceKwh = 10000.0;
      final breakEven = annualKwhLimit(
        totalAdvanceBudget: 1800,
        otherCosts: otherCosts,
        fixedHeatingCost: fixedHeating,
        variableHeatingCost: variableHeating,
        referenceAnnualKwh: referenceKwh,
      );
      final buffer = annualKwhLimit(
        totalAdvanceBudget: 1700,
        otherCosts: otherCosts,
        fixedHeatingCost: fixedHeating,
        variableHeatingCost: variableHeating,
        referenceAnnualKwh: referenceKwh,
      );
      expect(breakEven, closeTo(13333.3333, 0.1));
      expect(buffer, closeTo(12222.2222, 0.1));
    },
  );
}
