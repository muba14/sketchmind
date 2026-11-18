import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import '../data/note_store.dart';
import '../models/note.dart';
import '../theme.dart';

final _auth = LocalAuthentication();

/// Cihaz parmak izi / yüz tanıma destekliyor mu?
Future<bool> biometricsAvailable() async {
  try {
    return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
  } catch (_) {
    return false;
  }
}

Future<bool> _tryBiometrics() async {
  if (!await biometricsAvailable()) return false;
  try {
    return await _auth.authenticate(
      localizedReason: 'Kilitli notları açmak için doğrula',
      options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
    );
  } catch (_) {
    return false;
  }
}

/// Kilitli notlar için oturumu açar (önce parmak izi, olmazsa PIN).
/// Uygulama bir dakikadan uzun arka planda kalınca oturum yeniden kilitlenir.
Future<bool> ensureUnlocked(BuildContext context) async {
  final store = context.read<NoteStore>();
  if (store.sessionUnlocked) return true;
  if (!store.hasPin) return setupPin(context);
  if (store.useBiometrics && await _tryBiometrics()) {
    store.unlockSession();
    return true;
  }
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
        context: context,
        builder: (_) => const _PinDialog(create: false),
      ) ??
      false;
  if (ok) store.unlockSession();
  return ok;
}

/// Yeni PIN belirler (iki kez girilir).
Future<bool> setupPin(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => const _PinDialog(create: true),
  );
  return ok ?? false;
}

/// Notu kilitler ya da kilidini kaldırır.
Future<void> toggleLock(BuildContext context, Note note) async {
  final store = context.read<NoteStore>();
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (!note.locked) {
    final ready = store.hasPin ? await ensureUnlocked(context) : await setupPin(context);
    if (!ready) return;
    note.locked = true;
    store.update(note, touch: false);
    messenger?.showSnackBar(const SnackBar(content: Text('Not kilitlendi 🔒')));
  } else {
    if (!await ensureUnlocked(context)) return;
    note.locked = false;
    store.update(note, touch: false);
    messenger?.showSnackBar(const SnackBar(content: Text('Kilit kaldırıldı')));
  }
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.create});
  final bool create;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _ctrl = TextEditingController();
  String? _first;
  String? _error;
  int _attempts = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final store = context.read<NoteStore>();
    final pin = _ctrl.text;
    if (pin.length < 4) {
      setState(() => _error = 'PIN en az 4 haneli olmalı');
      return;
    }
    if (!widget.create) {
      if (store.checkPin(pin)) {
        Navigator.pop(context, true);
      } else {
        HapticFeedback.heavyImpact();
        _attempts++;
        _ctrl.clear();
        setState(() => _error = 'Yanlış PIN ($_attempts)');
      }
      return;
    }
    if (_first == null) {
      setState(() {
        _first = pin;
        _error = null;
      });
      _ctrl.clear();
    } else if (_first == pin) {
      store.setPin(pin);
      Navigator.pop(context, true);
    } else {
      _ctrl.clear();
      setState(() {
        _first = null;
        _error = 'PIN\'ler eşleşmedi, baştan dene';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = !widget.create
        ? 'PIN gir'
        : _first == null
            ? 'Yeni PIN belirle'
            : 'PIN\'i tekrar gir';
    return AlertDialog(
      backgroundColor: AppColors.surface,
      icon: const Icon(Icons.lock_outline_rounded, color: AppColors.accentSoft),
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.create && _first == null)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Kilitli notları açmak için kullanılacak. Unutursan kilitli notlara '
                'erişemezsin.',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ),
          TextField(
            controller: _ctrl,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 8,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, letterSpacing: 10),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(counterText: '', errorText: _error),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: _submit, child: Text(widget.create ? 'Devam' : 'Aç')),
      ],
    );
  }
}

/// Kilitli bir not açıkken (ya da oturum yeniden kilitlenince) gösterilir.
class LockedView extends StatelessWidget {
  const LockedView({super.key, required this.note});
  final Note note;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_rounded, size: 44, color: AppColors.accentSoft),
            ),
            const SizedBox(height: 16),
            Text(note.displayTitle,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('Bu not kilitli', style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => ensureUnlocked(context),
              icon: const Icon(Icons.fingerprint),
              label: const Text('Kilidi aç'),
            ),
          ],
        ),
      ),
    );
  }
}
