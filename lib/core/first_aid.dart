// Baby first aid and "spot the signs" (MA-50). Text follows WHO/IMCI and infant basic
// life support; clinical sign-off pending (resources/CLINICAL_RULES.md). The sign guide
// only explains signs that the daily-check rules already rate, so advice and rules agree.
import 'content.dart';
import 'tx.dart';

/// An animation made of picture layers in assets/learn/ (see AnimatedLesson).
enum LessonAnim { backBlows, chestPushes, pressTest }

class AidStep {
  final Tx title, text;
  final LessonAnim? anim;

  /// The animation counts each beat up to this number (5 back blows).
  final int count;
  const AidStep(this.title, this.text, {this.anim, this.count = 0});
}

class AidTopic {
  final String id;
  final Tx title, when;
  final String icon;
  final List<AidStep> steps;
  final Tx? goNow;
  const AidTopic(this.id, this.icon, this.title, this.when, this.steps, {this.goNow});
}

const firstAidTopics = <AidTopic>[
  AidTopic(
    'choking',
    'choke',
    Tx('Baby is choking', 'Mtoto amekabwa na kitu'),
    Tx(
      'Use this only if your baby cannot cry, cough or breathe. If baby is coughing hard, let them cough and stay with them.',
      'Tumia hii tu kama mtoto hawezi kulia, kukohoa wala kupumua. Kama anakohoa kwa nguvu, mwache akohoe na ukae naye.',
    ),
    [
      AidStep(
        Tx('5 back blows', 'Mapigo 5 mgongoni'),
        Tx(
          'Sit down. Lay baby face-down along your forearm, resting on your thigh, head lower than the chest. Hold the jaw; do not cover the mouth or squeeze the throat. With the heel of your other hand, give up to 5 firm blows between the shoulder blades.',
          'Keti. Mlaze mtoto kifudifudi juu ya mkono wako ulioegemea paja, kichwa chini kuliko kifua. Shika taya; usifunike mdomo wala kubana koo. Kwa sehemu ya chini ya kiganja cha mkono mwingine, mpige kwa nguvu hadi mara 5 katikati ya mabega.',
        ),
        anim: LessonAnim.backBlows,
        count: 5,
      ),
      AidStep(
        Tx('5 chest pushes', 'Misukumo 5 kifuani'),
        Tx(
          'Turn baby face-up along your other arm, head still lower. Put 2 fingers in the centre of the chest, just below the nipple line. Push down firmly up to 5 times, about 4 cm deep.',
          'Mgeuze mtoto alale chali juu ya mkono wako mwingine, kichwa bado chini. Weka vidole 2 katikati ya kifua, chini kidogo ya mstari wa chuchu. Sukuma chini kwa nguvu hadi mara 5, kina cha takriban sentimita 4.',
        ),
        anim: LessonAnim.chestPushes,
        count: 5,
      ),
      AidStep(
        Tx('Look, then repeat', 'Angalia, kisha rudia'),
        Tx(
          'Look in the mouth. Take the object out only if you can see it and reach it easily; never sweep blindly with a finger. Repeat steps 1 and 2 until it comes out.',
          'Angalia mdomoni. Toa kitu tu kama unakiona na unaweza kukifikia kwa urahisi; usipapase kwa kidole bila kuona. Rudia hatua 1 na 2 hadi kitoke.',
        ),
      ),
    ],
    goNow: Tx(
      'If baby stops responding, call 112 and start baby CPR. Even if the object comes out, take baby to a health facility to be checked.',
      'Mtoto akiacha kuitikia, piga 112 na anza CPR ya mtoto. Hata kitu kikitoka, mpeleke mtoto kituo cha afya akaguliwe.',
    ),
  ),
  AidTopic(
    'cpr',
    'heart',
    Tx('Baby is not breathing (CPR)', 'Mtoto hapumui (CPR)'),
    Tx(
      'Baby does not respond and is not breathing normally. Shout for help; someone calls 112.',
      'Mtoto haitikii na hapumui kawaida. Piga kelele kuomba msaada; mtu apige 112.',
    ),
    [
      AidStep(
        Tx('Check', 'Kagua'),
        Tx(
          'Tap the sole of the foot and call baby\'s name. Look for normal breathing for no more than 10 seconds.',
          'Gusa unyayo na mwite mtoto jina lake. Angalia kama anapumua kawaida kwa sekunde zisizozidi 10.',
        ),
      ),
      AidStep(
        Tx('Open the airway', 'Fungua njia ya hewa'),
        Tx(
          'Lay baby on the back on a firm, flat surface. Keep the head level and lift the chin with one finger. Do not tip the head far back.',
          'Mlaze mtoto chali mahali pagumu na tambarare. Weka kichwa sawa na inua kidevu kwa kidole kimoja. Usikirudishe kichwa nyuma sana.',
        ),
      ),
      AidStep(
        Tx('5 gentle breaths', 'Pumzi 5 za upole'),
        Tx(
          'Cover baby\'s mouth and nose with your mouth. Puff gently until the chest rises, 5 times.',
          'Funika mdomo na pua ya mtoto kwa mdomo wako. Puliza kwa upole hadi kifua kiinuke, mara 5.',
        ),
      ),
      AidStep(
        Tx('30 chest pushes, 2 breaths', 'Misukumo 30 kifuani, pumzi 2'),
        Tx(
          'Two fingers on the lower half of the breastbone. Push about 4 cm deep, fast: 100 to 120 a minute. After 30 pushes give 2 breaths. Keep going until help comes or baby breathes.',
          'Vidole viwili kwenye nusu ya chini ya mfupa wa kifua. Sukuma kina cha sentimita 4, haraka: mara 100 hadi 120 kwa dakika. Baada ya misukumo 30 toa pumzi 2. Endelea hadi msaada ufike au mtoto apumue.',
        ),
      ),
    ],
  ),
  AidTopic(
    'fits',
    'bolt',
    Tx('Baby has a fit (convulsion)', 'Mtoto ana degedege'),
    Tx('Any fit in a baby is a danger sign.', 'Degedege lolote kwa mtoto ni dalili ya hatari.'),
    [
      AidStep(
        Tx('Keep baby safe', 'Mlinde mtoto'),
        Tx(
          'Lay baby on the side on a safe, flat place. Move hard things away.',
          'Mlaze mtoto kwa ubavu mahali salama na tambarare. Ondoa vitu vigumu karibu naye.',
        ),
      ),
      AidStep(
        Tx('Do not', 'Usifanye'),
        Tx(
          'Do not put a spoon, fingers or anything in the mouth. Do not hold the arms or legs down. Do not pour water on the face.',
          'Usiweke kijiko, vidole wala kitu chochote mdomoni. Usimshikilie mikono wala miguu. Usimmwagie maji usoni.',
        ),
      ),
      AidStep(
        Tx('Time it, then go', 'Pima muda, kisha nenda'),
        Tx(
          'Note how long the fit lasts. Afterwards keep baby on the side and go to a health facility now.',
          'Angalia degedege linachukua muda gani. Baada yake mweke mtoto kwa ubavu na nenda kituo cha afya sasa.',
        ),
      ),
    ],
    goNow: Tx('Go to a health facility now.', 'Nenda kituo cha afya sasa.'),
  ),
  AidTopic(
    'fever',
    'thermo',
    Tx('Baby feels hot (fever)', 'Mtoto ana homa'),
    Tx('37.5 °C or more under the arm is a fever.', 'Nyuzi 37.5 au zaidi kwapani ni homa.'),
    [
      AidStep(
        Tx('Under 2 months: go now', 'Chini ya miezi 2: nenda sasa'),
        Tx(
          'A fever in a baby under 2 months old is a danger sign. Go to a health facility now.',
          'Homa kwa mtoto chini ya miezi 2 ni dalili ya hatari. Nenda kituo cha afya sasa.',
        ),
      ),
      AidStep(
        Tx('Keep baby cool and fed', 'Mpoze na umnyonyeshe'),
        Tx('Dress baby in one light layer. Breastfeed more often.', 'Mvalishe mtoto nguo moja nyepesi. Mnyonyeshe mara nyingi zaidi.'),
      ),
      AidStep(
        Tx('Do not', 'Usifanye'),
        Tx(
          'No cold baths, alcohol rubs or heavy wrapping. Give medicines only as a health worker advises.',
          'Usimwogeshe kwa maji ya baridi, usimpake pombe wala kumfunika sana. Mpe dawa tu kama mhudumu wa afya alivyoshauri.',
        ),
      ),
      AidStep(
        Tx('From 2 months', 'Kuanzia miezi 2'),
        Tx(
          'See a health worker within 24 hours. Go now if baby also has any danger sign.',
          'Muone mhudumu wa afya ndani ya saa 24. Nenda sasa kama mtoto ana dalili yoyote ya hatari pia.',
        ),
      ),
    ],
  ),
  AidTopic(
    'diarrhoea',
    'drop',
    Tx('Diarrhoea', 'Kuharisha'),
    Tx('Loose, watery stools more often than usual.', 'Kinyesi laini cha maji mara nyingi kuliko kawaida.'),
    [
      AidStep(Tx('Keep breastfeeding', 'Endelea kunyonyesha'), Tx('Breastfeed more often than usual.', 'Nyonyesha mara nyingi kuliko kawaida.')),
      AidStep(
        Tx('Give ORS', 'Mpe ORS'),
        Tx(
          'Mix one sachet with exactly the clean water the packet says. Give small sips from a cup or spoon after each loose stool. Make it fresh every day.',
          'Changanya pakiti moja na maji safi kiasi kilichoandikwa kwenye pakiti. Mpe kidogo kidogo kwa kikombe au kijiko baada ya kila choo laini. Tengeneza mpya kila siku.',
        ),
      ),
      AidStep(
        Tx('Zinc', 'Zinki'),
        Tx('Give zinc as the health worker prescribes, for 10 to 14 days.', 'Mpe zinki kama mhudumu wa afya alivyoandika, kwa siku 10 hadi 14.'),
      ),
    ],
    goNow: Tx(
      'Go now if baby has sunken eyes, a skin pinch that goes back slowly, blood in the stool, is very sleepy or cannot drink.',
      'Nenda sasa kama mtoto ana macho yaliyoingia ndani, ngozi inayorudi polepole ukiibana, damu kwenye kinyesi, amelegea au hawezi kunywa.',
    ),
  ),
  AidTopic(
    'burns',
    'fire',
    Tx('Burns', 'Kuungua'),
    Tx('From hot water, tea, porridge or fire.', 'Kutokana na maji ya moto, chai, uji au moto.'),
    [
      AidStep(
        Tx('Cool it', 'Poza'),
        Tx('Hold the burn under cool running water for 20 minutes.', 'Weka sehemu iliyoungua chini ya maji ya baridi yanayotiririka kwa dakika 20.'),
      ),
      AidStep(
        Tx('Uncover and cover', 'Vua na funika'),
        Tx(
          'Take off clothes near the burn unless they are stuck. Cover with a clean, dry cloth.',
          'Vua nguo karibu na jeraha isipokuwa zimeganda. Funika kwa kitambaa safi na kikavu.',
        ),
      ),
      AidStep(
        Tx('Do not', 'Usifanye'),
        Tx('Do not put butter, oil, toothpaste, egg or ice on a burn.', 'Usipake siagi, mafuta, dawa ya meno, yai wala barafu kwenye jeraha la moto.'),
      ),
    ],
    goNow: Tx(
      'Go now if the burn is on the face, hands, feet or private parts, is bigger than baby\'s palm, or has blisters.',
      'Nenda sasa kama jeraha liko usoni, mikononi, miguuni au sehemu za siri, ni kubwa kuliko kiganja cha mtoto, au lina malengelenge.',
    ),
  ),
  AidTopic(
    'falls',
    'fall',
    Tx('Falls and head knocks', 'Kuanguka na kugonga kichwa'),
    Tx('Baby fell from a bed, a chair or arms.', 'Mtoto ameanguka kutoka kitandani, kitini au mikononi.'),
    [
      AidStep(
        Tx('Calm and watch', 'Mtulize na umwangalie'),
        Tx(
          'Pick baby up gently and comfort them. Watch closely for the next 24 hours.',
          'Mbebe mtoto kwa upole na umtulize. Mwangalie kwa makini kwa saa 24 zijazo.',
        ),
      ),
      AidStep(
        Tx('Prevent', 'Zuia'),
        Tx(
          'Never leave baby alone on a bed or table. Let baby play on a mat on the floor.',
          'Usimwache mtoto peke yake kitandani au mezani. Mwache acheze kwenye mkeka sakafuni.',
        ),
      ),
    ],
    goNow: Tx(
      'Go now if baby was knocked out even briefly, vomits, has a fit, is very sleepy, has a soft swelling on the head, or will not feed.',
      'Nenda sasa kama mtoto alipoteza fahamu hata kwa muda mfupi, anatapika, ana degedege, amelegea, ana uvimbe laini kichwani, au hanyonyi.',
    ),
  ),
];

