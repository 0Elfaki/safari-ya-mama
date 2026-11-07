// Mother and baby content (English + Kiswahili), ported from the Safari ya Mama
// content pack. Sign keys are the same strings the database uses (rule_signs).
import 'package:flutter/material.dart';

import 'tx.dart';

enum Level { green, amber, red }

extension LevelX on Level {
  String get db => name;
  static Level parse(String? s) => s == 'red'
      ? Level.red
      : (s == 'amber' || s == 'yellow')
      ? Level.amber
      : Level.green;
  Level max(Level o) => index >= o.index ? this : o;
}

/// A warning sign the mother can tap. `level` is the single-sign level;
/// `ageDependent` marks baby fever (red under 60 days, IMCI).
class Sign {
  final String key;
  final IconData icon;
  final Level level;
  final bool ageDependent;
  final Tx label;
  const Sign(this.key, this.icon, this.level, this.label, {this.ageDependent = false});
}

/// WHO danger signs in pregnancy.
const pregnancySigns = <Sign>[
  Sign('bleeding', Icons.water_drop, Level.red, Tx('Bleeding from the vagina', 'Kutokwa na damu ukeni')),
  Sign('headache', Icons.psychology_alt, Level.amber, Tx('Severe headache', 'Maumivu makali ya kichwa')),
  Sign('vision', Icons.visibility_off, Level.amber, Tx('Blurred vision', 'Kuona ukungu')),
  Sign('fits', Icons.bolt, Level.red, Tx('Fits (convulsions)', 'Degedege')),
  Sign('bellypain', Icons.pregnant_woman, Level.red, Tx('Severe belly pain', 'Maumivu makali ya tumbo')),
  Sign('swelling', Icons.back_hand, Level.amber, Tx('Swollen face or hands', 'Uso au mikono kuvimba')),
  Sign('breathing', Icons.air, Level.red, Tx('Hard to breathe', 'Kupumua kwa shida')),
  Sign('fever', Icons.thermostat, Level.amber, Tx('Fever / very hot', 'Homa kali')),
  Sign('water', Icons.waves, Level.red, Tx('Water leaking', 'Maji kutoka ukeni')),
  Sign('urine', Icons.wc, Level.amber, Tx('Pain when urinating', 'Maumivu wakati wa kukojoa')),
  Sign('vomit', Icons.sick, Level.amber, Tx('Vomiting a lot', 'Kutapika sana')),
];

/// Mother after birth: WHO PCPNC.
const postnatalSigns = <Sign>[
  Sign('pp_bleed', Icons.water_drop, Level.red, Tx('Heavy bleeding (a pad soaked in under an hour)', 'Kutokwa damu nyingi (pedi inalowa chini ya saa moja)')),
  Sign('pp_fits', Icons.bolt, Level.red, Tx('Fits (convulsions)', 'Degedege')),
  Sign('pp_head', Icons.psychology_alt, Level.red, Tx('Severe headache or blurred vision', 'Kichwa kuuma sana au kuona ukungu')),
  Sign('pp_breath', Icons.air, Level.red, Tx('Hard to breathe or chest pain', 'Kupumua kwa shida au maumivu ya kifua')),
  Sign('pp_leg', Icons.directions_walk, Level.red, Tx('Painful, swollen leg', 'Mguu kuvimba na kuuma')),
  Sign('pp_fever', Icons.thermostat, Level.amber, Tx('Fever', 'Homa')),
  Sign('pp_belly', Icons.pregnant_woman, Level.amber, Tx('Belly pain', 'Maumivu ya tumbo')),
  Sign('pp_discharge', Icons.opacity, Level.amber, Tx('Smelly discharge from the vagina', 'Uchafu wenye harufu mbaya ukeni')),
  Sign('pp_breast', Icons.favorite, Level.amber, Tx('Painful, red or hot breast', 'Titi kuuma, jekundu au la moto')),
  Sign('pp_mood', Icons.nightlight, Level.amber, Tx('Very sad or hopeless most days', 'Huzuni kubwa au kukata tamaa siku nyingi')),
  Sign('pp_harm', Icons.warning_amber, Level.red, Tx('Thoughts of harming myself or my baby', 'Mawazo ya kujidhuru au kumdhuru mtoto')),
];

