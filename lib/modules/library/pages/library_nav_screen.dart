import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:u_player/main.dart';
import 'package:u_player/modules/library/pages/library_screen.dart';
import 'package:u_player/modules/library/pages/playlists_screen.dart';
import 'package:u_player/modules/library/pages/stats_screen.dart';
import 'package:u_player/modules/settings/pages/settings_screen.dart';

final ValueNotifier<int> currentTabNotifier = ValueNotifier<int>(0);
final ValueNotifier<bool> isNavScreenVisible = ValueNotifier<bool>(false);

class LibraryNavScreen extends StatefulWidget {
  const LibraryNavScreen({super.key});

  @override
  State<LibraryNavScreen> createState() => _LibraryNavScreenState();
}

class _LibraryNavScreenState extends State<LibraryNavScreen> {
  final List<Widget> _screens = const [
    LibraryScreen(),
    PlaylistsScreen(),
    StatsScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    isNavScreenVisible.value = true;
  }

  @override
  Widget build(BuildContext context) {
    if (!isNavScreenVisible.value) {
      isNavScreenVisible.value = true;
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: ValueListenableBuilder<int>(
        valueListenable: currentTabNotifier,
        builder: (context, index, _) {
          return IndexedStack(
            index: index,
            children: _screens,
          );
        },
      ),
    );
  }
}

class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({super.key});

  static const _icons = [
    Icons.library_music_rounded,
    Icons.queue_music_rounded,
    Icons.bar_chart_rounded,
    Icons.settings_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isNavScreenVisible,
      builder: (context, navVisible, _) {
        final visible = navVisible;

        return IgnorePointer(
          ignoring: !visible,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedSlide(
              offset: visible ? Offset.zero : const Offset(0, 1.5),
              duration: const Duration(milliseconds: 350),
              curve: Curves.fastOutSlowIn,
              child: AnimatedOpacity(
                opacity: visible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOut,
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).padding.bottom + 12,
                    left: 24,
                    right: 24,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                      child: Container(
                        height: 56,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E).withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                            width: 0.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ValueListenableBuilder<int>(
                          valueListenable: currentTabNotifier,
                          builder: (context, currentIndex, _) {
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: List.generate(_icons.length, (i) {
                                final isSelected = currentIndex == i;
                                return GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    rootNavigatorKey.currentState?.popUntil((route) => route.isFirst);
                                    currentTabNotifier.value = i;
                                  },
                                  child: SizedBox(
                                    width: 56,
                                    height: 56,
                                    child: Center(
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? Colors.white.withValues(alpha: 0.15)
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        child: Icon(
                                          _icons[i],
                                          size: 26,
                                          color: isSelected ? Colors.white : Colors.white38,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
