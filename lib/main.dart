import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _warmWhite = Color(0xFFF8F3EA);
const _warmWhite2 = Color(0xFFFFFCF7);
const _gold = Color(0xFFB08A43);
const _goldLight = Color(0xFFD9C08B);
const _charcoal = Color(0xFF2A2926);
const _muted = Color(0xFF7A746A);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: _warmWhite,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  runApp(const TvinderApp());
}

class TvinderApp extends StatelessWidget {
  const TvinderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _warmWhite,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _gold,
          brightness: Brightness.light,
          surface: _warmWhite,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(
            color: _charcoal,
            fontSize: 20,
            fontWeight: FontWeight.w500,
            height: 1.65,
          ),
        ),
      ),
      home: const SessionScreen(),
    );
  }
}

enum Stage { splash, guide, loading, question, analyzing, ready, movie, finished }

class AnswerRecord {
  final String question;
  final bool answer;
  const AnswerRecord(this.question, this.answer);

  Map<String, dynamic> toJson() => {'question': question, 'answer': answer ? 'yes' : 'no'};
}

class TasteProfile {
  final Map<String, double> values;
  const TasteProfile(this.values);

  factory TasteProfile.neutral() => const TasteProfile({
        'energy': 0.5,
        'emotionalIntensity': 0.5,
        'darkness': 0.5,
        'complexity': 0.5,
        'ambiguityTolerance': 0.5,
        'surrealism': 0.5,
        'pace': 0.5,
        'philosophicalDepth': 0.5,
        'escapism': 0.5,
        'novelty': 0.5,
        'romance': 0.5,
        'humor': 0.5,
        'fear': 0.5,
        'violenceTolerance': 0.5,
        'animationAffinity': 0.35,
        'classicAffinity': 0.5,
        'nonEnglishAffinity': 0.7,
      });

  factory TasteProfile.fromJson(Map<String, dynamic>? json, TasteProfile fallback) {
    if (json == null) return fallback;
    final out = <String, double>{...fallback.values};
    for (final entry in json.entries) {
      final n = entry.value;
      if (n is num && out.containsKey(entry.key)) {
        out[entry.key] = n.toDouble().clamp(0.0, 1.0).toDouble();
      }
    }
    return TasteProfile(out);
  }

  Map<String, dynamic> toJson() => values;
}

class BranchChoice {
  final TasteProfile profile;
  final String nextQuestion;
  final BranchBundle? nextBranches;
  const BranchChoice({
    required this.profile,
    required this.nextQuestion,
    this.nextBranches,
  });
}

class BranchBundle {
  final BranchChoice yes;
  final BranchChoice no;
  const BranchBundle({required this.yes, required this.no});

  BranchChoice choice(bool answer) => answer ? yes : no;
}

class InitialBundle {
  final String question;
  final BranchBundle branches;
  const InitialBundle({required this.question, required this.branches});
}

class FinalTaste {
  final TasteProfile profile;
  final List<int> preferredGenres;
  final List<int> avoidedGenres;
  final int? yearMin;
  final int? yearMax;
  final String summary;

  const FinalTaste({
    required this.profile,
    this.preferredGenres = const [],
    this.avoidedGenres = const [],
    this.yearMin,
    this.yearMax,
    this.summary = '',
  });
}

class Movie {
  final int id;
  final String title;
  final String? posterPath;
  final String overview;
  final List<int> genreIds;
  final double voteAverage;
  final int voteCount;
  final double popularity;
  final String releaseDate;

  const Movie({
    required this.id,
    required this.title,
    this.posterPath,
    this.overview = '',
    this.genreIds = const [],
    this.voteAverage = 0,
    this.voteCount = 0,
    this.popularity = 0,
    this.releaseDate = '',
  });

  factory Movie.fromJson(Map<String, dynamic> j) => Movie(
        id: (j['id'] as num?)?.toInt() ?? 0,
        title: (j['original_title'] ?? j['title'] ?? 'Untitled').toString(),
        posterPath: j['poster_path']?.toString(),
        overview: (j['overview'] ?? '').toString(),
        genreIds: ((j['genre_ids'] as List?) ?? const [])
            .whereType<num>()
            .map((e) => e.toInt())
            .toList(),
        voteAverage: (j['vote_average'] as num?)?.toDouble() ?? 0,
        voteCount: (j['vote_count'] as num?)?.toInt() ?? 0,
        popularity: (j['popularity'] as num?)?.toDouble() ?? 0,
        releaseDate: (j['release_date'] ?? '').toString(),
      );

  String? get posterUrl => posterPath == null ? null : 'https://image.tmdb.org/t/p/w780$posterPath';

  Map<String, dynamic> compactJson() => {
        'id': id,
        'title': title,
        'overview': overview,
        'genre_ids': genreIds,
        'vote_average': voteAverage,
        'vote_count': voteCount,
        'popularity': popularity,
        'release_date': releaseDate,
      };
}

class NetworkJson {
  static Future<Map<String, dynamic>> post(Uri uri, Map<String, dynamic> body,
      {Map<String, String> headers = const {}}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      headers.forEach((key, value) => request.headers.set(key, value));
      request.write(jsonEncode(body));
      final response = await request.close().timeout(const Duration(seconds: 25));
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}: $text', uri: uri);
      }
      return jsonDecode(text) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }

  static Future<Map<String, dynamic>> get(Uri uri,
      {Map<String, String> headers = const {}}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.getUrl(uri);
      headers.forEach((key, value) => request.headers.set(key, value));
      final response = await request.close().timeout(const Duration(seconds: 25));
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}: $text', uri: uri);
      }
      return jsonDecode(text) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }
}