/// How to look for each daily-check sign (same keys and levels as rules.dart).
class SignGuide {
  final String key;
  final Tx how;
  final LessonAnim? anim;
  const SignGuide(this.key, this.how, {this.anim});
  Sign get sign => babySigns.firstWhere((s) => s.key == key);
}

/// Content-kit pictures and animations for each first-aid step (topic id → per step).
const aidStepAssets = <String, List<List<String>>>{
  'choking': [
    [],
    [],
    ['FA-CHOKE-P3'],
  ],
  'cpr': [
    ['FA-CPR-A1'],
    ['FA-CPR-A2'],
    ['FA-CPR-A3'],
    ['FA-CPR-A4'],
  ],
  'fits': [
    ['FA-FITS-A1'],
    ['FA-FITS-P2'],
    ['FA-FITS-P3'],
  ],
  'fever': [
    ['FA-FEVER-A1'],
    ['FA-FEVER-P2'],
    ['FA-FEVER-P3'],
    [],
  ],
  'diarrhoea': [
    [],
    ['FA-DIAR-A1', 'FA-DIAR-A2'],
    ['FA-DIAR-P3'],
  ],
  'burns': [
    ['FA-BURN-A1'],
    ['FA-BURN-P2'],
    ['FA-BURN-P3'],
  ],
  'falls': [
    ['FA-FALL-P1'],
    ['FA-FALL-P3'],
  ],
};

