import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/note_store.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets/note_card.dart';

/// Obsidian mobildeki gibi açık sekmelerin kart görünümü.
class TabsScreen extends StatelessWidget {
  const TabsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NoteStore>();
    final tabs = store.openTabs.reversed.toList();
    final active = store.activeTabId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sekmeler'),
        actions: [
          if (tabs.isNotEmpty)
            TextButton(
              onPressed: store.closeAllTabs,
              child: const Text('Tümünü kapat'),
            ),
        ],
      ),
      body: tabs.isEmpty
          ? const Center(
              child: Text('Açık sekme yok', style: TextStyle(color: AppColors.muted)),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.7,
              ),
              itemCount: tabs.length,
              itemBuilder: (context, i) {
                final n = tabs[i];
                final isActive = n.id == active;
                return Column(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.of(context).pop();
                          openNote(context, n);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isActive ? AppColors.accent : AppColors.border,
                              width: isActive ? 2.5 : 1,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 34),
                                child: NotePreview(note: n),
                              ),
                              Positioned(
                                top: 2,
                                left: 4,
                                child: n.pinned
                                    ? const Padding(
                                        padding: EdgeInsets.all(8),
                                        child: Icon(Icons.push_pin,
                                            size: 18, color: AppColors.accentSoft),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                              Positioned(
                                top: 0,
                                right: 0,
                                child: IconButton(
                                  tooltip: 'Sekmeyi kapat',
                                  onPressed: () => store.closeTab(n.id),
                                  icon: const Icon(Icons.close_rounded, size: 20),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      n.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Yeni not',
                onPressed: () => showNewNoteSheet(context),
                icon: const Icon(Icons.add_rounded, size: 30),
              ),
              Expanded(
                child: Center(
                  child: Text('${tabs.length} sekme',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Tamam',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
