import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoattend/core/theme.dart';
import 'package:geoattend/utils/attendance_logic.dart';
import 'package:geoattend/widgets/common.dart';

/// Registers the real Roboto and Material Icons faces the SDK ships, so the
/// captured PNGs show actual glyphs instead of tofu boxes.
Future<void> loadRealFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.path;
  final fonts = '$root/bin/cache/artifacts/material_fonts';

  Future<void> register(String family, List<String> files) async {
    final loader = FontLoader(family);
    var found = false;
    for (final name in files) {
      final file = File('$fonts/$name');
      if (file.existsSync()) {
        found = true;
        loader.addFont(
          Future.value(ByteData.sublistView(file.readAsBytesSync())),
        );
      }
    }
    if (found) await loader.load();
  }

  const roboto = [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ];
  // The default text style resolves to a different family per host platform,
  // so cover the ones a macOS test host may ask for too.
  for (final family in [
    'Roboto',
    '.SF UI Text',
    '.SF UI Display',
    'CupertinoSystemText',
    'CupertinoSystemDisplay',
  ]) {
    await register(family, roboto);
  }
  await register('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

/// The real theme, with button labels pinned to the loaded Roboto face.
///
/// Button themes set an explicit `textStyle`, which replaces rather than
/// merges the family — in a test host that falls back to the box font.
ThemeData previewTheme() {
  final theme = buildAppTheme();
  final label = AppText.button.copyWith(fontFamily: 'Roboto');
  ButtonStyle withFont(ButtonStyle? style) =>
      (style ?? const ButtonStyle()).copyWith(
        textStyle: WidgetStatePropertyAll(label),
      );
  return theme.copyWith(
    filledButtonTheme:
        FilledButtonThemeData(style: withFont(theme.filledButtonTheme.style)),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: withFont(theme.outlinedButtonTheme.style)),
    textButtonTheme:
        TextButtonThemeData(style: withFont(theme.textButtonTheme.style)),
  );
}

void noop() {}

Future<void> shoot(WidgetTester tester, String name, Widget child,
    {Size size = const Size(390, 844)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: previewTheme(),
      debugShowCheckedModeBanner: false,
      home: child,
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('preview/$name.png'),
  );
}