/// Picture at the top of each topic, and next to its "go now" box.
const aidTopAsset = {'choking': 'FA-CHOKE-P0'};
const aidGoNowAsset = {'choking': 'FA-CHOKE-P4', 'diarrhoea': 'FA-DIAR-A4', 'burns': 'FA-BURN-P4', 'falls': 'FA-FALL-P2'};

/// Built-in animations are replaced by the delivered content-kit animation with the same job.
const animAsset = {LessonAnim.backBlows: 'FA-CHOKE-A1', LessonAnim.chestPushes: 'FA-CHOKE-A2', LessonAnim.pressTest: 'SS-YELLOW-A1'};

/// Content-kit pictures for each sign guide.
const signGuideAssets = <String, List<String>>{
  'b_yellow': ['SS-YELLOW-P3'],
  'b_yellow_severe': ['SS-YELLOW-P2', 'SS-YELLOW-P4'],
  'b_breath': ['SS-BREATH-A1'],
  'b_chest': ['SS-CHEST-A1'],
  'b_diarr': ['SS-DEHYD-A1', 'SS-DEHYD-P2', 'SS-STOOL-P1'],
  'b_cold': ['SS-COLD-P1'],
  'b_sleepy': ['SS-LIMP-P1'],
  'b_belly': ['SS-BELLY-P1', 'SS-BELLY-P2'],
  'b_fever': ['SS-FEVER-P1'],
  'b_cord': ['SS-CORD-P1'],
  'b_wet': ['SS-WET-P1'],
  'b_g_cold': ['SS-GCOLD-P1'],
  'b_g_spit': ['SS-GSPIT-P1'],
  'b_g_rash': ['SS-GRASH-P1'],
  'b_g_fussy': ['SS-GFUSSY-P1'],
  'b_g_stool': ['SS-GSTOOL-P1'],
};

