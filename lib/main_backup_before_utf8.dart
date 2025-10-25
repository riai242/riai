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

// 蠎・相
import 'ads_init.dart';
import 'ads_ids.dart';
import 'widgets/ad_banner.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ja_JP');
  await initAds(); // 蠎・相蛻晄悄蛹・
  runApp(const ShukkinboApp());
}

class ShukkinboApp extends StatelessWidget {
  const ShukkinboApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '蜃ｺ蜍､邁ｿ',
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
/// 繝・・繧ｿ繝｢繝・Ν
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
/// 繧ｹ繝医い
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
        AllowancePreset(name: '莠､騾夊ｲｻ', unitPrice: 500, perHour: false),
        AllowancePreset(name: '豺ｱ螟懈焔蠖・譎らｵｦ)', unitPrice: 300, perHour: true),
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

/// =======================
/// 逕ｻ髱｢繝ｫ繝ｼ繝茨ｼ医ち繝厄ｼ・
/// =======================
class HomeRoot extends StatefulWidget {
  const HomeRoot({super.key});
  @override
  State<HomeRoot> createState() => _HomeRootState();
}

class _HomeRootState extends State<HomeRoot> {
  int _idx = 0;
  late final Store _store;

  @override
  void initState() {
    super.initState();
    _store = Store()..load();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      CalendarTabPage(store: _store),
      ListTabPage(store: _store),
      SettingsTabPage(store: _store),
    ];
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('蜃ｺ蜍､邁ｿ')),
        // 竊・繧ｿ繝悶・Widget繧堤ｴ譽・＠縺ｪ縺・
        body: IndexedStack(index: _idx, children: pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _idx,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.edit_calendar), label: '蜈･蜉・),
            NavigationDestination(icon: Icon(Icons.list_alt), label: '繝ｪ繧ｹ繝・),
            NavigationDestination(icon: Icon(Icons.settings), label: '險ｭ螳・),
          ],
          onDestinationSelected: (i) => setState(() => _idx = i),
        ),
      ),
    );
  }
}

