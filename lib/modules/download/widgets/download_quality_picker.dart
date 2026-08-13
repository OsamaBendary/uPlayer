import 'package:flutter/material.dart';
import 'package:u_player/core/services/extension/extension_service.dart';

/// Centered dialog that lets the user pick the quality for one download:
/// every quality option the installed providers advertise (Dolby Atmos,
/// HiRes FLAC, Lossless, ...) plus the app's standard qualities. Rendered as
/// a centered dialog instead of a bottom sheet so the mini player / floating
/// nav bar overlays never cover it. Returns null when dismissed, or a
/// [DownloadQualityChoice] when picked.
Future<DownloadQualityChoice?> showDownloadQualityPicker(
  BuildContext context, {
  DownloadQualityChoice? initial,
}) async {
  final extensionService = ExtensionService();
  final current = initial ?? DownloadQualityChoice.app(extensionService.selectedQuality);
  final maxLabel = extensionService.highestAvailableQualityLabel();

  // Provider quality options (id + label + description + owning provider).
  final providerOptions = <({String id, String label, String description, String provider})>[];
  final seenIds = <String>{};
  for (final ext in extensionService.installedExtensions) {
    if (!ext.isEnabled || !ext.hasDownloadProvider) continue;
    final rawOptions = ext.raw['quality_options'];
    if (rawOptions is! List) continue;
    for (final option in rawOptions) {
      if (option is! Map) continue;
      final id = option['id']?.toString().trim() ?? '';
      if (id.isEmpty || seenIds.contains(id.toLowerCase())) continue;
      seenIds.add(id.toLowerCase());
      final label = option['label']?.toString().trim() ?? id;
      final description = option['description']?.toString().trim() ?? ext.name;
      providerOptions.add((id: id, label: label, description: description, provider: ext.name));
    }
  }

  List<Widget> optionTiles(List<DownloadQualityChoice> choices) => [
        for (final choice in choices)
          ListTile(
            title: Text(
              choice.label ?? '',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            subtitle: choice.description != null && choice.description!.isNotEmpty
                ? Text(
                    choice.description!,
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  )
                : null,
            trailing: Icon(
              current.matches(choice)
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: current.matches(choice)
                  ? const Color(0xFFFFD700)
                  : Colors.white38,
              size: 20,
            ),
            onTap: () => Navigator.pop(context, choice),
          ),
      ];

  return showDialog<DownloadQualityChoice>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: const Color(0xFF222222),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: MediaQuery.of(dialogContext).size.height * 0.7,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Download quality',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Highest available from your providers: $maxLabel',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (providerOptions.isNotEmpty) ...[
                  const _SectionHeader('From your providers'),
                  ...optionTiles([
                    for (final option in providerOptions)
                      DownloadQualityChoice(
                        providerQualityId: option.id,
                        label: option.label,
                        description: option.description,
                      ),
                  ]),
                ],
                const _SectionHeader('Standard'),
                ...optionTiles([for (final q in DownloadQuality.values) DownloadQualityChoice.app(q)]),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: Colors.white38,
          fontWeight: FontWeight.bold,
          fontSize: 11,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}