const signGuides = <SignGuide>[
  SignGuide(
    'b_sleepy',
    Tx(
      'Baby is floppy, sleeps much more than usual, or does not wake when you touch the feet or call. This is a danger sign.',
      'Mtoto amelegea, analala zaidi ya kawaida, au haamki ukigusa miguu au ukimwita. Hii ni dalili ya hatari.',
    ),
  ),
  SignGuide(
    'b_yellow',
    Tx(
      'On dark skin, yellow is easy to miss. In daylight, press the forehead or nose with one finger for 2 seconds, then lift it. If the skin looks yellow, that is a sign. Also look at the whites of the eyes and the gums.',
      'Kwenye ngozi nyeusi, njano ni rahisi kutoiona. Kwenye mwanga wa mchana, bonyeza paji la uso au pua kwa kidole kimoja kwa sekunde 2, kisha inua. Ngozi ikionekana ya njano, hiyo ni dalili. Angalia pia weupe wa macho na fizi.',
    ),
    anim: LessonAnim.pressTest,
  ),
  SignGuide(
    'b_yellow_severe',
    Tx(
      'Look at the palms of the hands and the soles of the feet in daylight. Any yellow there, or any yellow on the first day of life, means go now.',
      'Angalia viganja na nyayo kwenye mwanga wa mchana. Njano yoyote hapo, au njano yoyote siku ya kwanza ya maisha, maana yake nenda sasa.',
    ),
  ),
  SignGuide(
    'b_breath',
    Tx(
      'When baby is calm, count the breaths for one full minute. 60 or more under 2 months, or 50 or more from 2 to 12 months, is fast.',
      'Mtoto akiwa ametulia, hesabu pumzi kwa dakika nzima. 60 au zaidi chini ya miezi 2, au 50 au zaidi kuanzia miezi 2 hadi 12, ni haraka.',
    ),
  ),
  SignGuide(
    'b_chest',
    Tx(
      'Lift the clothes. If the lower chest sinks in when baby breathes in, that is chest pulling in.',
      'Inua nguo. Kama sehemu ya chini ya kifua inaingia ndani mtoto anapovuta pumzi, hicho ni kifua kuvutika.',
    ),
  ),
  SignGuide(
    'b_diarr',
    Tx(
      'Look for blood in the stool, and for eyes sunken deeper than usual. A pinch of belly skin that goes back slowly is also a danger sign.',
      'Angalia damu kwenye kinyesi, na macho yaliyoingia ndani kuliko kawaida. Ngozi ya tumbo inayorudi polepole ukiibana pia ni dalili ya hatari.',
    ),
  ),
  SignGuide(
    'b_cold',
    Tx(
      'Feel the belly and the feet with the back of your hand. Cold to touch is a danger sign.',
      'Gusa tumbo na miguu kwa nyuma ya kiganja chako. Mwili wa baridi ni dalili ya hatari.',
    ),
  ),
  SignGuide(
    'b_belly',
    Tx(
      'A belly that is swollen and hard, crying when it is touched, or vomit that is green: go now.',
      'Tumbo lililovimba na gumu, kulia likiguswa, au matapishi ya kijani: nenda sasa.',
    ),
  ),
  SignGuide(
    'b_fever',
    Tx(
      'Put a thermometer under the arm. 37.5 °C or more is a fever. Under 2 months, a fever means go now.',
      'Weka kipimajoto kwapani. Nyuzi 37.5 au zaidi ni homa. Chini ya miezi 2, homa maana yake nenda sasa.',
    ),
  ),
  SignGuide(
    'b_cord',
    Tx(
      'Look at the cord stump and the skin around it: redness, pus or a bad smell.',
      'Angalia kitovu na ngozi inayokizunguka: wekundu, usaha au harufu mbaya.',
    ),
  ),
  SignGuide(
    'b_wet',
    Tx(
      'After the first week, most babies wet 6 or more nappies a day. Fewer than usual can mean baby needs more milk.',
      'Baada ya wiki ya kwanza, watoto wengi hulowesha nepi 6 au zaidi kwa siku. Chache kuliko kawaida inaweza kumaanisha mtoto anahitaji maziwa zaidi.',
    ),
  ),
  SignGuide(
    'b_g_cold',
    Tx(
      'Keep breastfeeding and keep the nose clear. Watch for fast breathing or the chest pulling in.',
      'Endelea kunyonyesha na weka pua safi. Angalia kupumua haraka au kifua kuvutika.',
    ),
  ),
  SignGuide(
    'b_g_spit',
    Tx(
      'Hold baby upright after feeds. Watch for green vomit or vomiting everything.',
      'Mbebe mtoto wima baada ya kunyonya. Angalia matapishi ya kijani au kutapika kila kitu.',
    ),
  ),
  SignGuide(
    'b_g_rash',
    Tx(
      'Change nappies often, wash with plain water and let the skin dry in the air.',
      'Badilisha nepi mara kwa mara, osha kwa maji safi na acha ngozi ikauke hewani.',
    ),
  ),
  SignGuide(
    'b_g_fussy',
    Tx(
      'Feed, hold baby skin-to-skin and check for fever. Crying that will not stop needs a health worker.',
      'Mnyonyeshe, mbebe ngozi kwa ngozi na angalia homa. Kilio kisichokoma kinahitaji mhudumu wa afya.',
    ),
  ),
  SignGuide(
    'b_g_stool',
    Tx(
      'Breastfed babies can go a few days without a stool. Watch for a swollen, hard belly.',
      'Watoto wanaonyonya wanaweza kukaa siku chache bila choo. Angalia tumbo lililovimba na gumu.',
    ),
  ),
];