/// =======================
/// 蜈･蜉帙ち繝・
/// =======================
class CalendarTabPage extends StatefulWidget {
  final Store store;
  const CalendarTabPage({super.key, required this.store});
  @override
  State<CalendarTabPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarTabPage> {
  DateTime _focused = DateTime.now();
  DateTime? _selected;

  List<WorkRecord> _eventsFor(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return widget.store.records
        .where((r) =>
    r.date.year == d.year && r.date.month == d.month && r.date.day == d.day)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TableCalendar<WorkRecord>(
          locale: 'ja_JP',
          firstDay: DateTime(2000, 1, 1),
          lastDay: DateTime(2099, 12, 31),
          focusedDay: _focused,
          startingDayOfWeek: StartingDayOfWeek.sunday,
          calendarFormat: CalendarFormat.month,
          headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
          daysOfWeekHeight: 24,
          daysOfWeekStyle: DaysOfWeekStyle(
            dowTextFormatter: (date, _) {
              const jp = ['譌･', '譛・, '轣ｫ', '豌ｴ', '譛ｨ', '驥・, '蝨・];
              return jp[date.weekday % 7];
            },
            weekendStyle: const TextStyle(color: Colors.red),
          ),
          calendarStyle: const CalendarStyle(outsideDaysVisible: true),
          selectedDayPredicate: (d) => isSameDay(_selected, d),
          onDaySelected: (sel, foc) => setState(() {
            _selected = sel;
            _focused = foc;
          }),
          onPageChanged: (foc) => _focused = foc,
          eventLoader: _eventsFor,
          calendarBuilders: CalendarBuilders(
            defaultBuilder: (ctx, day, foc) =>
                _dayCell(ctx, day, isToday: isSameDay(day, DateTime.now())),
            outsideBuilder: (ctx, day, foc) => Opacity(
              opacity: 0.45,
              child: _dayCell(ctx, day, isToday: isSameDay(day, DateTime.now())),
            ),
            todayBuilder: (ctx, day, foc) => _dayCell(ctx, day, isToday: true),
            selectedBuilder: (ctx, day, foc) =>
                _dayCell(ctx, day, isSelected: true, isToday: isSameDay(day, DateTime.now())),
            markerBuilder: (ctx, day, evts) {
              if (evts.isEmpty) return const SizedBox.shrink();
              return Positioned(
                bottom: 4,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.indigo,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _selected == null
              ? const Center(child: Text('譌･莉倥ｒ繧ｿ繝・・縺励※蜍､蜍吶ｒ陦ｨ遉ｺ・剰ｿｽ蜉'))
              : _DayRecordList(
            day: _selected!,
            store: widget.store,
            onAddOrEdit: () => setState(() {}),
          ),
        ),
        const SizedBox(height: 8),
        // 蜈･蜉帙ち繝悶・繝舌リ繝ｼ
        AdBanner(adUnitId: AdUnitIds.bannerCalendar),
      ],
    );
  }

  Widget _dayCell(BuildContext ctx, DateTime day,
      {bool isToday = false, bool isSelected = false}) {
    final isHol = widget.store.isJapaneseHoliday(day);
    final isSun = day.weekday == DateTime.sunday;
    final isSat = day.weekday == DateTime.saturday;

    Color? bg;
    if (isHol || isSun) {
      bg = Colors.red.shade50;
    } else if (isSat) {
      bg = Colors.blue.shade50;
    }
    if (isSelected) bg = Colors.indigo.withOpacity(0.12);

    Color? textColor;
    if (isHol || isSun) {
      textColor = Colors.red;
    } else if (isSat) {
      textColor = Colors.blue.shade700;
    }
    if (isSelected) textColor = Colors.indigo;

    final holidayName = widget.store.holidayName(day);

    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: isToday ? Border.all(color: Colors.indigo, width: 1.6) : null,
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('${day.day}',
              style: TextStyle(
                color: textColor,
                fontWeight: isToday ? FontWeight.w600 : FontWeight.w400,
              )),
          if (holidayName != null && !isSelected)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                holidayName,
                style: TextStyle(fontSize: 9, color: textColor ?? Colors.redAccent),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

class _DayRecordList extends StatelessWidget {
  final DateTime day;
  final Store store;
  final VoidCallback onAddOrEdit;
  const _DayRecordList({required this.day, required this.store, required this.onAddOrEdit});

  @override
  Widget build(BuildContext context) {
    final d = DateTime(day.year, day.month, day.day);
    final recs = store.records
        .where((r) =>
    r.date.year == d.year && r.date.month == d.month && r.date.day == d.day)
        .toList();
    final fmt = DateFormat('M/d(EEE)', 'ja_JP');
    return Column(
      children: [
        ListTile(
          title: Text('${fmt.format(d)} 縺ｮ蜍､蜍・),
          trailing: FilledButton.icon(
            icon: const Icon(Icons.add), label: const Text('霑ｽ蜉'),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => EditRecordPage(store: store, date: d),
              ));
              onAddOrEdit();
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: recs.isEmpty
              ? const Center(child: Text('逋ｻ骭ｲ縺ｪ縺・))
              : ListView.builder(
            itemCount: recs.length,
            itemBuilder: (c, i) {
              final r = recs[i];
              final title = r.isOff
                  ? '莨第律'
                  : '${_hm(r.startMin)} - ${_hm(r.endMin)}  莨第・${formatMinutes(r.breakMin)}';
              final sub =
                  '螳溷ロ ${formatMinutes(r.workedMinutes())} / 谿区･ｭ ${formatMinutes(r.overtimeMinutes(auto: store.overtimeAuto))}'
                  '${r.memo?.isNotEmpty == true ? '\n${r.memo}' : ''}';
              return Dismissible(
                key: ValueKey('${r.date.toIso8601String()}_${r.hashCode}'),
                background: Container(
                  color: Colors.red.shade300,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) async {
                  return await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('蜑企勁縺励∪縺吶°・・),
                      content: const Text('縺薙・蜍､蜍吶ｒ蜑企勁縺励∪縺吶・),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('繧ｭ繝｣繝ｳ繧ｻ繝ｫ')),
                        FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('蜑企勁')),
                      ],
                    ),
                  ) ??
                      false;
                },
                onDismissed: (_) async {
                  await store.deleteRecord(r);
                  onAddOrEdit();
                },
                child: ListTile(
                  title: Text(title),
                  subtitle: Text(sub),
                  isThreeLine: r.memo?.isNotEmpty == true,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EditRecordPage(store: store, initial: r),
                      ),
                    );
                    onAddOrEdit();
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// =======================
/// 繝ｪ繧ｹ繝医ち繝厄ｼ医し繝槭Μ繝ｼ + CSV/PDF・・
/// =======================
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

  @override
  Widget build(BuildContext context) {
    final (s, e) = _range;
    final title =
        '${DateFormat('yyyy/MM/dd', 'ja_JP').format(s)} 縲・${DateFormat('yyyy/MM/dd', 'ja_JP').format(e)}';

    final workDays = _list.where((r) => !r.isOff && r.workedMinutes() > 0).length;
    final workTotal = _list.fold<int>(0, (p, r) => p + r.workedMinutes());
    final overTotal = _list.fold<int>(
        0, (p, r) => p + r.overtimeMinutes(auto: widget.store.overtimeAuto));
    final allowanceTotal = _list.fold<int>(0, (p, r) => p + r.allowanceTotal());

    return Column(
      children: [
        ListTile(
          title: Text('蟇ｾ雎｡譛滄俣・・title'),
          trailing: Wrap(
            spacing: 8,
            children: [
              IconButton(
                tooltip: '蜑阪・譛滄俣',
                onPressed: () => setState(() {
                  _anchor = _range.$1.subtract(const Duration(days: 1));
                }),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: '谺｡縺ｮ譛滄俣',
                onPressed: () => setState(() {
                  _anchor = _range.$2.add(const Duration(days: 1));
                }),
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
              _chip('蜃ｺ蜍､譌･謨ｰ', '$workDays 譌･'),
              _chip('螳溷ロ蜷郁ｨ・, formatMinutes(workTotal)),
              _chip('谿区･ｭ蜷郁ｨ・, formatMinutes(overTotal)),
              _chip('謇句ｽ楢ｨ・, '${_yen(allowanceTotal)}'),
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
              label: const Text('CSV 蜈ｱ譛・),
              onPressed: () => _shareCsv(s, e),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('PDF 蜊ｰ蛻ｷ'),
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
        // 繝ｪ繧ｹ繝医ち繝悶・繝舌リ繝ｼ
        AdBanner(adUnitId: AdUnitIds.bannerList),
        const Divider(height: 24),
        Expanded(
          child: ListView.separated(
            itemCount: _list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (c, i) {
              final r = _list[i];
              final title = r.isOff
                  ? '${DateFormat('M/d(EEE)', 'ja_JP').format(r.date)}  莨第律'
                  : '${DateFormat('M/d(EEE)', 'ja_JP').format(r.date)}  ${_hm(r.startMin)}-${_hm(r.endMin)}  莨第・${formatMinutes(r.breakMin)}';
              final sub =
                  '螳溷ロ ${formatMinutes(r.workedMinutes())} / 谿区･ｭ ${formatMinutes(r.overtimeMinutes(auto: widget.store.overtimeAuto))} / 謇句ｽ・${_yen(r.allowanceTotal())}${r.memo?.isNotEmpty == true ? '\n${r.memo}' : ''}';
              return ListTile(
                title: Text(title),
                subtitle: Text(sub),
                isThreeLine: r.memo?.isNotEmpty == true,
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
      ['譌･莉・, '蜃ｺ蜍､', '騾蜍､', '莨第・', '螳溷ロ', '谿区･ｭ', '謇句ｽ・, '繝｡繝｢', '莨第律?'],
      ...list.map((r) {
        final allow = r.allowances.isEmpty
            ? ''
            : r.allowances
            .map((a) => a.perHour
            ? '${a.name}:${a.unitPrice}蜀・h x ${a.minutes ?? 0}蛻・
            : '${a.name}:${a.unitPrice}蜀・)
            .join(' / ');
        return [
          DateFormat('yyyy-MM-dd').format(r.date),
          r.startMin != null ? _hm(r.startMin) : '',
          r.endMin != null ? _hm(r.endMin) : '',
          formatMinutes(r.breakMin),
          formatMinutes(r.workedMinutes()),
          formatMinutes(r.overtimeMinutes(auto: widget.store.overtimeAuto)),
          _yen(r.allowanceTotal()),
          r.memo ?? '',
          r.isOff ? '莨第律' : '',
        ].map((s) => esc(s)).toList();
      }),
    ];

    final csv = rows.map((r) => r.join(',')).join('\n');
    final name =
        '蜃ｺ蜍､邁ｿ_${DateFormat('yyyyMMdd').format(from)}-${DateFormat('yyyyMMdd').format(to)}.csv';
    await Share.share(csv, subject: name);
  }

  Future<Uint8List> _buildPeriodPdf(DateTime from, DateTime to) async {
    double mm(double v) => v * PdfPageFormat.mm;

    final doc = pw.Document();
    final fontData =
    await rootBundle.load('assets/fonts/NotoSansJP-Regular.ttf');
    final boldData =
    await rootBundle.load('assets/fonts/NotoSansJP-Bold.ttf');
    final font = pw.Font.ttf(fontData);
    final bold = pw.Font.ttf(boldData);

    final list = widget.store.recordsIn(from, to);
    final days = list.where((r) => !r.isOff && r.workedMinutes() > 0).length;
    final workTotal = list.fold<int>(0, (p, r) => p + r.workedMinutes());
    final overTotal = list.fold<int>(
        0, (p, r) => p + r.overtimeMinutes(auto: widget.store.overtimeAuto));
    final allowanceTotal =
    list.fold<int>(0, (p, r) => p + r.allowanceTotal());

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
              pw.Text('蜃ｺ蜍､邁ｿ', style: headerStyle),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('豌丞錐・・, style: subStyle),
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
                  pw.Text('蜊ｰ・・, style: subStyle),
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
                    '蟇ｾ雎｡譛滄俣  ${DateFormat('yyyy/MM/dd').format(from)} 縲・${DateFormat('yyyy/MM/dd').format(to)}',
                    style: subStyle,
                  ),
                  pw.Text('蜃ｺ蜍､譌･謨ｰ  $days 譌･', style: subStyle),
                  pw.Text('螳溷ロ蜷郁ｨ・ ${formatMinutes(workTotal)}', style: subStyle),
                  pw.Text('谿区･ｭ蜷郁ｨ・ ${formatMinutes(overTotal)}', style: subStyle),
                  pw.Text('謇句ｽ楢ｨ・   ${_yen(allowanceTotal)}', style: subStyle),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Table.fromTextArray(
            cellStyle: td,
            headerStyle: th,
            headerDecoration:
            pw.BoxDecoration(color: PdfColor.fromInt(0xFFE0E0E0)),
            cellAlignment: pw.Alignment.centerLeft,
            headerAlignment: pw.Alignment.centerLeft,
            columnWidths: const {
              0: pw.FixedColumnWidth(60),
              1: pw.FixedColumnWidth(44),
              2: pw.FixedColumnWidth(44),
              3: pw.FixedColumnWidth(40),
              4: pw.FixedColumnWidth(40),
              5: pw.FixedColumnWidth(40),
            },
            data: <List<String>>[
              ['譌･莉・, '蜃ｺ蜍､', '騾蜍､', '莨第・', '螳溷ロ', '谿区･ｭ', '謇句ｽ・, '繝｡繝｢', '莨第律?'],
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
                  r.isOff ? '莨第律' : '',
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
/// 險ｭ螳壹ち繝・
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
          const _SectionHeader('蜍､蜍咎・岼'),
          _SwitchTile(
            title: '蝗ｺ螳壹・譎ょ綾繧剃ｽｿ逕ｨ縺吶ｋ',
            value: store.useConfigTimes,
            onChanged: (v) => store.updateSettings(useConfigTimes_: v),
          ),
          _PickerTile(
            title: '蜃ｺ蜍､譎ょ綾',
            value: _hm(store.configStartMin),
            onTap: () async {
              final m = await pickTimeMinutes(context, store.configStartMin);
              if (m != null) {
                final end = store.configEndMin;
                await store.updateSettings(startMin_: m);
                if (m >= end) {
                  await store.updateSettings(endMin_: (m + 60).clamp(0, 1439));
                }
              }
            },
          ),
          _PickerTile(
            title: '騾蜍､譎ょ綾',
            value: _hm(store.configEndMin),
            onTap: () async {
              final m = await pickTimeMinutes(context, store.configEndMin);
              if (m != null) {
                await store.updateSettings(endMin_: m);
              }
            },
          ),
          _SwitchTile(
            title: '蝗ｺ螳壹・莨第・譎る俣繧剃ｽｿ逕ｨ縺吶ｋ',
            value: store.useConfigBreak,
            onChanged: (v) => store.updateSettings(useConfigBreak_: v),
          ),
          _PickerTile(
            title: '莨第・譎る俣',
            value: '${store.configBreakMin} 蛻・,
            onTap: () async {
              final v = await pickDurationMinutes(context,
                  title: '莨第・・亥・・・, initial: store.configBreakMin);
              if (v != null) {
                await store.updateSettings(breakMin_: v);
              }
            },
          ),
          const Divider(),
          const _SectionHeader('PDF鬆・岼'),
          ListTile(
            title: const Text('PDF豌丞錐・亥魂蟄暦ｼ・),
            subtitle: Text(
              store.reportName.isEmpty ? '譛ｪ險ｭ螳夲ｼ育ｩｺ谺・→縺励※荳狗ｷ壹・縺ｿ・・ : store.reportName,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final v = await _editTextDialog(context,
                  title: 'PDF縺ｫ蜊ｰ蟄励☆繧区ｰ丞錐', initial: store.reportName);
              if (v != null) {
                await store.updateSettings(reportName_: v);
              }
            },
          ),
          const Divider(),
          const _SectionHeader('谿区･ｭ鬆・岼'),
          _SwitchTile(
            title: '谿区･ｭ・夊・蜍戊ｨ育ｮ暦ｼ・譎る俣雜・℃蛻・ｼ・,
            subtitle: 'OFF縺ｫ縺吶ｋ縺ｨ縲∝推蜍､蜍吶〒謇句虚蜈･蜉・,
            value: store.overtimeAuto,
            onChanged: (v) => store.updateSettings(overtimeAuto_: v),
          ),
          const Divider(),
          const _SectionHeader('邱繧∵律繧ｵ繧､繧ｯ繝ｫ'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _NumberPickerChip(
                  label: '髢句ｧ区律',
                  value: store.cycleStartDay,
                  onTap: () async {
                    final v = await pickDayOfMonth(context, store.cycleStartDay);
                    if (v != null) store.updateSettings(cycleStart_: v);
                  },
                ),
                _NumberPickerChip(
                  label: '邱繧∵律',
                  value: store.cycleEndDay,
                  onTap: () async {
                    final v = await pickDayOfMonth(context, store.cycleEndDay);
                    if (v != null) store.updateSettings(cycleEnd_: v);
                  },
                ),
                Text(
                  '窶ｻ 萓具ｼ夐幕蟋・6 / 邱繧・5 縺ｯ譛郁ｷｨ縺弱し繧､繧ｯ繝ｫ縺ｫ縺ｪ繧翫∪縺・,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Divider(),
          const _SectionHeader('謇句ｽ薙・繝ｪ繧ｻ繝・ヨ'),
          ...store.presets
              .map((p) => ListTile(
            title: Text(p.name),
            subtitle:
            Text(p.perHour ? '${p.unitPrice}蜀・譎・ : '${p.unitPrice}蜀・蝗・),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => store.deletePreset(p.name),
            ),
            onTap: () => _editPresetDialog(context, store, preset: p),
          ))
              .toList(),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('繝励Μ繧ｻ繝・ヨ繧定ｿｽ蜉'),
            onTap: () => _editPresetDialog(context, store),
          ),
          const SizedBox(height: 8),
          // 險ｭ螳壹ち繝悶・繝舌リ繝ｼ・遺懷ｺ・相險ｺ譁ｭ窶昴・陦ｨ遉ｺ縺励∪縺帙ｓ・・
          AdBanner(adUnitId: AdUnitIds.bannerSettings),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _editPresetDialog(BuildContext ctx, Store store,
      {AllowancePreset? preset}) async {
    final nameCtl = TextEditingController(text: preset?.name ?? '');
    final priceCtl =
    TextEditingController(text: preset?.unitPrice.toString() ?? '');
    bool perHour = preset?.perHour ?? false;

    await showDialog(
      context: ctx,
      builder: (c) => AlertDialog(
        title: Text(preset == null ? '繝励Μ繧ｻ繝・ヨ霑ｽ蜉' : '繝励Μ繧ｻ繝・ヨ邱ｨ髮・),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtl, decoration: const InputDecoration(labelText: '蜷咲ｧｰ')),
            TextField(
              controller: priceCtl,
              decoration: const InputDecoration(labelText: '驥鷹｡搾ｼ亥・・・),
              keyboardType: TextInputType.number,
            ),
            SwitchListTile(
              value: perHour,
              onChanged: (v) => perHour = v,
              title: const Text('譎る俣蜊倅ｾ｡・亥・/譎ゑｼ・),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('繧ｭ繝｣繝ｳ繧ｻ繝ｫ')),
          FilledButton(
              onPressed: () async {
                final name = nameCtl.text.trim();
                final price = int.tryParse(priceCtl.text.trim()) ?? 0;
                if (name.isEmpty) return;
                await store.upsertPreset(
                    AllowancePreset(name: name, unitPrice: price, perHour: perHour));
                if (ctx.mounted) Navigator.pop(c);
              },
              child: const Text('菫晏ｭ・)),
        ],
      ),
    );
  }
}

/// =======================
/// 蜍､蜍咏ｷｨ髮・
/// =======================
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
    return Scaffold(
      appBar: AppBar(
        title: Text('${fmt.format(_date)} 縺ｮ蜍､蜍・),
        actions: [
          TextButton(onPressed: _save, child: const Text('菫晏ｭ・)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          SwitchListTile(
            title: const Text('莨第律縺ｨ縺励※逋ｻ骭ｲ'),
            value: _isOff,
            onChanged: (v) => setState(() => _isOff = v),
          ),
          if (!_isOff) ...[
            _TimeField(
              label: '蜃ｺ蜍､',
              value: _start,
              onTap: () async {
                final v = await pickTimeMinutes(context, _start ?? 9 * 60);
                if (v != null) setState(() => _start = v);
              },
            ),
            _TimeField(
              label: '騾蜍､',
              value: _end,
              onTap: () async {
                final v = await pickTimeMinutes(context, _end ?? 18 * 60);
                if (v != null) setState(() => _end = v);
              },
            ),
            _DurationField(
              label: '莨第・・亥・・・,
              value: _break,
              step: 15,
              onChanged: (v) => setState(() => _break = v),
            ),
            if (!widget.store.overtimeAuto)
              _DurationField(
                label: '谿区･ｭ・亥・繝ｻ謇句虚・・,
                value: _manualOver ?? 0,
                step: 15,
                onChanged: (v) => setState(() => _manualOver = v),
              ),
          ],
          const Divider(),
          ListTile(
            title: const Text('謇句ｽ・),
            subtitle: Text(
              _allowances.isEmpty
                  ? '縺ｪ縺・
                  : _allowances
                  .map((a) => a.perHour
                  ? '${a.name}:${a.unitPrice}蜀・譎・ﾃ・${a.minutes ?? 0}蛻・
                  : '${a.name}:${a.unitPrice}蜀・)
                  .join(' / '),
            ),
            trailing: FilledButton.tonalIcon(
              icon: const Icon(Icons.playlist_add),
              label: const Text('謇句ｽ薙ｒ驕ｸ縺ｶ'),
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
                    ? '${e.value.name} ${e.value.unitPrice}蜀・譎・${e.value.minutes ?? 0}蛻・
                    : '${e.value.name} ${e.value.unitPrice}蜀・),
                onDeleted: () => setState(() => _allowances.removeAt(e.key)),
              ),
            )
                .toList(),
          ),
          const SizedBox(height: 8),
          ListTile(
            title: const Text('繝｡繝｢'),
            subtitle: TextField(
              controller: _memoCtl,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: '莉ｻ諢・,
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
                const Text('繝励Μ繧ｻ繝・ヨ縺九ｉ驕ｸ謚・,
                    style: TextStyle(fontWeight: FontWeight.bold)),
                ...widget.store.presets.map((p) {
                  return ListTile(
                    title: Text(p.name),
                    subtitle:
                    Text(p.perHour ? '${p.unitPrice}蜀・譎・ : '${p.unitPrice}蜀・蝗・),
                    trailing: FilledButton(
                      onPressed: () async {
                        if (p.perHour) {
                          final m = await pickDurationMinutes(context,
                              title: '譎る俣・亥・・・, initial: 60);
                          if (m != null) {
                            setState(() => _allowances.add(Allowance(
                                name: p.name,
                                unitPrice: p.unitPrice,
                                perHour: true,
                                minutes: m)));
                          }
                        } else {
                          setState(() => _allowances.add(Allowance(
                              name: p.name, unitPrice: p.unitPrice, perHour: false)));
                        }
                        if (mounted) Navigator.pop(c);
                      },
                      child: const Text('霑ｽ蜉'),
                    ),
                  );
                }),
                const Divider(),
                ListTile(
                  title: const Text('譁ｰ縺励＞謇句ｽ薙ｒ逶ｴ謗･霑ｽ蜉'),
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
        title: const Text('謇句ｽ薙ｒ霑ｽ蜉'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtl, decoration: const InputDecoration(labelText: '蜷咲ｧｰ')),
            TextField(
              controller: priceCtl,
              decoration: const InputDecoration(labelText: '驥鷹｡搾ｼ亥・・・),
              keyboardType: TextInputType.number,
            ),
            SwitchListTile(
              value: perHour,
              onChanged: (v) => perHour = v,
              title: const Text('譎る俣蜊倅ｾ｡・亥・/譎ゑｼ・),
              contentPadding: EdgeInsets.zero,
            ),
            if (perHour)
              _DurationField(
                label: '譎る俣・亥・・・,
                value: minutes,
                step: 15,
                onChanged: (v) => minutes = v,
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('繧ｭ繝｣繝ｳ繧ｻ繝ｫ')),
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
              child: const Text('霑ｽ蜉')),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_isOff) {
      if (_start == null || _end == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('蜃ｺ蜍､/騾蜍､繧貞・蜉帙＠縺ｦ縺上□縺輔＞')));
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
/// 蜈ｱ騾啅I蟆冗黄
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
  const _SwitchTile({required this.title, this.subtitle, required this.value, required this.onChanged});
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
    return ActionChip(label: Text('$label: $value 譌･'), onPressed: onTap);
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
          Text(value == null ? '-' : _hm(value), style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
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
  const _DurationField({required this.label, required this.value, this.step = 15, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      subtitle: Text(formatMinutes(value)),
      trailing: Wrap(
        spacing: 8,
        children: [
          IconButton(onPressed: () => onChanged((value - step).clamp(0, 24 * 60)), icon: const Icon(Icons.remove)),
          IconButton(onPressed: () => onChanged((value + step).clamp(0, 24 * 60)), icon: const Icon(Icons.add)),
        ],
      ),
    );
  }
}

Future<String?> _editTextDialog(BuildContext context, {required String title, String initial = ''}) async {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(controller: ctl, decoration: const InputDecoration(hintText: '豌丞錐')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('繧ｭ繝｣繝ｳ繧ｻ繝ｫ')),
        FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('菫晏ｭ・)),
      ],
    ),
  );
}

/// =======================
/// 繝斐ャ繧ｫ繝ｼ
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
                children: [for (int i = 0; i < 24; i++) Center(child: Text('$i 譎・))],
              ),
            ),
            Expanded(
              child: CupertinoPicker(
                itemExtent: 36,
                scrollController: FixedExtentScrollController(initialItem: m),
                onSelectedItemChanged: (v) => m = v,
                children: [for (int i = 0; i < 60; i++) Center(child: Text('$i 蛻・))],
              ),
            ),
          ],
        ),
      );
    },
  ).then((_) => h * 60 + m);
}

Future<int?> pickDurationMinutes(BuildContext context, {required String title, int initial = 60}) async {
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
                children: [for (int i = 0; i <= 240; i++) Center(child: Text('$i 蛻・))],
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
          children: [for (int i = 1; i <= 31; i++) Center(child: Text('$i 譌･'))],
        ),
      );
    },
  ).then((_) => v);
}

/// =======================
/// 繝ｦ繝ｼ繝・ぅ繝ｪ繝・ぅ
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
  if (h == 0) return '${mm}蛻・;
  if (mm == 0) return '${h}譎る俣';
  return '${h}譎る俣${mm}蛻・;
}

String _yen(int v) => NumberFormat.currency(locale: 'ja_JP', symbol: 'ﾂ･').format(v);

Map<DateTime, String> buildJapaneseHolidays(int year) {
  final Map<DateTime, String> m = {};
  DateTime d(int y, int mo, int da) => DateTime(y, mo, da);
  void addFix(int mo, int da, String name) => m[d(year, mo, da)] = name;

  addFix(1, 1, '蜈・律');
  addFix(2, 11, '蟒ｺ蝗ｽ險伜ｿｵ縺ｮ譌･');
  addFix(2, 23, '螟ｩ逧・ｪ慕函譌･');
  addFix(4, 29, '譏ｭ蜥後・譌･');
  addFix(5, 3, '諞ｲ豕戊ｨ伜ｿｵ譌･');
  addFix(5, 4, '縺ｿ縺ｩ繧翫・譌･');
  addFix(5, 5, '縺薙←繧ゅ・譌･');
  addFix(11, 3, '譁・喧縺ｮ譌･');
  addFix(11, 23, '蜍､蜉ｴ諢溯ｬ昴・譌･');

  int shunbunDay(int y) =>
      (20.8431 + 0.242194 * (y - 1980) - ((y - 1980) / 4).floor()).floor();
  int shubunDay(int y) =>
      (23.2488 + 0.242194 * (y - 1980) - ((y - 1980) / 4).floor()).floor();
  m[d(year, 3, shunbunDay(year))] = '譏･蛻・・譌･';
  m[d(year, 9, shubunDay(year))] = '遘句・縺ｮ譌･';

  DateTime nthMonday(int month, int n) {
    var dt = d(year, month, 1);
    while (dt.weekday != DateTime.monday) {
      dt = dt.add(const Duration(days: 1));
    }
    return dt.add(Duration(days: 7 * (n - 1)));
  }

  m[nthMonday(1, 2)] = '謌蝉ｺｺ縺ｮ譌･';
  m[nthMonday(7, 3)] = '豬ｷ縺ｮ譌･';
  m[nthMonday(9, 3)] = '謨ｬ閠√・譌･';
  m[nthMonday(10, 2)] = '繧ｹ繝昴・繝・・譌･';

  if (year >= 2016) m[d(year, 8, 11)] = '螻ｱ縺ｮ譌･';

  final keys = m.keys.toList()..sort();
  for (final k in keys) {
    if (k.weekday == DateTime.sunday) {
      var sub = k.add(const Duration(days: 1));
      while (m.containsKey(sub)) {
        sub = sub.add(const Duration(days: 1));
      }
      m[sub] = '謖ｯ譖ｿ莨第律';
    }
  }

  final sorted = m.keys.toList()..sort();
  for (int i = 0; i < sorted.length - 1; i++) {
    final a = sorted[i];
    final b = sorted[i + 1];
    if (b.difference(a).inDays == 2) {
      final mid = a.add(const Duration(days: 1));
      if (!m.containsKey(mid) && mid.weekday != DateTime.sunday) {
        m[mid] = '蝗ｽ豌代・莨第律';
      }
    }
  }
  return m;
}