class GeminiEngine {
  static const apiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const model = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-3.5-flash-lite',
  );

  bool get enabled => apiKey.trim().isNotEmpty;

  Future<Map<String, dynamic>> _jsonPrompt(String prompt) async {
    final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent');
    final data = await NetworkJson.post(uri, {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.72,
        'responseMimeType': 'application/json',
      }
    }, headers: {
      'x-goog-api-key': apiKey,
    });
    final candidates = data['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw const FormatException('Empty Gemini response');
    }
    final firstCandidate = candidates.first;
    if (firstCandidate is! Map) throw const FormatException('Bad Gemini candidate');
    final content = firstCandidate['content'];
    if (content is! Map) throw const FormatException('Bad Gemini content');
    final parts = content['parts'];
    if (parts is! List || parts.isEmpty) throw const FormatException('Empty Gemini parts');
    final firstPart = parts.first;
    if (firstPart is! Map) throw const FormatException('Bad Gemini part');
    final raw = firstPart['text']?.toString() ?? '';
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  String _dimensions() =>
      'energy, emotionalIntensity, darkness, complexity, ambiguityTolerance, surrealism, pace, philosophicalDepth, escapism, novelty, romance, humor, fear, violenceTolerance, animationAffinity, classicAffinity, nonEnglishAffinity';

  String _baseRules() => '''
تو موتور انتخاب فیلم یک اپ فارسی هستی. هدفت تشخیص بیماری یا روان‌درمانی نیست؛ فقط باید سلیقه سینمایی و حال فعلی کاربر را برای پیشنهاد فیلم کشف کنی.
سؤال‌ها باید:
- دقیقاً بله/نه باشند.
- فقط یک جمله فارسی، مستقیم، خیلی صمیمی و طبیعی باشند.
- می‌توانند درباره حال، شخصیت، نیاز احساسی، ژانر، ریتم، بازیگر، دوره زمانی، زبان، پایان، خشونت، ترس، عشق، فلسفه، سوررئال بودن یا هر عامل مفید دیگری باشند.
- تکراری نباشند و برای بیشترین اطلاعات جدید طراحی شوند.
- از تشخیص پزشکی، برچسب‌زنی و ادعاهای بالینی دور باشند.
ابعاد عددی پروفایل بین صفر و یک هستند: ${_dimensions()}.
''';

  Future<InitialBundle> initialBundle(TasteProfile profile) async {
    final p = '''${_baseRules()}
این سؤال شماره ۱ از ۲۵ است. هیچ پاسخ قبلی وجود ندارد.
پروفایل اولیه: ${jsonEncode(profile.toJson())}
یک سؤال شروع قوی و غیرقابل‌پیش‌بینی بساز. برای هر پاسخ احتمالی، پروفایل را منطقی و محافظه‌کارانه به‌روزرسانی کن و سؤال شماره ۲ مناسب همان شاخه را بساز. سپس برای همان سؤال شماره ۲ نیز دو حالت بله/نه را از قبل تحلیل کن، پروفایل را دوباره به‌روزرسانی کن و سؤال شماره ۳ مناسب هر شاخه را بساز.
فقط JSON دقیقاً با این ساختار بده:
{"question":"...","yes":{"profile":{...},"next_question":"...","next_branches":{"yes":{"profile":{...},"next_question":"..."},"no":{"profile":{...},"next_question":"..."}}},"no":{"profile":{...},"next_question":"...","next_branches":{"yes":{"profile":{...},"next_question":"..."},"no":{"profile":{...},"next_question":"..."}}}}
تمام کلیدهای پروفایل را در هر سطح حفظ کن.''';
    final j = await _jsonPrompt(p);
    final q = j['question']?.toString().trim() ?? '';
    if (q.isEmpty) throw const FormatException('Missing initial question');
    return InitialBundle(question: q, branches: _parseBranches(j, profile));
  }

  Future<BranchBundle> branches({
    required String currentQuestion,
    required int questionNumber,
    required List<AnswerRecord> history,
    required TasteProfile profile,
  }) async {
    final p = '''${_baseRules()}
سؤال فعلی شماره $questionNumber از ۲۵:
$currentQuestion
پاسخ‌های قطعی قبلی: ${jsonEncode(history.map((e) => e.toJson()).toList())}
پروفایل فعلی: ${jsonEncode(profile.toJson())}
برای دو حالت بله و نه به سؤال فعلی، پروفایل را محافظه‌کارانه آپدیت کن و بهترین سؤال بعدی را برای همان شاخه بساز. سپس برای هرکدام از آن سؤال‌های بعدی نیز دو پاسخ احتمالی بله/نه را از قبل تحلیل کن و سؤال یک مرحله بعدتر را بساز. هیچ سؤال جدیدی نباید چیزهایی را که تقریباً روشن شده‌اند بیهوده تکرار کند.
فقط JSON دقیقاً با این ساختار بده:
{"yes":{"profile":{...},"next_question":"...","next_branches":{"yes":{"profile":{...},"next_question":"..."},"no":{"profile":{...},"next_question":"..."}}},"no":{"profile":{...},"next_question":"...","next_branches":{"yes":{"profile":{...},"next_question":"..."},"no":{"profile":{...},"next_question":"..."}}}}
تمام کلیدهای پروفایل را در هر سطح حفظ کن.''';
    return _parseBranches(await _jsonPrompt(p), profile);
  }

  BranchBundle _parseBranches(
    Map<String, dynamic> j,
    TasteProfile fallback, {
    bool parseNested = true,
  }) {
    BranchChoice parse(String key) {
      final b = (j[key] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
      final pr = TasteProfile.fromJson((b['profile'] as Map?)?.cast<String, dynamic>(), fallback);
      final nq = b['next_question']?.toString().trim() ?? '';
      if (nq.isEmpty) throw FormatException('Missing $key next_question');
      BranchBundle? nested;
      final nestedJson = b['next_branches'];
      if (parseNested && nestedJson is Map) {
        nested = _parseBranches(nestedJson.cast<String, dynamic>(), pr, parseNested: false);
      }
      return BranchChoice(profile: pr, nextQuestion: nq, nextBranches: nested);
    }

    return BranchBundle(yes: parse('yes'), no: parse('no'));
  }

  Future<FinalTaste> finalize(List<AnswerRecord> history, TasteProfile profile) async {
    final p = '''${_baseRules()}
۲۵ سؤال تمام شده. پاسخ‌ها: ${jsonEncode(history.map((e) => e.toJson()).toList())}
پروفایل فعلی: ${jsonEncode(profile.toJson())}
یک جمع‌بندی نهایی برای موتور پیشنهاد فیلم بساز. کیفیت خود فیلم باید وزن زیادی داشته باشد. محدودیت زبان، کشور، سال یا شدت محتوا را فقط اگر پاسخ‌های کاربر واقعاً نشان می‌دهند اعمال کن. انیمیشن مجاز است ولی معمولاً اولویت سوم دارد مگر علاقه بسیار قوی باشد.
شناسه ژانرهای TMDB که می‌توانی استفاده کنی: Action=28, Adventure=12, Animation=16, Comedy=35, Crime=80, Documentary=99, Drama=18, Family=10751, Fantasy=14, History=36, Horror=27, Music=10402, Mystery=9648, Romance=10749, ScienceFiction=878, TVMovie=10770, Thriller=53, War=10752, Western=37.
فقط JSON بده:
{"profile":{...},"preferred_genres":[int],"avoided_genres":[int],"year_min":null|int,"year_max":null|int,"summary":"یک خلاصه کوتاه برای رتبه‌بندی داخلی"}''';
    final j = await _jsonPrompt(p);
    int? asInt(dynamic v) => v is num ? v.toInt() : int.tryParse(v?.toString() ?? '');
    final pref = ((j['preferred_genres'] as List?) ?? const []).map(asInt).whereType<int>().toList();
    final avoid = ((j['avoided_genres'] as List?) ?? const []).map(asInt).whereType<int>().toList();
    return FinalTaste(
      profile: TasteProfile.fromJson((j['profile'] as Map?)?.cast<String, dynamic>(), profile),
      preferredGenres: pref,
      avoidedGenres: avoid,
      yearMin: asInt(j['year_min']),
      yearMax: asInt(j['year_max']),
      summary: j['summary']?.toString() ?? '',
    );
  }

  Future<List<int>> rankMovies(FinalTaste taste, List<Movie> candidates) async {
    final compact = candidates.take(60).map((e) => e.compactJson()).toList();
    final p = '''
تو رتبه‌بند نهایی فیلم هستی. هدف: بهترین فیلمی که این کاربر واقعاً دوست خواهد داشت، با وزن زیاد برای کیفیت خود فیلم و سپس match شخصی.
پروفایل: ${jsonEncode(taste.profile.toJson())}
خلاصه: ${taste.summary}
کاندیداها: ${jsonEncode(compact)}
قواعد:
- کیفیت، اعتبار و رضایت عمومی فیلم وزن بالایی دارد؛ صرف match بودن برای یک فیلم ضعیف کافی نیست.
- معروف بودن جریمه نیست.
- زبان و کشور محدودیت ندارند.
- انیمیشن فقط وقتی match قوی است بیاور و در حالت عادی آن را در رتبه سوم هر گروه سه‌تایی ترجیح بده، نه رتبه اول یا دوم.
- فقط شناسه‌های موجود در کاندیداها را استفاده کن و هیچ فیلمی اختراع نکن.
فقط JSON بده: {"ordered_ids":[int,...]} و همه کاندیداها را یک بار مرتب کن.''';
    final j = await _jsonPrompt(p);
    return ((j['ordered_ids'] as List?) ?? const [])
        .whereType<num>()
        .map((e) => e.toInt())
        .toList();
  }
}

