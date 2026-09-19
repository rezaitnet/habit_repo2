import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// ---------- داده‌ها ----------
class Habit {
  final String id, title, sub, remind;
  final IconData icon;
  final Color color, bg;
  final int hour;
  const Habit(this.id, this.title, this.sub, this.remind, this.icon, this.color,
      this.bg, this.hour);
}

const habits = [
  Habit('ex', 'ورزش کردم', 'ورزش امروز', 'وقت ورزشه', Icons.directions_run,
      Color(0xFF1D9E75), Color(0xFFE1F5EE), 7),
  Habit('study', 'درس خوندم', 'هدف: ۲ ساعت', 'وقت درس خوندنه', Icons.menu_book,
      Color(0xFFBA7517), Color(0xFFFAEEDA), 17),
  Habit('pill', 'قرصم رو خوردم', 'قرص امشب', 'وقت قرصته', Icons.medication,
      Color(0xFF7F77DD), Color(0xFFEEEDFE), 21),
];

const jMonths = ['فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور', 'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند'];
const gMonths = ['ژانویه', 'فوریه', 'مارس', 'آوریل', 'مه', 'ژوئن', 'ژوئیه', 'اوت', 'سپتامبر', 'اکتبر', 'نوامبر', 'دسامبر'];
const jWeek = ['شنبه', 'یکشنبه', 'دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه'];
const gWeek = ['دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه', 'شنبه', 'یکشنبه'];

String two(int n) => n.toString().padLeft(2, '0');
String keyOf(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
String fa(Object n) => n
    .toString()
    .replaceAllMapped(RegExp(r'\d'), (m) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(m[0]!)]);

class AppState extends ChangeNotifier {
  Map<String, Set<String>> done = {};
  bool jalali = true; // پیش‌فرض: شمسی
  Map<String, bool> on = {for (final h in habits) h.id: true};
  Map<String, int> mins = {for (final h in habits) h.id: h.hour * 60};
  late SharedPreferences p;

  Future<void> load() async {
    p = await SharedPreferences.getInstance();
    final d = p.getString('done');
    if (d != null) {
      (jsonDecode(d) as Map<String, dynamic>)
          .forEach((k, v) => done[k] = Set<String>.from(v as List));
    }
    jalali = p.getBool('jalali') ?? true;
    final r = p.getString('rem');
    if (r != null) {
      final m = jsonDecode(r) as Map<String, dynamic>;
      for (final h in habits) {
        if (m[h.id] != null) {
          on[h.id] = m[h.id]['on'] as bool;
          mins[h.id] = m[h.id]['min'] as int;
        }
      }
    }
  }

  Future<void> save() async {
    await p.setString('done', jsonEncode(done.map((k, v) => MapEntry(k, v.toList()))));
    await p.setBool('jalali', jalali);
    await p.setString('rem', jsonEncode({for (final h in habits) h.id: {'on': on[h.id], 'min': mins[h.id]}}));
    notifyListeners();
  }

  bool isDone(String id, DateTime d) => done[keyOf(d)]?.contains(id) ?? false;

  void toggle(String id, DateTime d) {
    final s = done.putIfAbsent(keyOf(d), () => <String>{});
    s.contains(id) ? s.remove(id) : s.add(id);
    save();
  }
}

final state = AppState();

// ---------- یادآور ----------
final plugin = FlutterLocalNotificationsPlugin();

Future<void> initNotif() async {
  tzdata.initializeTimeZones();
  final name = await FlutterTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(name));
  await plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher')));
  await plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
}