/// Baby: WHO IMCI young infant / child.
const babySigns = <Sign>[
  Sign('b_feed', Icons.baby_changing_station, Level.red, Tx('Not able to breastfeed or drink', 'Hawezi kunyonya wala kunywa')),
  Sign('b_fits', Icons.bolt, Level.red, Tx('Fits (convulsions)', 'Degedege')),
  Sign('b_breath', Icons.air, Level.red, Tx('Fast or difficult breathing', 'Anapumua haraka au kwa shida')),
  Sign('b_chest', Icons.monitor_heart, Level.red, Tx('Chest pulls in when breathing', 'Kifua kinavutika ndani anapovuta pumzi')),
  Sign('b_sleepy', Icons.bedtime, Level.red, Tx('Very sleepy, hard to wake', 'Amelegea, ni vigumu kumwamsha')),
  Sign('b_vomit', Icons.sick, Level.red, Tx('Vomits everything', 'Anatapika kila kitu')),
  Sign('b_diarr', Icons.water_drop, Level.red, Tx('Diarrhoea with blood, or sunken eyes', 'Kuharisha damu, au macho yameingia ndani')),
  Sign('b_cold', Icons.ac_unit, Level.red, Tx('Feels cold to touch', 'Mwili wa baridi')),
  Sign('b_fever', Icons.thermostat, Level.amber, Tx('Feels hot (fever)', 'Ana homa'), ageDependent: true),
  Sign('b_yellow', Icons.wb_sunny, Level.amber, Tx('Yellow skin or eyes', 'Ngozi au macho ya njano')),
  Sign('b_cord', Icons.child_care, Level.amber, Tx('Red or smelly cord, or pus', 'Kitovu chekundu, usaha au harufu')),
  Sign('b_wet', Icons.opacity, Level.amber, Tx('Fewer wet nappies than usual', 'Nepi chache zenye mkojo kuliko kawaida')),
  // rules 2026.12: IMCI severe jaundice and abdominal danger signs (clinical sign-off pending)
  Sign(
    'b_yellow_severe',
    Icons.light_mode,
    Level.red,
    Tx('Yellow palms or soles, or yellow on the first day of life', 'Viganja au nyayo za njano, au njano siku ya kwanza ya maisha'),
  ),
  Sign('b_belly', Icons.sick_outlined, Level.red, Tx('Swollen, hard belly or green vomit', 'Tumbo limevimba na gumu, au matapishi ya kijani')),
  // rules 2026.12: everyday signs. 4 or more together make the check amber (a Safari ya Mama
  // rule, not a WHO rule; clinical sign-off pending).
  Sign('b_g_cold', Icons.air, Level.green, Tx('Mild cough or runny nose', 'Kikohozi kidogo au mafua')),
  Sign('b_g_spit', Icons.water_drop_outlined, Level.green, Tx('Small spit-ups after feeds', 'Kucheua maziwa kidogo baada ya kunyonya')),
  Sign('b_g_rash', Icons.grain, Level.green, Tx('Nappy rash', 'Vipele vya nepi')),
  Sign('b_g_fussy', Icons.sentiment_dissatisfied_outlined, Level.green, Tx('Crying or fussy more than usual', 'Analia au anasumbua kuliko kawaida')),
  Sign('b_g_stool', Icons.hourglass_bottom, Level.green, Tx('Hard or fewer stools', 'Kinyesi kigumu au kichache')),
];

/// Everyday (green) baby signs on one check that make it amber (rules 2026.12).
const greenStepUp = 4;

Sign? signByKey(String k) {
  for (final s in [...pregnancySigns, ...postnatalSigns, ...babySigns]) {
    if (s.key == k) return s;
  }
  return null;
}

class PregMonth {
  final Tx baby, you;
  const PregMonth(this.baby, this.you);
}