class DemoEngine {
  final math.Random _random = math.Random();

  static const _questions = <_DemoQuestion>[
    _DemoQuestion('امشب دلت می‌خواد فیلم بعد از تموم شدنش هنوز چند ساعت توی ذهنت بچرخه؟', 'complexity', .14),
    _DemoQuestion('الان حوصله داری فیلم از نظر احساسی حسابی بهت فشار بیاره؟', 'emotionalIntensity', .16),
    _DemoQuestion('دلت می‌خواد امشب از دنیای واقعی تا جای ممکن فاصله بگیری؟', 'escapism', .17),
    _DemoQuestion('با پایان باز که مجبور شی خودت معنیش رو پیدا کنی حال می‌کنی؟', 'ambiguityTolerance', .16),
    _DemoQuestion('امشب فضای تاریک و تلخ برات جذابه؟', 'darkness', .17),
    _DemoQuestion('دوست داری فیلم آروم شروع بشه و کم‌کم تو رو ببلعه؟', 'pace', -.14),
    _DemoQuestion('الان بیشتر دنبال یه فیلم فلسفی و عمیقی؟', 'philosophicalDepth', .18),
    _DemoQuestion('با فیلمی که مرز واقعیت و خیال رو به‌هم می‌ریزه راحتی؟', 'surrealism', .17),
    _DemoQuestion('امشب ترجیح می‌دی فیلم پرانرژی و تند باشه؟', 'energy', .16),
    _DemoQuestion('اگه فیلم واقعاً خوب باشه، قدیمی بودنش اصلاً برات مهم نیست؟', 'classicAffinity', .18),
    _DemoQuestion('اگه بهترین انتخاب یه فیلم غیرانگلیسی باشه باهاش اوکی‌ای؟', 'nonEnglishAffinity', .18),
    _DemoQuestion('دوست داری آخر فیلم واقعاً غافلگیرت کنه؟', 'novelty', .14),
    _DemoQuestion('امشب یک داستان عاشقانه قوی می‌تونه انتخاب خوبی برات باشه؟', 'romance', .17),
    _DemoQuestion('الان بیشتر از هرچیز دلت می‌خواد فیلم حالت رو بهتر کنه؟', 'humor', .12),
    _DemoQuestion('با ترس و اضطراب شدید توی فیلم مشکلی نداری؟', 'fear', .18),
    _DemoQuestion('اگه خشونت برای داستان لازم باشه، با صحنه‌های سنگین مشکلی نداری؟', 'violenceTolerance', .18),
    _DemoQuestion('اگه یک انیمیشن واقعاً شاهکار بهترین match باشه، خوشحال می‌شی پیشنهادش بگیری؟', 'animationAffinity', .24),
    _DemoQuestion('ترجیح می‌دی فیلم بیشتر واقعی و زمینی باشه تا فانتزی؟', 'surrealism', -.15),
    _DemoQuestion('حوصله داستانی داری که برای فهمیدنش باید خیلی دقیق نگاه کنی؟', 'complexity', .17),
    _DemoQuestion('امشب دنبال چیزی هستی که یه کم اذیتت کنه ولی ارزشش رو داشته باشه؟', 'darkness', .13),
    _DemoQuestion('دوست داری فیلم بیشتر با احساساتت بازی کنه تا با معما و ایده؟', 'emotionalIntensity', .12),
    _DemoQuestion('الان حوصله شوخی و فضای سبک وسط داستان رو داری؟', 'humor', .15),
    _DemoQuestion('یک فیلم خیلی متفاوت و عجیب رو به یک انتخاب مطمئن و آشنا ترجیح می‌دی؟', 'novelty', .18),
    _DemoQuestion('امشب ترجیح می‌دی داستان سریع جلو بره و وقت تلف نکنه؟', 'pace', .17),
    _DemoQuestion('دوست داری فیلم درباره سؤال‌های بزرگ زندگی و معنی وجود حرف بزنه؟', 'philosophicalDepth', .17),
    _DemoQuestion('اگر پایان فیلم غمگین ولی فوق‌العاده باشه، باز هم انتخابش می‌کنی؟', 'emotionalIntensity', .14),
    _DemoQuestion('با قهرمان‌های خاکستری و تصمیم‌های اخلاقی سخت بیشتر ارتباط می‌گیری؟', 'complexity', .13),
    _DemoQuestion('فضای رازآلود برات از اکشن مستقیم جذاب‌تره؟', 'ambiguityTolerance', .13),
    _DemoQuestion('امشب دلت یک جهان کاملاً تازه و ناشناخته می‌خواد؟', 'escapism', .15),
    _DemoQuestion('اگر فیلم آهسته باشه ولی قاب‌به‌قاب زیبا و دقیق ساخته شده باشه، صبرش رو داری؟', 'pace', -.16),
    _DemoQuestion('دوست داری فیلم بیشتر امید بده تا اینکه واقعیت تلخ رو بی‌پرده نشون بده؟', 'darkness', -.13),
    _DemoQuestion('با فیلمی که جواب واضح بهت نمی‌ده و فقط سؤال می‌سازه مشکلی نداری؟', 'ambiguityTolerance', .16),
  ];

