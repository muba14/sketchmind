import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/export.dart';
import '../data/media_cache.dart';
import '../data/note_store.dart';
import '../security/lock.dart';
import '../theme.dart';
import 'trash_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;
  bool _bioAvailable = false;

  @override
  void initState() {
    super.initState();
    biometricsAvailable().then((v) {
      if (mounted) setState(() => _bioAvailable = v);
    });
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      _snack('Olmadı: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Kilitli not varsa dışa aktarmadan önce doğrulama iste.
  Future<bool> _guard(NoteStore store) async {
    if (!store.notes.any((n) => n.locked)) return true;
    return ensureUnlocked(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NoteStore>();
    final media = context.read<MediaCache>();

    Widget header(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
          child: Text(t.toUpperCase(),
              style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: Stack(
        children: [
          ListView(
            children: [
              header('Kilit'),
              ListTile(
                leading: const Icon(Icons.pin_outlined),
                title: Text(store.hasPin ? 'PIN\'i değiştir' : 'PIN belirle'),
                subtitle: const Text('Kilitli notları açmak için',
                    style: TextStyle(color: AppColors.muted, fontSize: 12)),
                onTap: () async {
                  if (store.hasPin && !await ensureUnlocked(context)) return;
                  if (!context.mounted) return;
                  if (await setupPin(context)) _snack('PIN kaydedildi');
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.fingerprint),
                title: const Text('Parmak izi / yüz tanıma'),
                subtitle: Text(
                  _bioAvailable ? 'PIN yerine kullanılır' : 'Bu cihazda kullanılamıyor',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                value: store.useBiometrics && _bioAvailable,
                onChanged: _bioAvailable ? store.setBiometrics : null,
              ),
              if (store.hasPin)
                ListTile(
                  leading: const Icon(Icons.lock_open_outlined),
                  title: const Text('PIN\'i kaldır'),
                  onTap: () async {
                    if (!await ensureUnlocked(context)) return;
                    if (store.removePin()) {
                      _snack('PIN kaldırıldı');
                    } else {
                      _snack('Önce tüm notların kilidini kaldır');
                    }
                  },
                ),
              header('Yedekleme'),
              ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: const Text('Yedek oluştur'),
                subtitle: const Text('Tüm notlar ve görseller tek .sketchmind dosyasında',
                    style: TextStyle(color: AppColors.muted, fontSize: 12)),
                onTap: () => _run(() async {
                  if (!await _guard(store)) return;
                  await shareBackup(store);
                }),
              ),
              ListTile(
                leading: const Icon(Icons.settings_backup_restore_rounded),
                title: const Text('Yedeği geri yükle'),
                subtitle: const Text('Var olan notlar korunur, yedektekiler eklenir',
                    style: TextStyle(color: AppColors.muted, fontSize: 12)),
                onTap: () => _run(() async {
                  final res = await FilePicker.platform.pickFiles(type: FileType.any);
                  final path = res?.files.single.path;
                  if (path == null) return;
                  final count = await restoreBackup(store, path);
                  _snack('$count not geri yüklendi');
                }),
              ),
              ListTile(
                leading: const Icon(Icons.folder_zip_outlined),
                title: const Text('Markdown olarak dışa aktar'),
                subtitle: const Text('Obsidian\'da açılabilen .zip (çizimler .png olur)',
                    style: TextStyle(color: AppColors.muted, fontSize: 12)),
                onTap: () => _run(() async {
                  if (!await _guard(store)) return;
                  await shareMarkdownZip(store, media);
                }),
              ),
              header('Veriler'),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Çöp kutusu'),
                trailing: Text('${store.trash.length}',
                    style: const TextStyle(color: AppColors.muted)),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const TrashScreen())),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Sketchmind'),
                subtitle: Text('${store.notes.length} not · sürüm 1.1.0',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: Text(
                  'Not: Kilit, notların uygulama içinde açılmasını engeller; dosyalar '
                  'cihazda şifrelenmeden saklanır.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
            ],
          ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x88000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ayarlar ekranına geçiş (çekmeceden).
void openSettings(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));

