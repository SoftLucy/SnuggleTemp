import 'dart:convert';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'techem_client.dart';
import 'techem_login_page.dart';

void main() => runApp(const SnuggleTemp());
const ink = Color(0xFFF0EEFF),
    purple = Color(0xFF7567F8),
    mint = Color(0xFF36B99A),
    amber = Color(0xFFFFB454),
    blue = Color(0xFF5D9CF5),
    muted = Color(0xFF777A91);
const months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

class SnuggleTemp extends StatelessWidget {
  const SnuggleTemp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SnuggleTemp',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF12111B),
      colorScheme: ColorScheme.fromSeed(
        seedColor: purple,
        brightness: Brightness.dark,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        fillColor: const Color(0xFF252334),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    ),
    home: const Home(),
  );
}

class Bill {
  Bill(
    this.year, {
    this.total = 0,
    this.advances = 0,
    this.balance = 0,
    this.heatingCosts = 0,
    this.heatingAdvances = 0,
    this.operatingCosts = 0,
    this.operatingAdvances = 0,
  });
  int year;
  double total,
      advances,
      balance,
      heatingCosts,
      heatingAdvances,
      operatingCosts,
      operatingAdvances;
  Map<String, dynamic> json() => {
    'year': year,
    'total': total,
    'advances': advances,
    'balance': balance,
    'heatingCosts': heatingCosts,
    'heatingAdvances': heatingAdvances,
    'operatingCosts': operatingCosts,
    'operatingAdvances': operatingAdvances,
  };
  factory Bill.from(Map<String, dynamic> j) => Bill(
    (j['year'] as num).toInt(),
    total: (j['total'] as num).toDouble(),
    advances: (j['advances'] as num).toDouble(),
    balance: (j['balance'] as num).toDouble(),
    heatingCosts: (j['heatingCosts'] as num?)?.toDouble() ?? 0,
    heatingAdvances: (j['heatingAdvances'] as num?)?.toDouble() ?? 0,
    operatingCosts: (j['operatingCosts'] as num?)?.toDouble() ?? 0,
    operatingAdvances: (j['operatingAdvances'] as num?)?.toDouble() ?? 0,
  );
}

class PaymentChange {
  PaymentChange(this.fromMonth, this.amount);
  int fromMonth;
  double amount;

  Map<String, dynamic> json() => {'fromMonth': fromMonth, 'amount': amount};

  factory PaymentChange.from(Map<String, dynamic> json) => PaymentChange(
    (json['fromMonth'] as num).toInt(),
    (json['amount'] as num).toDouble(),
  );
}

double scheduledPaymentForMonth(List<PaymentChange> schedule, int month) {
  final changes = schedule.where((change) => change.fromMonth <= month).toList()
    ..sort((a, b) => a.fromMonth.compareTo(b.fromMonth));
  return changes.isEmpty ? 0 : changes.last.amount;
}

double scheduledAnnualTotal(List<PaymentChange> schedule) => List.generate(
  12,
  (index) => scheduledPaymentForMonth(schedule, index + 1),
).fold<double>(0, (sum, amount) => sum + amount);

