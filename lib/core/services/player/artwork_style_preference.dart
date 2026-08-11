import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the player screen shows the current track's artwork.
enum PlayerArtworkStyle {
  normal('Normal artwork'),
  pictureDisc('Picture Disc'),
  silver('Classic Silver CD'),
  jewelCase('Jewel Case'),
  minimal('Minimal Dark CD');

  const PlayerArtworkStyle(this.label);

  final String label;
}

/// Global artwork style for PlayerScreen, chosen from the customization
/// screen. `normal` keeps the rectangular album art; the rest render the
/// spinning-disc variants.
final ValueNotifier<PlayerArtworkStyle> playerArtworkStyle =
    ValueNotifier<PlayerArtworkStyle>(PlayerArtworkStyle.normal);

const String _kPlayerArtworkStyle = 'player_artwork_style';
const String _kLegacyUseCdMode = 'use_cd_player_mode';

Future<void> loadArtworkStylePreference() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_kPlayerArtworkStyle);
  if (raw != null) {
    playerArtworkStyle.value = PlayerArtworkStyle.values.firstWhere(
      (style) => style.name == raw,
      orElse: () => PlayerArtworkStyle.normal,
    );
    return;
  }
  // Migrate the legacy boolean: if CD mode was on, default to the picture
  // disc (the old design).
  if (prefs.getBool(_kLegacyUseCdMode) ?? false) {
    playerArtworkStyle.value = PlayerArtworkStyle.pictureDisc;
  }
}

Future<void> setPlayerArtworkStyle(PlayerArtworkStyle style) async {
  playerArtworkStyle.value = style;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kPlayerArtworkStyle, style.name);
}