  InitialBundle initial(TasteProfile profile) {
    final q = _questions[_random.nextInt(math.min(8, _questions.length).toInt())];
    return InitialBundle(question: q.text, branches: _branchesFor(q, profile, const [], depth: 2));
  }

  BranchBundle branches(String currentQuestion, TasteProfile profile, List<AnswerRecord> history) {
    final q = _questions.firstWhere(
      (e) => e.text == currentQuestion,
      orElse: () => _questions[_random.nextInt(_questions.length)],
    );
    return _branchesFor(q, profile, history, depth: 2);
  }

  BranchBundle _branchesFor(
    _DemoQuestion current,
    TasteProfile profile,
    List<AnswerRecord> history, {
    required int depth,
  }) {
    BranchChoice make(bool answer) {
      final v = <String, double>{...profile.values};
      final delta = answer ? current.delta : -current.delta;
      v[current.dimension] = ((v[current.dimension] ?? .5) + delta).clamp(0.0, 1.0).toDouble();
      final used = history.map((e) => e.question).toSet()..add(current.text);
      final remaining = _questions.where((q) => !used.contains(q.text)).toList();
      final next = remaining.isEmpty ? _questions[_random.nextInt(_questions.length)] : _pickInformative(v, remaining);
      final updated = TasteProfile(v);
      BranchBundle? nested;
      if (depth > 1) {
        nested = _branchesFor(
          next,
          updated,
          [...history, AnswerRecord(current.text, answer)],
          depth: depth - 1,
        );
      }
      return BranchChoice(profile: updated, nextQuestion: next.text, nextBranches: nested);
    }

    return BranchBundle(yes: make(true), no: make(false));
  }

  _DemoQuestion _pickInformative(Map<String, double> v, List<_DemoQuestion> list) {
    list.shuffle(_random);
    list.sort((a, b) {
      final da = ((v[a.dimension] ?? .5) - .5).abs();
      final db = ((v[b.dimension] ?? .5) - .5).abs();
      return da.compareTo(db);
    });
    return list.first;
  }

  FinalTaste finalize(List<AnswerRecord> history, TasteProfile profile) {
    final p = profile.values;
    final genres = <int>[];
    if ((p['surrealism'] ?? .5) > .62) genres.addAll([14, 878]);
    if ((p['darkness'] ?? .5) > .65) genres.addAll([53, 80]);
    if ((p['fear'] ?? .5) > .67) genres.add(27);
    if ((p['humor'] ?? .5) > .66) genres.add(35);
    if ((p['romance'] ?? .5) > .66) genres.add(10749);
    if ((p['complexity'] ?? .5) > .62) genres.addAll([9648, 18]);
    return FinalTaste(profile: profile, preferredGenres: genres.toSet().toList(), summary: 'demo');
  }

  List<Movie> rank(FinalTaste taste) {
    final movies = [..._demoMovies];
    double score(Movie m) {
      var s = m.voteAverage * 1.5 + math.log(math.max(10, m.voteCount)) * .6;
      for (final g in m.genreIds) {
        if (taste.preferredGenres.contains(g)) s += 1.4;
      }
      if (m.genreIds.contains(16) && (taste.profile.values['animationAffinity'] ?? .35) < .72) s -= 1.0;
      return s;
    }

    movies.sort((a, b) => score(b).compareTo(score(a)));
    return movies;
  }

  static const _demoMovies = <Movie>[
    Movie(id: 1, title: 'The Shawshank Redemption', genreIds: [18], voteAverage: 9.3, voteCount: 29000),
    Movie(id: 2, title: 'The Godfather', genreIds: [18, 80], voteAverage: 9.2, voteCount: 21000),
    Movie(id: 3, title: 'The Dark Knight', genreIds: [28, 80, 18], voteAverage: 9.0, voteCount: 33000),
    Movie(id: 4, title: '12 Angry Men', genreIds: [18], voteAverage: 9.0, voteCount: 9000),
    Movie(id: 5, title: 'The Lord of the Rings: The Return of the King', genreIds: [12, 14], voteAverage: 9.0, voteCount: 20000),
    Movie(id: 6, title: 'Parasite', genreIds: [18, 53], voteAverage: 8.5, voteCount: 10000),
    Movie(id: 7, title: 'Whiplash', genreIds: [18, 10402], voteAverage: 8.5, voteCount: 10000),
    Movie(id: 8, title: 'The Prestige', genreIds: [18, 9648, 53], voteAverage: 8.5, voteCount: 15000),
    Movie(id: 9, title: 'Interstellar', genreIds: [12, 18, 878], voteAverage: 8.7, voteCount: 36000),
    Movie(id: 10, title: 'Inception', genreIds: [28, 878, 53], voteAverage: 8.8, voteCount: 37000),
    Movie(id: 11, title: 'Arrival', genreIds: [18, 878, 9648], voteAverage: 7.9, voteCount: 18000),
    Movie(id: 12, title: 'Blade Runner 2049', genreIds: [18, 878, 53], voteAverage: 8.0, voteCount: 14000),
    Movie(id: 13, title: 'Her', genreIds: [18, 10749, 878], voteAverage: 8.0, voteCount: 13000),
    Movie(id: 14, title: 'Eternal Sunshine of the Spotless Mind', genreIds: [18, 10749, 878], voteAverage: 8.3, voteCount: 11000),
    Movie(id: 15, title: 'No Country for Old Men', genreIds: [80, 18, 53], voteAverage: 8.2, voteCount: 11000),
    Movie(id: 16, title: 'The Truman Show', genreIds: [35, 18], voteAverage: 8.2, voteCount: 12000),
    Movie(id: 17, title: 'Pan’s Labyrinth', genreIds: [14, 18, 10752], voteAverage: 8.2, voteCount: 8000),
    Movie(id: 18, title: 'Incendies', genreIds: [18, 9648, 10752], voteAverage: 8.3, voteCount: 2200),
    Movie(id: 19, title: 'A Separation', genreIds: [18], voteAverage: 8.3, voteCount: 3000),
    Movie(id: 20, title: 'The Handmaiden', genreIds: [18, 10749, 53], voteAverage: 8.1, voteCount: 4000),
    Movie(id: 21, title: 'The Grand Budapest Hotel', genreIds: [35, 18], voteAverage: 8.1, voteCount: 15000),
    Movie(id: 22, title: 'Mad Max: Fury Road', genreIds: [28, 12, 878], voteAverage: 8.1, voteCount: 23000),
    Movie(id: 23, title: 'Spirited Away', genreIds: [16, 14, 10751], voteAverage: 8.6, voteCount: 17000),
    Movie(id: 24, title: 'Perfect Blue', genreIds: [16, 53, 9648], voteAverage: 8.0, voteCount: 3000),
    Movie(id: 25, title: 'Spider-Man: Into the Spider-Verse', genreIds: [16, 28, 12], voteAverage: 8.4, voteCount: 16000),
    Movie(id: 26, title: 'Stalker', genreIds: [18, 878], voteAverage: 8.1, voteCount: 2500),
    Movie(id: 27, title: 'City of God', genreIds: [18, 80], voteAverage: 8.6, voteCount: 9000),
    Movie(id: 28, title: 'The Lives of Others', genreIds: [18, 53], voteAverage: 8.4, voteCount: 4000),
    Movie(id: 29, title: 'Portrait of a Lady on Fire', genreIds: [18, 10749], voteAverage: 8.1, voteCount: 3000),
    Movie(id: 30, title: 'The Social Network', genreIds: [18], voteAverage: 7.8, voteCount: 12000),
  ];
}

