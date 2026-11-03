// Body self-check (MA-43): tap where it hurts, look as shown, answer yes/no, get a safe next
// step. Content: resources/HEALTH_EDUCATION_CURRICULUM.md "Body self-check". Every "yes" maps
// to a daily-check sign key (so combinations count exactly as in the check), or carries its
// own level when the check has no such sign. The level is computed only by rateSelfCheck()
// in rules.dart. It never names an illness.
import 'package:flutter/material.dart';

import 'content.dart';
import 'tx.dart';

class BodyQ {
  final String id;
  final Tx text;

  /// A daily-check sign key, or a special key: '_unwell' (feeling very unwell),
  /// '_move_none' / '_move_fewer' (baby's movements in pregnancy).
  final String? sign;

  /// Own level when there is no matching sign key.
  final Level? level;
  const BodyQ(this.id, this.text, {this.sign, this.level});
}

class BodyArea {
  final String id;
  final Tx title, how;
  final IconData icon;

  /// Where the tap target sits on the body picture (fractions of width and height).
  final double x, y;
  final List<BodyQ> qs;
  const BodyArea(this.id, this.title, this.icon, this.x, this.y, this.how, this.qs);
}

const bodyMaps = <String, List<BodyArea>>{
  'pregnant': [
    BodyArea(
      'head',
      Tx('Head and eyes', 'Kichwa na macho'),
      Icons.psychology_alt,
      .5,
      .07,
      Tx(
        'Rest for 30 minutes and drink water. Look at something far away. Ask for your blood pressure to be measured.',
        'Pumzika dakika 30 na kunywa maji. Tazama kitu kilicho mbali. Omba upimwe shinikizo la damu.',
      ),
      [
        BodyQ('p_head1', Tx('A severe headache that does not go away?', 'Kichwa kinauma sana na hakiachi?'), sign: 'headache'),
        BodyQ('p_head2', Tx('Blurred vision or seeing spots?', 'Kuona ukungu au madoa?'), sign: 'vision'),
        BodyQ('p_head3', Tx('A fit, or fainting?', 'Degedege, au kuzirai?'), sign: 'fits'),
      ],
    ),
    BodyArea(
      'face',
      Tx('Face and hands', 'Uso na mikono'),
      Icons.back_hand,
      .26,
      .40,
      Tx(
        'Look in a mirror. Are your rings tight? Press your shin for 5 seconds: does a dent stay?',
        'Jitazame kwenye kioo. Pete zinabana? Bonyeza muundi kwa sekunde 5: shimo linabaki?',
      ),
      [
        BodyQ('p_face1', Tx('Face or hands suddenly swollen?', 'Uso au mikono imevimba ghafla?'), sign: 'swelling'),
        BodyQ('p_face2', Tx('A severe headache or blurred vision as well?', 'Pia kichwa kikali au kuona ukungu?'), sign: 'headache'),
      ],
    ),
    BodyArea(
      'chest',
      Tx('Chest and breathing', 'Kifua na kupumua'),
      Icons.air,
      .5,
      .26,
      Tx('Sit still for 5 minutes and notice your breathing.', 'Kaa kimya dakika 5 na angalia kupumua kwako.'),
      [BodyQ('p_chest1', Tx('Hard to breathe at rest, or chest pain?', 'Kupumua kwa shida ukiwa umepumzika, au maumivu ya kifua?'), sign: 'breathing')],
    ),
    BodyArea(
      'belly',
      Tx('Belly', 'Tumbo'),
      Icons.pregnant_woman,
      .5,
      .42,
      Tx(
        'Lie on your left side. Is the pain constant, or does it come and go? Where is it?',
        'Lala kwa ubavu wa kushoto. Maumivu ni ya kudumu au yanakuja na kuondoka? Yako wapi?',
      ),
      [
        BodyQ('p_belly1', Tx('Severe or constant belly pain?', 'Maumivu makali au ya kudumu ya tumbo?'), sign: 'bellypain'),
        BodyQ('p_belly2', Tx('Pain high up, under the ribs?', 'Maumivu juu, chini ya mbavu?'), level: Level.red),
        BodyQ('p_belly3', Tx('Regular tightenings before 37 weeks?', 'Mikazo ya mara kwa mara kabla ya wiki 37?'), level: Level.red),
      ],
    ),
    BodyArea(
      'baby',
      Tx("Baby's movements", 'Mitikisiko ya mtoto'),
      Icons.child_care,
      .62,
      .5,
      Tx(
        'From 20 weeks: lie on your left side for an hour after eating and compare with baby\'s usual pattern.',
        'Kuanzia wiki 20: lala kwa ubavu wa kushoto saa moja baada ya kula na linganisha na tabia ya kawaida ya mtoto.',
      ),
      [
        BodyQ('p_baby1', Tx('No movements at all?', 'Hakuna mitikisiko kabisa?'), sign: '_move_none'),
        BodyQ('p_baby2', Tx('Fewer or different movements than usual?', 'Mitikisiko michache au tofauti na kawaida?'), sign: '_move_fewer'),
      ],
    ),
    BodyArea(
      'bleeding',
      Tx('Bleeding or fluid', 'Damu au maji'),
      Icons.water_drop,
      .5,
      .56,
      Tx('Put on a clean pad and look after 30 minutes. Notice the colour and smell.', 'Vaa pedi safi na angalia baada ya dakika 30. Angalia rangi na harufu.'),
      [
        BodyQ('p_bleed1', Tx('Any bleeding from the vagina?', 'Damu yoyote ukeni?'), sign: 'bleeding'),
        BodyQ('p_bleed2', Tx('Water leaking?', 'Maji yanatoka?'), sign: 'water'),
        BodyQ('p_bleed3', Tx('Itchy or smelly discharge?', 'Uchafu wenye muwasho au harufu?'), level: Level.amber),
      ],
    ),
    BodyArea(
      'urine',
      Tx('Passing urine', 'Kukojoa'),
      Icons.wc,
      .74,
      .56,
      Tx('Notice burning and how often you go.', 'Angalia kuungua na mara ngapi unakwenda.'),
      [
        BodyQ('p_urine1', Tx('Burning or pain when passing urine?', 'Kuungua au maumivu wakati wa kukojoa?'), sign: 'urine'),
        BodyQ('p_urine2', Tx('With fever, or pain in the side or back?', 'Pamoja na homa, au maumivu ubavuni au mgongoni?'), level: Level.amber),
      ],
    ),
    BodyArea(
      'legs',
      Tx('Legs and feet', 'Miguu'),
      Icons.directions_walk,
      .42,
      .82,
      Tx('Compare both legs. Swelling only in the evening is common.', 'Linganisha miguu yote miwili. Kuvimba jioni tu ni jambo la kawaida.'),
      [
        BodyQ('p_legs1', Tx('One leg swollen, red, warm or painful?', 'Mguu mmoja umevimba, mwekundu, wa moto au unauma?'), level: Level.red),
        BodyQ('p_legs2', Tx('Swelling there in the morning too, or growing fast?', 'Uvimbe upo hata asubuhi, au unaongezeka haraka?'), level: Level.amber),
      ],
    ),
    BodyArea(
      'fever',
      Tx('Fever', 'Homa'),
      Icons.thermostat,
      .74,
      .26,
      Tx(
        'Put a thermometer under the arm for 5 minutes. A fever needs a malaria test the same day.',
        'Weka kipimajoto kwapani dakika 5. Homa inahitaji kipimo cha malaria siku hiyo hiyo.',
      ),
      [
        BodyQ('p_fever1', Tx('Fever or shivering?', 'Homa au kutetemeka?'), sign: 'fever'),
        BodyQ('p_fever2', Tx('Too weak to get up?', 'Dhaifu kiasi cha kushindwa kuamka?'), sign: '_unwell'),
      ],
    ),
  ],
  'postnatal': [
    BodyArea(
      'bleeding',
      Tx('Bleeding', 'Damu'),
      Icons.water_drop,
      .5,
      .56,
      Tx('Put on a clean pad and look after one hour.', 'Vaa pedi safi na angalia baada ya saa moja.'),
      [
        BodyQ(
          'n_bleed1',
          Tx('A pad soaked in under an hour, or clots bigger than an egg?', 'Pedi imelowa chini ya saa moja, au mabonge makubwa kuliko yai?'),
          sign: 'pp_bleed',
        ),
        BodyQ('n_bleed2', Tx('A bad smell, or bleeding getting heavier again?', 'Harufu mbaya, au damu inaongezeka tena?'), sign: 'pp_discharge'),
      ],
    ),
    BodyArea(
      'belly',
      Tx('Belly and womb', 'Tumbo na mji wa mimba'),
      Icons.pregnant_woman,
      .5,
      .42,
      Tx('Press gently over the womb, below the belly button.', 'Bonyeza kwa upole juu ya mji wa mimba, chini ya kitovu.'),
      [BodyQ('n_belly1', Tx('Belly pain that is getting worse?', 'Maumivu ya tumbo yanayoongezeka?'), sign: 'pp_belly')],
    ),
    BodyArea(
      'wound',
      Tx('Stitches or wound', 'Mishono au kidonda'),
      Icons.healing,
      .62,
      .5,
      Tx(
        'Look at the stitches or caesarean wound in good light, with clean hands.',
        'Angalia mishono au kidonda cha upasuaji kwenye mwanga mzuri, kwa mikono safi.',
      ),
      [BodyQ('n_wound1', Tx('Red, with pus, a bad smell or opening?', 'Mwekundu, una usaha, harufu mbaya au unafunguka?'), level: Level.amber)],
    ),
    BodyArea('breasts', Tx('Breasts', 'Matiti'), Icons.favorite, .38, .3, Tx('Feel each breast in small circles.', 'Papasa kila titi kwa miduara midogo.'), [
      BodyQ('n_breast1', Tx('A red, hot, painful area?', 'Sehemu nyekundu, ya moto na inayouma?'), sign: 'pp_breast'),
      BodyQ('n_breast2', Tx('With fever and feeling very unwell?', 'Pamoja na homa na kujisikia vibaya sana?'), sign: '_unwell_fever'),
    ]),
    BodyArea('legs', Tx('Legs', 'Miguu'), Icons.directions_walk, .42, .82, Tx('Compare both calves.', 'Linganisha misuli ya miguu yote miwili.'), [
      BodyQ('n_legs1', Tx('One calf painful and swollen?', 'Mguu mmoja unauma na umevimba?'), sign: 'pp_leg'),
    ]),
    BodyArea(
      'head',
      Tx('Head and eyes', 'Kichwa na macho'),
      Icons.psychology_alt,
      .5,
      .07,
      Tx('Rest and drink water. Ask for your blood pressure to be measured.', 'Pumzika na kunywa maji. Omba upimwe shinikizo la damu.'),
      [
        BodyQ('n_head1', Tx('A severe headache or blurred vision?', 'Kichwa kikali au kuona ukungu?'), sign: 'pp_head'),
        BodyQ('n_head2', Tx('A fit?', 'Degedege?'), sign: 'pp_fits'),
      ],
    ),
    BodyArea(
      'chest',
      Tx('Breathing', 'Kupumua'),
      Icons.air,
      .5,
      .24,
      Tx('Sit still for 5 minutes and notice your breathing.', 'Kaa kimya dakika 5 na angalia kupumua kwako.'),
      [BodyQ('n_chest1', Tx('Hard to breathe, or chest pain?', 'Kupumua kwa shida, au maumivu ya kifua?'), sign: 'pp_breath')],
    ),
    BodyArea('fever', Tx('Fever', 'Homa'), Icons.thermostat, .74, .26, Tx('Thermometer under the arm for 5 minutes.', 'Kipimajoto kwapani dakika 5.'), [
      BodyQ('n_fever1', Tx('Fever or shivering?', 'Homa au kutetemeka?'), sign: 'pp_fever'),
    ]),
    BodyArea('feelings', Tx('Feelings', 'Hisia'), Icons.cloud_outlined, .26, .14, Tx('Think about the last two weeks.', 'Fikiria wiki mbili zilizopita.'), [
      BodyQ('n_feel1', Tx('Sad or unable to cope most days?', 'Huzuni au kushindwa kumudu siku nyingi?'), sign: 'pp_mood'),
      BodyQ('n_feel2', Tx('Thoughts of harming yourself or your baby?', 'Mawazo ya kujidhuru au kumdhuru mtoto?'), sign: 'pp_harm'),
    ]),
  ],
  'baby': [
    BodyArea(
      'breathing',
      Tx('Breathing', 'Kupumua'),
      Icons.air,
      .5,
      .36,
      Tx('When baby is calm, lift the clothes and count breaths for a full minute.', 'Mtoto akiwa ametulia, inua nguo na hesabu pumzi kwa dakika nzima.'),
      [
        BodyQ(
          'b_br1',
          Tx(
            '60 or more breaths a minute (under 2 months), or 50 or more (2–12 months)?',
            'Pumzi 60 au zaidi kwa dakika (chini ya miezi 2), au 50 au zaidi (miezi 2–12)?',
          ),
          sign: 'b_breath',
        ),
        BodyQ('b_br2', Tx('Chest pulls in, grunting, or blue lips?', 'Kifua kinavutika, kuguna, au midomo ya bluu?'), sign: 'b_chest'),
      ],
    ),
    BodyArea(
      'skin',
      Tx('Skin colour', 'Rangi ya ngozi'),
      Icons.wb_sunny_outlined,
      .26,
      .42,
      Tx(
        'In daylight, press the skin on the forehead for 2 seconds and lift. Look at the palms, soles and eyes.',
        'Kwenye mwanga wa mchana, bonyeza ngozi ya paji la uso sekunde 2 na inua. Angalia viganja, nyayo na macho.',
      ),
      [
        BodyQ(
          'b_sk1',
          Tx('Yellow on the first day, or yellow palms or soles?', 'Njano siku ya kwanza, au viganja au nyayo za njano?'),
          sign: 'b_yellow_severe',
        ),
        BodyQ('b_sk2', Tx('Yellow skin or eyes?', 'Ngozi au macho ya njano?'), sign: 'b_yellow'),
        BodyQ('b_sk3', Tx('Many spots with pus?', 'Vipele vingi vyenye usaha?'), level: Level.amber),
      ],
    ),
    BodyArea(
      'temp',
      Tx('Temperature', 'Joto la mwili'),
      Icons.thermostat,
      .74,
      .3,
      Tx('Feel the chest or back, or a thermometer under the arm for 3 minutes.', 'Gusa kifua au mgongo, au kipimajoto kwapani dakika 3.'),
      [
        BodyQ('b_t1', Tx('Feels hot, or 37.5 °C or more?', 'Ana homa, au nyuzi 37.5 au zaidi?'), sign: 'b_fever'),
        BodyQ('b_t2', Tx('Cold even when wrapped, or below 35.5 °C?', 'Baridi hata akifunikwa, au chini ya nyuzi 35.5?'), sign: 'b_cold'),
      ],
    ),
    BodyArea(
      'cord',
      Tx('Cord', 'Kitovu'),
      Icons.child_care,
      .5,
      .5,
      Tx('Look at the cord stump and the skin around it, with clean hands.', 'Angalia kitovu na ngozi inayokizunguka, kwa mikono safi.'),
      [BodyQ('b_c1', Tx('Red, smelly, or pus?', 'Chekundu, harufu mbaya, au usaha?'), sign: 'b_cord')],
    ),
    BodyArea(
      'feeding',
      Tx('Feeding and nappies', 'Kunyonya na nepi'),
      Icons.baby_changing_station,
      .62,
      .62,
      Tx('Think about the last day: feeds, vomiting, wet nappies and stools.', 'Fikiria siku iliyopita: kunyonya, kutapika, nepi zenye mkojo na choo.'),
      [
        BodyQ('b_f1', Tx('Not able to feed?', 'Hawezi kunyonya?'), sign: 'b_feed'),
        BodyQ('b_f2', Tx('Vomits everything?', 'Anatapika kila kitu?'), sign: 'b_vomit'),
        BodyQ('b_f5', Tx('Green vomit, or a swollen, hard belly?', 'Matapishi ya kijani, au tumbo limevimba na gumu?'), sign: 'b_belly'),
        BodyQ('b_f3', Tx('Fewer than 6 wet nappies a day?', 'Nepi chini ya 6 zenye mkojo kwa siku?'), sign: 'b_wet'),
        BodyQ('b_f4', Tx('Many watery stools, blood, or sunken eyes?', 'Choo cha maji mara nyingi, damu, au macho yaliyoingia ndani?'), sign: 'b_diarr'),
      ],
    ),
    BodyArea(
      'softspot',
      Tx('Soft spot', 'Utosi'),
      Icons.radio_button_unchecked,
      .5,
      .06,
      Tx('With baby calm and upright, gently feel the soft spot on top of the head.', 'Mtoto akiwa ametulia na wima, papasa utosi kwa upole.'),
      [BodyQ('b_s1', Tx('Bulging?', 'Umevimba juu?'), level: Level.red), BodyQ('b_s2', Tx('Sunken?', 'Umezama ndani?'), level: Level.amber)],
    ),
    BodyArea(
      'eyes',
      Tx('Eyes', 'Macho'),
      Icons.visibility_outlined,
      .38,
      .16,
      Tx('Look at the eyelids and the corners of the eyes.', 'Angalia kope na pembe za macho.'),
      [BodyQ('b_e1', Tx('Swollen eyelids with pus?', 'Kope zimevimba na zina usaha?'), level: Level.amber)],
    ),
    BodyArea(
      'awake',
      Tx('Awake and moving', 'Macho na kutikisika'),
      Icons.bedtime_outlined,
      .74,
      .82,
      Tx('Touch the feet and call baby\'s name. Watch the arms and legs.', 'Gusa miguu na mwite mtoto jina lake. Angalia mikono na miguu.'),
      [
        BodyQ('b_a1', Tx('Floppy, or hard to wake?', 'Amelegea, au ni vigumu kumwamsha?'), sign: 'b_sleepy'),
        BodyQ('b_a2', Tx('Fits?', 'Degedege?'), sign: 'b_fits'),
      ],
    ),
  ],
};