double annualKwhLimit({
  required double totalAdvanceBudget,
  required double otherCosts,
  required double fixedHeatingCost,
  required double variableHeatingCost,
  required double referenceAnnualKwh,
}) {
  final variableBudget = totalAdvanceBudget - otherCosts - fixedHeatingCost;
  if (variableBudget <= 0 || variableHeatingCost <= 0) return 0;
  return variableBudget * referenceAnnualKwh / variableHeatingCost;
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final Map<String, double> data = {};
  final List<Bill> bills = [];
  double other = 0, fixed = 0, variable = 0, baseKwh = 0;
  final List<PaymentChange> paymentSchedule = [PaymentChange(1, 0)];
  bool busy = false, loading = true, predictionZoom = false;
  String? checked;
  double? lat, lon;
  String locationAddress = '';
  final Map<int, double> weatherHdd = {};
  final Map<int, double> historicalHdd = {};

  @override
  void initState() {
    super.initState();
    load().catchError((Object error) {
      if (mounted) setState(() => loading = false);
    });
  }

  int get year => DateTime.now().year;
  int get latest {
    final k =
        data.keys.where((s) => s.startsWith(year.toString() + '-')).toList()
          ..sort();
    return k.isEmpty ? 0 : int.tryParse(k.last.substring(5)) ?? 0;
  }

  double get ytd => data.entries
      .where((e) => e.key.startsWith(year.toString() + '-'))
      .fold(0, (s, e) => s + e.value);
  double get annualAdvances => scheduledAnnualTotal(paymentSchedule);

  double paymentForMonth(int month) =>
      scheduledPaymentForMonth(paymentSchedule, month);

  String get paymentScheduleSummary {
    final sorted = paymentSchedule.toList()
      ..sort((a, b) => a.fromMonth.compareTo(b.fromMonth));
    return sorted
        .map(
          (change) =>
              '${months[change.fromMonth - 1]} €${change.amount.toStringAsFixed(0)}/mo',
        )
        .join(' · ');
  }

  double annualLimit(double cost) => annualKwhLimit(
    totalAdvanceBudget: cost,
    otherCosts: other,
    fixedHeatingCost: fixed,
    variableHeatingCost: variable,
    referenceAnnualKwh: baseKwh,
  );

  double get zeroLeft => math.max(0, annualLimit(annualAdvances) - ytd);
  double get bufferLeft =>
      math.max(0, annualLimit(math.max(0, annualAdvances - 100)) - ytd);
  List<int> get future => List.generate(
    12 - latest,
    (i) => latest + i + 1,
  ).where((m) => m >= 1 && m <= 12).toList();
  double get seasonal => future.fold(
    0,
    (s, m) =>
        s +
        (data[(year - 1).toString() + '-' + m.toString().padLeft(2, '0')] ?? 0),
  );
  double alloc(int m, double total) {
    final b =
        data[(year - 1).toString() + '-' + m.toString().padLeft(2, '0')] ?? 0;
    return seasonal == 0 ? 0 : total * b / seasonal;
  }

  Future<void> load() async {
    Map<String, dynamic>? privateSettings;
    try {
      privateSettings =
          jsonDecode(
                await rootBundle.loadString(
                  'assets/private/snuggletemp_settings.json',
                ),
              )
              as Map<String, dynamic>;
    } catch (_) {}
    final p = await SharedPreferences.getInstance();
    final configuredRoutePrefix = privateSettings?['techemRoutePrefix'];
    final savedRoutePrefix = p.getString('techemRoutePrefix');
    if (configuredRoutePrefix is String &&
        (savedRoutePrefix == null ||
            savedRoutePrefix == '/consumptions/heating/')) {
      await p.setString('techemRoutePrefix', configuredRoutePrefix);
    }
    final raw = p.getString('data');
    if (raw != null) {
      data.addAll(
        (jsonDecode(raw) as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, (v as num).toDouble()),
        ),
      );
    } else {
      try {
        final j = jsonDecode(
          await rootBundle.loadString(
            'assets/private/techem_heating_history.json',
          ),
        );
        for (final r in j['records'] as List) {
          if (r['service'] == 'HEATING' && r['unit'] == 'kWh') {
            data[r['period']] = (r['amount_kwh'] as num).toDouble();
          }
        }
      } catch (_) {}
    }
    final savedSchedule = p.getString('paymentSchedule');
    final rawSchedule = savedSchedule == null
        ? (privateSettings?['paymentSchedule'] as List?)
        : (jsonDecode(savedSchedule) as List);
    if (rawSchedule != null && rawSchedule.isNotEmpty) {
      paymentSchedule
        ..clear()
        ..addAll(
          rawSchedule.map(
            (entry) =>
                PaymentChange.from(Map<String, dynamic>.from(entry as Map)),
          ),
        );
    }
    other =
        p.getDouble('other') ??
        (privateSettings?['other'] as num?)?.toDouble() ??
        0;
    fixed =
        p.getDouble('fixed') ??
        (privateSettings?['fixed'] as num?)?.toDouble() ??
        0;
    variable =
        p.getDouble('variable') ??
        (privateSettings?['variable'] as num?)?.toDouble() ??
        0;
    baseKwh =
        p.getDouble('baseKwh') ??
        (privateSettings?['baseKwh'] as num?)?.toDouble() ??
        0;
    checked = p.getString('checked');
    lat = p.getDouble('lat');
    lon = p.getDouble('lon');
    locationAddress = p.getString('locationAddress') ?? '';
    final b = p.getString('bills');
    if (b != null) {
      bills.addAll((jsonDecode(b) as List).map((e) => Bill.from(e)));
    } else if (privateSettings?['bills'] is List) {
      bills.addAll(
        (privateSettings!['bills'] as List).map(
          (e) => Bill.from(e as Map<String, dynamic>),
        ),
      );
    }
    // Migrate new statement fields and add known historic years without overwriting user edits.
    if (privateSettings?['bills'] is List) {
      for (final rawBill in privateSettings!['bills'] as List) {
        final defaults = Bill.from(Map<String, dynamic>.from(rawBill as Map));
        final existing = bills
            .where((bill) => bill.year == defaults.year)
            .firstOrNull;
        if (existing == null) {
          bills.add(defaults);
        } else {
          if (existing.heatingCosts == 0)
            existing.heatingCosts = defaults.heatingCosts;
          if (existing.heatingAdvances == 0)
            existing.heatingAdvances = defaults.heatingAdvances;
          if (existing.operatingCosts == 0)
            existing.operatingCosts = defaults.operatingCosts;
          if (existing.operatingAdvances == 0)
            existing.operatingAdvances = defaults.operatingAdvances;
        }
      }
      bills.sort((a, b) => a.year.compareTo(b.year));
      await p.setString(
        'bills',
        jsonEncode(bills.map((bill) => bill.json()).toList()),
      );
    }
    updateOtherCostsFromStatement();
    if (lat != null && lon != null) await loadWeather();
    if (mounted) setState(() => loading = false);
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('data', jsonEncode(data));
    await p.setString(
      'paymentSchedule',
      jsonEncode(paymentSchedule.map((change) => change.json()).toList()),
    );
    await p.setDouble('other', other);
    await p.setDouble('fixed', fixed);
    await p.setDouble('variable', variable);
    await p.setDouble('baseKwh', baseKwh);
    if (checked != null) await p.setString('checked', checked!);
    if (lat != null) await p.setDouble('lat', lat!);
    if (lon != null) await p.setDouble('lon', lon!);
    await p.setString('locationAddress', locationAddress);
    await p.setString('bills', jsonEncode(bills.map((b) => b.json()).toList()));
  }

  void updateOtherCostsFromStatement() {
    final reference = bills.where((bill) => bill.year == year - 1).firstOrNull;
    if (reference != null && reference.total >= fixed + variable) {
      other = reference.total - fixed - variable;
    }
  }

  Future<void> geocodeLocation() async {
    if (locationAddress.trim().isEmpty) {
      lat = null;
      lon = null;
      return;
    }
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': locationAddress.trim(),
        'limit': '1',
        'countrycodes': 'de',
        'format': 'jsonv2',
      });
      final response = await http
          .get(
            uri,
            headers: const {
              'User-Agent': 'SnuggleTemp/1.0',
              'Accept-Language': 'de',
            },
          )
          .timeout(const Duration(seconds: 12));
      final results = jsonDecode(response.body) as List?;
      if (response.statusCode != 200 || results == null || results.isEmpty)
        throw Exception('not found');
      lat = double.parse(results.first['lat'] as String);
      lon = double.parse(results.first['lon'] as String);
    } catch (_) {
      lat = null;
      lon = null;
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Adresse nicht gefunden. Bitte Straße, PLZ und Ort prüfen.',
            ),
          ),
        );
    }
  }

  Future<void> loadWeather() async {
    if (lat == null || lon == null) return;
    try {
      // Use the latest standard 30-year climate-normal period. Two recent
      // years are too noisy to represent a month's usual heating demand and
      // can skew the projection after an unusually warm or cold winter.
      const start = '1991-01-01';
      const end = '2020-12-31';
      final u = Uri.https('archive-api.open-meteo.com', '/v1/archive', {
        'latitude': lat.toString(),
        'longitude': lon.toString(),
        'start_date': start,
        'end_date': end,
        'daily': 'temperature_2m_mean',
        'timezone': 'Europe/Berlin',
      });
      final r = await http.get(u).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) throw Exception('history');
      final d = jsonDecode(r.body)['daily'];
      final sum = <String, double>{};
      for (var i = 0; i < (d['time'] as List).length; i++) {
        final t = d['temperature_2m_mean'][i];
        if (t == null) continue;
        final dt = DateTime.parse(d['time'][i]);
        final k =
            dt.year.toString() + '-' + dt.month.toString().padLeft(2, '0');
        sum[k] = (sum[k] ?? 0) + math.max(0, 15.5 - (t as num).toDouble());
      }
      historicalHdd.clear();
      for (var m = 1; m <= 12; m++) {
        final vals = List.generate(30, (i) => 1991 + i)
            .map((y) => sum[y.toString() + '-' + m.toString().padLeft(2, '0')])
            .whereType<double>()
            .toList();
        if (vals.isNotEmpty) {
          historicalHdd[m] = vals.reduce((a, b) => a + b) / vals.length;
        }
      }
      final fu = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': lat.toString(),
        'longitude': lon.toString(),
        'daily': 'temperature_2m_mean',
        'forecast_days': '16',
        'timezone': 'Europe/Berlin',
      });
      final fr = await http.get(fu).timeout(const Duration(seconds: 15));
      if (fr.statusCode != 200) throw Exception('forecast');
      final fd = jsonDecode(fr.body)['daily'];
      // Start with a normal-weather estimate for every month. The live API
      // only forecasts about 16 days, so plotting only its returned months
      // would leave the rest of the year's projection disconnected.
      weatherHdd
        ..clear()
        ..addAll(historicalHdd);
      for (var i = 0; i < (fd['time'] as List).length; i++) {
        final t = fd['temperature_2m_mean'][i];
        if (t == null) continue;
        final dt = DateTime.parse(fd['time'][i]);
        final month = dt.month;
        final hist = historicalHdd[month];
        if (hist == null || hist <= 0) continue;
        final normalDaily = hist / DateTime(dt.year, month + 1, 0).day;
        final forecastDaily = math.max(0, 15.5 - (t as num).toDouble());
        weatherHdd[month] = math.max(
          0,
          (weatherHdd[month] ?? hist) + forecastDaily - normalDaily,
        );
      }
    } catch (_) {
      weatherHdd.clear();
    }
  }

  Future<void> refresh() async {
    setState(() => busy = true);
    try {
      final preferences = await SharedPreferences.getInstance();
      final routePrefix = preferences.getString('techemRoutePrefix');
      final userAgent = preferences.getString('techemUserAgent');
      List<TechemRecord> records;
      try {
        records = await TechemClient.fetchRecords(
          routePrefix: routePrefix,
          userAgent: userAgent,
        );
      } on TechemAuthenticationRequired {
        if (!mounted) return;
        final signedIn = await Navigator.of(context).push<List<TechemRecord>>(
          MaterialPageRoute(
            builder: (_) => TechemLoginPage(routePrefix: routePrefix),
          ),
        );
        if (signedIn == null) return;
        records = signedIn;
      }
      final before = Map<String, double>.from(data);
      for (final record in records) {
        data[record.period] = record.amountKwh;
      }
      final changed = data.entries
          .where((entry) => before[entry.key] != entry.value)
          .length;
      checked = DateTime.now().toIso8601String();
      await save();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              changed == 0
                  ? 'Techem is up to date.'
                  : '$changed month records updated; predictions recalculated.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not fetch Techem readings: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> importFile() async {
    setState(() => busy = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'json'],
        withData: true,
        dialogTitle: 'Choose a Techem CSV or JSON export',
      );
      if (picked == null || picked.files.single.bytes == null) return;
      final before = Map<String, double>.from(data);
      final file = picked.files.single;
      final contents = utf8.decode(file.bytes!);
      if (file.extension?.toLowerCase() == 'json') {
        final json = jsonDecode(contents);
        for (final record in json['records'] as List) {
          if (record['service'] == 'HEATING' &&
              record['unit'] == 'kWh' &&
              record['amount_kwh'] is num) {
            data[record['period']] = (record['amount_kwh'] as num).toDouble();
          }
        }
      } else {
        for (final line in const LineSplitter().convert(contents).skip(1)) {
          final columns = line.split(',');
          if (columns.length > 4 &&
              columns[1] == 'HEATING' &&
              columns[2] == 'kWh') {
            final amount = double.tryParse(columns[4]);
            if (amount != null) data[columns[0]] = amount;
          }
        }
      }
      final changed = data.entries
          .where((entry) => before[entry.key] != entry.value)
          .length;
      checked = DateTime.now().toIso8601String();
      await save();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              changed == 0
                  ? 'Already up to date.'
                  : '$changed month records imported; predictions recalculated.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Import failed: $error')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> settings() async {
    final localSchedule =
        paymentSchedule
            .map((change) => PaymentChange(change.fromMonth, change.amount))
            .toList()
          ..sort((a, b) => a.fromMonth.compareTo(b.fromMonth));
    final amountControllers = <PaymentChange, TextEditingController>{
      for (final change in localSchedule)
        change: TextEditingController(text: change.amount.toStringAsFixed(2)),
    };
    final address = TextEditingController(text: locationAddress);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, updateSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Advance payments',
                  style: Theme.of(sheetContext).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Enter the monthly amount and the month it takes effect. Each amount continues until the next change. The break-even and €100-buffer predictions update automatically.',
                ),
                const SizedBox(height: 16),
                ...localSchedule.map((change) {
                  final usedMonths = localSchedule
                      .where((otherChange) => otherChange != change)
                      .map((otherChange) => otherChange.fromMonth)
                      .toSet();
                  final options =
                      List.generate(12, (index) => index + 1)
                          .where(
                            (month) =>
                                !usedMonths.contains(month) ||
                                month == change.fromMonth,
                          )
                          .toList()
                        ..sort();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: DropdownButtonFormField<int>(
                            initialValue: change.fromMonth,
                            decoration: const InputDecoration(
                              labelText: 'Effective from',
                            ),
                            items: options
                                .map(
                                  (month) => DropdownMenuItem(
                                    value: month,
                                    child: Text(months[month - 1]),
                                  ),
                                )
                                .toList(),
                            onChanged: (month) {
                              if (month != null) {
                                updateSheet(() => change.fromMonth = month);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 4,
                          child: TextField(
                            controller: amountControllers[change],
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: '€ / month',
                            ),
                            onChanged: (value) {
                              change.amount =
                                  double.tryParse(value.replaceAll(',', '.')) ??
                                  0;
                            },
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove payment change',
                          onPressed: localSchedule.length <= 1
                              ? null
                              : () => updateSheet(() {
                                  localSchedule.remove(change);
                                  amountControllers.remove(change)?.dispose();
                                }),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                      ],
                    ),
                  );
                }),
                OutlinedButton.icon(
                  onPressed: localSchedule.length >= 12
                      ? null
                      : () => updateSheet(() {
                          final used = localSchedule
                              .map((c) => c.fromMonth)
                              .toSet();
                          final month = List.generate(
                            12,
                            (i) => i + 1,
                          ).firstWhere((m) => !used.contains(m));
                          final amount = localSchedule.isEmpty
                              ? 0.0
                              : localSchedule.last.amount;
                          final change = PaymentChange(month, amount);
                          localSchedule.add(change);
                          amountControllers[change] = TextEditingController(
                            text: amount.toStringAsFixed(2),
                          );
                          localSchedule.sort(
                            (a, b) => a.fromMonth.compareTo(b.fromMonth),
                          );
                        }),
                  icon: const Icon(Icons.add),
                  label: const Text('Add payment change'),
                ),
                const SizedBox(height: 20),
                Text(
                  'Weather location',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Optional: used only for the weather-aware forecast.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: address,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'German address',
                    hintText: 'Street, postcode, city',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheetContext, true),
                    child: const Text('Save & recalculate'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (ok == true) {
      localSchedule.sort((a, b) => a.fromMonth.compareTo(b.fromMonth));
      if (!localSchedule.any((change) => change.fromMonth == 1)) {
        localSchedule.insert(
          0,
          PaymentChange(
            1,
            localSchedule.isEmpty ? 0 : localSchedule.first.amount,
          ),
        );
      }
      setState(() {
        paymentSchedule
          ..clear()
          ..addAll(localSchedule);
        locationAddress = address.text.trim();
        weatherHdd.clear();
        historicalHdd.clear();
      });
      await geocodeLocation();
      await loadWeather();
      await save();
      if (mounted) setState(() {});
    }
    for (final controller in amountControllers.values) {
      controller.dispose();
    }
    address.dispose();
  }

  Future<void> importBillWithAi({
    List<Bill>? targetBills,
    VoidCallback? refreshLocal,
  }) async {
    final prompt =
        '''Read the attached German Nebenkostenabrechnung / Heizkostenabrechnung. Use OCR on the attached file (including scanned pages and tables), then extract only values explicitly present. Distinguish the billing year from the document date. Return ONLY valid JSON, no Markdown fences or commentary, in exactly this shape:
{
  "year": ${DateTime.now().year},
  "total": 1000.00,
  "advances": 900.00,
  "balance": 100.00,
  "heatingCosts": 500.00,
  "heatingAdvances": 450.00,
  "operatingCosts": 500.00,
  "operatingAdvances": 450.00
}
All monetary values must be numbers in euros (decimal point). Use 0 for a value not explicitly available; do not guess or calculate missing figures. balance is Nachzahlung positive / Guthaben negative. If multiple years appear, extract the main statement's billing year only. Double-check OCR digits and totals against the document before returning JSON.''';
    final answer = TextEditingController();
    final importedJson = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add year with AI'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '1. Copy this prompt into your AI chat and attach the statement PDF or photos. The AI should OCR the attachment and return JSON.',
                ),
                const SizedBox(height: 10),
                Container(
                  constraints: const BoxConstraints(maxHeight: 190),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF252334),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      prompt,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: prompt));
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('AI prompt copied')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy prompt'),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('2. Paste the AI JSON answer here:'),
                const SizedBox(height: 8),
                TextField(
                  controller: answer,
                  minLines: 5,
                  maxLines: 10,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    hintText: '{ "year": YYYY, "total": 0, ... }',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Import JSON'),
          ),
        ],
      ),
    );
    if (!mounted || importedJson != true) {
      answer.dispose();
      return;
    }
    try {
      final decoded = jsonDecode(answer.text.trim());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Expected one JSON object.');
      }
      final yearValue = decoded['year'];
      if (yearValue is! num ||
          yearValue.toInt() < 1900 ||
          yearValue.toInt() > year + 1) {
        throw const FormatException(
          'The JSON must contain a valid billing year.',
        );
      }
      double amount(String key) {
        final value = decoded[key] ?? 0;
        if (value is! num || !value.isFinite) {
          throw FormatException(
            '"$key" must be a number (or 0 if unavailable).',
          );
        }
        return value.toDouble();
      }

      final imported = Bill(
        yearValue.toInt(),
        total: amount('total'),
        advances: amount('advances'),
        balance: amount('balance'),
        heatingCosts: amount('heatingCosts'),
        heatingAdvances: amount('heatingAdvances'),
        operatingCosts: amount('operatingCosts'),
        operatingAdvances: amount('operatingAdvances'),
      );
      final destination = targetBills ?? bills;
      final existingIndex = destination.indexWhere(
        (b) => b.year == imported.year,
      );
      if (existingIndex >= 0) {
        final replace = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('${imported.year} already exists'),
            content: const Text(
              'Replace the existing statement values with the imported JSON?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Keep existing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Replace'),
              ),
            ],
          ),
        );
        if (replace != true) return;
        destination[existingIndex] = imported;
      } else {
        destination.add(imported);
      }
      destination.sort((a, b) => b.year.compareTo(a.year));
      if (targetBills == null) {
        updateOtherCostsFromStatement();
        await save();
      }
      if (mounted) {
        if (refreshLocal != null) {
          refreshLocal();
        } else {
          setState(() {});
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              targetBills == null
                  ? '${imported.year} statement imported'
                  : '${imported.year} added to the form — save statements to keep it',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not import JSON: $error')),
        );
      }
    } finally {
      answer.dispose();
    }
  }

  Future<void> statements() async {
    final local = bills
        .map(
          (b) => Bill(
            b.year,
            total: b.total,
            advances: b.advances,
            balance: b.balance,
            heatingCosts: b.heatingCosts,
            heatingAdvances: b.heatingAdvances,
            operatingCosts: b.operatingCosts,
            operatingAdvances: b.operatingAdvances,
          ),
        )
        .toList();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, ss) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.of(c).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nebenkostenabrechnungen',
                  style: Theme.of(c).textTheme.headlineSmall,
                ),
                const Text(
                  'Enter the overall balance and, where available, the separate heating and operating-cost totals and advances.',
                ),
                ...local.map((b) => BillEdit(key: ValueKey(b.year), bill: b)),
                OutlinedButton.icon(
                  onPressed: () => importBillWithAi(
                    targetBills: local,
                    refreshLocal: () => ss(() {}),
                  ),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Add year with AI'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    local.add(
                      Bill(
                        local.isEmpty
                            ? year - 1
                            : local.map((b) => b.year).reduce(math.max) - 1,
                      ),
                    );
                    ss(() {});
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add year'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Save statements'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok == true) {
      setState(() {
        bills
          ..clear()
          ..addAll(local);
        updateOtherCostsFromStatement();
      });
      await save();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: refresh,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: purple.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: const Icon(
                            Icons.pets,
                            color: purple,
                            size: 27,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'SnuggleTemp',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: ink,
                                ),
                              ),
                              Text(
                                'Your heating, under control',
                                style: TextStyle(fontSize: 12, color: muted),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: settings,
                          icon: const Icon(Icons.tune, color: ink),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: metricCard(
                            'Break-even',
                            zeroLeft.toStringAsFixed(0) + ' kWh',
                            'left this year',
                            mint,
                            Icons.check_circle_outline,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: metricCard(
                            '€100 buffer',
                            bufferLeft.toStringAsFixed(0) + ' kWh',
                            'left this year',
                            purple,
                            Icons.savings_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [purple, Color(0xFF9C8DFB)],
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  months[DateTime.now().month - 1] +
                                      ' allowance',
                                  style: const TextStyle(
                                    color: Color(0xFFEAE7FF),
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${alloc(DateTime.now().month, bufferLeft).toStringAsFixed(0)} kWh budget',
                                  style: const TextStyle(
                                    color: ink,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  'Last year: ${(data['${year - 1}-${DateTime.now().month.toString().padLeft(2, '0')}'] ?? 0).toStringAsFixed(0)} kWh',
                                  style: const TextStyle(
                                    color: Color(0xFFEAE7FF),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.thermostat_outlined,
                            color: Colors.white,
                            size: 28,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Monthly outlook',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: ink,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () =>
                              setState(() => predictionZoom = !predictionZoom),
                          icon: Icon(
                            predictionZoom ? Icons.zoom_out : Icons.zoom_in,
                            size: 17,
                          ),
                          label: Text(
                            predictionZoom ? 'Full year' : 'Predictions',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Monthly actuals and three ways to finish the year.',
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.fromLTRB(8, 18, 14, 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1D1B2A),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFF343145)),
                      ),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 240,
                            child: data.isEmpty
                                ? FilledButton.icon(
                                    onPressed: refresh,
                                    icon: const Icon(Icons.upload_file),
                                    label: const Text('Fetch Techem readings'),
                                  )
                                : chart(),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 10,
                            children: [
                              legend(blue, '${year - 1} actual'),
                              legend(ink, year.toString() + ' actual'),
                              legend(mint, '€0 left over'),
                              legend(purple, '€100 buffer'),
                              legend(
                                amber,
                                lat == null
                                    ? 'Seasonal baseline'
                                    : 'Weather-aware',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1D1B2A),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF343145)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Advance payments',
                                  style: TextStyle(
                                    color: Color(0xFFEAE7FF),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                '€${annualAdvances.toStringAsFixed(0)} / year',
                                style: const TextStyle(
                                  color: ink,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            paymentScheduleSummary,
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'Statements & data',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1D1B2A),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF343145)),
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            leading: lead(Icons.sync, purple),
                            title: const Text(
                              'Fetch latest Techem readings',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: ink,
                              ),
                            ),
                            subtitle: Text(
                              checked == null
                                  ? 'Sign in in-app if needed; predictions recalculate'
                                  : 'Last checked ' + date(checked!),
                              style: const TextStyle(
                                fontSize: 12,
                                color: muted,
                              ),
                            ),
                            trailing: busy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.chevron_right),
                            onTap: busy ? null : refresh,
                          ),
                          const Divider(height: 1, indent: 68),
                          ListTile(
                            leading: lead(Icons.file_open_outlined, blue),
                            title: const Text(
                              'Import Techem export file',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: ink,
                              ),
                            ),
                            subtitle: const Text(
                              'Optional fallback: import CSV or JSON',
                              style: TextStyle(fontSize: 12, color: muted),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: busy ? null : importFile,
                          ),
                          const Divider(height: 1, indent: 68),
                          ListTile(
                            leading: lead(Icons.receipt_long, amber),
                            title: const Text(
                              'Nebenkostenabrechnungen',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: ink,
                              ),
                            ),
                            subtitle: Text(
                              bills.length.toString() +
                                  ' statement(s) · total, advances and balance',
                              style: const TextStyle(
                                fontSize: 12,
                                color: muted,
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: statements,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Center(
                      child: Text(
                        'Weather by Open-Meteo · geocoding © OpenStreetMap · estimates',
                        style: TextStyle(color: muted, fontSize: 11),
                      ),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget chart() {
    final minX = predictionZoom ? math.max(1, latest.toDouble() - 0.5) : 1.0;
    // Draw projections first so their dashed strokes cannot hide historical
    // readings when the values happen to be close. Actuals remain on top.
    final bars = [
      target(mint, zeroLeft, true),
      target(purple, bufferLeft, true),
      weather(),
      line(year - 1, blue),
      line(year, ink),
    ];
    final visibleY = bars
        .expand((bar) => bar.spots)
        .where((spot) => spot.x >= minX && spot.x <= 12)
        .map((spot) => spot.y)
        .toList();
    final dataMin = visibleY.isEmpty ? 0.0 : visibleY.reduce(math.min);
    final dataMax = visibleY.isEmpty ? chartMax() : visibleY.reduce(math.max);
    final range = math.max(500.0, dataMax - dataMin);
    final minY = predictionZoom
        ? math.max(0.0, ((dataMin - range * 0.12) / 250).floorToDouble() * 250)
        : 0.0;
    final maxY = predictionZoom
        ? math.max(
            minY + 500,
            ((dataMax + range * 0.12) / 250).ceilToDouble() * 250,
          )
        : chartMax();
    final interval = math.max(
      250.0,
      ((maxY - minY) / 4 / 250).roundToDouble() * 250,
    );
    return LineChart(
      LineChartData(
        minX: minX.toDouble(),
        maxX: 12,
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (v) =>
              FlLine(color: const Color(0xFF343145), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              interval: interval,
              getTitlesWidget: (v, m) => Text(
                v == 0 ? '0' : (v / 1000).toStringAsFixed(1) + 'k',
                style: const TextStyle(fontSize: 9, color: muted),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              reservedSize: 24,
              getTitlesWidget: (v, m) {
                final i = v.toInt();
                return i < 1 || i > 12
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: Text(
                          months[i - 1],
                          style: TextStyle(
                            fontSize: 10,
                            color: i >= 10 ? ink : muted,
                          ),
                        ),
                      );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          enabled: true,
          touchSpotThreshold: 80,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF252334),
            getTooltipItems: (spots) => spots
                .map(
                  (s) => LineTooltipItem(
                    months[s.x.toInt() - 1] +
                        ' · ' +
                        s.y.toStringAsFixed(0) +
                        ' kWh',
                    TextStyle(
                      color: s.bar.color ?? Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        lineBarsData: bars,
      ),
    );
  }

  double chartMax() {
    var m = 1000.0;
    for (final v in data.values) {
      m = math.max(m, v);
    }
    for (final x in future) {
      m = math.max(m, alloc(x, zeroLeft));
      m = math.max(m, alloc(x, bufferLeft));
      m = math.max(m, weatherValue(x));
    }
    return (m / 500).ceil() * 500;
  }

  // Sample a shape-preserving cubic Hermite curve into ordinary line segments.
  // fl_chart's built-in Catmull-Rom-like handles can locally reverse between
  // rising points; dense PCHIP samples keep the line smooth and monotone.
  List<FlSpot> smoothSpots(List<FlSpot> input, {double? startX}) {
    if (input.length < 3) return input;
    final p = input;
    final n = p.length;
    final h = List<double>.generate(n - 1, (i) => p[i + 1].x - p[i].x);
    final d = List<double>.generate(n - 1, (i) => (p[i + 1].y - p[i].y) / h[i]);
    final m = List<double>.filled(n, 0);
    if (n == 2) {
      m[0] = d[0];
      m[1] = d[0];
    } else {
      for (var i = 1; i < n - 1; i++) {
        if (d[i - 1] == 0 || d[i] == 0 || d[i - 1].sign != d[i].sign) {
          m[i] = 0;
        } else {
          final w1 = 2 * h[i] + h[i - 1];
          final w2 = h[i] + 2 * h[i - 1];
          m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i]);
        }
      }
      double endpoint(double h0, double h1, double d0, double d1) {
        var slope = ((2 * h0 + h1) * d0 - h0 * d1) / (h0 + h1);
        if (slope == 0 || d0 == 0 || slope.sign != d0.sign) return 0;
        if (d0.sign != d1.sign && slope.abs() > 3 * d0.abs()) {
          slope = 3 * d0;
        }
        return slope;
      }

      m[0] = endpoint(h[0], h[1], d[0], d[1]);
      m[n - 1] = endpoint(h[n - 2], h[n - 3], d[n - 2], d[n - 3]);
    }
    final out = <FlSpot>[p.first];
    for (var i = 0; i < n - 1; i++) {
      for (var step = 1; step <= 12; step++) {
        final t = step / 12;
        final t2 = t * t;
        final t3 = t2 * t;
        final y =
            (2 * t3 - 3 * t2 + 1) * p[i].y +
            (t3 - 2 * t2 + t) * h[i] * m[i] +
            (-2 * t3 + 3 * t2) * p[i + 1].y +
            (t3 - t2) * h[i] * m[i + 1];
        out.add(FlSpot(p[i].x + h[i] * t, math.max(0, y)));
      }
    }
    return startX == null
        ? out
        : out.where((spot) => spot.x >= startX).toList();
  }

  LineChartBarData line(int y, Color c) => LineChartBarData(
    spots: smoothSpots(
      List.generate(12, (i) {
        final v = data[y.toString() + '-' + (i + 1).toString().padLeft(2, '0')];
        return v == null ? null : FlSpot((i + 1).toDouble(), v);
      }).whereType<FlSpot>().toList(),
    ),
    isCurved: false,
    color: c,
    dotData: const FlDotData(show: false),
  );
  LineChartBarData target(Color c, double remaining, bool dash) =>
      LineChartBarData(
        spots: smoothSpots([
          if (latest > 1 &&
              data['$year-${(latest - 1).toString().padLeft(2, '0')}'] != null)
            FlSpot(
              (latest - 1).toDouble(),
              data['$year-${(latest - 1).toString().padLeft(2, '0')}']!,
            ),
          if (latest >= 1 &&
              data['$year-${latest.toString().padLeft(2, '0')}'] != null)
            FlSpot(
              latest.toDouble(),
              data['$year-${latest.toString().padLeft(2, '0')}']!,
            ),
          ...future.map((m) => FlSpot(m.toDouble(), alloc(m, remaining))),
        ], startX: latest.toDouble()),
        isCurved: false,
        color: c,
        barWidth: 2.8,
        dashArray: dash ? [2, 4] : null,
        dotData: const FlDotData(show: false),
      );
  double weatherValue(int month) {
    final base =
        data[(year - 1).toString() + '-' + month.toString().padLeft(2, '0')] ??
        0;
    final hist = historicalHdd[month] ?? 0;
    final forecast = weatherHdd[month];
    if (lat == null || hist <= 0 || forecast == null) return base;
    return base * forecast / hist;
  }

  LineChartBarData weather() => LineChartBarData(
    // Anchor at the latest actual month, then project through December.
    // PCHIP sampling keeps weather and target curves smooth without reversals.
    spots: smoothSpots([
      if (latest > 1 &&
          data['$year-${(latest - 1).toString().padLeft(2, '0')}'] != null &&
          lat != null &&
          lon != null)
        FlSpot(
          (latest - 1).toDouble(),
          data['$year-${(latest - 1).toString().padLeft(2, '0')}']!,
        ),
      if (latest >= 1 &&
          data['$year-${latest.toString().padLeft(2, '0')}'] != null &&
          lat != null &&
          lon != null)
        FlSpot(
          latest.toDouble(),
          data['$year-${latest.toString().padLeft(2, '0')}']!,
        ),
      ...future
          .where(
            (m) =>
                lat != null &&
                lon != null &&
                (historicalHdd[m] ?? 0) > 0 &&
                weatherHdd.containsKey(m),
          )
          .map((m) => FlSpot(m.toDouble(), weatherValue(m))),
    ], startX: latest.toDouble()),
    isCurved: false,
    color: amber,
    barWidth: 2.8,
    dashArray: [2, 4],
    dotData: const FlDotData(show: false),
  );
  Widget metric(String a, String b) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(a, style: const TextStyle(color: Color(0xFFEAE7FF), fontSize: 11)),
      const SizedBox(height: 4),
      Text(
        b,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
  Widget metricCard(String a, String b, String c, Color color, IconData icon) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1D1B2A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF343145)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    a,
                    style: const TextStyle(
                      fontSize: 11,
                      color: muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 11),
            FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Text(
                b,
                style: const TextStyle(
                  fontSize: 22,
                  color: ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(c, style: const TextStyle(fontSize: 11, color: muted)),
          ],
        ),
      );
  Widget legend(Color c, String s) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 18, height: 3, color: c),
      const SizedBox(width: 5),
      Text(s, style: const TextStyle(fontSize: 10, color: muted)),
    ],
  );
  Widget lead(IconData i, Color c) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: c.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Icon(i, color: c),
  );
  String date(String s) {
    final d = DateTime.tryParse(s)?.toLocal();
    return d == null
        ? 'recently'
        : d.day.toString().padLeft(2, '0') +
              '.' +
              d.month.toString().padLeft(2, '0') +
              ' ' +
              d.hour.toString().padLeft(2, '0') +
              ':' +
              d.minute.toString().padLeft(2, '0');
  }
}