class _DemoQuestion {
  final String text;
  final String dimension;
  final double delta;
  const _DemoQuestion(this.text, this.dimension, this.delta);
}

class TmdbEngine {
  static const token = String.fromEnvironment('TMDB_BEARER_TOKEN');
  bool get enabled => token.trim().isNotEmpty;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'accept': 'application/json',
      };

  Future<List<Movie>> candidates(FinalTaste taste) async {
    final merged = <int, Movie>{};
    Future<void> fetch(Uri uri) async {
      final j = await NetworkJson.get(uri, headers: _headers);
      for (final raw in (j['results'] as List?) ?? const []) {
        if (raw is Map<String, dynamic>) {
          final m = Movie.fromJson(raw);
          if (m.id != 0 && m.voteCount >= 120 && m.voteAverage >= 6.6) merged[m.id] = m;
        } else if (raw is Map) {
          final m = Movie.fromJson(raw.cast<String, dynamic>());
          if (m.id != 0 && m.voteCount >= 120 && m.voteAverage >= 6.6) merged[m.id] = m;
        }
      }
    }

    for (var page = 1; page <= 3; page++) {
      await fetch(Uri.https('api.themoviedb.org', '/3/movie/top_rated', {
        'page': '$page',
        'language': 'en-US',
      }));
    }

    final params = <String, String>{
      'sort_by': 'vote_average.desc',
      'vote_count.gte': '350',
      'include_adult': 'false',
      'include_video': 'false',
      'page': '1',
    };
    if (taste.preferredGenres.isNotEmpty) params['with_genres'] = taste.preferredGenres.take(3).join('|');
    if (taste.avoidedGenres.isNotEmpty) params['without_genres'] = taste.avoidedGenres.join(',');
    if (taste.yearMin != null) params['primary_release_date.gte'] = '${taste.yearMin}-01-01';
    if (taste.yearMax != null) params['primary_release_date.lte'] = '${taste.yearMax}-12-31';
    for (var page = 1; page <= 3; page++) {
      params['page'] = '$page';
      await fetch(Uri.https('api.themoviedb.org', '/3/discover/movie', params));
    }

    final list = merged.values.toList();
    list.sort((a, b) => _qualityScore(b).compareTo(_qualityScore(a)));
    return list.take(80).toList();
  }

  double _qualityScore(Movie m) {
    final confidence = 1 - math.exp(-m.voteCount / 2400.0);
    return (m.voteAverage * (.65 + .35 * confidence)) + math.log(math.max(1, m.voteCount)) * .18;
  }
}

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  final _gemini = GeminiEngine();
  final _tmdb = TmdbEngine();

  Stage _stage = Stage.splash;
  TasteProfile _profile = TasteProfile.neutral();
  final List<AnswerRecord> _history = [];
  String _question = '';
  BranchBundle? _branches;
  Future<BranchBundle>? _branchFuture;
  Object? _branchError;

  List<Movie> _rankedMovies = [];
  final Set<int> _seenMovieIds = {};
  Movie? _currentMovie;
  int _candidateCursor = 0;
  int _round = 0;
  int _slot = 0;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    setState(() => _stage = Stage.splash);
    await Future.delayed(const Duration(milliseconds: 950));
    if (!mounted) return;
    setState(() => _stage = Stage.guide);
    await Future.delayed(const Duration(milliseconds: 1900));
    if (!mounted) return;
    await _startQuestions();
  }

  Future<void> _startQuestions() async {
    _profile = TasteProfile.neutral();
    _history.clear();
    _branches = null;
    _branchFuture = null;
    _branchError = null;
    _rankedMovies = [];
    _seenMovieIds.clear();
    _candidateCursor = 0;
    _round = 0;
    _slot = 0;
    setState(() => _stage = Stage.loading);

    if (!_gemini.enabled) {
      _showServiceError('سرویس هوش مصنوعی تنظیم نشده');
      return;
    }

    try {
      final initial = await _gemini.initialBundle(_profile);
      if (!mounted) return;
      _question = initial.question;
      _branches = initial.branches;
      setState(() => _stage = Stage.question);
    } on SocketException catch (_) {
      _showInternetError();
    } on TimeoutException catch (_) {
      _showInternetError();
    } catch (_) {
      _showServiceError('خطا در دریافت سؤال. دوباره وارد اپ شو');
    }
  }

  void _prefetchIfNeeded() {
    if (_stage != Stage.question || _branches != null || _branchFuture != null) return;
    final q = _question;
    final number = _history.length + 1;
    final historySnapshot = List<AnswerRecord>.of(_history);
    final profileSnapshot = _profile;
    _branchError = null;
    if (!_gemini.enabled) {
      _branchError = StateError('Gemini is not configured');
      return;
    }
    final future = _gemini.branches(
      currentQuestion: q,
      questionNumber: number,
      history: historySnapshot,
      profile: profileSnapshot,
    );
    _branchFuture = future;
    future.then((b) {
      if (!mounted || q != _question) return;
      _branches = b;
      _branchFuture = null;
      _branchError = null;
    }).catchError((e) {
      if (!mounted || q != _question) return;
      _branchFuture = null;
      _branchError = e;
    });
  }

  Future<bool> _answer(bool answer) async {
    BranchBundle? bundle = _branches;
    if (bundle == null) {
      _prefetchIfNeeded();
      try {
        bundle = await _branchFuture?.timeout(const Duration(seconds: 8));
      } catch (e) {
        if (e is SocketException || e is TimeoutException) {
          _showInternetError();
        } else {
          _showServiceError('خطا در دریافت سؤال بعدی');
        }
        return false;
      }
    }
    if (bundle == null) {
      _showInternetError();
      return false;
    }

    final current = _question;
    final chosen = bundle.choice(answer);
    _history.add(AnswerRecord(current, answer));
    _profile = chosen.profile;
    _branches = chosen.nextBranches;
    _branchFuture = null;
    _branchError = null;

    if (_history.length >= 25) {
      unawaited(_finishQuestions());
      return true;
    }

    _question = chosen.nextQuestion;
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefetchIfNeeded());
    return true;
  }

  Future<void> _finishQuestions() async {
    if (!mounted) return;
    setState(() => _stage = Stage.analyzing);
    try {
      if (!_gemini.enabled || !_tmdb.enabled) {
        throw StateError('Online services are not configured');
      }

      final taste = await _gemini.finalize(_history, _profile);
      _profile = taste.profile;

      var candidates = await _tmdb.candidates(taste);
      if (candidates.isNotEmpty) {
        final ids = await _gemini.rankMovies(taste, candidates);
        final map = {for (final m in candidates) m.id: m};
        final ranked = <Movie>[];
        for (final id in ids) {
          final m = map.remove(id);
          if (m != null) ranked.add(m);
        }
        ranked.addAll(map.values);
        candidates = ranked;
      }

      _rankedMovies = _enforceAnimationRule(candidates, taste.profile);
      if (_rankedMovies.isEmpty) throw StateError('No movies returned');
      _candidateCursor = 0;
      _seenMovieIds.clear();
      _round = 0;
      _slot = 0;
      _currentMovie = _takeNextMovie();
      if (!mounted) return;
      setState(() => _stage = Stage.ready);
      await Future.delayed(const Duration(milliseconds: 1450));
      if (mounted) setState(() => _stage = Stage.movie);
    } on SocketException catch (_) {
      _showInternetError();
    } on TimeoutException catch (_) {
      _showInternetError();
    } catch (_) {
      _showServiceError('خطا در آماده‌کردن پیشنهادها. دوباره وارد اپ شو');
    }
  }

  List<Movie> _enforceAnimationRule(List<Movie> input, TasteProfile p) {
    if ((p.values['animationAffinity'] ?? .35) >= .78) return input;
    final out = <Movie>[];
    for (var base = 0; base < input.length; base += 3) {
      final end = math.min(base + 3, input.length).toInt();
      final chunk = input.sublist(base, end);
      final liveAction = chunk.where((m) => !m.genreIds.contains(16));
      final animation = chunk.where((m) => m.genreIds.contains(16));
      out.addAll(liveAction);
      out.addAll(animation);
    }
    return out;
  }

  Movie? _takeNextMovie() {
    while (_candidateCursor < _rankedMovies.length) {
      final m = _rankedMovies[_candidateCursor++];
      if (_seenMovieIds.add(m.id)) return m;
    }
    return null;
  }

  void _seenMovie() {
    final replacement = _takeNextMovie();
    if (replacement == null) return;
    setState(() => _currentMovie = replacement);
  }

  void _nextMovie() {
    if (_slot < 2) {
      _slot++;
      final next = _takeNextMovie();
      if (next != null) setState(() => _currentMovie = next);
      return;
    }
    if (_round >= 4) {
      setState(() => _stage = Stage.finished);
      return;
    }
    _round++;
    _slot = 0;
    final next = _takeNextMovie();
    if (next != null) setState(() => _currentMovie = next);
  }

  void _showInternetError() {
    _showMessage('اتصال اینترنت را بررسی کنید');
  }

  void _showServiceError(String message) {
    _showMessage(message);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Text(message, textAlign: TextAlign.center),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _charcoal,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          margin: const EdgeInsets.all(18),
        ),
      );
  }

  Future<bool> _confirmExit() async {
    if (_stage == Stage.splash) return true;
    final result = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .18),
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: _warmWhite2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
            side: BorderSide(color: _gold.withValues(alpha: .35)),
          ),
          title: const Text(
            'اگه خارج شی، جواب‌هات پاک می‌شن. مطمئنی؟',
            textAlign: TextAlign.center,
            style: TextStyle(color: _charcoal, fontSize: 18, fontWeight: FontWeight.w600, height: 1.6),
          ),
          actionsAlignment: MainAxisAlignment.spaceEvenly,
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('بمون')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('خروج')),
          ],
        ),
      ),
    );
    if (result == true) {
      await SystemNavigator.pop();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_stage == Stage.question) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _prefetchIfNeeded());
    }
    return WillPopScope(
      onWillPop: _confirmExit,
      child: Scaffold(
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 340),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: KeyedSubtree(
              key: ValueKey(_stage),
              child: _buildStage(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStage() {
    switch (_stage) {
      case Stage.splash:
        return const _SplashScreen();
      case Stage.guide:
        return const _GuideScreen();
      case Stage.loading:
      case Stage.analyzing:
        return const _LoadingScreen();
      case Stage.question:
        return _QuestionScreen(
          question: _question,
          onAnswer: _answer,
        );
      case Stage.ready:
        return const _ReadyScreen();
      case Stage.movie:
        return _MovieScreen(
          movie: _currentMovie!,
          onNext: _nextMovie,
          onSeen: _seenMovie,
        );
      case Stage.finished:
        return _FinishedScreen(
          onAgain: _startQuestions,
          onExit: () => SystemNavigator.pop(),
        );
    }
  }
}

class _Background extends StatelessWidget {
  final Widget child;
  const _Background({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: _warmWhite,
      child: child,
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return _Background(
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: .82, end: 1),
          duration: const Duration(milliseconds: 850),
          curve: Curves.easeOutBack,
          builder: (_, v, child) => Opacity(
            opacity: ((v - .82) / .18).clamp(0.0, 1.0).toDouble(),
            child: Transform.scale(scale: v, child: child),
          ),
          child: const SizedBox(width: 84, height: 84, child: CustomPaint(painter: _MarkPainter())),
        ),
      ),
    );
  }
}

