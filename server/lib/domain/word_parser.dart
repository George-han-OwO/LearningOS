class ParsedWord {
  const ParsedWord({
    required this.word,
    required this.phonetic,
    required this.partOfSpeech,
    required this.translation,
    required this.exampleEnglish,
    required this.exampleChinese,
  });

  final String word;
  final String phonetic;
  final String partOfSpeech;
  final String translation;
  final String exampleEnglish;
  final String exampleChinese;

  ParsedWord copyWith({
    String? word,
    String? phonetic,
    String? partOfSpeech,
    String? translation,
    String? exampleEnglish,
    String? exampleChinese,
  }) {
    return ParsedWord(
      word: word ?? this.word,
      phonetic: phonetic ?? this.phonetic,
      partOfSpeech: partOfSpeech ?? this.partOfSpeech,
      translation: translation ?? this.translation,
      exampleEnglish: exampleEnglish ?? this.exampleEnglish,
      exampleChinese: exampleChinese ?? this.exampleChinese,
    );
  }
}

class WordParser {
  const WordParser._();

  static final RegExp _wordPattern = RegExp(r"[A-Za-z]+(?:[-'][A-Za-z]+)*");

  static const Map<String, ParsedWord> _starterDictionary = {
    'abandon': ParsedWord(
      word: 'abandon',
      phonetic: '/əˈbændən/',
      partOfSpeech: 'v.',
      translation: '放弃；遗弃',
      exampleEnglish: 'He abandoned the plan.',
      exampleChinese: '他放弃了这个计划。',
    ),
    'ability': ParsedWord(
      word: 'ability',
      phonetic: '/əˈbɪləti/',
      partOfSpeech: 'n.',
      translation: '能力；才能',
      exampleEnglish: 'She has the ability to lead.',
      exampleChinese: '她具备领导能力。',
    ),
    'absence': ParsedWord(
      word: 'absence',
      phonetic: '/ˈæbsəns/',
      partOfSpeech: 'n.',
      translation: '缺席；不存在',
      exampleEnglish: 'His absence was noticed.',
      exampleChinese: '人们注意到他缺席了。',
    ),
    'academic': ParsedWord(
      word: 'academic',
      phonetic: '/ˌækəˈdemɪk/',
      partOfSpeech: 'adj.',
      translation: '学术的；学院的',
      exampleEnglish: 'The course develops academic writing.',
      exampleChinese: '这门课程培养学术写作能力。',
    ),
    'accomplish': ParsedWord(
      word: 'accomplish',
      phonetic: '/əˈkʌmplɪʃ/',
      partOfSpeech: 'v.',
      translation: '完成；实现',
      exampleEnglish: 'We accomplished our goal.',
      exampleChinese: '我们实现了目标。',
    ),
    'active': ParsedWord(
      word: 'active',
      phonetic: '/ˈæktɪv/',
      partOfSpeech: 'adj.',
      translation: '积极的；活跃的',
      exampleEnglish: 'Active recall strengthens memory.',
      exampleChinese: '主动回忆可以加强记忆。',
    ),
    'memory': ParsedWord(
      word: 'memory',
      phonetic: '/ˈmeməri/',
      partOfSpeech: 'n.',
      translation: '记忆；记忆力',
      exampleEnglish: 'Sleep supports long-term memory.',
      exampleChinese: '睡眠有助于长期记忆。',
    ),
    'recall': ParsedWord(
      word: 'recall',
      phonetic: '/rɪˈkɔːl/',
      partOfSpeech: 'v./n.',
      translation: '回忆；召回',
      exampleEnglish: 'Try to recall the answer first.',
      exampleChinese: '先尝试回忆答案。',
    ),
    'study': ParsedWord(
      word: 'study',
      phonetic: '/ˈstʌdi/',
      partOfSpeech: 'v./n.',
      translation: '学习；研究',
      exampleEnglish: 'She studies every morning.',
      exampleChinese: '她每天早上学习。',
    ),
  };

  static List<ParsedWord> parse(String input) {
    final seen = <String>{};
    final output = <ParsedWord>[];

    for (final match in _wordPattern.allMatches(input)) {
      final normalized = match.group(0)!.toLowerCase();
      if (!seen.add(normalized)) continue;

      output.add(
        _starterDictionary[normalized] ??
            ParsedWord(
              word: normalized,
              phonetic: '待生成',
              partOfSpeech: '待识别',
              translation: '待 AI 翻译',
              exampleEnglish: '',
              exampleChinese: '',
            ),
      );
    }

    return output;
  }
}