class BillEdit extends StatefulWidget {
  const BillEdit({super.key, required this.bill});
  final Bill bill;
  @override
  State<BillEdit> createState() => _BillEditState();
}

class _BillEditState extends State<BillEdit> {
  late final TextEditingController a, b, c, hc, ha, oc, oa;
  @override
  void initState() {
    super.initState();
    a = TextEditingController(
      text: widget.bill.total == 0 ? '' : widget.bill.total.toStringAsFixed(2),
    );
    b = TextEditingController(
      text: widget.bill.advances == 0
          ? ''
          : widget.bill.advances.toStringAsFixed(2),
    );
    c = TextEditingController(
      text: widget.bill.balance == 0
          ? ''
          : widget.bill.balance.toStringAsFixed(2),
    );
    hc = TextEditingController(
      text: widget.bill.heatingCosts == 0
          ? ''
          : widget.bill.heatingCosts.toStringAsFixed(2),
    );
    ha = TextEditingController(
      text: widget.bill.heatingAdvances == 0
          ? ''
          : widget.bill.heatingAdvances.toStringAsFixed(2),
    );
    oc = TextEditingController(
      text: widget.bill.operatingCosts == 0
          ? ''
          : widget.bill.operatingCosts.toStringAsFixed(2),
    );
    oa = TextEditingController(
      text: widget.bill.operatingAdvances == 0
          ? ''
          : widget.bill.operatingAdvances.toStringAsFixed(2),
    );
  }