class _GuideScreen extends StatefulWidget {
  const _GuideScreen();

  @override
  State<_GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<_GuideScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Background(
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    _GuideLabel(text: 'بله', right: true),
                    _GuideLabel(text: 'نه', right: false),
                  ],
                ),
                const SizedBox(height: 22),
                AnimatedBuilder(
                  animation: _c,
                  builder: (_, child) {
                    final dx = math.sin(_c.value * math.pi * 2) * 26;
                    final rot = dx / 700;
                    return Transform.translate(
                      offset: Offset(dx, 0),
                      child: Transform.rotate(angle: rot, child: child),
                    );
                  },
                  child: SizedBox(
                    width: math.min(MediaQuery.sizeOf(context).width * .68, 310.0).toDouble(),
                    height: 250,
                    child: const _GlassCard(
                      child: Center(
                        child: SizedBox(width: 52, height: 52, child: CustomPaint(painter: _MarkPainter(strokeWidth: 1.5))),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GuideLabel extends StatelessWidget {
  final String text;
  final bool right;
  const _GuideLabel({required this.text, required this.right});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          if (!right) const Icon(Icons.arrow_back_rounded, color: _gold, size: 20),
          if (!right) const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: _charcoal, fontSize: 16, fontWeight: FontWeight.w600)),
          if (right) const SizedBox(width: 6),
          if (right) const Icon(Icons.arrow_forward_rounded, color: _gold, size: 20),
        ],
      );
}

