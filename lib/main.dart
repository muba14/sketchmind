import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'data/media_cache.dart';
import 'data/note_store.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.surface,
  ));
  final store = NoteStore();
  await store.load();
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider<NoteStore>.value(value: store),
      ChangeNotifierProvider<MediaCache>(create: (_) => MediaCache(store)),
    ],
    child: const SketchmindApp(),
  ));
}

class SketchmindApp extends StatefulWidget {
  const SketchmindApp({super.key});

  @override
  State<SketchmindApp> createState() => _SketchmindAppState();
}

class _SketchmindAppState extends State<SketchmindApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  DateTime? _pausedAt;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final store = context.read<NoteStore>();
    // Uygulama arka plana geçerken bekleyen kaydı hemen yaz.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      store.flush();
    }
    if (state == AppLifecycleState.paused) _pausedAt ??= DateTime.now();
    if (state == AppLifecycleState.resumed) {
      // 1 dakikadan uzun arka planda kaldıysa kilitli notlar yeniden kilitlenir.
      // (Fotoğraf seçerken kısa süre çıkmak kilitlemesin.)
      final p = _pausedAt;
      _pausedAt = null;
      if (p != null && DateTime.now().difference(p) > const Duration(minutes: 1)) {
        store.lockSession();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sketchmind',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const HomeScreen(),
    );
  }
}