const pregnancyMonths = <int, PregMonth>{
  1: PregMonth(
    Tx(
      'Baby is a tiny cluster of cells settling into the womb. The heart and spine start to form.',
      'Mtoto ni kundi dogo la seli linalojishikiza tumboni. Moyo na uti wa mgongo vinaanza kuumbika.',
    ),
    Tx(
      'Your period stops. You may feel tired or sick. Start folic acid and book your first antenatal visit.',
      'Hedhi inakoma. Unaweza kuchoka au kuhisi kichefuchefu. Anza vidonge vya foliki na panga kliniki ya kwanza.',
    ),
  ),
  2: PregMonth(
    Tx('The heart beats. Arms, legs and face begin to form.', 'Moyo unadunda. Mikono, miguu na uso vinaanza kuumbika.'),
    Tx('Nausea and tender breasts are common. Eat small meals often.', 'Kichefuchefu na matiti kuuma ni kawaida. Kula kidogo mara nyingi.'),
  ),
  3: PregMonth(
    Tx('All the organs have formed. Baby moves, but you cannot feel it yet.', 'Viungo vyote vimeumbika. Mtoto anasogea lakini bado huhisi.'),
    Tx(
      'Go to your first antenatal visit by 12 weeks. Nausea often eases soon.',
      'Hudhuria kliniki ya kwanza kabla ya wiki 12. Kichefuchefu hupungua hivi karibuni.',
    ),
  ),
  4: PregMonth(
    Tx('Baby can hear sounds. Hair and nails are growing.', 'Mtoto anasikia sauti. Nywele na kucha zinaota.'),
    Tx(
      'Energy often returns. Keep taking your iron and folic acid tablet. From 13 weeks, malaria prevention (SP) is given at the clinic.',
      'Nguvu mara nyingi hurudi. Endelea kumeza kidonge cha madini ya chuma na foliki. Kuanzia wiki 13, kinga ya malaria (SP) hutolewa kliniki.',
    ),
  ),
  5: PregMonth(
    Tx('You may feel the first movements, like small flutters.', 'Unaweza kuhisi mtoto akicheza kwa mara ya kwanza.'),
    Tx('Your belly shows. Start sleeping on your side.', 'Tumbo linaonekana. Anza kulala kwa ubavu.'),
  ),
  6: PregMonth(
    Tx("Baby's lungs are developing and baby reacts to your voice.", 'Mapafu ya mtoto yanakua na anaitikia sauti yako.'),
    Tx(
      "Back pain and heartburn are common. Get to know your baby's usual pattern of movements.",
      'Maumivu ya mgongo na kiungulia ni kawaida. Ifahamu mitikisiko ya kawaida ya mtoto wako.',
    ),
  ),
  7: PregMonth(
    Tx('Baby opens their eyes and puts on fat.', 'Mtoto anafumbua macho na kuongeza mafuta mwilini.'),
    Tx(
      "Notice baby's movements every day. Watch for headache, swelling or blurred vision.",
      'Fuatilia mateke ya mtoto kila siku. Angalia kichwa kuuma, kuvimba au kuona ukungu.',
    ),
  ),
  8: PregMonth(
    Tx('Baby grows fast and usually turns head-down.', 'Mtoto anakua haraka na kwa kawaida hugeuka kichwa chini.'),
    Tx('Finish your birth plan and learn the signs of labour.', 'Kamilisha mpango wa kujifungua na jifunze dalili za uchungu.'),
  ),
  9: PregMonth(
    Tx('Baby is getting ready to be born.', 'Mtoto anajiandaa kuzaliwa.'),
    Tx(
      'Keep your bag ready. Go to the facility when labour starts or your water breaks.',
      'Weka begi tayari. Nenda kituoni uchungu ukianza au chupa ikipasuka.',
    ),
  ),
};

/// Local fruit sizes by week of pregnancy.
const babySizes = <(int, Tx)>[
  (8, Tx('bean', 'haragwe')),
  (12, Tx('passion fruit', 'pasheni')),
  (16, Tx('avocado', 'parachichi')),
  (20, Tx('banana', 'ndizi')),
  (24, Tx('maize cob', 'gunzi la mahindi')),
  (28, Tx('pawpaw', 'papai')),
  (32, Tx('pineapple', 'nanasi')),
  (36, Tx('small jackfruit', 'fenesi dogo')),
  (40, Tx('small watermelon', 'tikiti maji dogo')),
];

/// The size stage a week belongs to (8, 12, 16 … 40): the picture ID is `SZ-<stage>`.
int sizeStageWeek(int w) {
  var s = babySizes.first.$1;
  for (final x in babySizes) {
    if (w >= x.$1) s = x.$1;
  }
  return s;
}

Tx sizeForWeek(int w) {
  var s = babySizes.first.$2;
  for (final x in babySizes) {
    if (w >= x.$1) s = x.$2;
  }
  return s;
}

/// WHO 2016 ANC model: 8 contacts (week, title, what happens).
class AncContact {
  final int week;
  final Tx title;
  final List<Tx> items;
  const AncContact(this.week, this.title, this.items);
}

