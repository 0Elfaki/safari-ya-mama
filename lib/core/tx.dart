/// Bilingual text. Every mother-facing string exists in Kiswahili and English
/// (NF-09). Sudanese Arabic and Luganda are added later as content packs.
class Tx {
  final String en;
  final String sw;
  const Tx(this.en, this.sw);

  String of(String lang) => lang == 'sw' ? sw : en;

  Tx operator +(Tx other) => Tx(en + other.en, sw + other.sw);

  @override
  String toString() => en;
}

const supportedLangs = ['sw', 'en'];