class _LoadingScreen extends StatefulWidget {
  const _LoadingScreen();

  @override
  State<_LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<_LoadingScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Background(
        child: Center(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, child) {
              final v = Curves.easeInOut.transform(_c.value);
              return Container(
                width: 102,
                height: 102,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _gold.withValues(alpha: .08 + .11 * v),
                      blurRadius: 38 + 22 * v,
                      spreadRadius: 2 + 6 * v,
                    )
                  ],
                ),
                child: Transform.scale(scale: .92 + .08 * v, child: child),
              );
            },
            child: const Center(child: SizedBox(width: 48, height: 48, child: CustomPaint(painter: _MarkPainter(strokeWidth: 1.4)))),
          ),
        ),
      );
}

class _QuestionScreen extends StatelessWidget {
  final String question;
  final Future<bool> Function(bool) onAnswer;
  const _QuestionScreen({required this.question, required this.onAnswer});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = math.min(size.width * .82, 410.0).toDouble();
    final height = (size.height * .46).clamp(300.0, 470.0).toDouble();
    return _Background(
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          transitionBuilder: (child, animation) {
            final slide = Tween<Offset>(begin: const Offset(0, .15), end: Offset.zero).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );
            return FadeTransition(opacity: animation, child: SlideTransition(position: slide, child: child));
          },
          child: SizedBox(
            key: ValueKey(question),
            width: width,
            height: height,
            child: _SwipeCard(question: question, onAnswer: onAnswer),
          ),
        ),
      ),
    );
  }
}

class _SwipeCard extends StatefulWidget {
  final String question;
  final Future<bool> Function(bool) onAnswer;
  const _SwipeCard({required this.question, required this.onAnswer});

  @override
  State<_SwipeCard> createState() => _SwipeCardState();
}

