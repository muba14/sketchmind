import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/note_store.dart';
import '../models/note.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets/note_card.dart';
import 'graph_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'trash_screen.dart';
import 'tabs_screen.dart';

enum FilterKind { all, favorites, folder, tag }

class NoteFilter {
  const NoteFilter._(this.kind, [this.value = '']);
  const NoteFilter.all() : this._(FilterKind.all);
  const NoteFilter.favorites() : this._(FilterKind.favorites);
  const NoteFilter.folder(String f) : this._(FilterKind.folder, f);
  const NoteFilter.tag(String t) : this._(FilterKind.tag, t);

  final FilterKind kind;
  final String value;

  String get title => switch (kind) {
        FilterKind.all => 'Son Notlar',
        FilterKind.favorites => 'Favoriler',
        FilterKind.folder => value,
        FilterKind.tag => '#$value',
      };

  bool matches(Note n) => switch (kind) {
        FilterKind.all => true,
        FilterKind.favorites => n.favorite,
        FilterKind.folder => n.folder == value,
        FilterKind.tag => n.tags.contains(value),
      };

  @override
  bool operator ==(Object other) =>
      other is NoteFilter && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);
}

/// Alt gezinme çubuklu ana ekran: Notlar · Grafik · Ara
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: switch (_index) {
        0 => const NotesPage(),
        1 => const GraphPage(),
        _ => const SearchPage(),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        height: 64,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Notlar',
          ),
          NavigationDestination(
            icon: Icon(Icons.hub_outlined),
            selectedIcon: Icon(Icons.hub_rounded),
            label: 'Grafik',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_rounded),
            label: 'Ara',
          ),
        ],
      ),
    );
  }
}

enum TypeFilter { all, text, sketch }

class NotesPage extends StatefulWidget {
  const NotesPage({super.key, this.initialFilter = const NoteFilter.all(), this.standalone = false});

  final NoteFilter initialFilter;

  /// Tek başına açılmış (ör. etiket sayfası) ise çekmece yerine geri tuşu.
  final bool standalone;

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  late NoteFilter _filter = widget.initialFilter;
  TypeFilter _type = TypeFilter.all;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NoteStore>();
    final notes = store.sorted(store.notes.where((n) {
      if (!_filter.matches(n)) return false;
      return switch (_type) {
        TypeFilter.all => true,
        TypeFilter.text => n.type == NoteType.text,
        TypeFilter.sketch => n.type == NoteType.sketch,
      };
    }));

