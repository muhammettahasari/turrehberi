import 'dart:convert';
import 'dart:io';

import 'net.dart';

/// Derleme numarası; GitHub derlemesinde --dart-define=BUILD=<n> ile verilir.
const int kBuild = int.fromEnvironment('BUILD', defaultValue: 0);

const String _releasesApi =
    'https://api.github.com/repos/muhammettahasari/turrehberi/releases?per_page=10';

class UpdateInfo {
  UpdateInfo(this.build, this.url, this.size);

  final int build;
  final String url;
  final int size;
}

/// GitHub "Releases" sayfasındaki deneme sürümlerini denetler ve indirir.
class Updater {
  static Future<UpdateInfo?> check() async {
    if (kBuild == 0) return null; // elle derlenmiş sürüm
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse(_releasesApi));
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('User-Agent', 'TurSes');
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      final list = jsonDecode(body);
      if (list is! List) return null;

      final want64 = await Net.is64Bit();
      UpdateInfo? best;
      for (final r in list) {
        if (r is! Map || r['draft'] == true) continue;
        final m = RegExp(r'^deneme-(\d+)$').firstMatch((r['tag_name'] ?? '').toString());
        if (m == null) continue;
        final n = int.parse(m.group(1)!);
        if (n <= kBuild || (best != null && n <= best.build)) continue;
        final assetName = want64 ? 'TurSes-$n.apk' : 'TurSes-$n-eski-telefonlar.apk';
        for (final a in (r['assets'] as List? ?? const [])) {
          if (a is Map && a['name'] == assetName) {
            best = UpdateInfo(n, a['browser_download_url'].toString(),
                (a['size'] as num?)?.toInt() ?? 0);
          }
        }
      }
      return best;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<File> download(UpdateInfo u, void Function(double) onProgress) async {
    final dir = Directory(await Net.updateDir());
    for (final old in dir.listSync()) {
      try {
        old.deleteSync();
      } catch (_) {}
    }
    final file = File('${dir.path}/TurSes-${u.build}.apk');
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(u.url));
      req.headers.set('User-Agent', 'TurSes');
      final res = await req.close();
      if (res.statusCode != 200) throw Exception('İndirme hatası (${res.statusCode})');
      final total = res.contentLength > 0 ? res.contentLength : u.size;
      final sink = file.openWrite();
      var got = 0;
      await for (final chunk in res) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress(got / total);
      }
      await sink.close();
      return file;
    } finally {
      client.close(force: true);
    }
  }
}
