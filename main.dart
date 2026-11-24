// Wealth Desk — Android app.
// It shows your Wealth Desk website (so every update you install from the
// Owner panel appears here instantly) and adds native AdMob ads, reminders,
// UPI / WhatsApp hand-off, the back button and PDF printing.
//
// You don't need to edit this file: all settings live in wealthdesk_config.json.

import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:workmanager/workmanager.dart';

import 'config.dart';

final FlutterLocalNotificationsPlugin notifs = FlutterLocalNotificationsPlugin();
const String reminderTask = 'wealthdesk-reminders';
String? pendingHash; // set when a notification is tapped

// ---------------------------------------------------------------- reminders
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    DartPluginRegistrant.ensureInitialized();
    try {
      await pollReminders();
    } catch (_) {}
    return true;
  });
}

Future<void> initNotifications() async {
  const settings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  );
  await notifs.initialize(
    settings,
    onDidReceiveNotificationResponse: (NotificationResponse r) {
      final p = r.payload ?? '#home';
      pendingHash = p;
      _HomePageState.instance?.openHash(p);
    },
  );
}

String baseUrl(String? saved) {
  var b = (saved == null || saved.isEmpty) ? AppConfig.websiteUrl : saved;
  if (!b.endsWith('/')) b = '$b/';
  return b;
}

/// Asks your server for any reminders waiting for this person and shows them.
Future<void> pollReminders() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('wd_token') ?? '';
  if (token.isEmpty || !(prefs.getBool('wd_notif') ?? false)) return;
  final b = baseUrl(prefs.getString('wd_base'));
  try {
    await http.get(Uri.parse('${b}api.php?a=tick')).timeout(const Duration(seconds: 20));
  } catch (_) {}
  final r = await http
      .get(Uri.parse('${b}api.php?a=notif_pull'), headers: {'X-Auth': token})
      .timeout(const Duration(seconds: 20));
  if (r.statusCode != 200) return;
  final data = jsonDecode(r.body);
  final items = (data is Map && data['items'] is List) ? data['items'] as List : const [];
  if (items.isEmpty) return;
  await initNotifications();
  for (final n in items) {
    if (n is! Map) continue;
    final key = (n['key'] ?? DateTime.now().millisecondsSinceEpoch).toString();
    await notifs.show(
      key.hashCode & 0x7fffffff,
      (n['title'] ?? AppConfig.appName).toString(),
      (n['body'] ?? '').toString(),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'reminders',
          'Reminders',
          channelDescription: 'Bills, EMIs, SIPs, goals and daily items',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: (n['url'] ?? '#home').toString(),
    );
  }
}

// ---------------------------------------------------------------- start
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(AppConfig.backgroundColor),
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Color(AppConfig.backgroundColor),
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  try {
    await initNotifications();
    final launch = await notifs.getNotificationAppLaunchDetails();
    if (launch != null && launch.didNotificationLaunchApp) {
      pendingHash = launch.notificationResponse?.payload;
    }
  } catch (_) {}
  try {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
    await Workmanager().registerPeriodicTask(
      reminderTask,
      reminderTask,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
  } catch (_) {}
  if (AppConfig.showBanner || AppConfig.interstitialEvery > 0) {
    try {
      await MobileAds.instance.initialize();
    } catch (_) {}
  }
  runApp(const WealthDeskApp());
}

class WealthDeskApp extends StatelessWidget {
  const WealthDeskApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(AppConfig.brandColor),
        scaffoldBackgroundColor: const Color(AppConfig.backgroundColor),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static _HomePageState? instance;
  InAppWebViewController? _web;
  BannerAd? _banner;
  AdSize? _bannerSize;
  bool _bannerLoaded = false;
  bool _pro = false;
  bool _failed = false;
  double _progress = 0;
  late final Uri _home = Uri.parse(baseUrl(null));

