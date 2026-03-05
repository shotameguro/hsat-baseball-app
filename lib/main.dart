import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';

const _bg      = Color(0xFF0F172A);
const _surface = Color(0xFF1E293B);
const _border  = Color(0xFF334155);
const _accent  = Color(0xFFF97316);
const _textPri = Color(0xFFF1F5F9);
const _textSec = Color(0xFF94A3B8);

void main() {
  ErrorWidget.builder = (details) => Scaffold(
        body: Center(child: SelectableText("⚠️ エラー: ${details.exception}")),
      );
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _bg,
      colorScheme: const ColorScheme.dark(
        primary: _accent,
        surface: _surface,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0C1220),
        foregroundColor: _textPri,
        elevation: 0,
      ),
      tabBarTheme: const TabBarThemeData(
        indicatorColor: _accent,
        labelColor: _accent,
        unselectedLabelColor: _textSec,
        dividerColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surface,
        labelStyle: const TextStyle(color: _textSec, fontSize: 12),
        hintStyle: const TextStyle(color: _textSec),
        border: OutlineInputBorder(borderSide: const BorderSide(color: _border), borderRadius: BorderRadius.circular(6)),
        enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: _border), borderRadius: BorderRadius.circular(6)),
        focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: _accent, width: 1.5), borderRadius: BorderRadius.circular(6)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      dataTableTheme: const DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(_surface),
        dataRowColor: WidgetStatePropertyAll(_bg),
        headingTextStyle: TextStyle(color: _textPri, fontWeight: FontWeight.bold, fontSize: 10),
        dataTextStyle: TextStyle(color: _textSec, fontSize: 10),
        dividerThickness: 0.3,
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: _surface),
      ),
      dividerColor: _border,
      textTheme: const TextTheme(bodyMedium: TextStyle(color: _textPri)),
    ),
    home: const YakyuApp(),
  ));
}

class YakyuApp extends StatefulWidget {
  const YakyuApp({super.key});
  @override
  State<YakyuApp> createState() => _YakyuAppState();
}

class _YakyuAppState extends State<YakyuApp> {
  String? selectedPlayer;
  String selectedYear = "すべて";
  List<String> players = [];
  List<String> years = ["すべて"];
  List<dynamic> analysisData = [];
  List<dynamic> pitchMapData = [];
  List<String> mapDates = ["すべて"];
  String selectedMapDate = "すべて";
  Set<String> hiddenPitchTypes = {};
  List<dynamic> armAngleData = [];
  List<String> armAngleDates = ["すべて"];
  String selectedArmDate = "すべて";
  Set<String> hiddenArmPitchTypes = {};
  List<dynamic> tiltData = [];
  List<String> tiltDates = ["すべて"];
  String selectedTiltDate = "すべて";
  Set<String> hiddenTiltPitchTypes = {};
  Set<String> hiddenTrajPitchTypes = {};
  String selectedReportDate = "すべて";
  List<dynamic> pitchesData = [];
  bool isLoading = false;
  String get baseUrl {
    if (kIsWeb) {
      final base = Uri.base;
      final port = base.port;
      final portStr = (port == 80 || port == 443 || port == 0) ? '' : ':$port';
      return '${base.scheme}://${base.host}$portStr';
    }
    return 'http://127.0.0.1:5003';
  }

  // メモ
  final String _commentsPath = '/Users/shotameguro/Downloads/yakyu-app/my_yakyu_app/comments.json';
  Map<String, String> _comments = {};
  final TextEditingController _commentController = TextEditingController();
  String _aiComment = '';
  bool _aiLoading = false;