void main() {
  setUpAll(() async {
    initializeTimezones();
    await loadRealFonts();
  });

  const tz = 'Asia/Kolkata';
  final checkIn = DateTime.utc(2026, 9, 18, 3, 35); // 9:05 AM IST
  final checkOut = DateTime.utc(2026, 9, 18, 12, 50); // 6:20 PM IST
  final now = DateTime.utc(2026, 9, 18, 9, 47); // 3:17 PM IST

  testWidgets('today - live', (tester) async {
    await shoot(
      tester,
      '01_today_live',
      Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(Insets.gutter),
            children: [
              const PageHeader(
                title: 'Good afternoon, Harshit',
                subtitle: 'Friday, 18 September',
              ),
              TodayHero(
                status: 'PRESENT',
                now: now,
                timezone: tz,
                checkInAt: checkIn,
              ),
              const SizedBox(height: Insets.md),
              const BusyButton(
                label: 'Check out',
                icon: Icons.logout_rounded,
                onPressed: noop,
              ),
              const SizedBox(height: Insets.md),
              Text(
                'A short work summary is required.',
                textAlign: TextAlign.center,
                style: AppText.bodySm.copyWith(fontSize: 12.5),
              ),
              const SizedBox(height: Insets.lg),
              SectionCard(
                title: 'Workplace',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('Head office',
                              style: AppText.subhead.copyWith(fontSize: 16)),
                        ),
                        Text('150 m', style: AppText.bodySm),
                      ],
                    ),
                    const SizedBox(height: Insets.lg),
                    Container(height: 1, color: AppColors.hairline),
                    const SizedBox(height: Insets.lg),
                    Row(
                      children: [
                        Icon(Icons.sensors_rounded,
                            size: 17, color: AppColors.ink),
                        const SizedBox(width: Insets.md),
                        Expanded(
                          child: Text(
                            'Automatic detection is on. Arrivals and departures '
                            'are recorded for you.',
                            style: AppText.bodySm.copyWith(fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  });

  testWidgets('today - not checked in and checked out', (tester) async {
    await shoot(
      tester,
      '02_today_states',
      Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(Insets.gutter),
            children: [
              const Eyebrow('Not checked in'),
              const SizedBox(height: Insets.sm),
              TodayHero(status: null, now: now, timezone: tz),
              const SizedBox(height: Insets.md),
              const BusyButton(
                label: 'Check in',
                icon: Icons.login_rounded,
                onPressed: noop,
              ),
              const SizedBox(height: Insets.xxl),
              const Eyebrow('Checked out'),
              const SizedBox(height: Insets.sm),
              TodayHero(
                status: 'CHECKED_OUT',
                now: now,
                timezone: tz,
                checkInAt: checkIn,
                checkOutAt: checkOut,
                totalDurationSeconds: 33300,
              ),
              const SizedBox(height: Insets.md),
              OutlinedButton.icon(
                onPressed: noop,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Update work summary'),
              ),
            ],
          ),
        ),
      ),
    );
  });

  testWidgets('component gallery', (tester) async {
    await shoot(
      tester,
      '03_components',
      Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(Insets.gutter),
            children: [
              const PageHeader(title: 'History', subtitle: 'Tap any day.'),
              Row(
                children: const [
                  Expanded(
                      child: StatTile(
                          label: 'Present', value: '18', emphasis: true)),
                  SizedBox(width: Insets.md),
                  Expanded(child: StatTile(label: 'Hours', value: '146h')),
                  SizedBox(width: Insets.md),
                  Expanded(child: StatTile(label: 'Absent', value: '2')),
                ],
              ),
              const SizedBox(height: Insets.lg),
              Wrap(
                spacing: Insets.sm,
                runSpacing: Insets.sm,
                children: [
                  for (final status in statusLabels.keys)
                    StatusBadge(status: status),
                ],
              ),
              const SizedBox(height: Insets.lg),
              const GroupedList(
                title: 'Account',
                children: [
                  AppRow(title: 'Employee ID', subtitle: 'ENG-0142'),
                  AppRow(title: 'Email', subtitle: 'harshit@company.com'),
                  AppRow(title: 'Department', subtitle: 'Engineering'),
                ],
              ),
              const SizedBox(height: Insets.lg),
              DateRangeBar(
                from: DateTime(2026, 8, 19),
                to: DateTime(2026, 9, 18),
                onPick: (_) {},
              ),
              const SizedBox(height: Insets.lg),
              const Notice('Settings saved.', tone: NoticeTone.success),
              const SizedBox(height: Insets.sm),
              const Notice(
                'You are about 240 m from Head office. Move inside to check in.',
                tone: NoticeTone.alert,
              ),
            ],
          ),
        ),
      ),
    );
  });

  testWidgets('checkout sheet', (tester) async {
    await shoot(
      tester,
      '04_sheet',
      Scaffold(
        backgroundColor: AppColors.sunkStrong,
        body: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
            ),
            child: const SheetShell(
              title: 'Check out',
              subtitle: 'A short note on today’s work is required to check out.',
              primaryLabel: 'Confirm check-out',
              children: [
                TextField(
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText:
                        'Shipped the attendance API, reviewed two PRs, ran standup.',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  });

  testWidgets('dark theme', (tester) async {
    AppColors.palette = AppPalette.dark;
    addTearDown(() => AppColors.palette = AppPalette.light);

    await shoot(
      tester,
      '08_dark',
      Scaffold(
        body: SafeArea(
          child: ListView(
            padding: AppPadding.page,
            children: [
              const PageHeader(
                title: 'Good afternoon, Harshit',
                subtitle: 'Friday, 18 September',
              ),
              TodayHero(
                status: 'PRESENT',
                now: now,
                timezone: tz,
                checkInAt: checkIn,
              ),
              const SizedBox(height: Insets.md),
              const BusyButton(
                label: 'Check out',
                icon: Icons.logout_rounded,
                onPressed: noop,
              ),
              const SizedBox(height: Insets.lg),
              Wrap(
                spacing: Insets.sm,
                runSpacing: Insets.sm,
                children: [
                  for (final status in statusLabels.keys)
                    StatusBadge(status: status),
                ],
              ),
              const SizedBox(height: Insets.lg),
              Row(
                children: const [
                  Expanded(
                      child: StatTile(
                          label: 'Present', value: '18', emphasis: true)),
                  SizedBox(width: Insets.md),
                  Expanded(child: StatTile(label: 'Hours', value: '146h')),
                  SizedBox(width: Insets.md),
                  Expanded(child: StatTile(label: 'Absent', value: '2')),
                ],
              ),
              const SizedBox(height: Insets.lg),
              const GroupedList(
                title: 'Account',
                children: [
                  AppRow(title: 'Employee ID', subtitle: 'ENG-0142'),
                  AppRow(title: 'Email', subtitle: 'harshit@company.com'),
                ],
              ),
              const SizedBox(height: Insets.lg),
              const Notice('Settings saved.', tone: NoticeTone.success),
              const SizedBox(height: Insets.sm),
              const Notice(
                'You are about 240 m from Head office.',
                tone: NoticeTone.alert,
              ),
            ],
          ),
        ),
      ),
    );
  });
}
