// Content kit (MA-51): pictures, animations, icons and videos made from
// resources/content-kit/ and imported with `node tools/import_content.mjs <folder>`.
// The importer writes assets/content/manifest.json; the app shows a delivered file
// when its ID is in the manifest and falls back to the built-in drawing when not,
// so the app works before, during and after content delivery.
import 'dart:convert';

import 'package:flutter/services.dart';

import 'tx.dart';

class ContentAsset {
  final String id, type, path;

  /// Videos only: where to stream or download it from, and caption files.
  final String? url, captionsSw, captionsEn;
  const ContentAsset(this.id, this.type, this.path, {this.url, this.captionsSw, this.captionsEn});
}

class ContentAssets {
  static final Map<String, ContentAsset> _m = {};
  static bool _loaded = false;

  static Future<void> load({AssetBundle? bundle}) async {
    if (_loaded) return;
    try {
      final raw = await (bundle ?? rootBundle).loadString('assets/content/manifest.json');
      final j = jsonDecode(raw) as Map<String, dynamic>;
      for (final e in (j['assets'] as Map<String, dynamic>? ?? const {}).entries) {
        final v = e.value as Map<String, dynamic>;
        _m[e.key] = ContentAsset(
          e.key,
          v['type'] as String,
          v['file'] == null ? '' : 'assets/content/${v['file']}',
          url: v['url'] as String?,
          captionsSw: v['captions_sw'] as String?,
          captionsEn: v['captions_en'] as String?,
        );
      }
    } catch (_) {
      // no manifest yet: every screen uses its built-in drawing
    }
    _loaded = true;
  }

  /// Tests and previews.
  static void debugSet(Map<String, ContentAsset> m) {
    _m
      ..clear()
      ..addAll(m);
    _loaded = true;
  }

  static ContentAsset? get(String id) => _m[id];
  static bool has(String id) => _m.containsKey(id);
  static List<ContentAsset> ofType(String type) => _m.values.where((a) => a.type == type).toList()..sort((a, b) => a.id.compareTo(b.id));
  static int get count => _m.length;
}

/// Daily-check icon for each sign key (content-kit IDs IC-…).
const signIconAsset = <String, String>{
  'bleeding': 'IC-PR-01',
  'headache': 'IC-PR-02',
  'vision': 'IC-PR-03',
  'fits': 'IC-PR-04',
  'bellypain': 'IC-PR-05',
  'swelling': 'IC-PR-06',
  'breathing': 'IC-PR-07',
  'fever': 'IC-PR-08',
  'water': 'IC-PR-09',
  'urine': 'IC-PR-10',
  'vomit': 'IC-PR-11',
  'pp_bleed': 'IC-PP-01',
  'pp_fits': 'IC-PP-02',
  'pp_head': 'IC-PP-03',
  'pp_breath': 'IC-PP-04',
  'pp_leg': 'IC-PP-05',
  'pp_fever': 'IC-PP-06',
  'pp_belly': 'IC-PP-07',
  'pp_discharge': 'IC-PP-08',
  'pp_breast': 'IC-PP-09',
  'pp_mood': 'IC-PP-10',
  'pp_harm': 'IC-PP-11',
  'b_feed': 'IC-B-01',
  'b_fits': 'IC-B-02',
  'b_breath': 'IC-B-03',
  'b_chest': 'IC-B-04',
  'b_sleepy': 'IC-B-05',
  'b_vomit': 'IC-B-06',
  'b_diarr': 'IC-B-07',
  'b_cold': 'IC-B-08',
  'b_fever': 'IC-B-09',
  'b_yellow': 'IC-B-10',
  'b_cord': 'IC-B-11',
  'b_wet': 'IC-B-12',
  'b_yellow_severe': 'IC-B-13',
  'b_belly': 'IC-B-14',
  'b_g_cold': 'IC-G-1',
  'b_g_spit': 'IC-G-2',
  'b_g_rash': 'IC-G-3',
  'b_g_fussy': 'IC-G-4',
  'b_g_stool': 'IC-G-5',
};

/// The ten videos in the content kit.
const videoTitles = <String, Tx>{
  'V-01': Tx('Breastfeeding in the first hour', 'Kunyonyesha saa ya kwanza'),
  'V-02': Tx('Good attachment and positions', 'Kunyonya vizuri na mikao'),
  'V-03': Tx('Expressing milk and cup feeding', 'Kukamua maziwa na kulisha kwa kikombe'),
  'V-04': Tx('Kangaroo mother care', 'Malezi ya kangaruu'),
  'V-05': Tx('Danger signs in a newborn', 'Dalili za hatari kwa mtoto mchanga'),
  'V-06': Tx('Baby choking: first aid', 'Mtoto amekabwa: huduma ya kwanza'),
  'V-07': Tx('Baby CPR', 'CPR ya mtoto'),
  'V-08': Tx('Making and giving ORS', 'Kutengeneza na kutoa ORS'),
  'V-09': Tx('Starting foods at 6 months', 'Kuanza chakula miezi 6'),
  'V-10': Tx('Blood pressure in pregnancy', 'Shinikizo la damu wakati wa ujauzito'),
};
