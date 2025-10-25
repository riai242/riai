// lib/main.dart
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show FontFeature;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// ===== AdMob =====
import 'package:google_mobile_ads/google_mobile_ads.dart';

// ★ 本番の AdMob アプリID（使わないならそのままでOK）
const String kAdMobAppIdAndroid = 'ca-app-pub-1472749699236972~3938027692';
// ★ バナーのユニットID（開発中はテストID推奨 / 本番は本番IDに差し替え）
const String kBannerAdUnitId    = 'ca-app-pub-3940256099942544/6300978111';

Future<void> initAds() async {
  final status = await MobileAds.instance.initialize();
  debugPrint('AdMob init: ${status.adapterStatuses}');
}

// ===== バナーを出すクラス（そのまま貼り付け）=====
class AdBanner extends StatefulWidget {
  const AdBanner({super.key, this.height = 50});
  final double height;

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _ad;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    final ad = BannerAd(
      size: AdSize.banner,
      adUnitId: kBannerAdUnitId,          // ← テストID／本番ID
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) => setState(() => _isLoaded = true),
        onAdFailedToLoad: (ad, err) {
          ad.dispose();
          debugPrint('Banner failed: ${err.code} ${err.message}');
        },
      ),
    );
    ad.load();
    _ad = ad;
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _ad == null) {
      // 読み込み中も高さを確保してレイアウトが跳ねないようにする
      return SizedBox(height: widget.height);
    }
    return SafeArea( // 端末のナビゲーションバーと重ならないように
      top: false,
      child: SizedBox(
        height: widget.height,
        width: _ad!.size.width.toDouble(),
        child: AdWidget(ad: _ad!),
      ),
    );
  }
}

// ======================
// アプリ本体
// ======================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ja_JP');
  await initAds();
  runApp(const ShukkinboApp());
}

class ShukkinboApp extends StatelessWidget {
  const ShukkinboApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '出勤簿（日本語UI、日曜始まり）',
      locale: const Locale('ja', 'JP'),
      supportedLocales: const [Locale('ja', 'JP')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const HomeRoot(),
    );
  }
}

/// =======================
/// データモデル
/// =======================
class Allowance {
  final String name;
  final int unitPrice;
  final bool perHour;
  final int? minutes;
  Allowance({
    required this.name,
    required this.unitPrice,
    required this.perHour,
    this.minutes,
  });
  int amountForRecord() {
    if (perHour) {
      final m = (minutes ?? 0);
      return (unitPrice * m / 60).round();
    } else {
      return unitPrice;
    }
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'unitPrice': unitPrice,
    'perHour': perHour,
    'minutes': minutes,
  };
  static Allowance fromJson(Map<String, dynamic> j) => Allowance(
    name: j['name'],
    unitPrice: j['unitPrice'],
    perHour: j['perHour'] ?? false,
    minutes: j['minutes'],
  );
}

class AllowancePreset {
  final String name;
  final int unitPrice;
  final bool perHour;
  AllowancePreset({
    required this.name,
    required this.unitPrice,
    required this.perHour,
  });
  Map<String, dynamic> toJson() =>
      {'name': name, 'unitPrice': unitPrice, 'perHour': perHour};
  static AllowancePreset fromJson(Map<String, dynamic> j) => AllowancePreset(
    name: j['name'],
    unitPrice: j['unitPrice'],
    perHour: j['perHour'] ?? false,
  );
}

class WorkRecord {
  final DateTime date;
  final int? startMin;
  final int? endMin;
  final int breakMin;
  final int? manualOverMin;
  final List<Allowance> allowances;
  final String? memo;
  final bool isOff;
  WorkRecord({
    required this.date,
    this.startMin,
    this.endMin,
    this.breakMin = 0,
    this.manualOverMin,
    this.allowances = const [],
    this.memo,
    this.isOff = false,
  });

  int workedMinutes() {
    if (isOff) return 0;
    if (startMin == null || endMin == null) return 0;
    int w = endMin! - startMin! - breakMin;
    if (w < 0) w = 0;
    return w;
  }

  int overtimeMinutes({required bool auto}) {
    if (isOff) return 0;
    if (auto) {
      final w = workedMinutes();
      return w > 480 ? w - 480 : 0;
    } else {
      return manualOverMin ?? 0;
    }
  }

  int allowanceTotal() => allowances.fold(0, (p, a) => p + a.amountForRecord());

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'startMin': startMin,
    'endMin': endMin,
    'breakMin': breakMin,
    'manualOverMin': manualOverMin,
    'allowances': allowances.map((e) => e.toJson()).toList(),
    'memo': memo,
    'isOff': isOff,
  };

  static WorkRecord fromJson(Map<String, dynamic> j) => WorkRecord(
    date: DateTime.parse(j['date']),
    startMin: j['startMin'],
    endMin: j['endMin'],
    breakMin: j['breakMin'] ?? 0,
    manualOverMin: j['manualOverMin'],
    allowances: (j['allowances'] as List? ?? [])
        .map((e) => Allowance.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    memo: j['memo'],
    isOff: j['isOff'] ?? false,
  );
}

/// =======================
/// ストア
/// =======================
class Store extends ChangeNotifier {
  static const kRecordsKey = 'work_records_v1';
  static const kPresetKey = 'allowance_presets_v2';
  static const kUseConfigTimesKey = 'use_config_times_v1';
  static const kConfigStartKey = 'config_start_min_v1';
  static const kConfigEndKey = 'config_end_min_v1';
  static const kUseConfigBreakKey = 'use_config_break_v1';
  static const kConfigBreakKey = 'config_break_min_v1';
  static const kOvertimeAutoKey = 'overtime_auto_v1';
  static const kCycleStartKey = 'cycle_start_day_v1';
  static const kCycleEndKey = 'cycle_end_day_v1';
  static const kReportNameKey = 'report_name_v1';