const ancContacts = <AncContact>[
  AncContact(12, Tx('First contact', 'Ziara ya kwanza'), [
    Tx('Date of your last period, weight and height', 'Tarehe ya hedhi ya mwisho, uzito na urefu'),
    Tx('Blood pressure', 'Shinikizo la damu'),
    Tx('Blood tests: Hb, blood group, HIV, syphilis, hepatitis B', 'Vipimo vya damu: Hb, kundi la damu, VVU, kaswende, homa ya ini B'),
    Tx('Start daily iron and folic acid', 'Anza vidonge vya madini ya chuma na foliki kila siku'),
    Tx('Get your clinic card and a treated mosquito net', 'Pata kadi ya kliniki na chandarua chenye dawa'),
  ]),
  AncContact(20, Tx('Second contact', 'Ziara ya pili'), [
    Tx('Blood pressure and weight', 'Shinikizo la damu na uzito'),
    Tx('Belly measured for baby growth', 'Tumbo kupimwa kwa ukuaji wa mtoto'),
    Tx('Malaria prevention (SP), deworming, tetanus (Td) if due', 'Kinga ya malaria (SP), dawa ya minyoo, chanjo ya pepopunda (Td)'),
    Tx('Ultrasound before 24 weeks if not done', 'Ultrasound kabla ya wiki 24 kama bado'),
  ]),
  AncContact(26, Tx('Third contact', 'Ziara ya tatu'), [
    Tx('Blood pressure: it can rise without you feeling it', 'Shinikizo la damu: linaweza kupanda bila kuhisi'),
    Tx('Urine for protein (pre-eclampsia)', 'Mkojo kupimwa protini (kifafa cha mimba)'),
    Tx('Hb again, baby\'s heartbeat, second Td', 'Hb tena, mapigo ya moyo wa mtoto, Td ya pili'),
  ]),
  AncContact(30, Tx('Fourth contact', 'Ziara ya nne'), [
    Tx('Blood pressure, weight, belly measured', 'Shinikizo la damu, uzito, tumbo kupimwa'),
    Tx('Tell the health worker how your baby usually moves', 'Mwambie mhudumu jinsi mtoto wako anavyocheza kwa kawaida'),
    Tx('SP dose; start your birth plan', 'Dozi ya SP; anza mpango wa kujifungua'),
  ]),
  AncContact(34, Tx('Fifth contact', 'Ziara ya tano'), [
    Tx('Blood pressure and urine protein', 'Shinikizo la damu na protini kwenye mkojo'),
    Tx('Hb; keep taking iron and folic acid', 'Hb; endelea na madini ya chuma na foliki'),
    Tx('Check your birth plan: transport, money, companion, bag', 'Kagua mpango: usafiri, pesa, msindikizaji, begi'),
  ]),
  AncContact(36, Tx('Sixth contact', 'Ziara ya sita'), [
    Tx("Baby's position (most are head-down)", 'Mkao wa mtoto (wengi wako kichwa chini)'),
    Tx('Blood pressure and heartbeat', 'Shinikizo la damu na mapigo ya moyo'),
    Tx('Where will you go at night?', 'Utaenda wapi usiku?'),
  ]),
  AncContact(38, Tx('Seventh contact', 'Ziara ya saba'), [
    Tx('Baby could come any day: bag by the door', 'Mtoto anaweza kuzaliwa siku yoyote: begi mlangoni'),
    Tx('Blood pressure, position and heartbeat', 'Shinikizo la damu, mkao na mapigo ya moyo'),
  ]),
  AncContact(40, Tx('Eighth contact', 'Ziara ya nane'), [
    Tx('Due date: blood pressure, heartbeat, position', 'Tarehe ya kujifungua: shinikizo, mapigo ya moyo, mkao'),
    Tx('If not born by 41 weeks, go back to be checked', 'Usipojifungua kufikia wiki 41, rudi kuchunguzwa'),
  ]),
];

/// Tanzania routine immunisation: 16 doses (same keys as vaccine_doses.vaccine_key).
class VaccineDose {
  final String key;
  final int day;
  final String label;
  const VaccineDose(this.key, this.day, this.label);
}

const vaccineDoses = <VaccineDose>[
  VaccineDose('bcg', 0, 'BCG'),
  VaccineDose('opv0', 0, 'OPV 0'),
  VaccineDose('opv1', 42, 'OPV 1'),
  VaccineDose('penta1', 42, 'Penta 1'),
  VaccineDose('pcv1', 42, 'PCV 1'),
  VaccineDose('rota1', 42, 'Rota 1'),
  VaccineDose('opv2', 70, 'OPV 2'),
  VaccineDose('penta2', 70, 'Penta 2'),
  VaccineDose('pcv2', 70, 'PCV 2'),
  VaccineDose('rota2', 70, 'Rota 2'),
  VaccineDose('opv3', 98, 'OPV 3'),
  VaccineDose('penta3', 98, 'Penta 3'),
  VaccineDose('pcv3', 98, 'PCV 3'),
  VaccineDose('ipv', 98, 'IPV'),
  VaccineDose('vita1', 182, 'Vitamin A'),
  VaccineDose('mr1', 273, 'Measles-Rubella 1'),
];

Tx vaccineGroupName(int day) => switch (day) {
  0 => const Tx('At birth', 'Wakati wa kuzaliwa'),
  42 => const Tx('6 weeks', 'Wiki 6'),
  70 => const Tx('10 weeks', 'Wiki 10'),
  98 => const Tx('14 weeks', 'Wiki 14'),
  182 => const Tx('6 months', 'Miezi 6'),
  _ => const Tx('9 months', 'Miezi 9'),
};

/// Postnatal contacts (day after birth).
const postnatalContacts = <(int, Tx)>[
  (1, Tx('Postnatal check within 24 hours', 'Uchunguzi ndani ya saa 24')),
  (3, Tx('Postnatal visit, day 3', 'Kliniki ya siku ya 3')),
  (10, Tx('Postnatal visit, day 7–14', 'Kliniki ya siku 7–14')),
  (42, Tx('Postnatal visit, week 6', 'Kliniki ya wiki 6')),
];

class Milestone {
  final String key;
  final Tx label;
  const Milestone(this.key, this.label);
}

