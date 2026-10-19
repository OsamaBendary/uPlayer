/// Discord Rich Presence configuration.
///
/// The application is registered on the Discord Developer Portal as "uPlayer";
/// its portal name and icon are what other users see on the activity card,
/// so they are not set here.
library;

/// Discord application ID used for Rich Presence.
///
/// Can be overridden at build time without touching this file:
///   flutter build linux --dart-define=DISCORD_CLIENT_ID=123456789
const String kDiscordApplicationId = String.fromEnvironment(
  'DISCORD_CLIENT_ID',
  defaultValue: '1561842160926720130',
);

/// Optional Discord asset key (uploaded under Rich Presence → Art Assets)
/// shown as the large image when no public cover URL could be resolved.
///
/// Left empty by default: the app icon already appears automatically next to
/// the activity name, and a missing/unknown asset would render as a broken
/// image. Set this to e.g. 'uplayer' after uploading one if a fallback cover
/// is desired.
const String kDiscordFallbackArtworkKey = '';

/// Hard limits enforced by Discord for activity text fields.
const int kDiscordMaxDetailsLength = 128;
const int kDiscordMaxStateLength = 128;

/// Soft cap for the state line. Discord doesn't wrap rich presence text, and
/// the small profile card starts ellipsizing around this width, so longer
/// values are progressively shortened (album first) to keep the card clean.
const int kDiscordSoftStateLength = 80;