Future<void> syncReminders() async {
  try {
    for (var i = 0; i < habits.length; i++) {
      final h = habits[i];
      await plugin.cancel(i);
      if (state.on[h.id] != true) continue;
      final m = state.mins[h.id]!;
      final now = tz.TZDateTime.now(tz.local);
      var t = tz.TZDateTime(tz.local, now.year, now.month, now.day, m ~/ 60, m % 60);
      if (t.isBefore(now)) t = t.add(const Duration(days: 1));
      await plugin.zonedSchedule(
        i,
        h.remind,
        'بعد از انجامش تیکش رو بزن',
        t,
        const NotificationDetails(
          android: AndroidNotificationDetails('habits', 'یادآور عادت‌ها',
              importance: Importance.high, priority: Priority.high),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  } catch (_) {}
}

// ---------- کمکی‌ها ----------
String dateLabel(DateTime d) {
  if (state.jalali) {
    final j = Jalali.fromDateTime(d);
    return '${jWeek[j.weekDay - 1]} ${fa(j.day)} ${jMonths[j.month - 1]}';
  }
  return '${gWeek[d.weekday - 1]} ${fa(d.day)} ${gMonths[d.month - 1]}';
}

int streak() {
  var d = DateTime.now();
  bool all(DateTime x) => habits.every((h) => state.isDone(h.id, x));
  if (!all(d)) d = DateTime(d.year, d.month, d.day - 1);
  var c = 0;
  while (all(d)) {
    c++;
    d = DateTime(d.year, d.month, d.day - 1);
  }
  return c;
}

int daysLeft() {
  final n = DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  DateTime end;
  if (state.jalali) {
    final j = Jalali.now();
    end = Jalali(j.year, 12, Jalali(j.year, 12, 1).monthLength).toDateTime();
  } else {
    end = DateTime(n.year, 12, 31);
  }
  return DateTime(end.year, end.month, end.day).difference(today).inDays;
}

void editDay(BuildContext c, DateTime dt) {
  showModalBottomSheet(
    context: c,
    builder: (_) => ListenableBuilder(
      listenable: state,
      builder: (_, __) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(dateLabel(dt), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (final h in habits)
            CheckboxListTile(
              value: state.isDone(h.id, dt),
              onChanged: (_) => state.toggle(h.id, dt),
              title: Text(h.title),
              secondary: Icon(h.icon, color: h.color),
              activeColor: h.color,
            ),
        ]),
      ),
    ),
  );
}

// ---------- برنامه ----------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await state.load();
  try {
    await initNotif();
    await syncReminders();
  } catch (_) {}
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'عادت‌ها',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF1D9E75)),
        darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorSchemeSeed: const Color(0xFF1D9E75)),
        builder: (c, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const Home(),
      );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int i = 0;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: state,
        builder: (_, __) => Scaffold(
          body: SafeArea(child: [const TodayPage(), const CalendarPage(), const SettingsPage()][i]),
          bottomNavigationBar: NavigationBar(
            selectedIndex: i,
            onDestinationSelected: (v) => setState(() => i = v),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_outlined), label: 'امروز'),
              NavigationDestination(icon: Icon(Icons.calendar_month_outlined), label: 'تقویم'),
              NavigationDestination(icon: Icon(Icons.notifications_outlined), label: 'یادآور'),
            ],
          ),
        ),
      );
}

// ---------- صفحه امروز ----------
class TodayPage extends StatelessWidget {
  const TodayPage({super.key});
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final n = habits.where((h) => state.isDone(h.id, now)).length;
    final cs = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text(dateLabel(now), style: TextStyle(color: cs.onSurfaceVariant)),
      const Text('امروز چطور بود؟', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
      const SizedBox(height: 18),
      Row(children: [
        SizedBox(
          width: 72,
          height: 72,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                  value: n / habits.length,
                  strokeWidth: 8,
                  color: const Color(0xFF1D9E75),
                  backgroundColor: cs.outlineVariant),
            ),
            Text('${fa(n)}/${fa(habits.length)}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(width: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${fa(streak())} روز پشت‌سرهم',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('${fa(daysLeft())} روز تا آخر سال', style: TextStyle(color: cs.onSurfaceVariant)),
        ]),
      ]),
      const SizedBox(height: 22),
      for (final h in habits) HabitCard(h, now),
    ]);
  }
}

class HabitCard extends StatelessWidget {
  final Habit h;
  final DateTime day;
  const HabitCard(this.h, this.day, {super.key});
  @override
  Widget build(BuildContext context) {
    final done = state.isDone(h.id, day);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => state.toggle(h.id, day),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: done ? (dark ? h.color.withOpacity(.25) : h.bg) : Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(.4),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: done ? h.color : Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? h.color : Colors.transparent,
                border: Border.all(color: h.color, width: 2),
              ),
              child: done ? const Icon(Icons.check, color: Colors.white) : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(h.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                Text(done ? 'ثبت شد' : h.sub,
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ]),
            ),
            Icon(h.icon, color: h.color, size: 28),
          ]),
        ),
      ),
    );
  }
}

// ---------- تقویم ----------
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});
  @override
  State<CalendarPage> createState() => _CalState();
}

class _CalState extends State<CalendarPage> {
  DateTime anchor = DateTime.now();

