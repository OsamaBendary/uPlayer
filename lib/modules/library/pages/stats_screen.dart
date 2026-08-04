import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:u_player/core/models/library_group.dart';
import 'package:u_player/core/services/player/playback_controller.dart';
import 'package:u_player/core/services/play_count/play_count_service.dart';
import 'package:u_player/modules/library/widgets/app_gradient_background.dart';
import 'package:u_player/modules/library/widgets/label_chip.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  Map<String, int> _playCounts = {};
  List<SongModel> _songs = [];
  int _viewMode = 0; // 0: Songs, 1: Artists, 2: Albums
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
    PlaybackController.instance.addListener(_loadStats);
  }

  @override
  void dispose() {
    PlaybackController.instance.removeListener(_loadStats);
    super.dispose();
  }

  Future<void> _loadStats() async {
    final counts = await PlayCountService().getAllPlayCounts();
    setState(() {
      _playCounts = counts;
      _songs = PlaybackController.instance.songs;
      _isLoading = false;
    });
  }

  int _getSongPlayCount(SongModel song) {
    return _playCounts[song.id.toString()] ?? 0;
  }

  Color _getRankColor(int index) {
    if (index == 0) return const Color(0xFFFFD700);
    if (index == 1) return const Color(0xFFC0C0C0);
    if (index == 2) return const Color(0xFFCD7F32);
    return Colors.white70;
  }

  Widget _buildToggle() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _buildToggleItem(0, 'Songs'),
          _buildToggleItem(1, 'Artists'),
          _buildToggleItem(2, 'Albums'),
        ],
      ),
    );
  }

  Widget _buildToggleItem(int mode, String text) {
    final isSelected = _viewMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _viewMode = mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white.withValues(alpha: 0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            text,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white60,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSongsList() {
    final playedSongs = _songs.where((s) => _getSongPlayCount(s) > 0).toList();
    playedSongs.sort((a, b) => _getSongPlayCount(b).compareTo(_getSongPlayCount(a)));

    if (playedSongs.isEmpty) return _buildEmptyState();

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 160),
      itemCount: playedSongs.length,
      itemBuilder: (context, index) {
        final song = playedSongs[index];
        final count = _getSongPlayCount(song);
        final minutes = (count * (song.duration ?? 0)) ~/ 60000;
        return _buildStatRow(
          index: index,
          title: song.title,
          subtitle: song.artist ?? 'Unknown Artist',
          count: count,
          minutes: minutes,
          artworkId: song.id,
          artworkType: ArtworkType.AUDIO,
        );
      },
    );
  }

  Widget _buildArtistsList() {
    final artistGroups = groupSongsByArtist(_songs);
    final stats = <_GroupStat>[];
    for (final group in artistGroups) {
      int count = 0;
      int duration = 0;
      for (final song in group.songs) {
        final sc = _getSongPlayCount(song);
        count += sc;
        duration += sc * (song.duration ?? 0);
      }
      if (count > 0) {
        stats.add(_GroupStat(
          name: group.name,
          count: count,
          duration: duration,
          representativeId: group.songs.first.id,
        ));
      }
    }
    stats.sort((a, b) => b.count.compareTo(a.count));

    if (stats.isEmpty) return _buildEmptyState();

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 160),
      itemCount: stats.length,
      itemBuilder: (context, index) {
        final stat = stats[index];
        final minutes = stat.duration ~/ 60000;
        return _buildStatRow(
          index: index,
          title: stat.name,
          subtitle: '$minutes min total',
          count: stat.count,
          minutes: minutes,
          artworkId: stat.representativeId,
          artworkType: ArtworkType.AUDIO,
        );
      },
    );
  }

  Widget _buildAlbumsList() {
    final albumGroups = groupSongsByAlbum(_songs);
    final stats = <_GroupStat>[];
    for (final group in albumGroups) {
      int count = 0;
      int duration = 0;
      for (final song in group.songs) {
        final sc = _getSongPlayCount(song);
        count += sc;
        duration += sc * (song.duration ?? 0);
      }
      if (count > 0) {
        stats.add(_GroupStat(
          name: group.name,
          count: count,
          duration: duration,
          representativeId: group.songs.first.id,
        ));
      }
    }
    stats.sort((a, b) => b.count.compareTo(a.count));

    if (stats.isEmpty) return _buildEmptyState();

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 160),
      itemCount: stats.length,
      itemBuilder: (context, index) {
        final stat = stats[index];
        final minutes = stat.duration ~/ 60000;
        return _buildStatRow(
          index: index,
          title: stat.name,
          subtitle: '$minutes min total',
          count: stat.count,
          minutes: minutes,
          artworkId: stat.representativeId,
          artworkType: ArtworkType.AUDIO,
        );
      },
    );
  }

  Widget _buildStatRow({
    required int index,
    required String title,
    required String subtitle,
    required int count,
    required int minutes,
    required int artworkId,
    required ArtworkType artworkType,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '#${index + 1}',
              style: TextStyle(
                color: _getRankColor(index),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 48,
              height: 48,
              child: QueryArtworkWidget(
                id: artworkId,
                type: artworkType,
                nullArtworkWidget: Container(
                  color: Colors.white12,
                  child: const Icon(Icons.music_note, color: Colors.white38),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$count plays',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              Text(
                '~$minutes min',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.insert_chart_outlined, size: 48, color: Colors.white24),
          SizedBox(height: 16),
          Text(
            'No play counts yet',
            style: TextStyle(color: Colors.white54, fontSize: 16),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppGradientBackground(
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 24, bottom: 8),
              child: LabelChip(
                'Stats',
                style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
              ),
            ),
            _buildToggle(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                  : (_viewMode == 0
                      ? _buildSongsList()
                      : _viewMode == 1
                          ? _buildArtistsList()
                          : _buildAlbumsList()),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupStat {
  final String name;
  final int count;
  final int duration;
  final int representativeId;

  _GroupStat({
    required this.name,
    required this.count,
    required this.duration,
    required this.representativeId,
  });
}