  @override
  void initState() {
    super.initState();
    instance = this;
    WidgetsBinding.instance.addObserver(this);
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() => _pro = p.getBool('wd_pro') ?? false);
      _maybeInterstitial(p);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadBanner();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _banner?.dispose();
    if (instance == this) instance = null;
    super.dispose();
  }

  bool get _adsAllowed => !_pro || AppConfig.adsForPro;

  // ---------------- ads
  Future<void> _loadBanner() async {
    if (!AppConfig.showBanner || _banner != null || AppConfig.bannerId.isEmpty) return;
    final width = MediaQuery.of(context).size.width.truncate();
    final size = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);
    if (size == null || !mounted) return;
    _bannerSize = size;
    _banner = BannerAd(
      adUnitId: AppConfig.bannerId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _bannerLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _banner = null;
        },
      ),
    )..load();
  }

  Future<void> _maybeInterstitial(SharedPreferences p) async {
    final every = AppConfig.interstitialEvery;
    if (every <= 0 || AppConfig.interstitialId.isEmpty || !_adsAllowed) return;
    final opens = (p.getInt('wd_opens') ?? 0) + 1;
    await p.setInt('wd_opens', opens);
    if (opens % every != 0) return;
    await Future.delayed(const Duration(seconds: 4));
    InterstitialAd.load(
      adUnitId: AppConfig.interstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) => ad.dispose(),
            onAdFailedToShowFullScreenContent: (ad, error) => ad.dispose(),
          );
          ad.show();
        },
        onAdFailedToLoad: (error) {},
      ),
    );
  }

  // ---------------- links that belong to other apps
  Future<void> _openOutside(Uri uri) async {
    var u = uri;
    if (u.scheme == 'intent') {
      // intent://pay?pa=...#Intent;scheme=upi;package=...;end  ->  upi://pay?pa=...
      final raw = uri.toString();
      final scheme = RegExp(r';scheme=([^;]+)').firstMatch(raw)?.group(1) ?? 'https';
      final rest = raw.substring('intent://'.length).split('#Intent').first;
      u = Uri.parse('$scheme://$rest');
      final fallback = RegExp(r';S\.browser_fallback_url=([^;]+)').firstMatch(raw)?.group(1);
      try {
        if (await launchUrl(u, mode: LaunchMode.externalApplication)) return;
      } catch (_) {}
      if (fallback != null) {
        await launchUrl(Uri.parse(Uri.decodeComponent(fallback)), mode: LaunchMode.externalApplication);
      } else {
        _toast(scheme == 'upi' ? 'No UPI app found on this phone' : 'Could not open that app');
      }
      return;
    }
    try {
      final ok = await launchUrl(u, mode: LaunchMode.externalApplication);
      if (!ok) _toast(u.scheme == 'upi' ? 'No UPI app found on this phone' : 'Could not open that link');
    } catch (_) {
      _toast(u.scheme == 'upi' ? 'No UPI app found on this phone' : 'Could not open that link');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  void openHash(String hash) {
    final h = hash.startsWith('#') ? hash : '#$hash';
    _web?.evaluateJavascript(source: "location.hash = ${jsonEncode(h)};");
  }

  // ---------------- messages from the web app
  Future<dynamic> _onWebMessage(List<dynamic> args) async {
    final m = args.isNotEmpty && args.first is Map ? Map<String, dynamic>.from(args.first as Map) : <String, dynamic>{};
    final prefs = await SharedPreferences.getInstance();
    switch (m['type']) {
      case 'auth':
        await prefs.setString('wd_token', (m['token'] ?? '').toString());
        await prefs.setString('wd_base', (m['base'] ?? '').toString());
        final pro = m['pro'] == true;
        await prefs.setBool('wd_pro', pro);
        if (mounted && pro != _pro) setState(() => _pro = pro);
        return true;
      case 'logout':
        await prefs.remove('wd_token');
        await prefs.setBool('wd_notif', false);
        return true;
      case 'notif':
        final android = notifs.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        final granted = await android?.requestNotificationsPermission() ?? true;
        await prefs.setBool('wd_notif', granted);
        return granted;
      case 'poll':
        Future.delayed(const Duration(seconds: 2), () => pollReminders().catchError((_) {}));
        return true;
      case 'print':
        final html = (m['html'] ?? '').toString();
        final title = (m['title'] ?? 'Wealth Desk report').toString();
        try {
          await Printing.layoutPdf(name: title, onLayout: (format) async => Printing.convertHtml(format: format, html: html));
        } catch (_) {
          _toast('Could not create the PDF on this phone');
        }
        return true;
      case 'open':
        final url = (m['url'] ?? '').toString();
        if (url.isNotEmpty) await _openOutside(Uri.parse(url));
        return true;
    }
    return null;
  }

  // ---------------- back button
  Future<void> _onBack() async {
    final c = _web;
    if (c == null) {
      SystemNavigator.pop();
      return;
    }
    dynamic handled;
    try {
      handled = await c.evaluateJavascript(source: 'window.wdBack ? window.wdBack() : false');
    } catch (_) {}
    if (handled == true || handled == 'true') return;
    if (await c.canGoBack()) {
      await c.goBack();
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    var start = _home.toString();
    final ph = pendingHash;
    if (ph != null && ph.isNotEmpty) start += ph.startsWith('#') ? ph : '#$ph';
    pendingHash = null;
    final showBanner = _bannerLoaded && _banner != null && _bannerSize != null && _adsAllowed;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: const Color(AppConfig.backgroundColor),
        body: SafeArea(
          child: Column(
            children: [
              if (_progress < 1 && !_failed)
                LinearProgressIndicator(
                  value: _progress == 0 ? null : _progress,
                  minHeight: 2,
                  color: Colors.black,
                  backgroundColor: Colors.transparent,
                ),
              Expanded(
                child: Stack(
                  children: [
                    InAppWebView(
                      initialUrlRequest: URLRequest(url: WebUri(start)),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        domStorageEnabled: true,
                        databaseEnabled: true,
                        cacheEnabled: true,
                        useShouldOverrideUrlLoading: true,
                        supportMultipleWindows: true,
                        javaScriptCanOpenWindowsAutomatically: true,
                        applicationNameForUserAgent: 'WealthDeskApp/1.0',
                        mediaPlaybackRequiresUserGesture: false,
                        supportZoom: false,
                        builtInZoomControls: false,
                        displayZoomControls: false,
                        useHybridComposition: true,
                        thirdPartyCookiesEnabled: true,
                        transparentBackground: true,
                      ),
                      onWebViewCreated: (c) {
                        _web = c;
                        c.addJavaScriptHandler(handlerName: 'wd', callback: _onWebMessage);
                      },
                      shouldOverrideUrlLoading: (c, action) async {
                        final uri = action.request.url;
                        if (uri == null) return NavigationActionPolicy.ALLOW;
                        final s = uri.scheme;
                        if (s == 'about' || s == 'data' || s == 'blob' || s == 'javascript') return NavigationActionPolicy.ALLOW;
                        if ((s == 'http' || s == 'https') && uri.host == _home.host) return NavigationActionPolicy.ALLOW;
                        _openOutside(uri);
                        return NavigationActionPolicy.CANCEL;
                      },
                      onCreateWindow: (c, action) async {
                        final uri = action.request.url;
                        if (uri != null) _openOutside(uri);
                        return false;
                      },
                      onProgressChanged: (c, p) {
                        if (mounted) setState(() => _progress = p / 100);
                      },
                      onLoadStart: (c, url) {
                        if (mounted && _failed) setState(() => _failed = false);
                      },
                      onReceivedError: (c, request, error) {
                        if (request.isForMainFrame ?? false) {
                          if (mounted) setState(() => _failed = true);
                        }
                      },
                    ),
                    if (_failed)
                      Container(
                        color: const Color(AppConfig.backgroundColor),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(color: const Color(AppConfig.brandColor), borderRadius: BorderRadius.circular(20)),
                              alignment: Alignment.center,
                              child: const Text('₹', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w800)),
                            ),
                            const SizedBox(height: 18),
                            const Text("You're offline", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            const Text('Check your internet connection and try again.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
                            const SizedBox(height: 18),
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14)),
                              onPressed: () {
                                setState(() => _failed = false);
                                _web?.reload();
                              },
                              child: const Text('Try again'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (showBanner)
                SizedBox(
                  width: _bannerSize!.width.toDouble(),
                  height: _bannerSize!.height.toDouble(),
                  child: AdWidget(ad: _banner!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
