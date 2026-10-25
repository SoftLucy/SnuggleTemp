import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'techem_client.dart';

class TechemLoginPage extends StatefulWidget {
  const TechemLoginPage({super.key, this.routePrefix});

  final String? routePrefix;

  @override
  State<TechemLoginPage> createState() => _TechemLoginPageState();
}

class _TechemLoginPageState extends State<TechemLoginPage> {
  late final WebViewController _controller;
  int _progress = 0;
  bool _fetching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
              setState(
                () => _error = 'Could not load Techem: ${error.description}',
              );
            }
          },
        ),
      )
      ..loadRequest(
        TechemClient.heatingPageUri(routePrefix: widget.routePrefix),
      );
  }

  Future<void> _fetch() async {
    setState(() {
      _fetching = true;
      _error = null;
    });
    try {
      final currentUrl = await _controller.currentUrl();
      final routePrefix = TechemClient.routePrefixFromUri(
        currentUrl == null ? null : Uri.tryParse(currentUrl),
      );
      final preferences = await SharedPreferences.getInstance();
      final userAgent = await _controller.getUserAgent();
      if (routePrefix != null) {
        await preferences.setString('techemRoutePrefix', routePrefix);
      }
      if (userAgent != null && userAgent.isNotEmpty) {
        await preferences.setString('techemUserAgent', userAgent);
      }
      final records = await TechemClient.fetchRecords(
        routePrefix:
            routePrefix ??
            widget.routePrefix ??
            preferences.getString('techemRoutePrefix'),
        userAgent: userAgent ?? preferences.getString('techemUserAgent'),
      );
      if (mounted) Navigator.of(context).pop(records);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is TechemAuthenticationRequired
              ? 'You are not signed in yet. Sign in above, wait for the heating page to load, then tap Fetch readings.'
              : error.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Sign in to Techem'),
      actions: [
        IconButton(
          tooltip: 'Reload Techem',
          onPressed: () => _controller.reload(),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        if (_progress < 100) LinearProgressIndicator(value: _progress / 100),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(
            children: const [
              Icon(Icons.lock_outline, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sign in directly on Techem. SnuggleTemp does not save your password; it uses the portal session on this device.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        Expanded(child: WebViewWidget(controller: _controller)),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _fetching ? null : _fetch,
                icon: _fetching
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: Text(
                  _fetching
                      ? 'Fetching readings…'
                      : 'I’m signed in — fetch readings',
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