    return Scaffold(
      drawer: widget.standalone
          ? null
          : AppDrawer(
              selected: _filter,
              onSelect: (f) => setState(() => _filter = f),
            ),
      appBar: AppBar(
        title: Text(_filter.title),
        actions: [
          TabsButton(count: store.openTabs.length),
          PopupMenuButton<SortMode>(
            tooltip: 'Sırala',
            icon: const Icon(Icons.sort_rounded),
            color: AppColors.surface,
            onSelected: store.setSort,
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: SortMode.updated,
                checked: store.sortMode == SortMode.updated,
                child: const Text('Son düzenlenen'),
              ),
              CheckedPopupMenuItem(
                value: SortMode.created,
                checked: store.sortMode == SortMode.created,
                child: const Text('Oluşturulma tarihi'),
              ),
              CheckedPopupMenuItem(
                value: SortMode.title,
                checked: store.sortMode == SortMode.title,
                child: const Text('Başlık (A-Z)'),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showNewNoteSheet(
          context,
          folder: _filter.kind == FilterKind.folder ? _filter.value : '',
        ),
        child: const Icon(Icons.add_rounded, size: 30),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _typeChip('Tümü', TypeFilter.all, Icons.apps_rounded),
                _typeChip('Metin', TypeFilter.text, Icons.notes_rounded),
                _typeChip('El yazısı', TypeFilter.sketch, Icons.draw_rounded),
              ],
            ),
          ),
          Expanded(
            child: notes.isEmpty
                ? _empty()
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 230,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.68,
                    ),
                    itemCount: notes.length,
                    itemBuilder: (context, i) {
                      final n = notes[i];
                      return NoteCard(
                        key: ValueKey(n.id),
                        note: n,
                        onTap: () => openNote(context, n),
                        onLongPress: () => showNoteActions(context, n),
                        onToggleFavorite: () {
                          n.favorite = !n.favorite;
                          store.update(n, touch: false);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _typeChip(String label, TypeFilter t, IconData icon) {
    final sel = _type == t;
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
      child: ChoiceChip(
        selected: sel,
        showCheckmark: false,
        avatar: Icon(icon, size: 16, color: sel ? Colors.white : AppColors.muted),
        label: Text(label),
        labelStyle: TextStyle(color: sel ? Colors.white : AppColors.text, fontSize: 13),
        selectedColor: AppColors.accent,
        backgroundColor: AppColors.card,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        onSelected: (_) => setState(() => _type = t),
      ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_stories_outlined,
                  size: 64, color: AppColors.accent.withValues(alpha: 0.6)),
              const SizedBox(height: 12),
              const Text('Burada henüz not yok',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              const Text(
                'Sağ alttaki + ile metin ya da el yazısı notu oluştur.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
            ],
          ),
        ),
      );
}

/// Etiket/klasör sayfası (ör. bir #etikete dokununca).
class FilteredNotesScreen extends StatelessWidget {
  const FilteredNotesScreen({super.key, required this.filter});
  final NoteFilter filter;

  @override
  Widget build(BuildContext context) =>
      NotesPage(initialFilter: filter, standalone: true);
}

/// Obsidian mobildeki sekme sayacı düğmesi.
class TabsButton extends StatelessWidget {
  const TabsButton({super.key, required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Açık sekmeler',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const TabsScreen()),
      ),
      icon: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.text, width: 2),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          count > 99 ? '∞' : '$count',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, required this.selected, required this.onSelect});

  final NoteFilter selected;
  final ValueChanged<NoteFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NoteStore>();
    final folders = store.folders;
    final tags = store.tagCounts;

    Widget item(NoteFilter f, IconData icon, String label, {int? count, Widget? trailing}) {
      final sel = f == selected;
      return ListTile(
        dense: true,
        selected: sel,
        selectedTileColor: AppColors.accent.withValues(alpha: 0.18),
        selectedColor: AppColors.accentSoft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: Icon(icon, size: 20),
        title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: trailing ??
            (count == null
                ? null
                : Text('$count', style: const TextStyle(color: AppColors.muted))),
        onTap: () {
          Navigator.pop(context);
          onSelect(f);
        },
      );
    }

    Widget header(String text, {Widget? action}) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(text.toUpperCase(),
                    style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700)),
              ),
              if (action != null) action,
            ],
          ),
        );

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset('assets/icon/icon.png', width: 40, height: 40),
                  ),
                  const SizedBox(width: 12),
                  const Text('Sketchmind',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            item(const NoteFilter.all(), Icons.grid_view_rounded, 'Tüm notlar',
                count: store.notes.length),
            item(const NoteFilter.favorites(), Icons.star_rounded, 'Favoriler',
                count: store.notes.where((n) => n.favorite).length),
            header(
              'Klasörler',
              action: IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Yeni klasör',
                icon: const Icon(Icons.create_new_folder_outlined, size: 20),
                onPressed: () async {
                  final name =
                      await promptText(context, title: 'Yeni klasör', hint: 'Klasör adı');
                  if (name != null && name.isNotEmpty) store.addFolder(name);
                },
              ),
            ),
            if (folders.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text('Klasör yok', style: TextStyle(color: AppColors.muted)),
              ),
            for (final f in folders)
              GestureDetector(
                onLongPress: () async {
                  final ok = await confirm(context,
                      title: 'Klasör silinsin mi?',
                      message: '"$f" klasörü silinecek. İçindeki notlar silinmez, '
                          'klasörsüz kalır.');
                  if (ok) store.deleteFolder(f);
                },
                child: item(NoteFilter.folder(f), Icons.folder_outlined, f,
                    count: store.notes.where((n) => n.folder == f).length),
              ),
            header('Etiketler'),
            if (tags.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text('Notlarına #etiket yazınca burada görünür',
                    style: TextStyle(color: AppColors.muted, fontSize: 13)),
              ),
            for (final e in tags.entries)
              item(NoteFilter.tag(e.key), Icons.tag_rounded, e.key, count: e.value),
            const Divider(height: 28, indent: 12, endIndent: 12),
            ListTile(
              dense: true,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              leading: const Icon(Icons.delete_outline, size: 20),
              title: const Text('Çöp kutusu'),
              trailing: Text('${store.trash.length}',
                  style: const TextStyle(color: AppColors.muted)),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const TrashScreen()));
              },
            ),
            ListTile(
              dense: true,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              leading: const Icon(Icons.settings_outlined, size: 20),
              title: const Text('Ayarlar ve yedekleme'),
              onTap: () {
                Navigator.pop(context);
                openSettings(context);
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