  final List<WorkRecord> _records = [];
  final List<AllowancePreset> _presets = [];

  bool useConfigTimes = true;
  int configStartMin = 9 * 60;
  int configEndMin = 18 * 60;

  bool useConfigBreak = true;
  int configBreakMin = 60;

  bool overtimeAuto = true;
  int cycleStartDay = 1;
  int cycleEndDay = 31;

  String reportName = '';

  Map<DateTime, String> _holidayNameCache = {};

  List<WorkRecord> get records =>
      List.unmodifiable(_records..sort((a, b) => a.date.compareTo(b.date)));
  List<AllowancePreset> get presets => List.unmodifiable(_presets);

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final rs = sp.getString(kRecordsKey);
    if (rs != null) {
      final list = (jsonDecode(rs) as List)
          .map((e) => WorkRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      _records
        ..clear()
        ..addAll(list);
    }
    final ps = sp.getString(kPresetKey);
    if (ps != null) {
      final list = (jsonDecode(ps) as List)
          .map((e) => AllowancePreset.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      _presets
        ..clear()
        ..addAll(list);
    } else {
      _presets.addAll([
        AllowancePreset(name: '交通費', unitPrice: 500, perHour: false),
        AllowancePreset(name: '深夜手当(時給)', unitPrice: 300, perHour: true),
      ]);
    }
    useConfigTimes = sp.getBool(kUseConfigTimesKey) ?? true;
    configStartMin = sp.getInt(kConfigStartKey) ?? 9 * 60;
    configEndMin = sp.getInt(kConfigEndKey) ?? 18 * 60;
    useConfigBreak = sp.getBool(kUseConfigBreakKey) ?? true;
    configBreakMin = sp.getInt(kConfigBreakKey) ?? 60;
    overtimeAuto = sp.getBool(kOvertimeAutoKey) ?? true;
    cycleStartDay = sp.getInt(kCycleStartKey) ?? 1;
    cycleEndDay = sp.getInt(kCycleEndKey) ?? 31;
    reportName = sp.getString(kReportNameKey) ?? '';
    _rebuildHolidayCache();
    notifyListeners();
  }

  Future<void> _saveRecords() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
        kRecordsKey, jsonEncode(_records.map((e) => e.toJson()).toList()));
  }

  Future<void> _savePresets() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
        kPresetKey, jsonEncode(_presets.map((e) => e.toJson()).toList()));
  }

  Future<void> _saveSettings() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(kUseConfigTimesKey, useConfigTimes);
    await sp.setInt(kConfigStartKey, configStartMin);
    await sp.setInt(kConfigEndKey, configEndMin);
    await sp.setBool(kUseConfigBreakKey, useConfigBreak);
    await sp.setInt(kConfigBreakKey, configBreakMin);
    await sp.setBool(kOvertimeAutoKey, overtimeAuto);
    await sp.setInt(kCycleStartKey, cycleStartDay);
    await sp.setInt(kCycleEndKey, cycleEndDay);
    await sp.setString(kReportNameKey, reportName);
  }

  Future<void> addRecord(WorkRecord r) async {
    _records.removeWhere((e) =>
    e.date.year == r.date.year &&
        e.date.month == r.date.month &&
        e.date.day == r.date.day);
    _records.add(r);
    await _saveRecords();
    notifyListeners();
  }

  Future<void> deleteRecord(WorkRecord r) async {
    _records.remove(r);
    await _saveRecords();
    notifyListeners();
  }

  Future<void> upsertPreset(AllowancePreset p) async {
    final idx = _presets.indexWhere((e) => e.name == p.name);
    if (idx >= 0) {
      _presets[idx] = p;
    } else {
      _presets.add(p);
    }
    await _savePresets();
    notifyListeners();
  }

  Future<void> deletePreset(String name) async {
    _presets.removeWhere((e) => e.name == name);
    await _savePresets();
    notifyListeners();
  }

  Future<void> updateSettings({
    bool? useConfigTimes_,
    int? startMin_,
    int? endMin_,
    bool? useConfigBreak_,
    int? breakMin_,
    bool? overtimeAuto_,
    int? cycleStart_,
    int? cycleEnd_,
    String? reportName_,
  }) async {
    if (useConfigTimes_ != null) useConfigTimes = useConfigTimes_;
    if (startMin_ != null) configStartMin = startMin_;
    if (endMin_ != null) configEndMin = endMin_;
    if (useConfigBreak_ != null) useConfigBreak = useConfigBreak_;
    if (breakMin_ != null) configBreakMin = breakMin_;
    if (overtimeAuto_ != null) overtimeAuto = overtimeAuto_;
    if (cycleStart_ != null) cycleStartDay = cycleStart_;
    if (cycleEnd_ != null) cycleEndDay = cycleEnd_;
    if (reportName_ != null) reportName = reportName_;
    await _saveSettings();
    notifyListeners();
  }

  (DateTime start, DateTime end) currentCycleRange(DateTime anchor) {
    DateTime norm(DateTime d) => DateTime(d.year, d.month, d.day);
    int lastDay(int y, int m) => DateTime(y, m + 1, 0).day;

    final y = anchor.year;
    final m = anchor.month;

    final startThis = DateTime(y, m, cycleStartDay.clamp(1, lastDay(y, m)));
    final endThis = DateTime(y, m, cycleEndDay.clamp(1, lastDay(y, m)));

    if (cycleEndDay >= cycleStartDay) {
      final start = startThis;
      final end = endThis;
      if (anchor.isBefore(start)) {
        final py = m == 1 ? y - 1 : y;
        final pm = m == 1 ? 12 : m - 1;
        final pStart =
        DateTime(py, pm, cycleStartDay.clamp(1, lastDay(py, pm)));
        final pEnd = DateTime(py, pm, cycleEndDay.clamp(1, lastDay(py, pm)));
        return (norm(pStart), norm(pEnd));
      } else if (anchor.isAfter(end)) {
        final ny = m == 12 ? y + 1 : y;
        final nm = m == 12 ? 1 : m + 1;
        final nStart =
        DateTime(ny, nm, cycleStartDay.clamp(1, lastDay(ny, nm)));
        final nEnd = DateTime(ny, nm, cycleEndDay.clamp(1, lastDay(ny, nm)));
        return (norm(nStart), norm(nEnd));
      } else {
        return (norm(start), norm(end));
      }
    } else {
      final start = anchor.day >= cycleStartDay
          ? startThis
          : DateTime(y, m == 1 ? 12 : m - 1,
          cycleStartDay.clamp(1, lastDay(y, m == 1 ? 12 : m - 1)));
      final end = anchor.day >= cycleStartDay
          ? DateTime(y, m + 1, cycleEndDay.clamp(1, lastDay(y, m + 1)))
          : endThis;
      return (norm(start), norm(end));
    }
  }

  List<WorkRecord> recordsIn(DateTime from, DateTime to) {
    final f = DateTime(from.year, from.month, from.day);
    final t = DateTime(to.year, to.month, to.day, 23, 59, 59, 999);
    return records
        .where((r) =>
    r.date.isAfter(f.subtract(const Duration(milliseconds: 1))) &&
        r.date.isBefore(t.add(const Duration(milliseconds: 1))))
        .toList();
  }

  void _rebuildHolidayCache() {
    _holidayNameCache.clear();
    for (int y = 2000; y <= 2099; y++) {
      _holidayNameCache.addAll(buildJapaneseHolidays(y));
    }
  }

  bool isJapaneseHoliday(DateTime d) {
    final key = DateTime(d.year, d.month, d.day);
    return _holidayNameCache.containsKey(key);
  }

  String? holidayName(DateTime d) {
    final key = DateTime(d.year, d.month, d.day);
    return _holidayNameCache[key];
  }
}