class _SwipeCardState extends State<_SwipeCard> with SingleTickerProviderStateMixin {
  Offset _offset = Offset.zero;
  bool _locked = false;
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 190));
  Animation<Offset>? _animation;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _animateTo(Offset target, {VoidCallback? done}) {
    _c.stop();
    _c.reset();
    _animation = Tween<Offset>(begin: _offset, end: target).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic))
      ..addListener(() {
        if (mounted) setState(() => _offset = _animation!.value);
      });
    _c.forward().whenComplete(() => done?.call());
  }

  Future<void> _release(DragEndDetails details) async {
    if (_locked) return;
    final width = context.size?.width ?? 320;
    final threshold = width * .24;
    if (_offset.dx.abs() < threshold) {
      _animateTo(Offset.zero);
      return;
    }
    _locked = true;
    final answer = _offset.dx > 0;
    HapticFeedback.lightImpact();
    SystemSound.play(SystemSoundType.click);
    final target = Offset((answer ? 1 : -1) * width * 1.65, _offset.dy * .25);
    _animateTo(target);
    final ok = await widget.onAnswer(answer);
    if (!mounted) return;
    if (!ok) {
      _locked = false;
      _animateTo(Offset.zero);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = context.size?.width ?? 320;
    final progress = (_offset.dx.abs() / (width * .55)).clamp(0.0, 1.0).toDouble();
    final rotation = (_offset.dx / width) * .13;
    final scale = 1 - .035 * progress;
    final yesOpacity = (_offset.dx > 0 ? progress : 0.0);
    final noOpacity = (_offset.dx < 0 ? progress : 0.0);

    return GestureDetector(
      onPanUpdate: _locked
          ? null
          : (d) => setState(() {
                _offset += d.delta;
              }),
      onPanEnd: _locked ? null : _release,
      child: Transform.translate(
        offset: _offset,
        child: Transform.rotate(
          angle: rotation,
          child: Transform.scale(
            scale: scale,
            child: Stack(
              children: [
                _GlassCard(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 28, 28, 34),
                    child: Column(
                      children: [
                        const _CardMark(),
                        Expanded(
                          child: Center(
                            child: Directionality(
                              textDirection: TextDirection.rtl,
                              child: Text(
                                widget.question,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _charcoal.withValues(alpha: .96),
                                  fontSize: (MediaQuery.sizeOf(context).width * .052).clamp(18.0, 23.0).toDouble(),
                                  fontWeight: FontWeight.w500,
                                  height: 1.72,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 24,
                  top: 76,
                  child: Opacity(
                    opacity: yesOpacity,
                    child: Transform.rotate(
                      angle: -.08,
                      child: const _SwipeStamp(text: 'بله'),
                    ),
                  ),
                ),
                Positioned(
                  left: 24,
                  top: 76,
                  child: Opacity(
                    opacity: noOpacity,
                    child: Transform.rotate(
                      angle: .08,
                      child: const _SwipeStamp(text: 'نه'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SwipeStamp extends StatelessWidget {
  final String text;
  const _SwipeStamp({required this.text});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _gold, width: 1.2),
          color: _warmWhite2.withValues(alpha: .55),
        ),
        child: Text(text, style: const TextStyle(color: _gold, fontSize: 16, fontWeight: FontWeight.w700)),
      );
}

class _CardMark extends StatefulWidget {
  const _CardMark();
  @override
  State<_CardMark> createState() => _CardMarkState();
}

class _CardMarkState extends State<_CardMark> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420))..forward();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: CurvedAnimation(parent: _c, curve: Curves.easeOut),
        child: const SizedBox(width: 34, height: 34, child: CustomPaint(painter: _MarkPainter(strokeWidth: 1.2))),
      );
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        boxShadow: [
          BoxShadow(color: const Color(0xFF79694D).withValues(alpha: .12), blurRadius: 34, offset: const Offset(0, 18)),
          BoxShadow(color: Colors.white.withValues(alpha: .82), blurRadius: 12, offset: const Offset(-4, -6)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .42),
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: _goldLight.withValues(alpha: .62), width: .9),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ReadyScreen extends StatefulWidget {
  const _ReadyScreen();
  @override
  State<_ReadyScreen> createState() => _ReadyScreenState();
}

class _ReadyScreenState extends State<_ReadyScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => _Background(
        child: Center(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, child) {
              final v = Curves.easeInOut.transform(_c.value);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(color: _gold.withValues(alpha: .08 + .12 * v), blurRadius: 45 + 18 * v, spreadRadius: 6 * v),
                  ],
                ),
                child: child,
              );
            },
            child: const Directionality(
              textDirection: TextDirection.rtl,
              child: Text(
                'انتخابت آماده‌ست',
                textAlign: TextAlign.center,
                style: TextStyle(color: _charcoal, fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -.3),
              ),
            ),
          ),
        ),
      );
}

class _MovieScreen extends StatelessWidget {
  final Movie movie;
  final VoidCallback onNext;
  final VoidCallback onSeen;
  const _MovieScreen({required this.movie, required this.onNext, required this.onSeen});

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context);
    final posterW = math.min(s.width * .60, 310.0).toDouble();
    final posterH = (posterW * 1.48).clamp(330.0, s.height * .56).toDouble();
    return _Background(
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TweenAnimationBuilder<double>(
                key: ValueKey(movie.id),
                tween: Tween(begin: .94, end: 1),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                builder: (_, v, child) => Opacity(
                  opacity: ((v - .94) / .06).clamp(0.0, 1.0).toDouble(),
                  child: Transform.scale(scale: v, child: child),
                ),
                child: Container(
                  width: posterW,
                  height: posterH,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .14), blurRadius: 28, offset: const Offset(0, 16))],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: movie.posterUrl == null
                        ? _PosterFallback(title: movie.title)
                        : Image.network(
                            movie.posterUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _PosterFallback(title: movie.title),
                            loadingBuilder: (_, child, progress) => progress == null ? child : const _PosterFallback(title: ''),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                movie.title,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _charcoal, fontSize: 21, fontWeight: FontWeight.w600, height: 1.35),
              ),
              const SizedBox(height: 26),
              Row(
                children: [
                  Expanded(child: _GoldOutlineButton(label: 'دیدم', onTap: onSeen)),
                  const SizedBox(width: 14),
                  Expanded(child: _GoldOutlineButton(label: 'بعدی', onTap: onNext)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  final String title;
  const _PosterFallback({required this.title});
  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFFEDE4D5),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 48, height: 48, child: CustomPaint(painter: _MarkPainter(strokeWidth: 1.3))),
            if (title.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text(title, textDirection: TextDirection.ltr, textAlign: TextAlign.center, style: const TextStyle(color: _charcoal, fontSize: 19, fontWeight: FontWeight.w600)),
            ]
          ],
        ),
      );
}

class _GoldOutlineButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _GoldOutlineButton({required this.label, required this.onTap});
  @override
  State<_GoldOutlineButton> createState() => _GoldOutlineButtonState();
}

class _GoldOutlineButtonState extends State<_GoldOutlineButton> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => AnimatedScale(
        scale: _down ? .965 : 1,
        duration: const Duration(milliseconds: 90),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) {
            setState(() => _down = false);
            HapticFeedback.selectionClick();
            widget.onTap();
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .42),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: _gold.withValues(alpha: .76), width: 1),
                ),
                child: Text(widget.label, style: const TextStyle(color: _charcoal, fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
      );
}

class _FinishedScreen extends StatelessWidget {
  final VoidCallback onAgain;
  final VoidCallback onExit;
  const _FinishedScreen({required this.onAgain, required this.onExit});

  @override
  Widget build(BuildContext context) => _Background(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 34),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 52, height: 52, child: CustomPaint(painter: _MarkPainter(strokeWidth: 1.4))),
                  const SizedBox(height: 34),
                  Row(
                    children: [
                      Expanded(child: _GoldOutlineButton(label: 'خروج', onTap: onExit)),
                      const SizedBox(width: 14),
                      Expanded(child: _GoldOutlineButton(label: 'از نو', onTap: onAgain)),
                    ],
                  )
                ],
              ),
            ),
          ),
        ),
      );
}

class _MarkPainter extends CustomPainter {
  final double strokeWidth;
  const _MarkPainter({this.strokeWidth = 1.7});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = _gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final r = Rect.fromLTWH(size.width * .14, size.height * .24, size.width * .72, size.height * .52);
    canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(size.width * .12)), p);
    final eye = Path()
      ..moveTo(size.width * .28, size.height * .50)
      ..quadraticBezierTo(size.width * .50, size.height * .34, size.width * .72, size.height * .50)
      ..quadraticBezierTo(size.width * .50, size.height * .66, size.width * .28, size.height * .50);
    canvas.drawPath(eye, p);
    canvas.drawCircle(Offset(size.width * .50, size.height * .50), size.width * .055, p);
    canvas.drawLine(Offset(size.width * .26, size.height * .24), Offset(size.width * .34, size.height * .14), p);
    canvas.drawLine(Offset(size.width * .50, size.height * .24), Offset(size.width * .50, size.height * .12), p);
    canvas.drawLine(Offset(size.width * .74, size.height * .24), Offset(size.width * .66, size.height * .14), p);
  }

  @override
  bool shouldRepaint(covariant _MarkPainter oldDelegate) => oldDelegate.strokeWidth != strokeWidth;
}