  // 管理者モード
  static const String _adminPin = '07261992';
  bool _adminUnlocked = false;
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _questionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    fetchInitialData();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _pinController.dispose();
    _questionController.dispose();
    super.dispose();
  }

  void _loadComments() {
    try {
      final f = File(_commentsPath);
      if (f.existsSync()) {
        _comments = Map<String, String>.from(json.decode(f.readAsStringSync()));
      }
    } catch (e) {
      debugPrint("comments load error: $e");
    }
  }

  void _saveComment(String key, String text) {
    _comments[key] = text;
    try {
      File(_commentsPath).writeAsStringSync(json.encode(_comments));
    } catch (e) {
      debugPrint("comments save error: $e");
    }
  }

  String get _commentKey => '${selectedPlayer ?? ""}_$selectedReportDate';

  void _updateCommentController() {
    _commentController.text = _comments[_commentKey] ?? '';
    _commentController.selection = TextSelection.collapsed(offset: _commentController.text.length);
  }

  Future<void> _fetchAiComment() async {
    if (selectedPlayer == null) return;
    setState(() { _aiLoading = true; _aiComment = ''; });
    try {
      final res = await http.get(Uri.parse(
        '$baseUrl/ai_comment'
        '?player_name=${Uri.encodeComponent(selectedPlayer!)}'
        '&year=${Uri.encodeComponent(selectedYear)}'
        '&date=${Uri.encodeComponent(selectedReportDate)}'
        '&question=${Uri.encodeComponent(_questionController.text)}',
      ));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        setState(() {
          _aiComment = (data['comment'] ?? data['error'] ?? '').toString();
        });
      }
    } catch (e) {
      setState(() => _aiComment = '通信エラー: $e');
    } finally {
      setState(() => _aiLoading = false);
    }
  }

  Future<void> fetchInitialData() async {
    try {
      final pRes = await http.get(Uri.parse('$baseUrl/players'));
      final yRes = await http.get(Uri.parse('$baseUrl/years'));
      if (pRes.statusCode == 200 && yRes.statusCode == 200) {
        setState(() {
          players = List<String>.from(json.decode(pRes.body));
          years = List<String>.from(json.decode(yRes.body));
        });
      }
    } catch (e) {
      debugPrint("初期ロードエラー: $e");
    }
  }

  Future<void> fetchAnalysis(String name, String year) async {
    setState(() { isLoading = true; selectedReportDate = "すべて"; pitchesData = []; _aiComment = ''; _adminUnlocked = false; });
    try {
      final res = await http.get(Uri.parse(
          '$baseUrl/analyze?player_name=${Uri.encodeComponent(name)}&year=$year'));
      if (res.statusCode == 200) {
        setState(() {
          analysisData = json.decode(res.body);
        });
      }
      await fetchPitchMap(name, year);
      await fetchArmAngle(name, year);
      await fetchTilt(name, year);
      await fetchPitches(name, year);
    } finally {
      setState(() => isLoading = false);
      _updateCommentController();
    }
  }

  Future<void> fetchTilt(String name, String year) async {
    try {
      final res = await http.get(Uri.parse(
          '$baseUrl/tilt?player_name=${Uri.encodeComponent(name)}&year=$year'));
      if (res.statusCode == 200) {
        final data = List<dynamic>.from(json.decode(res.body));
        final dates = data.map((e) => e['date'].toString()).toSet().toList()..sort();
        setState(() {
          tiltData = data;
          tiltDates = ["すべて", ...dates];
          selectedTiltDate = "すべて";
          hiddenTiltPitchTypes = {};
        });
      }
    } catch (e) {
      debugPrint("tilt error: $e");
    }
  }

  Future<void> fetchPitches(String name, String year) async {
    try {
      final res = await http.get(Uri.parse(
          '$baseUrl/pitches?player_name=${Uri.encodeComponent(name)}&year=$year'));
      if (res.statusCode == 200) {
        setState(() {
          pitchesData = List<dynamic>.from(json.decode(res.body));
        });
      }
    } catch (e) {
      debugPrint("pitches error: $e");
    }
  }

  Future<void> fetchArmAngle(String name, String year) async {
    try {
      final res = await http.get(Uri.parse(
          '$baseUrl/arm_angle?player_name=${Uri.encodeComponent(name)}&year=$year'));
      if (res.statusCode == 200) {
        final data = List<dynamic>.from(json.decode(res.body));
        final dates = data.map((e) => e['date'].toString()).toSet().toList()..sort();
        setState(() {
          armAngleData = data;
          armAngleDates = ["すべて", ...dates];
          selectedArmDate = "すべて";
          hiddenArmPitchTypes = {};
        });
      }
    } catch (e) {
      debugPrint("arm_angle error: $e");
    }
  }

  Future<void> fetchPitchMap(String name, String year) async {
    try {
      final res = await http.get(Uri.parse(
          '$baseUrl/pitch_map?player_name=${Uri.encodeComponent(name)}&year=$year'));
      if (res.statusCode == 200) {
        final data = List<dynamic>.from(json.decode(res.body));
        final dates = data.map((e) => e['date'].toString()).toSet().toList()..sort();
        setState(() {
          pitchMapData = data;
          mapDates = ["すべて", ...dates];
          selectedMapDate = "すべて";
          hiddenPitchTypes = {};
        });
      }
    } catch (e) {
      debugPrint("pitch_map error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 10,
      child: Scaffold(
        appBar: AppBar(
          title: Builder(builder: (context) {
            final isNarrow = MediaQuery.of(context).size.width < 500;
            return Text(
              isNarrow ? "HSAT" : "HSAT Honda Suzuka Analytics System",
              style: TextStyle(color: _textPri, fontSize: isNarrow ? 15 : 17, fontWeight: FontWeight.bold, letterSpacing: 1.5),
            );
          }),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [Tab(text: "球速"), Tab(text: "回転数"), Tab(text: "変化量"), Tab(text: "変化量マップ"), Tab(text: "リリース"), Tab(text: "位置3D"), Tab(text: "チルト"), Tab(text: "軌道"), Tab(text: "レポート"), Tab(text: "管理者")],
          ),
        ),
        body: Column(
          children: [
            _buildSelectors(),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : selectedPlayer == null
                      ? const Center(child: Text("選手を選択してください"))
                      : analysisData.isEmpty
                          ? const Center(child: Text("データがありません"))
                          : TabBarView(children: [
                              _buildValuePage("RelSpeed", Colors.blue),
                              _buildValuePage("SpinRate", Colors.orange),
                              _buildDoubleValuePage("InducedVertBreak", "HorzBreak"),
                              _buildPitchMapPage(),
                              _buildReleasePointPage(),
                              _buildArmAnglePage(),
                              _buildTiltPage(),
                              _buildTrajectoryPage(),
                              _buildReportPage(),
                              _buildAdminPage(),
                            ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectors() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: _surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 480;
          final playerField = DropdownButtonFormField<String>(
            value: players.contains(selectedPlayer) ? selectedPlayer : null,
            decoration: const InputDecoration(labelText: "選手名", filled: true, fillColor: _surface),
            items: players.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
            onChanged: (v) {
              setState(() => selectedPlayer = v);
              fetchAnalysis(v!, selectedYear);
            },
          );
          final yearField = DropdownButtonFormField<String>(
            value: years.contains(selectedYear) ? selectedYear : "すべて",
            decoration: const InputDecoration(labelText: "年度", filled: true, fillColor: _surface),
            items: years.map((y) => DropdownMenuItem(value: y, child: Text(y))).toList(),
            onChanged: (v) {
              setState(() => selectedYear = v!);
              fetchAnalysis(selectedPlayer!, v!);
            },
          );
          if (isNarrow) {
            return Column(children: [playerField, const SizedBox(height: 8), yearField]);
          }
          return Row(children: [
            Expanded(child: playerField),
            const SizedBox(width: 8),
            Expanded(child: yearField),
          ]);
        },
      ),
    );
  }

  Widget _buildGraph(String key, Color baseColor, {double height = 300}) {
    final screenWidth = MediaQuery.of(context).size.width;
    final effectiveHeight = screenWidth < 480 ? height * 0.65 : height;
    List<dynamic> chartData = List.from(analysisData)
      ..sort((a, b) => a['date'].toString().compareTo(b['date'].toString()));

    if (chartData.isEmpty) return const SizedBox.shrink();

    List<String> allDates = chartData.map((e) => e['date'].toString()).toSet().toList()..sort();
    var pitchGroups = groupBy(chartData, (dynamic e) => e['pitch_type'].toString());

    double minY = double.infinity;
    double maxY = double.negativeInfinity;
    for (var item in chartData) {
      final metricData = item['metrics'][key];
      if (metricData == null) continue;
      double val = (metricData['avg'] as num).toDouble();
      if (val < minY) minY = val;
      if (val > maxY) maxY = val;
    }
    if (minY == double.infinity) { minY = 0; maxY = 1; }

    double range = maxY - minY;
    double buffer = range == 0 ? 1.0 : range * 0.25;
    minY = minY - buffer;
    maxY = maxY + buffer;

    // データ範囲から適切な軸間隔と小数点桁数を計算
    double totalRange = maxY - minY;
    double rawInterval = totalRange / 5;
    double magnitude = pow(10, (log(rawInterval == 0 ? 1 : rawInterval) / log(10)).floor()).toDouble();
    double normalized = rawInterval / magnitude;
    double yInterval;
    if (normalized < 1.5) yInterval = magnitude;
    else if (normalized < 3.5) yInterval = 2 * magnitude;
    else if (normalized < 7.5) yInterval = 5 * magnitude;
    else yInterval = 10 * magnitude;
    if (yInterval == 0) yInterval = 1.0;

    int labelDecimals = yInterval >= 10 ? 0 : yInterval >= 1 ? 1 : 2;

    Map<String, Color> pitchColors = {
      "Fastball": Colors.red,
      "Sinker": Colors.orange,
      "Curveball": Colors.blue,
      "Slider": Colors.yellow.shade700,
      "Cutter": Colors.brown,
      "Splitter": const Color(0xFF1A237E),
      "Changeup": Colors.green,
    };

    List<String> barPitchNames = [];
    List<LineChartBarData> lineBarsData = [];
    
    pitchGroups.forEach((pitchType, dataList) {
      final lineColor = pitchColors[pitchType] ?? Colors.black54;
      barPitchNames.add(pitchType);

      List<FlSpot> spots = [];
      for (var item in dataList) {
        final metricData = item['metrics'][key];
        if (metricData == null) continue;
        int xIndex = allDates.indexOf(item['date'].toString());
        if (xIndex != -1) {
          spots.add(FlSpot(xIndex.toDouble(), (metricData['avg'] as num).toDouble()));
        }
      }
      spots.sort((a, b) => a.x.compareTo(b.x));

      lineBarsData.add(
        LineChartBarData(
          isCurved: false,
          color: lineColor,
          barWidth: 2,
          dotData: const FlDotData(show: true),
          spots: spots,
        ),
      );
    });

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: pitchGroups.keys.map((p) => Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Row(
                  children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: pitchColors[p] ?? Colors.black54, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text(p, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              )).toList(),
            ),
          ),
        ),
        Container(
          height: effectiveHeight,
          padding: const EdgeInsets.fromLTRB(10, 10, 20, 5),
          child: LineChart(
            LineChartData(
              minY: minY,
              maxY: maxY,
              lineBarsData: lineBarsData,
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: 1,
                    getTitlesWidget: (double value, TitleMeta meta) {
                      int index = value.toInt();
                      if (index >= 0 && index < allDates.length) {
                        String dateStr = allDates[index];
                        List<String> parts = dateStr.split('/');
                        String shortDate = parts.length >= 3 ? "${parts[1]}/${parts[2]}" : dateStr;
                        return SideTitleWidget(meta: meta, space: 5, child: Text(shortDate, style: const TextStyle(fontSize: 9)));
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    interval: yInterval,
                    getTitlesWidget: (value, meta) => SideTitleWidget(meta: meta, child: Text(value.toStringAsFixed(labelDecimals), style: const TextStyle(fontSize: 9))),
                  ),
                ),
              ),
              gridData: const FlGridData(show: true, drawVerticalLine: true, verticalInterval: 1),
              borderData: FlBorderData(show: true, border: Border(bottom: BorderSide(color: _border), left: BorderSide(color: _border))),
              lineTouchData: LineTouchData(
                handleBuiltInTouches: true,
                touchTooltipData: LineTouchTooltipData(
                  // 背景を少し暗くして視認性をアップ
                  getTooltipColor: (LineBarSpot touchedSpot) => const Color(0xFF0C1220).withValues(alpha: 0.95),
                  tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  tooltipMargin: 15,
                  // 画面端での「はみ出し」を自動で防ぐ設定
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItems: (List<LineBarSpot> touchedSpots) {
                    return touchedSpots.map((s) {
                      final pitchName = barPitchNames[s.barIndex];
                      final barColor = lineBarsData[s.barIndex].color;
                      
                      return LineTooltipItem(
                        '$pitchName: ',
                        TextStyle(
                          color: barColor, // 球種名を線の色と一致させる
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                        children: [
                          TextSpan(
                            text: s.y.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white, // 数値は読みやすく白
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      );
                    }).toList();
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildValuePage(String key, Color color) {
    final grouped = groupBy(analysisData, (dynamic o) => o['date'].toString());
    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    final bool showPerceived = key == 'RelSpeed';
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildGraph(key, color),
          const Divider(),
          for (int i = 0; i < sortedDates.length; i++)
            _buildDateCard(sortedDates[i], [
              const DataColumn(label: Text('球種')),
              const DataColumn(label: Text('投球数')),
              const DataColumn(label: Text('MAX')),
              const DataColumn(label: Text('平均')),
              const DataColumn(label: Text('MIN')),
              if (showPerceived) const DataColumn(label: Text('体感')),
              if (showPerceived) const DataColumn(label: Text('減衰')),
            ], grouped[sortedDates[i]]!.map((item) {
              final m = item['metrics'][key];
              final ev = item['metrics']['EffVelocity'];
              final sd = item['metrics']['SpeedDecay'];
              return DataRow(cells: [
                DataCell(Text(item['pitch_type'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                DataCell(Text('${item['count'] ?? 0}')),
                DataCell(Text(((m['max'] ?? 0) as num).toStringAsFixed(1), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
                DataCell(Text(((m['avg'] ?? 0) as num).toStringAsFixed(1))),
                DataCell(Text(((m['min'] ?? 0) as num).toStringAsFixed(1), style: const TextStyle(color: Colors.blue))),
                if (showPerceived) DataCell(Text(
                  ((ev?['avg'] ?? 0) as num).toStringAsFixed(1),
                  style: const TextStyle(color: Colors.purple, fontWeight: FontWeight.bold),
                )),
                if (showPerceived) DataCell(Text(
                  ((sd?['avg'] ?? 0) as num).toStringAsFixed(1),
                  style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold),
                )),
              ]);
            }).toList(), i == 0),
        ],
      ),
    );
  }

  Widget _buildDoubleValuePage(String k1, String k2) {
    final grouped = groupBy(analysisData, (dynamic o) => o['date'].toString());
    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(builder: (context, constraints) {
            final vertCol = Column(mainAxisSize: MainAxisSize.min, children: [
              const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text("縦変化量", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
              _buildGraph(k1, Colors.green),
            ]);
            final horizCol = Column(mainAxisSize: MainAxisSize.min, children: [
              const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text("横変化量", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
              _buildGraph(k2, Colors.red),
            ]);
            if (constraints.maxWidth < 480) {
              return Column(children: [vertCol, horizCol]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: vertCol),
              Expanded(child: horizCol),
            ]);
          }),
          const Divider(),
          for (int i = 0; i < sortedDates.length; i++)
            _buildDateCard(sortedDates[i], [
              const DataColumn(label: Text('球種')),
              const DataColumn(label: Text('投球数')),
              const DataColumn(label: Text('ホップ')),
              const DataColumn(label: Text('横変化')),
            ], grouped[sortedDates[i]]!.map((item) {
              return DataRow(cells: [
                DataCell(Text(item['pitch_type'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                DataCell(Text('${item['count'] ?? 0}')),
                DataCell(Text(item['metrics'][k1]['avg'].toStringAsFixed(1))),
                DataCell(Text(item['metrics'][k2]['avg'].toStringAsFixed(1))),
              ]);
            }).toList(), i == 0),
        ],
      ),
    );
  }

  Widget _buildArmAnglePage() {
    final Map<String, Color> pitchColors = {
      "Fastball": Colors.red,
      "Sinker": Colors.orange,
      "Curveball": Colors.blue,
      "Slider": Colors.yellow.shade700,
      "Cutter": Colors.brown,
      "Splitter": const Color(0xFF1A237E),
      "Changeup": Colors.green,
    };

    final filtered = selectedArmDate == "すべて"
        ? List<dynamic>.from(armAngleData)
        : armAngleData.where((e) => e['date'] == selectedArmDate).toList();

    final visibleFiltered = filtered
        .where((e) => !hiddenArmPitchTypes.contains(e['pitch_type'].toString()))
        .toList();

    final pitchTypes = filtered.map((e) => e['pitch_type'].toString()).toSet().toList();

    // 軸範囲をデータから動的に計算
    double minX = -5, maxX = 5, minY = -15, maxY = 0;
    double minExt = 5, maxExt = 7;
    if (visibleFiltered.isNotEmpty) {
      minX = visibleFiltered.map((e) => (e['rel_side'] as num).toDouble()).reduce(min);
      maxX = visibleFiltered.map((e) => (e['rel_side'] as num).toDouble()).reduce(max);
      minY = visibleFiltered.map((e) => (e['rel_height'] as num).toDouble()).reduce(min);
      maxY = visibleFiltered.map((e) => (e['rel_height'] as num).toDouble()).reduce(max);
      minExt = visibleFiltered.map((e) => (e['extension'] as num).toDouble()).reduce(min);
      maxExt = visibleFiltered.map((e) => (e['extension'] as num).toDouble()).reduce(max);
      final bx = max((maxX - minX) * 0.05, 0.1);
      final by = max((maxY - minY) * 0.05, 0.1);
      minX = minX - bx; maxX = maxX + bx;
      minY = minY - by; maxY = maxY + by;
    }
    final extRange = maxExt - minExt;

    double getRadius(double ext) =>
        extRange == 0 ? 6.0 : 3.0 + (ext - minExt) / extRange * 7.0;

    final List<ScatterSpot> spots = visibleFiltered.map((e) {
      final color = pitchColors[e['pitch_type'].toString()] ?? Colors.black54;
      return ScatterSpot(
        (e['rel_side'] as num).toDouble(),
        (e['rel_height'] as num).toDouble(),
        dotPainter: FlDotCirclePainter(
          radius: getRadius((e['extension'] as num).toDouble()),
          color: color.withOpacity(0.7),
        ),
      );
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: DropdownButtonFormField<String>(
            value: armAngleDates.contains(selectedArmDate) ? selectedArmDate : "すべて",
            decoration: const InputDecoration(labelText: "日付", filled: true, fillColor: _surface),
            items: armAngleDates.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
            onChanged: (v) => setState(() => selectedArmDate = v!),
          ),
        ),
        if (filtered.isEmpty)
          const Expanded(child: Center(child: Text("データがありません")))
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Wrap(
              spacing: 12,
              runSpacing: 2,
              children: pitchTypes.map((p) {
                final hidden = hiddenArmPitchTypes.contains(p);
                final color = pitchColors[p] ?? Colors.black54;
                return GestureDetector(
                  onTap: () => setState(() {
                    if (hidden) hiddenArmPitchTypes.remove(p);
                    else hiddenArmPitchTypes.add(p);
                  }),
                  child: Opacity(
                    opacity: hidden ? 0.3 : 1.0,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                      Text(p, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, decoration: hidden ? TextDecoration.lineThrough : null)),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text("● バブルの大きさ = Extension（大きいほど前でリリース）", style: TextStyle(fontSize: 9, color: _textSec)),
          ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1.0,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 20, 8),
                  child: ScatterChart(ScatterChartData(
                    scatterSpots: spots,
                    minX: minX, maxX: maxX, minY: minY, maxY: maxY,
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(),
                      rightTitles: const AxisTitles(),
                      bottomTitles: AxisTitles(
                        axisNameWidget: const Text('← 三塁側　横位置 (RelSide, ft)　一塁側 →', style: TextStyle(fontSize: 9)),
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          getTitlesWidget: (v, meta) => SideTitleWidget(meta: meta, child: Text(v.toStringAsFixed(1), style: const TextStyle(fontSize: 8))),
                        ),
                      ),
                      leftTitles: AxisTitles(
                        axisNameWidget: const Text('高さ\n(RelHeight, ft)', style: TextStyle(fontSize: 9)),
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 36,
                          getTitlesWidget: (v, meta) => SideTitleWidget(meta: meta, child: Text(v.toStringAsFixed(1), style: const TextStyle(fontSize: 8))),
                        ),
                      ),
                    ),
                    gridData: FlGridData(
                      show: true,
                      getDrawingHorizontalLine: (value) => FlLine(
                        color: value == 0 ? const Color(0xFF94A3B8) : _border,
                        strokeWidth: value == 0 ? 2.0 : 0.5,
                      ),
                      getDrawingVerticalLine: (value) => FlLine(
                        color: value == 0 ? const Color(0xFF94A3B8) : _border,
                        strokeWidth: value == 0 ? 2.0 : 0.5,
                      ),
                    ),
                    borderData: FlBorderData(show: true, border: Border.all(color: _border)),
                    scatterTouchData: ScatterTouchData(
                      enabled: true,
                      touchTooltipData: ScatterTouchTooltipData(
                        getTooltipColor: (_) => const Color(0xFF0C1220).withValues(alpha: 0.95),
                        getTooltipItems: (touchedSpot) {
                          final index = spots.indexOf(touchedSpot);
                          if (index == -1) return null;
                          final item = visibleFiltered[index];
                          return ScatterTooltipItem(
                            '${item['pitch_type']}\n高さ: ${(item['rel_height'] as num).toStringAsFixed(2)} ft\n横: ${(item['rel_side'] as num).toStringAsFixed(2)} ft\nExt: ${(item['extension'] as num).toStringAsFixed(2)} ft',
                            textStyle: const TextStyle(color: _textPri, fontSize: 11, fontWeight: FontWeight.bold),
                          );
                        },
                      ),
                    ),
                  )),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildReleasePointPage() {
    final grouped = groupBy(analysisData, (dynamic o) => o['date'].toString());
    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(builder: (context, constraints) {
            final sideCol = Column(mainAxisSize: MainAxisSize.min, children: [
              const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text("横位置 (RelSide)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              _buildGraph("RelSide", Colors.indigo, height: 200),
            ]);
            final heightCol = Column(mainAxisSize: MainAxisSize.min, children: [
              const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text("高さ (RelHeight)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              _buildGraph("RelHeight", Colors.teal, height: 200),
            ]);
            final extCol = Column(mainAxisSize: MainAxisSize.min, children: [
              const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text("前への距離 (Extension)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              _buildGraph("Extension", Colors.brown, height: 200),
            ]);
            if (constraints.maxWidth < 480) {
              return Column(children: [sideCol, heightCol, extCol]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: sideCol),
              Expanded(child: heightCol),
              Expanded(child: extCol),
            ]);
          }),
          const Divider(),
          for (int i = 0; i < sortedDates.length; i++)
            _buildDateCard(sortedDates[i], [
              const DataColumn(label: Text('球種')),
              const DataColumn(label: Text('RelSide')),
              const DataColumn(label: Text('RelHeight')),
              const DataColumn(label: Text('Extension')),
            ], grouped[sortedDates[i]]!.map((item) {
              final rs = item['metrics']['RelSide'];
              final rh = item['metrics']['RelHeight'];
              final ex = item['metrics']['Extension'];
              return DataRow(cells: [
                DataCell(Text(item['pitch_type'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                DataCell(Text(((rs?['avg'] ?? 0) as num).toStringAsFixed(2))),
                DataCell(Text(((rh?['avg'] ?? 0) as num).toStringAsFixed(2))),
                DataCell(Text(((ex?['avg'] ?? 0) as num).toStringAsFixed(2))),
              ]);
            }).toList(), i == 0),
        ],
      ),
    );
  }

  Widget _buildPitchMapPage() {
    final Map<String, Color> pitchColors = {
      "Fastball": Colors.red,
      "Sinker": Colors.orange,
      "Curveball": Colors.blue,
      "Slider": Colors.yellow.shade700,
      "Cutter": Colors.brown,
      "Splitter": const Color(0xFF1A237E),
      "Changeup": Colors.green,
    };

    final filtered = selectedMapDate == "すべて"
        ? List<dynamic>.from(pitchMapData)
        : pitchMapData.where((e) => e['date'] == selectedMapDate).toList();

    final visibleFiltered = filtered
        .where((e) => !hiddenPitchTypes.contains(e['pitch_type'].toString()))
        .toList();

    // 平均・楕円の計算は日付フィルター前（年度全体）のデータを使う
    final yearBaseData = pitchMapData
        .where((e) => !hiddenPitchTypes.contains(e['pitch_type'].toString()))
        .toList();

    final List<ScatterSpot> spots = visibleFiltered.map((e) {
      final color = pitchColors[e['pitch_type'].toString()] ?? Colors.black54;
      return ScatterSpot(
        (e['horz'] as num).toDouble(),
        (e['vert'] as num).toDouble(),
        dotPainter: FlDotCirclePainter(radius: 4, color: color.withOpacity(0.7)),
      );
    }).toList();

    final pitchTypes = filtered.map((e) => e['pitch_type'].toString()).toSet().toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: DropdownButtonFormField<String>(
            value: mapDates.contains(selectedMapDate) ? selectedMapDate : "すべて",
            decoration: const InputDecoration(labelText: "日付", filled: true, fillColor: _surface),
            items: mapDates.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
            onChanged: (v) => setState(() => selectedMapDate = v!),
          ),
        ),
        if (filtered.isEmpty)
          const Expanded(child: Center(child: Text("データがありません")))
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Wrap(
              spacing: 12,
              runSpacing: 2,
              children: pitchTypes.map((p) {
                final hidden = hiddenPitchTypes.contains(p);
                final color = pitchColors[p] ?? Colors.black54;
                return GestureDetector(
                  onTap: () => setState(() {
                    if (hidden) {
                      hiddenPitchTypes.remove(p);
                    } else {
                      hiddenPitchTypes.add(p);
                    }
                  }),
                  child: Opacity(
                    opacity: hidden ? 0.3 : 1.0,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                        const SizedBox(width: 4),
                        Text(p, style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          decoration: hidden ? TextDecoration.lineThrough : null,
                        )),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                // プロット面積を実測して縦横スケールを揃える
                const double pad = 8.0, rL = 28.0, rR = 4.0, rT = 4.0, rB = 28.0;
                final pw = (box.maxWidth  - 2 * pad - rL - rR).clamp(1.0, 1e9);
                final ph = (box.maxHeight - 2 * pad - rT - rB).clamp(1.0, 1e9);
                final halfX = pw >= ph ? 60.0 * pw / ph : 60.0;
                final halfY = ph >  pw ? 60.0 * ph / pw : 60.0;

                return Padding(
                  padding: const EdgeInsets.all(pad),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ScatterChart(
                        ScatterChartData(
                          scatterSpots: spots,
                          minX: -halfX, maxX: halfX, minY: -halfY, maxY: halfY,
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(),
                            rightTitles: const AxisTitles(),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 28,
                                interval: 10,
                                getTitlesWidget: (v, meta) => SideTitleWidget(meta: meta, child: Text(v.toStringAsFixed(0), style: const TextStyle(fontSize: 8))),
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 28,
                                interval: 10,
                                getTitlesWidget: (v, meta) => SideTitleWidget(meta: meta, child: Text(v.toStringAsFixed(0), style: const TextStyle(fontSize: 8))),
                              ),
                            ),
                          ),
                          gridData: FlGridData(
                            show: true,
                            horizontalInterval: 10,
                            verticalInterval: 10,
                            getDrawingHorizontalLine: (value) => FlLine(
                              color: value == 0 ? const Color(0xFF94A3B8) : _border,
                              strokeWidth: value == 0 ? 2.0 : 0.5,
                            ),
                            getDrawingVerticalLine: (value) => FlLine(
                              color: value == 0 ? const Color(0xFF94A3B8) : _border,
                              strokeWidth: value == 0 ? 2.0 : 0.5,
                            ),
                          ),
                          borderData: FlBorderData(show: true, border: Border.all(color: _border)),
                          scatterTouchData: ScatterTouchData(
                            enabled: true,
                            touchTooltipData: ScatterTouchTooltipData(
                              getTooltipColor: (_) => const Color(0xFF0C1220).withValues(alpha: 0.95),
                              getTooltipItems: (touchedSpot) {
                                final index = spots.indexOf(touchedSpot);
                                if (index == -1) return null;
                                final item = visibleFiltered[index];
                                final pitchType = item['pitch_type'].toString();
                                final horz = (item['horz'] as num).toStringAsFixed(1);
                                final vert = (item['vert'] as num).toStringAsFixed(1);
                                return ScatterTooltipItem(
                                  '$pitchType\n縦: $vert cm\n横: $horz cm',
                                  textStyle: const TextStyle(
                                    color: _textPri,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      CustomPaint(
                        painter: _PitchMapOverlayPainter(
                          data: visibleFiltered,
                          pitchColors: pitchColors,
                          minX: -halfX, maxX: halfX,
                          minY: -halfY, maxY: halfY,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  void _tryUnlock() {
    if (_pinController.text == _adminPin) {
      setState(() { _adminUnlocked = true; });
      _pinController.clear();
    } else {
      _pinController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PINが違います'), backgroundColor: Colors.red, duration: Duration(seconds: 2)),
      );
    }
  }

  Widget _buildAdminPage() {
    if (!_adminUnlocked) {
      return Center(
        child: Container(
          width: 280,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 12)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock, size: 48, color: _textSec),
              const SizedBox(height: 12),
              const Text('管理者モード', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              TextField(
                controller: _pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 8,
                decoration: const InputDecoration(
                  labelText: 'PIN',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
                onSubmitted: (_) => _tryUnlock(),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _tryUnlock,
                  style: ElevatedButton.styleFrom(backgroundColor: _accent),
                  child: const Text('ロック解除', style: TextStyle(color: _textPri)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ── ロック解除後 ──
    final adminDates = ["すべて",
      ...({for (final e in analysisData) e['date'].toString()}.toList()..sort())
    ];

    return Column(
      children: [
        // ヘッダー
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: const Color(0xFF0C1220),
          child: Row(children: [
            const Icon(Icons.admin_panel_settings, color: Colors.orangeAccent, size: 16),
            const SizedBox(width: 8),
            Text(selectedPlayer ?? '-',
                style: const TextStyle(color: _textPri, fontSize: 15, fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => setState(() => _adminUnlocked = false),
              icon: const Icon(Icons.lock, size: 14, color: _textSec),
              label: const Text('ロック', style: TextStyle(color: _textSec, fontSize: 11)),
            ),
          ]),
        ),

        // 日付フィルター
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
          child: DropdownButtonFormField<String>(
            value: adminDates.contains(selectedReportDate) ? selectedReportDate : "すべて",
            decoration: const InputDecoration(labelText: "日付", filled: true, fillColor: _surface),
            items: adminDates.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
            onChanged: (v) {
              setState(() { selectedReportDate = v!; _aiComment = ''; });
              _updateCommentController();
            },
          ),
        ),

        // 質問入力
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: TextField(
            controller: _questionController,
            decoration: InputDecoration(
              labelText: '分析の観点（任意）',
              hintText: '例：球速が落ちた原因は？ / 前回との変化は？',
              filled: true,
              fillColor: _surface,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              suffixIcon: _aiLoading
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                : IconButton(
                    icon: const Icon(Icons.auto_awesome, color: _accent),
                    tooltip: 'AI分析',
                    onPressed: _fetchAiComment,
                  ),
            ),
            style: const TextStyle(fontSize: 12),
            onSubmitted: (_) => _fetchAiComment(),
          ),
        ),

        // AI コメント + メモ
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // AI コメント
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      color: const Color(0xFF0D1F35),
                      child: const Row(children: [
                        Icon(Icons.auto_awesome, size: 13, color: _accent),
                        SizedBox(width: 4),
                        Text('AI分析', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _accent)),
                      ]),
                    ),
                    Expanded(
                      child: _aiComment.isEmpty
                        ? Center(child: Text('「✨」ボタンを押すと分析します',
                            style: TextStyle(fontSize: 11, color: _textSec)))
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(12),
                            child: Text(_aiComment,
                                style: TextStyle(fontSize: 12, color: _textPri, height: 1.7)),
                          ),
                    ),
                  ],
                ),
              ),

              Container(width: 1, color: _border),

              // メモ
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      color: const Color(0xFF1C1A0A),
                      child: const Row(children: [
                        Icon(Icons.edit_note, size: 13, color: _textSec),
                        SizedBox(width: 4),
                        Text('メモ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _textSec)),
                      ]),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: TextField(
                          controller: _commentController,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: InputDecoration(
                            hintText: '気づいたことを入力...',
                            filled: true,
                            fillColor: const Color(0xFF1C1A0A),
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.all(8),
                            hintStyle: TextStyle(fontSize: 11, color: _textSec),
                          ),
                          style: const TextStyle(fontSize: 12),
                          onChanged: (v) => _saveComment(_commentKey, v),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReportPage() {
    final Map<String, Color> pitchColors = {
      "Fastball": Colors.red,
      "Sinker": Colors.orange,
      "Curveball": Colors.blue,
      "Slider": Colors.yellow.shade700,
      "Cutter": Colors.brown,
      "Splitter": const Color(0xFF1A237E),
      "Changeup": Colors.green,
    };

    // 利用可能な日付リストを analysisData から作成
    final reportDates = ["すべて",
      ...({for (final e in analysisData) e['date'].toString()}.toList()..sort())
    ];

    // 日付フィルター
    final filteredAnalysis = selectedReportDate == "すべて"
        ? analysisData
        : analysisData.where((e) => e['date'] == selectedReportDate).toList();
    final filteredPitchMap = selectedReportDate == "すべて"
        ? pitchMapData
        : pitchMapData.where((e) => e['date'] == selectedReportDate).toList();
    final filteredTilt = selectedReportDate == "すべて"
        ? tiltData
        : tiltData.where((e) => e['date'] == selectedReportDate).toList();
    final filteredPitches = selectedReportDate == "すべて"
        ? pitchesData
        : pitchesData.where((e) => e['date'] == selectedReportDate).toList();

    // 集計テーブル用
    const pitchOrder = ["Fastball", "Sinker", "Curveball", "Slider", "Cutter", "Splitter", "Changeup"];
    final pitchGroups = groupBy(filteredAnalysis, (dynamic e) => e['pitch_type'].toString());
    final allPitchTypes = pitchGroups.keys.toList()
      ..sort((a, b) {
        final ia = pitchOrder.indexOf(a);
        final ib = pitchOrder.indexOf(b);
        return (ia == -1 ? 999 : ia).compareTo(ib == -1 ? 999 : ib);
      });

    // チルト円形平均
    final tiltGroups = groupBy(filteredTilt, (dynamic e) => e['pitch_type'].toString());
    final Map<String, String> avgTiltStr = {};
    for (final entry in tiltGroups.entries) {
      final degs = entry.value.map((e) => (e['tilt_deg'] as num).toDouble()).toList();
      if (degs.isEmpty) continue;
      final s = degs.map((d) => sin(d * pi / 180)).reduce((a, b) => a + b) / degs.length;
      final c = degs.map((d) => cos(d * pi / 180)).reduce((a, b) => a + b) / degs.length;
      double meanDeg = atan2(s, c) * 180 / pi;
      if (meanDeg < 0) meanDeg += 360;
      final total = (meanDeg * 2).round();
      final h = total ~/ 60;
      final m = total % 60;
      avgTiltStr[entry.key] = '${h == 0 ? 12 : h}:${m.toString().padLeft(2, '0')}';
    }

    List<double> mVals(List<dynamic> items, String key, String stat) =>
      items.map((e) {
        final mv = e['metrics'][key];
        if (mv == null) return null;
        final v = (mv[stat] as num).toDouble();
        return (v.isNaN || v.isInfinite || v == 0.0) ? null : v;
      }).where((v) => v != null).cast<double>().toList();

    double mAvg(List<dynamic> items, String key) {
      final vals = mVals(items, key, 'avg');
      return vals.isEmpty ? 0.0 : vals.reduce((a, b) => a + b) / vals.length;
    }

    double mMax(List<dynamic> items, String key) {
      final vals = mVals(items, key, 'max');
      return vals.isEmpty ? 0.0 : vals.reduce((a, b) => a > b ? a : b);
    }

    // 変化量マップ散布点
    final mapSpots = filteredPitchMap.map((e) {
      final color = pitchColors[e['pitch_type'].toString()] ?? Colors.black54;
      return ScatterSpot(
        (e['horz'] as num).toDouble(),
        (e['vert'] as num).toDouble(),
        dotPainter: FlDotCirclePainter(radius: 3, color: color.withOpacity(0.6)),
      );
    }).toList();

    final totalPitches = filteredAnalysis.fold<int>(0, (sum, e) => sum + (e['count'] as int? ?? 0));

    return Column(
      children: [
        // ── ヘッダー ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: const Color(0xFF0C1220),
          child: Row(children: [
            Text(selectedPlayer ?? '-',
                style: const TextStyle(color: _textPri, fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(width: 12),
            Text(selectedYear, style: const TextStyle(color: _textSec, fontSize: 12)),
            const Spacer(),
            Text('総投球数: $totalPitches', style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
          ]),
        ),

        // ── 日付フィルター ──
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
          child: DropdownButtonFormField<String>(
            value: reportDates.contains(selectedReportDate) ? selectedReportDate : "すべて",
            decoration: const InputDecoration(labelText: "日付", filled: true, fillColor: _surface),
            items: reportDates.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
            onChanged: (v) {
              setState(() { selectedReportDate = v!; _aiComment = ''; });
              _updateCommentController();
            },
          ),
        ),

        // ── 変化量マップ + チルト ──
        Expanded(
          flex: 5,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 4, bottom: 2),
                    child: Text("変化量マップ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                  Expanded(
                    child: filteredPitchMap.isEmpty
                      ? const Center(child: Text("データなし", style: TextStyle(color: _textSec, fontSize: 11)))
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 16, 4),
                          child: ScatterChart(ScatterChartData(
                            scatterSpots: mapSpots,
                            minX: -60, maxX: 60, minY: -60, maxY: 60,
                            titlesData: FlTitlesData(
                              topTitles: const AxisTitles(),
                              rightTitles: const AxisTitles(),
                              bottomTitles: AxisTitles(sideTitles: SideTitles(
                                showTitles: true, reservedSize: 20, interval: 20,
                                getTitlesWidget: (v, meta) => SideTitleWidget(meta: meta,
                                    child: Text(v.toStringAsFixed(0), style: const TextStyle(fontSize: 7))),
                              )),
                              leftTitles: AxisTitles(sideTitles: SideTitles(
                                showTitles: true, reservedSize: 26, interval: 20,
                                getTitlesWidget: (v, meta) => SideTitleWidget(meta: meta,
                                    child: Text(v.toStringAsFixed(0), style: const TextStyle(fontSize: 7))),
                              )),
                            ),
                            gridData: FlGridData(
                              show: true, horizontalInterval: 20, verticalInterval: 20,
                              getDrawingHorizontalLine: (v) => FlLine(
                                color: v == 0 ? const Color(0xFF94A3B8) : _border,
                                strokeWidth: v == 0 ? 1.5 : 0.5),
                              getDrawingVerticalLine: (v) => FlLine(
                                color: v == 0 ? const Color(0xFF94A3B8) : _border,
                                strokeWidth: v == 0 ? 1.5 : 0.5),
                            ),
                            borderData: FlBorderData(show: true, border: Border.all(color: _border)),
                            scatterTouchData: ScatterTouchData(enabled: false),
                          )),
                        ),
                  ),
                ]),
              ),
              Container(width: 1, color: _border),
              Expanded(
                child: Column(children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 4, bottom: 2),
                    child: Text("チルト", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                  Expanded(
                    child: filteredTilt.isEmpty
                      ? const Center(child: Text("データなし", style: TextStyle(color: _textSec, fontSize: 11)))
                      : Padding(
                          padding: const EdgeInsets.all(8),
                          child: CustomPaint(
                            painter: _TiltClockPainter(data: filteredTilt, pitchColors: pitchColors),
                            child: const SizedBox.expand(),
                          ),
                        ),
                  ),
                ]),
              ),
            ],
          ),
        ),

        Container(height: 1, color: _border),

        // ── 集計テーブル（左）＋ 一球ごとデータ（右）──
        Expanded(
          flex: 4,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 左：集計テーブル ──
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      color: _surface,
                      child: const Text('集計', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _textSec)),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columnSpacing: 10,
                            dataRowMinHeight: 28,
                            dataRowMaxHeight: 34,
                            headingRowHeight: 30,
                            headingRowColor: const WidgetStatePropertyAll(_surface),
                            headingTextStyle: const TextStyle(
                                color: _textPri, fontWeight: FontWeight.bold, fontSize: 10),
                            dataTextStyle: const TextStyle(fontSize: 10, color: _textSec),
                            columns: const [
                              DataColumn(label: Text('球種')),
                              DataColumn(label: Text('球速avg')),
                              DataColumn(label: Text('球速max')),
                              DataColumn(label: Text('回転数')),
                              DataColumn(label: Text('縦変化')),
                              DataColumn(label: Text('横変化')),
                              DataColumn(label: Text('高さ')),
                              DataColumn(label: Text('横位置')),
                              DataColumn(label: Text('Ext')),
                              DataColumn(label: Text('チルト')),
                            ],
                            rows: allPitchTypes.map((pt) {
                              final items = pitchGroups[pt]!;
                              final color = pitchColors[pt] ?? Colors.black54;
                              return DataRow(cells: [
                                DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                                  Container(width: 7, height: 7,
                                      decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                                  const SizedBox(width: 4),
                                  Text(pt, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10)),
                                ])),
                                DataCell(Text(mAvg(items, 'RelSpeed').toStringAsFixed(1))),
                                DataCell(Text(mMax(items, 'RelSpeed').toStringAsFixed(1),
                                    style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold))),
                                DataCell(Text(mAvg(items, 'SpinRate').toStringAsFixed(0),
                                    style: TextStyle(color: Colors.orange.shade800))),
                                DataCell(Text(mAvg(items, 'InducedVertBreak').toStringAsFixed(1))),
                                DataCell(Text(mAvg(items, 'HorzBreak').toStringAsFixed(1))),
                                DataCell(Text(mAvg(items, 'RelHeight').toStringAsFixed(2))),
                                DataCell(Text(mAvg(items, 'RelSide').toStringAsFixed(2))),
                                DataCell(Text(mAvg(items, 'Extension').toStringAsFixed(2))),
                                DataCell(Text(avgTiltStr[pt] ?? '-',
                                    style: TextStyle(color: Colors.teal.shade700))),
                              ]);
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Container(width: 1, color: _border),

              // ── 中：一球ごとデータ ──
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      color: _surface,
                      child: Text('一球データ (${filteredPitches.length}球)', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _textSec)),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columnSpacing: 10,
                            dataRowMinHeight: 26,
                            dataRowMaxHeight: 30,
                            headingRowHeight: 30,
                            headingRowColor: const WidgetStatePropertyAll(_surface),
                            headingTextStyle: const TextStyle(
                                color: _textPri, fontWeight: FontWeight.bold, fontSize: 10),
                            dataTextStyle: const TextStyle(fontSize: 10, color: _textSec),
                            columns: const [
                              DataColumn(label: Text('日付')),
                              DataColumn(label: Text('球種')),
                              DataColumn(label: Text('球速')),
                              DataColumn(label: Text('回転数')),
                              DataColumn(label: Text('縦変化')),
                              DataColumn(label: Text('横変化')),
                              DataColumn(label: Text('横位置')),
                              DataColumn(label: Text('高さ')),
                              DataColumn(label: Text('Ext')),
                              DataColumn(label: Text('体感速')),
                              DataColumn(label: Text('減衰')),
                              DataColumn(label: Text('チルト')),
                            ],
                            rows: filteredPitches.map((item) {
                              final pt = item['pitch_type'].toString();
                              final color = pitchColors[pt] ?? Colors.black54;
                              String fv(dynamic v, {int dec = 1}) {
                                if (v == null) return '-';
                                final d = (v as num).toDouble();
                                return (d.isNaN || d.isInfinite) ? '-' : d.toStringAsFixed(dec);
                              }
                              return DataRow(cells: [
                                DataCell(Text(item['date'].toString(),
                                    style: const TextStyle(fontSize: 9, color: _textSec))),
                                DataCell(Text(pt,
                                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10))),
                                DataCell(Text(fv(item['speed']))),
                                DataCell(Text(fv(item['spin'], dec: 0),
                                    style: TextStyle(color: Colors.orange.shade800))),
                                DataCell(Text(fv(item['vert']))),
                                DataCell(Text(fv(item['horz']))),
                                DataCell(Text(fv(item['rel_side'], dec: 2))),
                                DataCell(Text(fv(item['rel_height'], dec: 2))),
                                DataCell(Text(fv(item['extension'], dec: 2))),
                                DataCell(Text(fv(item['eff_vel']),
                                    style: TextStyle(color: Colors.purple.shade700))),
                                DataCell(Text(fv(item['decay']),
                                    style: TextStyle(color: Colors.teal.shade700))),
                                DataCell(Text(item['tilt']?.toString() ?? '-')),
                              ]);
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Container(width: 1, color: _border),

              // ── 右：メモ ──
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ヘッダー
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      color: const Color(0xFF1C1A0A),
                      child: const Row(children: [
                        Icon(Icons.edit_note, size: 13, color: _textSec),
                        SizedBox(width: 4),
                        Text('メモ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _textSec)),
                      ]),
                    ),
                    // 手入力メモ
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: TextField(
                          controller: _commentController,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: InputDecoration(
                            hintText: '気づいたことを入力...',
                            filled: true,
                            fillColor: const Color(0xFF1C1A0A),
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.all(8),
                            hintStyle: TextStyle(fontSize: 11, color: _textSec),
                          ),
                          style: const TextStyle(fontSize: 12),
                          onChanged: (v) => _saveComment(_commentKey, v),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTrajectoryPage() {
    final Map<String, Color> pitchColors = {
      "Fastball": Colors.red,
      "Sinker": Colors.orange,
      "Curveball": Colors.blue,
      "Slider": Colors.yellow.shade700,
      "Cutter": Colors.brown,
      "Splitter": const Color(0xFF1A237E),
      "Changeup": Colors.green,
    };

    // 球種ごとの平均メトリクスを計算（全日付の平均）
    final metricKeys = ['RelSpeed', 'ZoneSpeed', 'VertRelAngle', 'HorzRelAngle',
                        'RelSide', 'RelHeight', 'Extension', 'InducedVertBreak', 'HorzBreak'];
    final pitchGroups = groupBy(analysisData, (dynamic e) => e['pitch_type'].toString());
    final Map<String, Map<String, double>> avgMetrics = {};

    for (final entry in pitchGroups.entries) {
      avgMetrics[entry.key] = {};
      for (final mk in metricKeys) {
        final vals = entry.value.map((e) {
          final mv = e['metrics'][mk];
          if (mv == null) return null;
          final v = (mv['avg'] as num).toDouble();
          return (v.isNaN || v.isInfinite || v == 0.0) ? null : v;
        }).where((v) => v != null).cast<double>().toList();
        if (vals.isNotEmpty) {
          avgMetrics[entry.key]![mk] = vals.reduce((a, b) => a + b) / vals.length;
        }
      }
    }

    final pitchTypes = avgMetrics.keys.toList();
    final visibleMetrics = Map<String, Map<String, double>>.fromEntries(
      avgMetrics.entries.where((e) => !hiddenTrajPitchTypes.contains(e.key)),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Wrap(
            spacing: 12,
            runSpacing: 2,
            children: pitchTypes.map((p) {
              final hidden = hiddenTrajPitchTypes.contains(p);
              final color = pitchColors[p] ?? Colors.black54;
              return GestureDetector(
                onTap: () => setState(() {
                  if (hidden) hiddenTrajPitchTypes.remove(p);
                  else hiddenTrajPitchTypes.add(p);
                }),
                child: Opacity(
                  opacity: hidden ? 0.3 : 1.0,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text(p, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                        decoration: hidden ? TextDecoration.lineThrough : null)),
                  ]),
                ),
              );
            }).toList(),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text("実線 = 実軌道　点線 = 変化なし参考（重力のみ）　○ = 曲がり始め(1.5inch)", style: TextStyle(fontSize: 9, color: _textSec)),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text("側面図（高さ）", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 12, 8),
                        child: CustomPaint(
                          painter: _TrajectoryPainter(avgMetrics: visibleMetrics, pitchColors: pitchColors, mode: 'side'),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(width: 1, color: _border),
              Expanded(
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text("上面図（横位置）", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 12, 8),
                        child: CustomPaint(
                          painter: _TrajectoryPainter(avgMetrics: visibleMetrics, pitchColors: pitchColors, mode: 'top'),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTiltPage() {
    final Map<String, Color> pitchColors = {
      "Fastball": Colors.red,
      "Sinker": Colors.orange,
      "Curveball": Colors.blue,
      "Slider": Colors.yellow.shade700,
      "Cutter": Colors.brown,
      "Splitter": const Color(0xFF1A237E),
      "Changeup": Colors.green,
    };

    final filtered = selectedTiltDate == "すべて"
        ? List<dynamic>.from(tiltData)
        : tiltData.where((e) => e['date'] == selectedTiltDate).toList();

    final visibleFiltered = filtered
        .where((e) => !hiddenTiltPitchTypes.contains(e['pitch_type'].toString()))
        .toList();

    final pitchTypes = filtered.map((e) => e['pitch_type'].toString()).toSet().toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: DropdownButtonFormField<String>(
            value: tiltDates.contains(selectedTiltDate) ? selectedTiltDate : "すべて",
            decoration: const InputDecoration(labelText: "日付", filled: true, fillColor: _surface),
            items: tiltDates.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
            onChanged: (v) => setState(() => selectedTiltDate = v!),
          ),
        ),
        if (filtered.isEmpty)
          const Expanded(child: Center(child: Text("データがありません")))
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Wrap(
              spacing: 12,
              runSpacing: 2,
              children: pitchTypes.map((p) {
                final hidden = hiddenTiltPitchTypes.contains(p);
                final color = pitchColors[p] ?? Colors.black54;
                return GestureDetector(
                  onTap: () => setState(() {
                    if (hidden) hiddenTiltPitchTypes.remove(p);
                    else hiddenTiltPitchTypes.add(p);
                  }),
                  child: Opacity(
                    opacity: hidden ? 0.3 : 1.0,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                      Text(p, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, decoration: hidden ? TextDecoration.lineThrough : null)),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text("● 線 = 平均チルト方向　点 = 各投球のチルト", style: TextStyle(fontSize: 9, color: _textSec)),
          ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1.0,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: CustomPaint(
                    painter: _TiltClockPainter(
                      data: visibleFiltered,
                      pitchColors: pitchColors,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDateCard(String date, List<DataColumn> cols, List<DataRow> rows, bool expanded) {
    return Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        elevation: 1,
        child: ExpansionTile(
          initiallyExpanded: expanded,
          title: Text(date, style: const TextStyle(fontWeight: FontWeight.bold, color: _textSec, fontSize: 13)),
          children: [SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(columnSpacing: 20, columns: cols, rows: rows))],
        ));
  }
}

class _PitchMapOverlayPainter extends CustomPainter {
  final List<dynamic> data;
  final Map<String, Color> pitchColors;
  final double minX, maxX, minY, maxY;

  // fl_chart内部のプロット領域オフセット（reservedSize=28 に対応）
  static const double _plotL = 28.0;
  static const double _plotR = 4.0;
  static const double _plotT = 4.0;
  static const double _plotB = 28.0;

  _PitchMapOverlayPainter({
    required this.data,
    required this.pitchColors,
    this.minX = -60, this.maxX = 60,
    this.minY = -60, this.maxY = 60,
  });

  Offset _toPixel(double dataX, double dataY, Size size) {
    final pw = size.width  - _plotL - _plotR;
    final ph = size.height - _plotT - _plotB;
    final px = _plotL + (dataX - minX) / (maxX - minX) * pw;
    final py = _plotT + ph - (dataY - minY) / (maxY - minY) * ph;
    return Offset(px, py);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // (球種, 年) ごとにグループ化
    final Map<String, Map<String, List<({double h, double v})>>> byTypeYear = {};
    for (final e in data) {
      final pt = e['pitch_type'].toString();
      final year = e['date'].toString().split('/')[0];
      final h = (e['horz'] as num).toDouble();
      final v = (e['vert'] as num).toDouble();
      byTypeYear.putIfAbsent(pt, () => {});
      byTypeYear[pt]!.putIfAbsent(year, () => []);
      byTypeYear[pt]![year]!.add((h: h, v: v));
    }

    final pw = size.width - _plotL - _plotR;
    final ph = size.height - _plotT - _plotB;

    for (final ptEntry in byTypeYear.entries) {
      final pt = ptEntry.key;
      final color = pitchColors[pt] ?? Colors.black54;
      final allPoints = ptEntry.value.values.expand((l) => l).toList();
      if (allPoints.isEmpty) continue;

      // 全データの平均・標準偏差（楕円用）
      final meanH = allPoints.map((p) => p.h).reduce((a, b) => a + b) / allPoints.length;
      final meanV = allPoints.map((p) => p.v).reduce((a, b) => a + b) / allPoints.length;
      final stdH = allPoints.length > 1
          ? sqrt(allPoints.map((p) => pow(p.h - meanH, 2)).reduce((a, b) => a + b) / allPoints.length)
          : 0.0;
      final stdV = allPoints.length > 1
          ? sqrt(allPoints.map((p) => pow(p.v - meanV, 2)).reduce((a, b) => a + b) / allPoints.length)
          : 0.0;

      // 楕円（ばらつき）を描画
      if (stdH > 0 || stdV > 0) {
        final center = _toPixel(meanH, meanV, size);
        final rx = stdH / (maxX - minX) * pw;
        final ry = stdV / (maxY - minY) * ph;
        canvas.drawOval(
          Rect.fromCenter(center: center, width: rx * 2, height: ry * 2),
          Paint()..color = color.withOpacity(0.12)..style = PaintingStyle.fill,
        );
        canvas.drawOval(
          Rect.fromCenter(center: center, width: rx * 2, height: ry * 2),
          Paint()..color = color.withOpacity(0.4)..style = PaintingStyle.stroke..strokeWidth = 1.0,
        );
      }

      // 全データの平均マーカーを描画（1点）
      final c = _toPixel(meanH, meanV, size);
      canvas.drawCircle(c, 8, Paint()..color = Colors.white..style = PaintingStyle.fill);
      canvas.drawCircle(c, 7, Paint()..color = color..style = PaintingStyle.fill);
      final cross = Paint()..color = Colors.white..strokeWidth = 1.5..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(c.dx - 4, c.dy), Offset(c.dx + 4, c.dy), cross);
      canvas.drawLine(Offset(c.dx, c.dy - 4), Offset(c.dx, c.dy + 4), cross);
    }
  }

  @override
  bool shouldRepaint(_PitchMapOverlayPainter old) => true;
}

class _TiltClockPainter extends CustomPainter {
  final List<dynamic> data;
  final Map<String, Color> pitchColors;

  _TiltClockPainter({required this.data, required this.pitchColors});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final R = min(size.width, size.height) / 2 * 0.88;

    // 時計の背景
    canvas.drawCircle(center, R, Paint()..color = const Color(0xFF1E293B)..style = PaintingStyle.fill);
    canvas.drawCircle(center, R, Paint()..color = const Color(0xFF475569)..style = PaintingStyle.stroke..strokeWidth = 1.5);

    // 同心円ガイド
    for (final factor in [0.33, 0.66]) {
      canvas.drawCircle(center, R * factor, Paint()
        ..color = const Color(0xFF334155)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5);
    }

    // 時間目盛りとラベル
    for (int h = 0; h < 12; h++) {
      final angle = -pi / 2 + h * pi / 6;
      final isMain = (h % 3 == 0);
      final innerR = isMain ? R * 0.87 : R * 0.92;
      canvas.drawLine(
        Offset(center.dx + innerR * cos(angle), center.dy + innerR * sin(angle)),
        Offset(center.dx + R * cos(angle), center.dy + R * sin(angle)),
        Paint()
          ..color = isMain ? const Color(0xFF94A3B8) : const Color(0xFF475569)
          ..strokeWidth = isMain ? 2.0 : 1.0,
      );

      // 時刻ラベル
      final hour = h == 0 ? 12 : h;
      final labelR = R * 0.76;
      final lx = center.dx + labelR * cos(angle);
      final ly = center.dy + labelR * sin(angle);
      final tp = TextPainter(
        text: TextSpan(
          text: '$hour',
          style: TextStyle(
            color: const Color(0xFF94A3B8),
            fontSize: R * 0.10,
            fontWeight: isMain ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(lx - tp.width / 2, ly - tp.height / 2));
    }

    // 球種ごとにグループ化
    final grouped = <String, List<double>>{};
    for (final e in data) {
      final pt = e['pitch_type'].toString();
      final deg = (e['tilt_deg'] as num).toDouble();
      grouped.putIfAbsent(pt, () => []).add(deg);
    }

    for (final entry in grouped.entries) {
      final pitchType = entry.key;
      final degrees = entry.value;
      final color = pitchColors[pitchType] ?? Colors.black54;

      // 各投球の点（R*0.55 付近にばらつかせて表示）
      for (final deg in degrees) {
        final angle = -pi / 2 + deg * pi / 180;
        const r = 0.55;
        canvas.drawCircle(
          Offset(center.dx + R * r * cos(angle), center.dy + R * r * sin(angle)),
          2.5,
          Paint()..color = color.withOpacity(0.45),
        );
      }

      // 円形平均（circular mean）で平均チルト方向を計算
      if (degrees.isNotEmpty) {
        final radAngles = degrees.map((d) => -pi / 2 + d * pi / 180).toList();
        final meanSin = radAngles.map(sin).reduce((a, b) => a + b) / radAngles.length;
        final meanCos = radAngles.map(cos).reduce((a, b) => a + b) / radAngles.length;
        final meanAngle = atan2(meanSin, meanCos);

        final endR = R * 0.68;
        final endPt = Offset(center.dx + endR * cos(meanAngle), center.dy + endR * sin(meanAngle));

        // 平均方向ライン
        canvas.drawLine(
          center,
          endPt,
          Paint()
            ..color = color
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round,
        );
        // 先端マーカー
        canvas.drawCircle(endPt, 5.0, Paint()..color = color..style = PaintingStyle.fill);
        canvas.drawCircle(endPt, 5.0, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.2);
      }
    }

    // 中心点
    canvas.drawCircle(center, 4.0, Paint()..color = const Color(0xFF0F172A));
  }

  @override
  bool shouldRepaint(_TiltClockPainter old) => true;
}

class _TrajectoryPainter extends CustomPainter {
  final Map<String, Map<String, double>> avgMetrics;
  final Map<String, Color> pitchColors;
  final String mode; // 'side' (height) or 'top' (horizontal)

  static const double _mphToFt = 1.46667;
  static const double _g = 32.174; // ft/s²
  static const int _steps = 80;
  static const double _bpThreshFt = 1.5 / 12.0; // 1.5 inch break threshold

  _TrajectoryPainter({required this.avgMetrics, required this.pitchColors, required this.mode});

  // 物理モデルで軌道を計算
  // Offset.dx = distance from plate (ft), Offset.dy = height or horizontal (ft)
  ({List<Offset> traj, List<Offset> ref, double? bpFrac})? _compute(Map<String, double> m) {
    final relSpeed = m['RelSpeed'];
    final relHeight = m['RelHeight'];
    final extension = m['Extension'];
    if (relSpeed == null || relHeight == null || extension == null) return null;

    final zoneSpeed = (m['ZoneSpeed'] ?? 0.0);
    final effectiveZoneSpeed = zoneSpeed > 10.0 ? zoneSpeed : relSpeed * 0.9;
    final vAngle = (m['VertRelAngle'] ?? 0.0) * pi / 180;
    final hAngle = (m['HorzRelAngle'] ?? 0.0) * pi / 180;
    final relSide = m['RelSide'] ?? 0.0;
    final ivbFt = (m['InducedVertBreak'] ?? 0.0) / 12.0;
    final hbFt = (m['HorzBreak'] ?? 0.0) / 12.0;

    final v0 = relSpeed * _mphToFt;
    final vAvg = (relSpeed + effectiveZoneSpeed) / 2 * _mphToFt;
    final y0 = 60.5 - extension;
    if (y0 <= 0 || vAvg <= 0) return null;

    final T = y0 / vAvg;
    final vx0 = v0 * sin(hAngle);
    final vz0 = v0 * sin(vAngle);

    final List<Offset> traj = [];
    final List<Offset> ref = [];
    double? bpFrac;

    for (int i = 0; i <= _steps; i++) {
      final f = i / _steps;
      final t = f * T;
      final y = y0 * (1 - f);

      if (mode == 'side') {
        // 実軌道：重力 + Magnus縦変化
        final z = relHeight + vz0 * t - _g * t * t / 2 + ivbFt * f * f;
        // 参考線：重力のみ（Magnus無し）
        final zRef = relHeight + vz0 * t - _g * t * t / 2;
        traj.add(Offset(y, z));
        ref.add(Offset(y, zRef));
        if (bpFrac == null && ivbFt.abs() * f * f >= _bpThreshFt) bpFrac = f;
      } else {
        // 実軌道：直線 + Magnus横変化
        final x = relSide + vx0 * t + hbFt * f * f;
        // 参考線：Magnus無し
        final xRef = relSide + vx0 * t;
        traj.add(Offset(y, x));
        ref.add(Offset(y, xRef));
        if (bpFrac == null && hbFt.abs() * f * f >= _bpThreshFt) bpFrac = f;
      }
    }

    return (traj: traj, ref: ref, bpFrac: bpFrac);
  }

  @override
  void paint(Canvas canvas, Size size) {
    const plotL = 38.0, plotR = 10.0, plotT = 8.0, plotB = 26.0;
    final pw = size.width - plotL - plotR;
    final ph = size.height - plotT - plotB;

    // 全球種の軌道を先に計算して軸範囲を決定
    final results = <({String name, List<Offset> traj, List<Offset> ref, double? bpFrac})>[];
    double maxY0 = 0;
    double xzMin = double.infinity, xzMax = double.negativeInfinity;

    for (final entry in avgMetrics.entries) {
      final r = _compute(entry.value);
      if (r == null) continue;
      results.add((name: entry.key, traj: r.traj, ref: r.ref, bpFrac: r.bpFrac));
      for (final pt in [...r.traj, ...r.ref]) {
        if (pt.dx > maxY0) maxY0 = pt.dx;
        if (pt.dy < xzMin) xzMin = pt.dy;
        if (pt.dy > xzMax) xzMax = pt.dy;
      }
    }

    if (results.isEmpty) {
      final tp = TextPainter(
        text: const TextSpan(text: 'データがありません', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width / 2 - tp.width / 2, size.height / 2 - tp.height / 2));
      return;
    }

    final xzRange = max(xzMax - xzMin, 0.5);
    final buf = xzRange * 0.18;
    xzMin -= buf;
    xzMax += buf;

    Offset toCanvas(double y, double xz) => Offset(
      plotL + (1 - y / maxY0) * pw,
      plotT + (1 - (xz - xzMin) / (xzMax - xzMin)) * ph,
    );

    // 背景
    canvas.drawRect(Rect.fromLTWH(plotL, plotT, pw, ph), Paint()..color = const Color(0xFF0F172A));

    // グリッド計算
    final rawInt = (xzMax - xzMin) / 4;
    final mag = pow(10, (log(rawInt <= 0 ? 1 : rawInt) / log(10)).floor()).toDouble();
    final norm = rawInt / mag;
    final gridInt = norm < 1.5 ? mag : norm < 3.5 ? 2 * mag : norm < 7.5 ? 5 * mag : 10 * mag;
    final gridPaint = Paint()..color = const Color(0xFF334155)..strokeWidth = 0.5;
    const labelStyle = TextStyle(color: Color(0xFF94A3B8), fontSize: 8);

    // 横グリッド線とYラベル
    var gv = (xzMin / gridInt).ceil() * gridInt;
    while (gv <= xzMax + gridInt * 0.01) {
      final p1 = toCanvas(maxY0, gv);
      final p2 = toCanvas(0, gv);
      canvas.drawLine(p1, p2, gridPaint);
      final tp = TextPainter(
        text: TextSpan(text: gv.toStringAsFixed(1), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(plotL - tp.width - 3, p1.dy - tp.height / 2));
      gv += gridInt;
    }

    // 縦グリッド線（距離）
    for (int d = 0; d <= maxY0.ceil(); d += 10) {
      final p1 = toCanvas(d.toDouble(), xzMin);
      final p2 = toCanvas(d.toDouble(), xzMax);
      canvas.drawLine(p1, p2, gridPaint);
      final tp = TextPainter(
        text: TextSpan(text: '${d}ft', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(p1.dx - tp.width / 2, plotT + ph + 3));
    }

    // 枠線
    canvas.drawRect(
      Rect.fromLTWH(plotL, plotT, pw, ph),
      Paint()..color = const Color(0xFF334155)..style = PaintingStyle.stroke..strokeWidth = 1.0,
    );

    // ホームベースライン（y=0）
    canvas.drawLine(
      toCanvas(0, xzMin),
      toCanvas(0, xzMax),
      Paint()..color = const Color(0xFF64748B)..strokeWidth = 1.5,
    );

    // 軸ラベル
    final yAxisLabel = mode == 'side' ? '高さ (ft)' : '横位置 (ft)';
    final yTp = TextPainter(
      text: TextSpan(text: yAxisLabel, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 8)),
      textDirection: TextDirection.ltr,
    )..layout();
    yTp.paint(canvas, Offset(2, plotT + ph / 2 - yTp.height / 2));

    final xTp = TextPainter(
      text: const TextSpan(text: '← 投手　　捕手 →', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 8)),
      textDirection: TextDirection.ltr,
    )..layout();
    xTp.paint(canvas, Offset(plotL + pw / 2 - xTp.width / 2, size.height - 14));

    // 軌道を描画
    for (final r in results) {
      final color = pitchColors[r.name] ?? Colors.black54;
      final trajOffsets = r.traj.map((pt) => toCanvas(pt.dx, pt.dy)).toList();
      final refOffsets = r.ref.map((pt) => toCanvas(pt.dx, pt.dy)).toList();

      // 参考線（ダッシュ風：1セグメントおきに描画）
      final refPaint = Paint()
        ..color = color.withOpacity(0.28)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      for (int i = 0; i < refOffsets.length - 1; i += 2) {
        canvas.drawLine(refOffsets[i], refOffsets[i + 1], refPaint);
      }

      // 実軌道（実線）
      final trajPaint = Paint()
        ..color = color
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round;
      for (int i = 0; i < trajOffsets.length - 1; i++) {
        canvas.drawLine(trajOffsets[i], trajOffsets[i + 1], trajPaint);
      }

      // 曲がり始めマーカー
      if (r.bpFrac != null) {
        final idx = (r.bpFrac! * _steps).round().clamp(0, trajOffsets.length - 1);
        canvas.drawCircle(trajOffsets[idx], 5.0, Paint()..color = Colors.white..style = PaintingStyle.fill);
        canvas.drawCircle(trajOffsets[idx], 5.0, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.8);
      }

      // 捕手側の端にラベル
      if (trajOffsets.isNotEmpty) {
        final endPt = trajOffsets.last;
        final labelTp = TextPainter(
          text: TextSpan(text: r.name, style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.bold)),
          textDirection: TextDirection.ltr,
        )..layout();
        final labelX = (endPt.dx + 2).clamp(plotL, size.width - labelTp.width - 2);
        final labelY = (endPt.dy - labelTp.height / 2).clamp(plotT, plotT + ph - labelTp.height);
        labelTp.paint(canvas, Offset(labelX, labelY));
      }
    }
  }

  @override
  bool shouldRepaint(_TrajectoryPainter old) => old.avgMetrics != avgMetrics || old.mode != mode;
}