const milestonesByMonth = <int, List<Milestone>>{
  1: [
    Milestone('m1a', Tx('Lifts head briefly on tummy', 'Huinua kichwa kidogo akilala kifudifudi')),
    Milestone('m1b', Tx('Looks at your face', 'Hutazama uso wako')),
    Milestone('m1c', Tx('Startles at loud sounds', 'Hushtuka kwa sauti kubwa')),
  ],
  2: [
    Milestone('m2a', Tx('Smiles at people', 'Huwatabasamia watu')),
    Milestone('m2b', Tx('Coos and makes sounds', 'Hutoa sauti za kuongea')),
    Milestone('m2c', Tx('Follows you with eyes', 'Hukufuata kwa macho')),
  ],
  4: [
    Milestone('m4a', Tx('Holds head steady', 'Hushikilia kichwa imara')),
    Milestone('m4b', Tx('Laughs', 'Hucheka')),
    Milestone('m4c', Tx('Brings hands to mouth', 'Hupeleka mikono mdomoni')),
    Milestone('m4d', Tx('Pushes up on arms on tummy', 'Hujiinua kwa mikono akilala kifudifudi')),
  ],
  6: [
    Milestone('m6a', Tx('Rolls over', 'Hujigeuza')),
    Milestone('m6b', Tx('Sits with support', 'Hukaa akishikiliwa')),
    Milestone('m6c', Tx('Reaches for things', 'Hunyoosha mkono kushika vitu')),
    Milestone('m6d', Tx('Turns to their name', 'Huitikia jina lake')),
  ],
  9: [
    Milestone('m9a', Tx('Sits without support', 'Hukaa bila kushikiliwa')),
    Milestone('m9b', Tx('Crawls or pulls up to stand', 'Hutambaa au hujaribu kusimama')),
    Milestone('m9c', Tx('Says "mama", "baba" sounds', 'Hutamka "mama", "baba"')),
    Milestone('m9d', Tx('Shy with strangers', 'Huogopa wageni')),
  ],
};

/// Birth-preparation checklist (birth_plans.items_ready keys).
const birthReady = <(String, Tx)>[
  ('facility', Tx('Facility chosen for the birth', 'Kituo cha kujifungulia kimechaguliwa')),
  ('transport', Tx('Transport planned, money saved', 'Usafiri umepangwa, akiba ipo')),
  ('companion', Tx('Birth companion chosen', 'Msindikizaji amechaguliwa')),
  ('cloths', Tx('Clean cloths and baby clothes packed', 'Vitambaa safi na nguo za mtoto vimeandaliwa')),
  ('card', Tx('Clinic card in the bag', 'Kadi ya kliniki iko kwenye begi')),
  ('net', Tx('Treated mosquito net ready for baby', 'Chandarua chenye dawa kiko tayari kwa mtoto')),
];

/// Foods: protein g, iron mg, folate µg, calcium mg per typical serving (Tanzania pack).
class Food {
  final String key;
  final Tx name, serving;
  final double protein, iron, folate, calcium;
  const Food(this.key, this.name, this.serving, this.protein, this.iron, this.folate, this.calcium);
}

const dailyNeeds = (protein: 71.0, iron: 27.0, folate: 600.0, calcium: 1000.0);
const foodsTz = <Food>[
  Food('beans', Tx('Beans', 'Maharage'), Tx('1 cup cooked', 'Kikombe 1 kilichopikwa'), 15, 4, 250, 80),
  Food('greens', Tx('Mchicha (amaranth)', 'Mchicha'), Tx('1 cup cooked', 'Kikombe 1 kilichopikwa'), 3, 3, 150, 180),
  Food('fish', Tx('Dagaa (small fish)', 'Dagaa'), Tx('50 g, eaten whole', 'Gramu 50, liwa zima'), 25, 3, 10, 600),
  Food('eggs', Tx('Eggs', 'Mayai'), Tx('2 eggs', 'Mayai 2'), 12, 1.8, 45, 50),
  Food('gnuts', Tx('Groundnuts', 'Karanga'), Tx('2 tablespoons', 'Vijiko 2 vikubwa'), 8, 0.7, 70, 30),
  Food('milk', Tx('Milk', 'Maziwa'), Tx('1 cup', 'Kikombe 1'), 8, 0.1, 12, 300),
  Food('liver', Tx('Liver', 'Maini'), Tx('75 g', 'Gramu 75'), 20, 5, 190, 5),
  Food('avocado', Tx('Avocado', 'Parachichi'), Tx('half', 'nusu'), 2, 0.5, 80, 10),
  Food('fruit', Tx('Orange or mango', 'Chungwa au embe'), Tx('1 fruit, helps iron absorb', 'Tunda 1, husaidia madini ya chuma'), 1, 0.2, 40, 40),
  Food('staple', Tx('Ugali or rice', 'Ugali au wali'), Tx('1 plate', 'Sahani 1'), 4, 1, 20, 20),
  Food('ifa', Tx('Iron + folic acid tablet', 'Kidonge cha IFA'), Tx('1 tablet daily', 'Kidonge 1 kila siku'), 0, 60, 400, 0),
];

