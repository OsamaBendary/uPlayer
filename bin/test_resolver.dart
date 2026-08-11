import 'dart:convert';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final query = 'King Crimson I Talk To The Wind';
  print('=== TESTING POPULAR INVIDIOUS / PIPED INSTANCES ===');

  final instances = [
    'https://yewtu.be',
    'https://vid.puffyan.us',
    'https://invidious.flokinet.to',
    'https://invidious.eclipso.at',
    'https://inv.riverside.rocks',
    'https://invidious.nerdvpn.de',
    'https://pipedapi.kavin.rocks',
    'https://pipedapi.drgns.space',
    'https://pipedapi.adminforge.de',
    'https://pipedapi.astral.cheap',
    'https://pipedapi.private.coffee',
    'https://pipedapi.rs200.ro',
  ];

  for (final inst in instances) {
    try {
      print('\nTesting $inst...');
      if (inst.contains('piped')) {
        final res = await http.get(Uri.parse('$inst/search?q=${Uri.encodeComponent(query)}&filter=all')).timeout(const Duration(seconds: 4));
        print('Piped $inst status: ${res.statusCode}');
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final items = data['items'] as List?;
          if (items != null && items.isNotEmpty) {
            final urlStr = items.first['url']?.toString() ?? '';
            final vId = urlStr.replaceAll('/watch?v=', '');
            print('Piped $inst found vId: $vId');
            final sRes = await http.get(Uri.parse('$inst/streams/$vId')).timeout(const Duration(seconds: 4));
            print('Piped $inst streams status: ${sRes.statusCode}');
            if (sRes.statusCode == 200) {
              final sData = jsonDecode(sRes.body);
              final audio = sData['audioStreams'] as List?;
              if (audio != null && audio.isNotEmpty) {
                print('=== SUCCESS PIPED STREAM URL! ===');
                print('URL: ${audio.first['url']}');
                return;
              }
            }
          }
        }
      } else {
        final res = await http.get(Uri.parse('$inst/api/v1/search?q=${Uri.encodeComponent(query)}')).timeout(const Duration(seconds: 4));
        print('Invidious $inst status: ${res.statusCode}');
        if (res.statusCode == 200) {
          final items = jsonDecode(res.body) as List?;
          if (items != null && items.isNotEmpty) {
            final vId = items.first['videoId'];
            print('Invidious $inst found vId: $vId');
            final vRes = await http.get(Uri.parse('$inst/api/v1/videos/$vId')).timeout(const Duration(seconds: 4));
            print('Invidious $inst video status: ${vRes.statusCode}');
            if (vRes.statusCode == 200) {
              final vData = jsonDecode(vRes.body);
              final adaptive = vData['adaptiveFormats'] as List?;
              if (adaptive != null) {
                final audio = adaptive.where((f) => (f['type'] as String? ?? '').startsWith('audio/')).toList();
                if (audio.isNotEmpty) {
                  print('=== SUCCESS INVIDIOUS STREAM URL! ===');
                  print('URL: ${audio.first['url']}');
                  return;
                }
              }
            }
          }
        }
      }
    } catch (e) {
      print('$inst failed: $e');
    }
  }
}