  DateTime shift(int delta) {
    if (state.jalali) {
      final x = Jalali.fromDateTime(anchor);
      var m = x.month + delta, y = x.year;
      while (m > 12) { m -= 12; y++; }
      while (m < 1) { m += 12; y--; }
      return Jalali(y, m, 1).toDateTime();
    }
    return DateTime(anchor.year, anchor.month + delta, 1);
  }

  @override
  Widget build(BuildContext context) {
    final j = state.jalali;
    final cs = Theme.of(context).colorScheme;
    late int len, off;
    late String title;
    late DateTime Function(int) at;
    if (j) {
      final a = Jalali.fromDateTime(anchor);
      final f = Jalali(a.year, a.month, 1);
      len = f.monthLength;
      off = f.weekDay - 1;
      title = '${jMonths[a.month - 1]} ${fa(a.year)}';
      at = (d) => Jalali(a.year, a.month, d).toDateTime();
    } else {
      len = DateTime(anchor.year, anchor.month + 1, 0).day;
      off = DateTime(anchor.year, anchor.month, 1).weekday - 1;
      title = '${gMonths[anchor.month - 1]} ${fa(anchor.year)}';
      at = (d) => DateTime(anchor.year, anchor.month, d);
    }
    final heads = j ? ['ش', 'ی', 'د', 'س', 'چ', 'پ', 'ج'] : ['د', 'س', 'چ', 'پ', 'ج', 'ش', 'ی'];
    final today = keyOf(DateTime.now());
    final nowT = DateTime.now();

    Widget cell(int d) {
      final dt = at(d);
      final isToday = keyOf(dt) == today;
      final future = dt.isAfter(nowT) && !isToday;
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => editDay(context, dt),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: isToday ? const BoxDecoration(color: Color(0xFF1D9E75), shape: BoxShape.circle) : null,
            child: Text(fa(d), style: TextStyle(fontSize: 13, color: isToday ? Colors.white : null)),
          ),
          const SizedBox(height: 3),
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (final h in habits)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: !future && state.isDone(h.id, dt) ? h.color : cs.outlineVariant),
              ),
          ]),
        ]),
      );
    }

    return ListView(padding: const EdgeInsets.all(20), children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => anchor = shift(-1))),
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => anchor = shift(1))),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        for (final x in heads)
          Expanded(child: Center(child: Text(x, style: TextStyle(color: cs.onSurfaceVariant)))),
      ]),
      const SizedBox(height: 6),
      GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: .85,
        children: [for (var i = 0; i < off; i++) const SizedBox(), for (var d = 1; d <= len; d++) cell(d)],
      ),
      const SizedBox(height: 16),
      Row(children: [
        for (final h in habits)
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: h.color.withOpacity(.15), borderRadius: BorderRadius.circular(14)),
              child: Column(children: [
                Icon(h.icon, color: h.color),
                Text(fa([for (var d = 1; d <= len; d++) if (state.isDone(h.id, at(d))) d].length),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                Text('روز', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ]),
            ),
          ),
      ]),
      const SizedBox(height: 8),
      Center(child: Text('برای ویرایش هر روز روی آن بزن', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
    ]);
  }
}

// ---------- تنظیمات و یادآور ----------
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(20), children: [
      const Text('یادآورها', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),
      for (final h in habits)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(h.icon, color: h.color, size: 28),
          title: Text(h.title.replaceAll(' کردم', '').replaceAll(' خوندم', '').replaceAll(' رو خوردم', '')),
          subtitle: Text('هر روز، ${fa(two(state.mins[h.id]! ~/ 60))}:${fa(two(state.mins[h.id]! % 60))}'),
          onTap: () async {
            final m = state.mins[h.id]!;
            final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60));
            if (t != null) {
              state.mins[h.id] = t.hour * 60 + t.minute;
              await state.save();
              await syncReminders();
            }
          },
          trailing: Switch(
            value: state.on[h.id]!,
            activeColor: h.color,
            onChanged: (v) async {
              state.on[h.id] = v;
              await state.save();
              await syncReminders();
            },
          ),
        ),
      const Divider(height: 32),
      const Text('نوع تقویم', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: true, label: Text('شمسی')),
          ButtonSegment(value: false, label: Text('میلادی')),
        ],
        selected: {state.jalali},
        onSelectionChanged: (s) {
          state.jalali = s.first;
          state.save();
        },
      ),
    ]);
  }
}