const recipesTz = <(Tx, List<Tx>)>[
  (
    Tx('Maharage ya nazi with mchicha', 'Maharage ya nazi na mchicha'),
    [
      Tx('Boil the beans until soft.', 'Chemsha maharage hadi yalainike.'),
      Tx('Add coconut milk, onion and tomato; simmer 15 minutes.', 'Ongeza tui la nazi, kitunguu na nyanya; pika dakika 15.'),
      Tx('Serve with rice and mchicha.', 'Pakua na wali na mchicha.'),
    ],
  ),
  (
    Tx('Dagaa wa nazi', 'Dagaa wa nazi'),
    [
      Tx('Wash dagaa in warm water.', 'Osha dagaa kwa maji ya uvuguvugu.'),
      Tx('Fry onion and tomato, add dagaa and coconut milk.', 'Kaanga kitunguu na nyanya, ongeza dagaa na tui la nazi.'),
      Tx('Simmer 10 minutes, serve with ugali.', 'Pika dakika 10, pakua na ugali.'),
    ],
  ),
  (
    Tx('Mchicha wa karanga', 'Mchicha wa karanga'),
    [
      Tx('Cook chopped mchicha with onion and tomato.', 'Pika mchicha uliokatwa na kitunguu na nyanya.'),
      Tx('Stir in 2 tablespoons of peanut paste and a little water.', 'Ongeza vijiko 2 vya karanga zilizosagwa na maji kidogo.'),
      Tx('Simmer 5 minutes.', 'Pika dakika 5.'),
    ],
  ),
];

/// Emergency numbers for the Tanzania country pack.
/// OPEN QUESTION: the Council Health Management Team must confirm these numbers
/// and the district ambulance line before the pilot (see resources/PRD.md).
const emergencyNumbersTz = <(Tx, String)>[(Tx('National emergency line', 'Namba ya dharura ya taifa'), '112')];

/// Baby month by month (MA-48): the same layout as pregnancyMonths, so the after-birth
/// journey looks familiar. `short` is the one-line highlight on Home; `watch` is when to
/// talk to a health worker. Months are counted from birth (month 1 = days 0–30).
class BabyMonth {
  final Tx short, baby, you, watch;
  const BabyMonth(this.short, this.baby, this.you, this.watch);
}

