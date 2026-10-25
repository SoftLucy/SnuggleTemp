import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';

const techemBaseUrl = 'https://mieter.techem.de';

class TechemRecord {
  const TechemRecord(this.period, this.amountKwh);
  final String period;
  final double amountKwh;
}

class TechemAuthenticationRequired implements Exception {
  const TechemAuthenticationRequired();
  @override
  String toString() => 'Please sign in to your Techem account.';
}

class TechemClient {
  static final WebViewCookieManager _cookieManager = WebViewCookieManager();

  static Future<http.Response> _getWithoutRedirects(
    Uri uri,
    Map<String, String> headers,
    Duration timeout,
  ) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers.addAll(headers);
      final streamed = await client.send(request).timeout(timeout);
      return await http.Response.fromStream(streamed).timeout(timeout);
    } finally {
      client.close();
    }
  }

  static Uri heatingPageUri({DateTime? now, String? routePrefix}) {
    final current = now ?? DateTime.now();
    final month = DateTime(
      current.year,
      current.month,
      1,
    ).subtract(const Duration(days: 1));
    final period = '${month.year}-${month.month.toString().padLeft(2, '0')}';
    final prefix = routePrefix ?? '/consumptions/heating/';
    return Uri.parse('$techemBaseUrl$prefix$period');
  }

  static String? routePrefixFromUri(Uri? uri) {
    if (uri == null || uri.host != 'mieter.techem.de') return null;
    return RegExp(
      r'^(.*?/consumptions/heating/)\d{4}-\d{2}/?$',
    ).firstMatch(uri.path)?.group(1);
  }

  static Future<List<TechemRecord>> fetchRecords({
    String? routePrefix,
    String? userAgent,
  }) async {
    final cookies = await _cookieManager.getCookies(
      domain: Uri.parse(techemBaseUrl),
    );
    final cookieHeader = cookies
        .map((cookie) => '${cookie.name}=${cookie.value}')
        .join('; ');
    final hasSession = cookies.any(
      (cookie) =>
          cookie.name == '__Secure-next-auth.session-token' &&
          cookie.value.isNotEmpty,
    );
    if (!hasSession) throw const TechemAuthenticationRequired();

    final headers = <String, String>{
      if (userAgent != null && userAgent.isNotEmpty) 'User-Agent': userAgent,
      'Cookie': cookieHeader,
      'Accept-Language': 'en-US,en;q=0.9,de;q=0.8',
      'Cache-Control': 'no-cache',
      'Pragma': 'no-cache',
      'Origin': techemBaseUrl,
      'Referer': heatingPageUri(routePrefix: routePrefix).toString(),
    };
    final sessionResponse = await _getWithoutRedirects(
      Uri.parse('$techemBaseUrl/api/auth/session'),
      {...headers, 'Accept': 'application/json'},
      const Duration(seconds: 25),
    );
    if (sessionResponse.statusCode == 401 ||
        sessionResponse.statusCode == 403 ||
        (sessionResponse.statusCode >= 300 &&
            sessionResponse.statusCode < 400)) {
      throw const TechemAuthenticationRequired();
    }
    if (sessionResponse.statusCode != 200) {
      throw Exception(
        'Techem session check failed (HTTP ${sessionResponse.statusCode}).',
      );
    }
    dynamic session;
    try {
      session = jsonDecode(sessionResponse.body);
    } catch (_) {
      throw const TechemAuthenticationRequired();
    }
    if (session is! Map || session['user'] == null) {
      throw const TechemAuthenticationRequired();
    }

    final pageResponse =
        await _getWithoutRedirects(heatingPageUri(routePrefix: routePrefix), {
          ...headers,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        }, const Duration(seconds: 45));
    if (pageResponse.statusCode == 401 ||
        pageResponse.statusCode == 403 ||
        (pageResponse.statusCode >= 300 && pageResponse.statusCode < 400)) {
      throw const TechemAuthenticationRequired();
    }
    if (pageResponse.statusCode != 200) {
      throw Exception(
        'Techem heating history failed (HTTP ${pageResponse.statusCode}).',
      );
    }

    return parseRecordsFromHtml(pageResponse.body);
  }

  static List<TechemRecord> parseRecordsFromHtml(String body) {
    // Techem embeds readings in an escaped Next.js server-rendered payload.
    // Normalize any backslashes before quotes, then match the known record shape.
    final html = body.replaceAll(RegExp(r'\\+"'), '"');
    final pattern = RegExp(
      r'"period":"(\d{4}-\d{2})","service":"HEATING","unitOfMeasure":"KWH",'
      r'"status":"([^"]+)","amount":([^,]+),"quality":([^,]+),'
      r'"revision":(\d+),"createdAt":"([^"]+)","mixedHeatingEquipment":(true|false)',
    );
    final byPeriod = <String, TechemRecord>{};
    for (final match in pattern.allMatches(html)) {
      final period = match.group(1);
      final amount = double.tryParse(match.group(3) ?? '');
      if (period != null && amount != null && amount.isFinite) {
        byPeriod[period] = TechemRecord(period, amount);
      }
    }
    if (byPeriod.isEmpty) {
      throw Exception(
        'No heating readings were found. The Techem portal may have changed or access to the heating history may be unavailable.',
      );
    }
    final records = byPeriod.values.toList()
      ..sort((a, b) => a.period.compareTo(b.period));
    return records;
  }
}