  double parse(String s) => double.tryParse(s.replaceAll(',', '.')) ?? 0;
  @override
  void dispose() {
    a.dispose();
    b.dispose();
    c.dispose();
    hc.dispose();
    ha.dispose();
    oc.dispose();
    oa.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF1D1B2A),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.bill.year.toString() + ' statement',
          style: const TextStyle(fontWeight: FontWeight.w800, color: ink),
        ),
        const SizedBox(height: 8),
        const Text(
          'Heating (Heizkosten)',
          style: TextStyle(color: purple, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: hc,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Heizkosten'),
          onChanged: (v) => widget.bill.heatingCosts = parse(v),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: ha,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Heizkosten-Vorauszahlung',
          ),
          onChanged: (v) => widget.bill.heatingAdvances = parse(v),
        ),
        const SizedBox(height: 14),
        const Text(
          'Operating costs (Betriebskosten)',
          style: TextStyle(color: purple, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: oc,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Betriebskosten'),
          onChanged: (v) => widget.bill.operatingCosts = parse(v),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: oa,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Betriebskosten-Vorauszahlung',
          ),
          onChanged: (v) => widget.bill.operatingAdvances = parse(v),
        ),
        const SizedBox(height: 14),
        const Text(
          'Overall statement',
          style: TextStyle(color: purple, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: a,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Gesamtkosten'),
          onChanged: (v) => widget.bill.total = parse(v),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: b,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Vorauszahlungen gesamt',
          ),
          onChanged: (v) => widget.bill.advances = parse(v),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          decoration: const InputDecoration(
            labelText: 'Nachzahlung (+) / Guthaben (-)',
          ),
          onChanged: (v) => widget.bill.balance = parse(v),
        ),
      ],
    ),
  );
}