// =======================
// 画面ルート（タブ + 常時バナー）
// =======================
class HomeRoot extends StatefulWidget {
  const HomeRoot({super.key});
  @override
  State<HomeRoot> createState() => _HomeRootState();
}

class _HomeRootState extends State<HomeRoot> {
  int _idx = 0;
  late final Store _store;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _store = Store();
    _store.load(); // 非同期ロード
    _pages = [
      CalendarTabPage(store: _store), // 入力
      ListTabPage(store: _store),     // リスト
      SettingsTabPage(store: _store), // 設定
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('出勤簿')),
      body: IndexedStack(index: _idx, children: _pages),

      // バナーを「bottomNavigationBar」に統合して常時表示
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AdBanner(height: 50), // ← 常時表示
          NavigationBar(
            selectedIndex: _idx,
            onDestinationSelected: (i) => setState(() => _idx = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.edit_calendar), label: '入力'),
              NavigationDestination(icon: Icon(Icons.list_alt), label: 'リスト'),
              NavigationDestination(icon: Icon(Icons.settings), label: '設定'),
            ],
          ),
        ],
      ),
    );
  }
}

// =======================
// 入力タブ（マーカー付きカレンダー）
// =======================
class CalendarTabPage extends StatefulWidget {
  final Store store;
  const CalendarTabPage({super.key, required this.store});
  @override
  State<CalendarTabPage> createState() => _CalendarTabPageState();
}

class _CalendarTabPageState extends State<CalendarTabPage> {
  DateTime _focused = DateTime.now();
  DateTime? _selected;