const babyMonthsGuide = <int, BabyMonth>{
  1: BabyMonth(
    Tx('Knows your voice and smell', 'Anaijua sauti na harufu yako'),
    Tx(
      'Baby sleeps most of the day and wakes to feed 8 or more times. Baby looks at faces and knows your smell and voice.',
      'Mtoto analala sehemu kubwa ya siku na kuamka kunyonya mara 8 au zaidi. Anatazama nyuso na anaijua harufu na sauti yako.',
    ),
    Tx(
      'Rest when baby sleeps. Bleeding gets lighter each week. Eat well and drink plenty of water while breastfeeding.',
      'Pumzika mtoto akilala. Damu inapungua kila wiki. Kula vizuri na kunywa maji mengi unaponyonyesha.',
    ),
    Tx(
      'Go now if baby cannot feed, has yellow palms or soles, a fever, or feels cold.',
      'Nenda sasa kama mtoto hawezi kunyonya, ana viganja au nyayo za njano, homa, au mwili wa baridi.',
    ),
  ),
  2: BabyMonth(
    Tx('Smiles back at you', 'Anakutabasamia'),
    Tx(
      'Baby starts to smile at you and makes cooing sounds. The 6-week vaccines are due.',
      'Mtoto anaanza kukutabasamia na kutoa sauti za kuongea. Chanjo za wiki 6 zinafika.',
    ),
    Tx(
      'At your 6-week check, ask about family planning. Many mothers feel tired: ask your family for help at home.',
      'Kwenye kliniki ya wiki 6, uliza kuhusu uzazi wa mpango. Akina mama wengi huchoka: omba familia ikusaidie nyumbani.',
    ),
    Tx(
      'Tell your health worker if baby does not smile or follow your face by the end of this month.',
      'Mwambie mhudumu wa afya kama mtoto hatabasamu wala kufuata uso wako kufikia mwisho wa mwezi huu.',
    ),
  ),
  3: BabyMonth(
    Tx('Lifts the head on the tummy', 'Anainua kichwa akilala kifudifudi'),
    Tx(
      'Baby lifts the head and chest when lying on the tummy, opens the hands and watches them. The 10-week vaccines are due.',
      'Mtoto anainua kichwa na kifua akilala kifudifudi, anafungua mikono na kuitazama. Chanjo za wiki 10 zinafika.',
    ),
    Tx(
      'Give tummy time a few times a day while baby is awake and you are watching. Keep giving breast milk only.',
      'Mlaze kifudifudi mara chache kwa siku akiwa macho na wewe ukimwangalia. Endelea na maziwa ya mama pekee.',
    ),
    Tx('Tell your health worker if baby cannot lift the head at all.', 'Mwambie mhudumu wa afya kama mtoto hawezi kuinua kichwa kabisa.'),
  ),
  4: BabyMonth(
    Tx('Laughs and holds the head steady', 'Anacheka na kushikilia kichwa'),
    Tx(
      'Baby laughs, holds the head steady and brings the hands to the mouth. The 14-week vaccines are due.',
      'Mtoto anacheka, anashikilia kichwa imara na kupeleka mikono mdomoni. Chanjo za wiki 14 zinafika.',
    ),
    Tx(
      'Talk and sing to baby: it builds language. Keep small objects out of reach.',
      'Ongea na mwimbie mtoto: inajenga lugha. Weka vitu vidogo mbali na mkono wake.',
    ),
    Tx(
      'Tell your health worker if the head is still floppy, or baby does not turn to sounds.',
      'Mwambie mhudumu wa afya kama kichwa bado kinalegea, au mtoto hageuki kufuata sauti.',
    ),
  ),
  5: BabyMonth(
    Tx('Rolls over and reaches out', 'Anajigeuza na kunyoosha mkono'),
    Tx('Baby rolls over and reaches for things.', 'Mtoto anajigeuza na kunyoosha mkono kushika vitu.'),
    Tx(
      'Never leave baby alone on a bed or table. Breast milk is still all baby needs.',
      'Usimwache mtoto peke yake kitandani au mezani. Maziwa ya mama bado ndiyo yote anayohitaji.',
    ),
    Tx(
      'Tell your health worker if baby does not reach for things, or the body is very stiff or very floppy.',
      'Mwambie mhudumu wa afya kama mtoto hanyooshi mkono kushika vitu, au mwili ni mgumu sana au umelegea sana.',
    ),
  ),
  6: BabyMonth(
    Tx('Ready for first foods', 'Yuko tayari kwa chakula cha kwanza'),
    Tx(
      'Baby sits with support and is ready for first foods besides breast milk. Vitamin A is due.',
      'Mtoto anakaa akishikiliwa na yuko tayari kwa chakula pamoja na maziwa ya mama. Vitamini A inafika.',
    ),
    Tx(
      'Start thick porridge with groundnut or dagaa powder, 2 to 3 times a day, and keep breastfeeding.',
      'Anza uji mzito wenye unga wa karanga au dagaa, mara 2 hadi 3 kwa siku, na endelea kunyonyesha.',
    ),
    Tx(
      'Tell your health worker if baby cannot sit with support, or the weight is not going up.',
      'Mwambie mhudumu wa afya kama mtoto hawezi kukaa akishikiliwa, au uzito hauongezeki.',
    ),
  ),
  7: BabyMonth(
    Tx('Babbles "ba-ba"', 'Anatamka "ba-ba"'),
    Tx('Baby passes toys from hand to hand and babbles "ba-ba".', 'Mtoto anahamisha vitu kutoka mkono mmoja hadi mwingine na kutamka "ba-ba".'),
    Tx(
      'Give a variety of mashed foods: beans, greens, fruit, egg. Wash hands and keep cups and spoons clean.',
      'Mpe vyakula mbalimbali vilivyopondwa: maharage, mboga za majani, matunda, yai. Nawa mikono na weka vikombe na vijiko safi.',
    ),
    Tx('Tell your health worker if baby makes no babbling sounds.', 'Mwambie mhudumu wa afya kama mtoto hatoi sauti za kuongea.'),
  ),
  8: BabyMonth(
    Tx('Sits alone', 'Anakaa mwenyewe'),
    Tx('Baby sits alone and may start to crawl.', 'Mtoto anakaa mwenyewe na anaweza kuanza kutambaa.'),
    Tx(
      'Make the floor safe: keep kerosene, medicines and small objects out of reach.',
      'Fanya sakafu iwe salama: weka mafuta ya taa, dawa na vitu vidogo mbali na mtoto.',
    ),
    Tx('Tell your health worker if baby cannot sit alone.', 'Mwambie mhudumu wa afya kama mtoto hawezi kukaa mwenyewe.'),
  ),
  9: BabyMonth(
    Tx('Pulls up to stand', 'Anajaribu kusimama'),
    Tx(
      'Baby pulls up to stand, makes "mama" and "baba" sounds and may be shy with strangers. The measles-rubella vaccine is due.',
      'Mtoto anajaribu kusimama, anatamka "mama" na "baba" na anaweza kuogopa wageni. Chanjo ya surua-rubela inafika.',
    ),
    Tx(
      'Give 3 meals and 1 to 2 snacks a day, plus breast milk. Keep using the child health card after this month.',
      'Mpe milo 3 na vitafunio 1 hadi 2 kwa siku, pamoja na maziwa ya mama. Endelea kutumia kadi ya mtoto baada ya mwezi huu.',
    ),
    Tx(
      'Tell your health worker if baby cannot sit, does not turn to their name, or loses skills they had.',
      'Mwambie mhudumu wa afya kama mtoto hawezi kukaa, haitikii jina lake, au anapoteza uwezo aliokuwa nao.',
    ),
  ),
};

