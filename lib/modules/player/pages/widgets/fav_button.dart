import 'package:flutter/material.dart';
import 'package:u_player/core/services/favorites_service/favorites_service.dart';

class FavoriteButton extends StatefulWidget {
  final int songId;
  final String songTitle; // Optional: used for showing feedback Toasts/SnackBars

  const FavoriteButton({
    super.key,
    required this.songId,
    required this.songTitle,
  });

  @override
  State<FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<FavoriteButton> {
  final FavoritesService _favoritesService = FavoritesService();
  bool _isFav = false;

  @override
  void initState() {
    super.initState();
    _checkFavStatus();
  }

  // Essential: Re-check favorite status when user skips to the next track
  @override
  void didUpdateWidget(covariant FavoriteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId != widget.songId) {
      _checkFavStatus();
    }
  }

  Future<void> _checkFavStatus() async {
    final isFav = await _favoritesService.isFavorite(widget.songId);
    if (mounted) {
      setState(() {
        _isFav = isFav;
      });
    }
  }

  void _onToggleFavorite() async {
    // 1. Optimistic UI Update (change color instantly before waiting for disk write)
    setState(() {
      _isFav = !_isFav;
    });

    // 2. Persist to SharedPreferences
    final isStillFav = await _favoritesService.toggleFavorite(widget.songId);

    // 3. Ensure UI state matches persisted result
    if (mounted && _isFav != isStillFav) {
      setState(() {
        _isFav = isStillFav;
      });
    }

    // 4. Quick visual feedback for the user
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFav
                ? 'Added "${widget.songTitle}" to Favorites'
                : 'Removed "${widget.songTitle}" from Favorites',
          ),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF2A2A2A),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      iconSize: 28,
      splashRadius: 24,
      color: _isFav ? Colors.redAccent : Colors.white70,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
        child: Icon(
          _isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          key: ValueKey<bool>(_isFav),
        ),
      ),
      onPressed: _onToggleFavorite,
    );
  }
}