  Future<void> _openEditorFor(DateTime day) async {
    final d = DateTime(day.year, day.month, day.day);
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EditRecordPage(store: widget.store, date: d)),
    );
    if (mounted) setState(() {}); // 戻ったら再描画
  }

  /// その日のレコード一覧（TableCalendar の eventLoader 用）
  List<WorkRecord> _eventsForDay(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return widget.store.records
        .where((r) => r.date.year == d.year && r.date.month == d.month && r.date.day == d.day)
        .toList();
  }

  Widget _buildCalendar() {
    return TableCalendar<WorkRecord>(
      locale: 'ja_JP',
      startingDayOfWeek: StartingDayOfWeek.sunday,
      firstDay: DateTime.utc(2000, 1, 1),
      lastDay: DateTime.utc(2100, 12, 31),
      focusedDay: _focused,
      selectedDayPredicate: (day) => isSameDay(_selected, day),
      onDaySelected: (selectedDay, focusedDay) {
        setState(() {
          _selected = selectedDay;
          _focused  = focusedDay;
        });
      },
      onDayLongPressed: (selectedDay, focusedDay) {
        _selected = selectedDay;
        _focused  = focusedDay;
        _openEditorFor(selectedDay); // 長押しでその日の編集へ
      },
      onPageChanged: (focusedDay) {
        _focused = focusedDay; // setState不要（TableCalendar 推奨）
      },
      headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
      calendarStyle: const CalendarStyle(outsideDaysVisible: true),

      // === ここでイベント(=その日のレコード)を渡す ===
      eventLoader: _eventsForDay,

      // === マーカーの描画 ===
      calendarBuilders: CalendarBuilders<WorkRecord>(
        markerBuilder: (context, day, events) {
          if (events.isEmpty) return const SizedBox.shrink();

          final recs   = events.cast<WorkRecord>();
          final hasOff = recs.any((r) => r.isOff);
          final hasWork = recs.any((r) => !r.isOff && r.workedMinutes() > 0);

          final dots = <Widget>[];
          if (hasWork) {
            dots.add(_dot(color: Colors.green));
          }
          if (hasOff) {
            dots.add(_dot(color: Colors.orange));
          }
          if (dots.isEmpty) return const SizedBox.shrink();

          return Positioned(
            bottom: 4,
            child: Row(mainAxisSize: MainAxisSize.min, children: dots),
          );
        },
      ),
    );
  }

  Widget _dot({required Color color}) {
    return Container(
      width: 6, height: 6,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (_, __) {
        final day = _selected ?? _focused;
        return Scaffold(
          body: Column(
            children: [
              _buildCalendar(),
              const Divider(height: 1),
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: _DayRecordList(
                        day: day,
                        store: widget.store,
                        onAddOrEdit: () => setState(() {}),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // 選択日の編集を開く
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openEditorFor(day),
            icon: const Icon(Icons.edit),
            label: Text('${DateFormat('M/d', 'ja_JP').format(day)} に入力'),
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        );
      },
    );
  }
}

// =======================
// 選択日のレコード一覧
// =======================
class _DayRecordList extends StatelessWidget {
  const _DayRecordList({
    super.key,
    required this.day,
    required this.store,
    required this.onAddOrEdit,
  });

  final DateTime day;
  final Store store;
  final VoidCallback onAddOrEdit;

  @override
  Widget build(BuildContext context) {
    final d = DateTime(day.year, day.month, day.day);
    final recs = store.records
        .where((r) => r.date.year == d.year && r.date.month == d.month && r.date.day == d.day)
        .toList()
      ..sort((a, b) {
        final as = a.startMin, bs = b.startMin;
        if (as == null && bs == null) return 0;
        if (as == null) return 1;
        if (bs == null) return -1;
        return as.compareTo(bs);
      });

    if (recs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('この日の勤務はありません')),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: recs.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (c, i) {
        final r = recs[i];
        final startStr = r.startMin != null ? _hm(r.startMin) : '-';
        final endStr   = r.endMin   != null ? _hm(r.endMin)   : '-';
        final title    = '$startStr – $endStr${(r.breakMin) > 0 ? '（休憩 ${r.breakMin} 分）' : ''}';
        final sub      = '実働 ${formatMinutes(r.workedMinutes())}'
            ' / 残業 ${formatMinutes(r.overtimeMinutes(auto: store.overtimeAuto))}';

        return ListTile(
          title: Text(title),
          subtitle: Text(sub),
          isThreeLine: (r.memo?.isNotEmpty ?? false),
          onTap: () async {
            await Navigator.of(c).push(
              MaterialPageRoute(builder: (_) => EditRecordPage(store: store, initial: r)),
            );
            onAddOrEdit();
          },
        );
      },
    );
  }
}

// =======================
// リストタブ（期間サマリ＋一覧）
// =======================
class ListTabPage extends StatefulWidget {
  final Store store;
  const ListTabPage({super.key, required this.store});
  @override
  State<ListTabPage> createState() => _ListTabPageState();
}

class _ListTabPageState extends State<ListTabPage> {
  DateTime _anchor = DateTime.now();
  (DateTime, DateTime) get _range => widget.store.currentCycleRange(_anchor);

  List<WorkRecord> get _list {
    final (s, e) = _range;
    return widget.store.recordsIn(s, e);
  }

  // —— 期間移動を安定させるための共通処理（±15日ずつ動かし、"別の期間"に入るまで進む）
  void _jumpPeriod(int dir /* -1:前 / +1:次 */) {
    final (curS, curE) = _range;
    DateTime a = _anchor;
    // 最大6ステップ（約3ヶ月分）で別期間に入るまで移動
    for (int i = 0; i < 6; i++) {
      a = a.add(Duration(days: 15 * dir));
      final (ns, ne) = widget.store.currentCycleRange(a);
      // 期間が変わったら確定
      if (ns != curS || ne != curE) {
        setState(() => _anchor = a);
        return;
      }
    }
    // それでも変わらなければ大きくジャンプ（フォールバック）
    setState(() => _anchor = dir > 0 ? curE.add(const Duration(days: 40))
        : curS.subtract(const Duration(days: 40)));
  }

  void _goPrevPeriod() => _jumpPeriod(-1);
  void _goNextPeriod() => _jumpPeriod(1);

  @override
  Widget build(BuildContext context) {
    final (s, e) = _range;
    final title =
        '${DateFormat('yyyy/MM/dd', 'ja_JP').format(s)} 〜 ${DateFormat('yyyy/MM/dd', 'ja_JP').format(e)}';

    final workDays = _list.where((r) => !r.isOff && r.workedMinutes() > 0).length;
    final workTotal = _list.fold<int>(0, (p, r) => p + r.workedMinutes());
    final overTotal =
    _list.fold<int>(0, (p, r) => p + r.overtimeMinutes(auto: widget.store.overtimeAuto));
    final allowanceTotal = _list.fold<int>(0, (p, r) => p + r.allowanceTotal());

    return Column(
      children: [
        ListTile(
          title: Text('対象期間：$title'),
          trailing: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: '前の期間',
                onPressed: _goPrevPeriod,
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: '次の期間',
                onPressed: _goNextPeriod,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _chip('出勤日数', '$workDays 日'),
              _chip('実働合計', formatMinutes(workTotal)),
              _chip('残業合計', formatMinutes(overTotal)),
              _chip('手当計', _yen(allowanceTotal)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.ios_share),
              label: const Text('CSV 共有'),
              onPressed: () => _shareCsv(s, e),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('PDF 印刷'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PdfPreview(
                      build: (format) => _buildPeriodPdf(s, e),
                      initialPageFormat: PdfPageFormat.a4,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Divider(height: 24),
        Expanded(
          child: ListView.separated(
            itemCount: _list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (c, i) {
              final r = _list[i];
              final title = r.isOff
                  ? '${DateFormat('M/d(EEE)', 'ja_JP').format(r.date)}  休日'
                  : '${DateFormat('M/d(EEE)', 'ja_JP').format(r.date)}  ${_hm(r.startMin)}-${_hm(r.endMin)}  休憩${formatMinutes(r.breakMin)}';
              final sub =
                  '実働 ${formatMinutes(r.workedMinutes())} / 残業 ${formatMinutes(r.overtimeMinutes(auto: widget.store.overtimeAuto))} / 手当 ${_yen(r.allowanceTotal())}${r.memo?.isNotEmpty == true ? '\n${r.memo}' : ''}';
              return ListTile(
                title: Text(title),
                subtitle: Text(sub),
                isThreeLine: r.memo?.isNotEmpty == true,
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => EditRecordPage(store: widget.store, initial: r),
                    ),
                  );
                  if (!mounted) return;
                  setState(() {}); // 編集後更新
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, String value) {
    return Chip(
      label: Text('$label  $value'),
      side: BorderSide(color: Colors.grey.shade300),
    );
  }

  Future<void> _shareCsv(DateTime from, DateTime to) async {
    final list = widget.store.recordsIn(from, to);
    String esc(String s) {
      if (s.contains(',') || s.contains('"') || s.contains('\n')) {
        return '"${s.replaceAll('"', '""')}"';
      }
      return s;
    }

    final rows = <List<String>>[
      ['日付', '出勤', '退勤', '休憩', '実働', '残業', '手当', 'メモ', '休日?'],
      ...list.map((r) {
        return [
          DateFormat('yyyy-MM-dd').format(r.date),
          r.startMin != null ? _hm(r.startMin) : '',
          r.endMin != null ? _hm(r.endMin) : '',
          formatMinutes(r.breakMin),
          formatMinutes(r.workedMinutes()),
          formatMinutes(r.overtimeMinutes(auto: widget.store.overtimeAuto)),
          _yen(r.allowanceTotal()),
          r.memo ?? '',
          r.isOff ? '休日' : '',
        ].map((s) => esc(s)).toList();
      }),
    ];

    final csv = rows.map((r) => r.join(',')).join('\n');
    final name =
        '出勤簿_${DateFormat('yyyyMMdd').format(from)}-${DateFormat('yyyyMMdd').format(to)}.csv';
    await Share.share(csv, subject: name);
  }

  Future<Uint8List> _buildPeriodPdf(DateTime from, DateTime to) async {
    double mm(double v) => v * PdfPageFormat.mm;

    final doc = pw.Document();
    final fontData = await rootBundle.load('assets/fonts/NotoSansJP-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/NotoSansJP-Bold.ttf');
    final font = pw.Font.ttf(fontData);
    final bold = pw.Font.ttf(boldData);

    final list = widget.store.recordsIn(from, to);
    final days = list.where((r) => !r.isOff && r.workedMinutes() > 0).length;
    final workTotal = list.fold<int>(0, (p, r) => p + r.workedMinutes());
    final overTotal =
    list.fold<int>(0, (p, r) => p + r.overtimeMinutes(auto: widget.store.overtimeAuto));
    final allowanceTotal = list.fold<int>(0, (p, r) => p + r.allowanceTotal());

    final headerStyle = pw.TextStyle(font: bold, fontSize: 18);
    final subStyle = pw.TextStyle(font: font, fontSize: 11);
    final th = pw.TextStyle(font: bold, fontSize: 11);
    final td = pw.TextStyle(font: font, fontSize: 10);

    doc.addPage(
      pw.MultiPage(
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${ctx.pageNumber}/${ctx.pagesCount}',
            style: pw.TextStyle(font: font, fontSize: 10),
          ),
        ),
        build: (ctx) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('出勤簿', style: headerStyle),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('氏名：', style: subStyle),
                  pw.Container(
                    width: mm(50),
                    padding: const pw.EdgeInsets.only(bottom: 2),
                    decoration: pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(width: 0.7, color: PdfColors.grey700),
                      ),
                    ),
                    child: pw.Text(
                      widget.store.reportName,
                      style: subStyle,
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                    ),
                  ),
                  pw.SizedBox(width: mm(8)),
                  pw.Text('印：', style: subStyle),
                  pw.Container(
                    width: mm(18), height: mm(18),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(width: 1.2, color: PdfColors.black),
                    ),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.SizedBox(width: 1),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    '対象期間  ${DateFormat('yyyy/MM/dd').format(from)} 〜 ${DateFormat('yyyy/MM/dd').format(to)}',
                    style: subStyle,
                  ),
                  pw.Text('出勤日数  $days 日', style: subStyle),
                  pw.Text('実働合計  ${formatMinutes(workTotal)}', style: subStyle),
                  pw.Text('残業合計  ${formatMinutes(overTotal)}', style: subStyle),
                  pw.Text('手当計    ${_yen(allowanceTotal)}', style: subStyle),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Table.fromTextArray(
            cellStyle: td,
            headerStyle: th,
            headerDecoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFE0E0E0)),
            cellAlignment: pw.Alignment.centerLeft,
            headerAlignment: pw.Alignment.centerLeft,
            data: <List<String>>[
              ['日付', '出勤', '退勤', '休憩', '実働', '残業', '手当', 'メモ', '休日?'],
              ...list.map((r) {
                return [
                  DateFormat('yyyy/MM/dd (E)', 'ja_JP').format(r.date),
                  r.startMin != null ? _hm(r.startMin) : '',
                  r.endMin != null ? _hm(r.endMin) : '',
                  formatMinutes(r.breakMin),
                  formatMinutes(r.workedMinutes()),
                  formatMinutes(r.overtimeMinutes(auto: widget.store.overtimeAuto)),
                  _yen(r.allowanceTotal()),
                  r.memo ?? '',
                  r.isOff ? '休日' : '',
                ];
              })
            ],
          ),
        ],
      ),
    );
    return doc.save();
  }
}