/// Baby's month on the 9-month journey (1–9), the way pregnancy has months 1–9.
int babyMonthOf(int days) => (days ~/ 30.44 + 1).clamp(1, 9);

/// Child clinic contacts (MA-49): eight, like the eight antenatal contacts. Postnatal checks
/// (WHO PNC) and the Tanzania routine immunisation visits. `pnc` = index in postnatalContacts
/// (1-based); `vaccines` = vaccine keys given at that visit.
class ChildContact {
  final int day;
  final Tx title;
  final List<Tx> items;
  final int? pnc;
  final List<String> vaccines;
  const ChildContact(this.day, this.title, this.items, {this.pnc, this.vaccines = const []});
}

const childContacts = <ChildContact>[
  ChildContact(
    0,
    Tx('Birth and the first day', 'Kuzaliwa na siku ya kwanza'),
    [
      Tx('Baby weighed and examined; skin-to-skin and first breastfeed', 'Mtoto kupimwa uzito na kuchunguzwa; kugusana ngozi na kunyonya mara ya kwanza'),
      Tx('BCG and polio (OPV 0) vaccines', 'Chanjo za BCG na polio (OPV 0)'),
      Tx('Mother: bleeding, blood pressure and temperature checked', 'Mama: damu, shinikizo la damu na joto kuchunguzwa'),
    ],
    pnc: 1,
    vaccines: ['bcg', 'opv0'],
  ),
  ChildContact(3, Tx('Day 3 check', 'Kliniki ya siku ya 3'), [
    Tx('Feeding watched; yellow skin and cord checked', 'Unyonyeshaji kuangaliwa; njano na kitovu kuchunguzwa'),
    Tx('Baby kept warm; danger signs explained', 'Mtoto kupata joto; dalili za hatari kuelezwa'),
    Tx('Mother: bleeding, fever, breasts', 'Mama: damu, homa, matiti'),
  ], pnc: 2),
  ChildContact(10, Tx('Day 7–14 check', 'Kliniki ya siku 7–14'), [
    Tx('Weight back to birth weight?', 'Uzito umerudi kama wa kuzaliwa?'),
    Tx('Cord healing; eyes and skin checked', 'Kitovu kupona; macho na ngozi kuchunguzwa'),
    Tx('Mother: mood and sleep', 'Mama: hisia na usingizi'),
  ], pnc: 3),
  ChildContact(
    42,
    Tx('6 weeks: check and vaccines', 'Wiki 6: uchunguzi na chanjo'),
    [
      Tx('Polio, Penta, pneumococcal (PCV) and rotavirus vaccines', 'Chanjo za polio, Penta, nimonia (PCV) na rota'),
      Tx('Growth on the child health card', 'Ukuaji kwenye kadi ya mtoto'),
      Tx('Mother: family planning, blood pressure, mood', 'Mama: uzazi wa mpango, shinikizo la damu, hisia'),
    ],
    pnc: 4,
    vaccines: ['opv1', 'penta1', 'pcv1', 'rota1'],
  ),
  ChildContact(
    70,
    Tx('10 weeks: vaccines', 'Wiki 10: chanjo'),
    [Tx('Second polio, Penta, PCV and rotavirus doses', 'Dozi ya pili ya polio, Penta, PCV na rota'), Tx('Weight and growth', 'Uzito na ukuaji')],
    vaccines: ['opv2', 'penta2', 'pcv2', 'rota2'],
  ),
  ChildContact(
    98,
    Tx('14 weeks: vaccines', 'Wiki 14: chanjo'),
    [Tx('Third polio, Penta and PCV doses, and IPV', 'Dozi ya tatu ya polio, Penta na PCV, na IPV'), Tx('Weight and growth', 'Uzito na ukuaji')],
    vaccines: ['opv3', 'penta3', 'pcv3', 'ipv'],
  ),
  ChildContact(
    182,
    Tx('6 months: vitamin A and first foods', 'Miezi 6: vitamini A na chakula cha kwanza'),
    [
      Tx('Vitamin A', 'Vitamini A'),
      Tx('Ask how to start foods besides breast milk', 'Uliza jinsi ya kuanza chakula pamoja na maziwa ya mama'),
      Tx('Weight, growth and development', 'Uzito, ukuaji na makuzi'),
    ],
    vaccines: ['vita1'],
  ),
  ChildContact(
    273,
    Tx('9 months: measles-rubella', 'Miezi 9: surua-rubela'),
    [
      Tx('Measles-rubella vaccine', 'Chanjo ya surua-rubela'),
      Tx('Weight, growth and development check', 'Uzito, ukuaji na makuzi kuchunguzwa'),
      Tx('Keep using the child health card after 9 months', 'Endelea kutumia kadi ya mtoto baada ya miezi 9'),
    ],
    vaccines: ['mr1'],
  ),
];