/// =======================
/// 設定タブ
/// =======================
class SettingsTabPage extends StatelessWidget {
  final Store store;
  const SettingsTabPage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const _SectionHeader('勤務項目'),
          _SwitchTile(
            title: '固定の時刻を使用する',
            value: store.useConfigTimes,
            onChanged: (v) => store.updateSettings(useConfigTimes_: v),
          ),
          _PickerTile(
            title: '出勤時刻',
            value: _hm(store.configStartMin),
            onTap: () async {
              final m = await pickTimeMinutes(context, store.configStartMin);
              if (m != null) {
                final end = store.configEndMin;
                await store.updateSettings(startMin_: m);
                if (m >= end) {
                  await store
                      .updateSettings(endMin_: (m + 60).clamp(0, 1439));
                }
              }
            },
          ),
          _PickerTile(
            title: '退勤時刻',
            value: _hm(store.configEndMin),
            onTap: () async {
              final m = await pickTimeMinutes(context, store.configEndMin);
              if (m != null) {
                await store.updateSettings(endMin_: m);
              }
            },
          ),
          _SwitchTile(
            title: '固定の休憩時間を使用する',
            value: store.useConfigBreak,
            onChanged: (v) => store.updateSettings(useConfigBreak_: v),
          ),
          _PickerTile(
            title: '休憩時間',
            value: '${store.configBreakMin} 分',
            onTap: () async {
              final v = await pickDurationMinutes(context,
                  title: '休憩（分）', initial: store.configBreakMin);
              if (v != null) {
                await store.updateSettings(breakMin_: v);
              }
            },
          ),
          const Divider(),
          const _SectionHeader('PDF項目'),
          ListTile(
            title: const Text('PDF氏名（印字）'),
            subtitle: Text(
              store.reportName.isEmpty
                  ? '未設定（空欄として下線のみ）'
                  : store.reportName,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final v = await _editTextDialog(context,
                  title: 'PDFに印字する氏名', initial: store.reportName);
              if (v != null) {
                await store.updateSettings(reportName_: v);
              }
            },
          ),
          const Divider(),
          const _SectionHeader('残業項目'),
          _SwitchTile(
            title: '残業：自動計算（8時間超過分）',
            subtitle: 'OFFにすると、各勤務で手動入力',
            value: store.overtimeAuto,
            onChanged: (v) => store.updateSettings(overtimeAuto_: v),
          ),
          const Divider(),
          const _SectionHeader('締め日サイクル'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _NumberPickerChip(
                  label: '開始日',
                  value: store.cycleStartDay,
                  onTap: () async {
                    final v = await pickDayOfMonth(
                        context, store.cycleStartDay);
                    if (v != null) store.updateSettings(cycleStart_: v);
                  },
                ),
                _NumberPickerChip(
                  label: '締め日',
                  value: store.cycleEndDay,
                  onTap: () async {
                    final v =
                    await pickDayOfMonth(context, store.cycleEndDay);
                    if (v != null) store.updateSettings(cycleEnd_: v);
                  },
                ),
                Text(
                  '※ 例：開始26 / 締め25 は月跨ぎサイクルになります',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Divider(),
          const _SectionHeader('広告'),
          ListTile(
            leading: const Icon(Icons.bug_report),
            title: const Text('広告診断（Ad Inspector）を開く'),
            subtitle: const Text('テスト端末ではテスト広告が出ます'),
            onTap: () async {
              MobileAds.instance.openAdInspector((error) {
                final msg = (error == null)
                    ? 'Ad Inspector を開きました'
                    : 'Inspector エラー: ${error.message} (code: ${error.code})';
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(msg)));
              });
            },
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// =======================
// 勤務編集
// =======================
class EditRecordPage extends StatefulWidget {
  final Store store;
  final DateTime? date;
  final WorkRecord? initial;
  const EditRecordPage({super.key, required this.store, this.date, this.initial})
      : assert((date != null) ^ (initial != null));

  @override
  State<EditRecordPage> createState() => _EditRecordPageState();
}

class _EditRecordPageState extends State<EditRecordPage> {
  late DateTime _date;
  int? _start;
  int? _end;
  int _break = 0;
  int? _manualOver;
  bool _isOff = false;
  final _memoCtl = TextEditingController();
  final List<Allowance> _allowances = [];

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      final r = widget.initial!;
      _date = DateTime(r.date.year, r.date.month, r.date.day);
      _start = r.startMin;
      _end = r.endMin;
      _break = r.breakMin;
      _manualOver = r.manualOverMin;
      _isOff = r.isOff;
      _memoCtl.text = r.memo ?? '';
      _allowances.addAll(r.allowances);
    } else {
      _date = DateTime(widget.date!.year, widget.date!.month, widget.date!.day);
      if (widget.store.useConfigTimes) {
        _start = widget.store.configStartMin;
        _end = widget.store.configEndMin;
      }
      if (widget.store.useConfigBreak) {
        _break = widget.store.configBreakMin;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy/MM/dd (E)', 'ja_JP');
    final bottomPad = MediaQuery.of(context).viewInsets.bottom; // ← キーボード分の余白
    return Scaffold(
      appBar: AppBar(
        title: Text('${fmt.format(_date)} の勤務'),
        actions: [TextButton(onPressed: _save, child: const Text('保存'))],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottomPad),
        children: [
          SwitchListTile(
            title: const Text('休日として登録'),
            value: _isOff,
            onChanged: (v) => setState(() => _isOff = v),
          ),
          if (!_isOff) ...[
            _TimeField(
              label: '出勤',
              value: _start,
              onTap: () async {
                final v = await pickTimeMinutes(context, _start ?? 9 * 60);
                if (v != null) setState(() => _start = v);
              },
            ),
            _TimeField(
              label: '退勤',
              value: _end,
              onTap: () async {
                final v = await pickTimeMinutes(context, _end ?? 18 * 60);
                if (v != null) setState(() => _end = v);
              },
            ),
            _DurationField(
              label: '休憩（分）',
              value: _break,
              step: 15,
              onChanged: (v) => setState(() => _break = v),
            ),
            if (!widget.store.overtimeAuto)
              _DurationField(
                label: '残業（分・手動）',
                value: _manualOver ?? 0,
                step: 15,
                onChanged: (v) => setState(() => _manualOver = v),
              ),
          ],
          const Divider(),
          ListTile(
            title: const Text('手当'),
            subtitle: Text(
              _allowances.isEmpty
                  ? 'なし'
                  : _allowances
                  .map((a) => a.perHour
                  ? '${a.name}:${a.unitPrice}円/時 × ${a.minutes ?? 0}分'
                  : '${a.name}:${a.unitPrice}円')
                  .join(' / '),
            ),
            trailing: FilledButton.tonalIcon(
              icon: const Icon(Icons.playlist_add),
              label: const Text('手当を選ぶ'),
              onPressed: () => _chooseAllowance(),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _allowances
                .asMap()
                .entries
                .map(
                  (e) => InputChip(
                label: Text(e.value.perHour
                    ? '${e.value.name} ${e.value.unitPrice}円/時 ${e.value.minutes ?? 0}分'
                    : '${e.value.name} ${e.value.unitPrice}円'),
                onDeleted: () =>
                    setState(() => _allowances.removeAt(e.key)),
              ),
            )
                .toList(),
          ),
          const SizedBox(height: 8),
          ListTile(
            title: const Text('メモ'),
            subtitle: TextField(
              controller: _memoCtl,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: '任意',
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseAllowance() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) {
        return AnimatedBuilder(
          animation: widget.store,
          builder: (_, __) => Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                const Text('プリセットから選択',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                ...widget.store.presets.map((p) {
                  return ListTile(
                    title: Text(p.name),
                    subtitle: Text(
                        p.perHour ? '${p.unitPrice}円/時' : '${p.unitPrice}円/回'),
                    trailing: FilledButton(
                      onPressed: () async {
                        if (p.perHour) {
                          final m = await pickDurationMinutes(context,
                              title: '時間（分）', initial: 60);
                          if (m != null) {
                            setState(() => _allowances.add(Allowance(
                                name: p.name,
                                unitPrice: p.unitPrice,
                                perHour: true,
                                minutes: m)));
                          }
                        } else {
                          setState(() => _allowances.add(Allowance(
                              name: p.name,
                              unitPrice: p.unitPrice,
                              perHour: false)));
                        }
                        if (mounted) Navigator.pop(c);
                      },
                      child: const Text('追加'),
                    ),
                  );
                }),
                const Divider(),
                ListTile(
                  title: const Text('新しい手当を直接追加'),
                  trailing: const Icon(Icons.add),
                  onTap: () async {
                    final a = await _editAllowanceDialog(context);
                    if (a != null) {
                      setState(() => _allowances.add(a));
                      if (mounted) Navigator.pop(c);
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<Allowance?> _editAllowanceDialog(BuildContext ctx) async {
    final nameCtl = TextEditingController();
    final priceCtl = TextEditingController(text: '0');
    bool perHour = false;
    int minutes = 60;

    return showDialog<Allowance>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('手当を追加'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameCtl,
                decoration: const InputDecoration(labelText: '名称')),
            TextField(
              controller: priceCtl,
              decoration: const InputDecoration(labelText: '金額（円）'),
              keyboardType: TextInputType.number,
            ),
            SwitchListTile(
              value: perHour,
              onChanged: (v) => perHour = v,
              title: const Text('時間単価（円/時）'),
              contentPadding: EdgeInsets.zero,
            ),
            if (perHour)
              _DurationField(
                label: '時間（分）',
                value: minutes,
                step: 15,
                onChanged: (v) => minutes = v,
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () {
                final name = nameCtl.text.trim();
                final price = int.tryParse(priceCtl.text.trim()) ?? 0;
                if (name.isEmpty) return;
                Navigator.pop(
                  c,
                  Allowance(
                    name: name,
                    unitPrice: price,
                    perHour: perHour,
                    minutes: perHour ? minutes : null,
                  ),
                );
              },
              child: const Text('追加')),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_isOff) {
      if (_start == null || _end == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('出勤/退勤を入力してください')));
        return;
      }
    }
    final r = WorkRecord(
      date: _date,
      startMin: _isOff ? null : _start,
      endMin: _isOff ? null : _end,
      breakMin: _isOff ? 0 : _break,
      manualOverMin: _isOff ? 0 : (_manualOver ?? 0),
      allowances: List.of(_allowances),
      memo: _memoCtl.text.trim().isEmpty ? null : _memoCtl.text.trim(),
      isOff: _isOff,
    );
    await widget.store.addRecord(r);
    if (!mounted) return;
    Navigator.pop(context);
  }
}

/// =======================
/// 共通UI
/// =======================
class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchTile(
      {required this.title, this.subtitle, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
    );
  }
}

class _PickerTile extends StatelessWidget {
  final String title;
  final String value;
  final VoidCallback onTap;
  const _PickerTile({required this.title, required this.value, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _NumberPickerChip extends StatelessWidget {
  final String label;
  final int value;
  final VoidCallback onTap;
  const _NumberPickerChip({required this.label, required this.value, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return ActionChip(label: Text('$label: $value 日'), onPressed: onTap);
  }
}

class _TimeField extends StatelessWidget {
  final String label;
  final int? value;
  final VoidCallback onTap;
  const _TimeField({required this.label, required this.value, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value == null ? '-' : _hm(value),
              style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
          const SizedBox(width: 8),
          const Icon(Icons.schedule),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _DurationField extends StatelessWidget {
  final String label;
  final int value;
  final int step;
  final ValueChanged<int> onChanged;
  const _DurationField(
      {required this.label, required this.value, this.step = 15, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      subtitle: Text(formatMinutes(value)),
      trailing: Wrap(
        spacing: 8,
        children: [
          IconButton(
              onPressed: () => onChanged((value - step).clamp(0, 24 * 60)),
              icon: const Icon(Icons.remove)),
          IconButton(
              onPressed: () => onChanged((value + step).clamp(0, 24 * 60)),
              icon: const Icon(Icons.add)),
        ],
      ),
    );
  }
}

Future<String?> _editTextDialog(BuildContext context,
    {required String title, String initial = ''}) async {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content:
      TextField(controller: ctl, decoration: const InputDecoration(hintText: '氏名')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('キャンセル')),
        FilledButton(
            onPressed: () => Navigator.pop(c, ctl.text.trim()),
            child: const Text('保存')),
      ],
    ),
  );
}

/// =======================
/// ピッカー
/// =======================
Future<int?> pickTimeMinutes(BuildContext context, int initial) async {
  int h = (initial ~/ 60) % 24;
  int m = initial % 60;
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (c) {
      return SizedBox(
        height: 280,
        child: Row(
          children: [
            Expanded(
              child: CupertinoPicker(
                itemExtent: 36,
                scrollController: FixedExtentScrollController(initialItem: h),
                onSelectedItemChanged: (v) => h = v,
                children: [for (int i = 0; i < 24; i++) Center(child: Text('$i 時'))],
              ),
            ),
            Expanded(
              child: CupertinoPicker(
                itemExtent: 36,
                scrollController: FixedExtentScrollController(initialItem: m),
                onSelectedItemChanged: (v) => m = v,
                children: [for (int i = 0; i < 60; i++) Center(child: Text('$i 分'))],
              ),
            ),
          ],
        ),
      );
    },
  ).then((_) => h * 60 + m);
}

Future<int?> pickDurationMinutes(BuildContext context,
    {required String title, int initial = 60}) async {
  int v = (initial.clamp(0, 24 * 60));
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (c) {
      return SizedBox(
        height: 280,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            Expanded(
              child: CupertinoPicker(
                itemExtent: 36,
                scrollController: FixedExtentScrollController(initialItem: v),
                onSelectedItemChanged: (i) => v = i,
                children: [
                  for (int i = 0; i <= 240; i++) Center(child: Text('$i 分'))
                ],
              ),
            ),
          ],
        ),
      );
    },
  ).then((_) => v);
}

Future<int?> pickDayOfMonth(BuildContext context, int initial) async {
  int v = (initial.clamp(1, 31));
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (c) {
      return SizedBox(
        height: 280,
        child: CupertinoPicker(
          itemExtent: 36,
          scrollController: FixedExtentScrollController(initialItem: v - 1),
          onSelectedItemChanged: (i) => v = i + 1,
          children: [for (int i = 1; i <= 31; i++) Center(child: Text('$i 日'))],
        ),
      );
    },
  ).then((_) => v);
}

/// =======================
/// ユーティリティ
/// =======================
String _hm(int? m) {
  if (m == null) return '-';
  final h = (m ~/ 60).toString().padLeft(2, '0');
  final mm = (m % 60).toString().padLeft(2, '0');
  return '$h:$mm';
}

String formatMinutes(int m) {
  final h = m ~/ 60;
  final mm = m % 60;
  if (h == 0) return '${mm}分';
  if (mm == 0) return '${h}時間';
  return '${h}時間${mm}分';
}

String _yen(int v) =>
    NumberFormat.currency(locale: 'ja_JP', symbol: '¥').format(v);

Map<DateTime, String> buildJapaneseHolidays(int year) {
  final Map<DateTime, String> m = {};
  DateTime d(int y, int mo, int da) => DateTime(y, mo, da);
  void addFix(int mo, int da, String name) => m[d(year, mo, da)] = name;

  addFix(1, 1, '元日');
  addFix(2, 11, '建国記念の日');
  addFix(2, 23, '天皇誕生日');
  addFix(4, 29, '昭和の日');
  addFix(5, 3, '憲法記念日');
  addFix(5, 4, 'みどりの日');
  addFix(5, 5, 'こどもの日');
  addFix(11, 3, '文化の日');
  addFix(11, 23, '勤労感謝の日');

  int shunbunDay(int y) =>
      (20.8431 + 0.242194 * (y - 1980) - ((y - 1980) / 4).floor()).floor();
  int shubunDay(int y) =>
      (23.2488 + 0.242194 * (y - 1980) - ((y - 1980) / 4).floor()).floor();
  m[d(year, 3, shunbunDay(year))] = '春分の日';
  m[d(year, 9, shubunDay(year))] = '秋分の日';

  DateTime nthMonday(int month, int n) {
    var dt = d(year, month, 1);
    while (dt.weekday != DateTime.monday) {
      dt = dt.add(const Duration(days: 1));
    }
    return dt.add(Duration(days: 7 * (n - 1)));
  }

  m[nthMonday(1, 2)] = '成人の日';
  m[nthMonday(7, 3)] = '海の日';
  m[nthMonday(9, 3)] = '敬老の日';
  m[nthMonday(10, 2)] = 'スポーツの日';

  if (year >= 2016) m[d(year, 8, 11)] = '山の日';

  final keys = m.keys.toList()..sort();
  for (final k in keys) {
    if (k.weekday == DateTime.sunday) {
      var sub = k.add(const Duration(days: 1));
      while (m.containsKey(sub)) {
        sub = sub.add(const Duration(days: 1));
      }
      m[sub] = '振替休日';
    }
  }

  final sorted = m.keys.toList()..sort();
  for (int i = 0; i < sorted.length - 1; i++) {
    final a = sorted[i];
    final b = sorted[i + 1];
    if (b.difference(a).inDays == 2) {
      final mid = a.add(const Duration(days: 1));
      if (!m.containsKey(mid) && mid.weekday != DateTime.sunday) {
        m[mid] = '国民の休日';
      }
    }
  }
  return m;
}
