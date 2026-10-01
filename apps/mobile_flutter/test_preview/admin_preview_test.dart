import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoattend/core/theme.dart';
import 'package:geoattend/screens/admin/admin_shell.dart';
import 'package:geoattend/utils/attendance_logic.dart';
import 'package:geoattend/widgets/common.dart';

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

  const roboto = ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf'];
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

ThemeData previewTheme() {
  final theme = buildAppTheme();
  final label = AppText.button.copyWith(fontFamily: 'Roboto');
  ButtonStyle withFont(ButtonStyle? style) =>
      (style ?? const ButtonStyle()).copyWith(
        textStyle: WidgetStatePropertyAll(label),
      );
  return theme.copyWith(
    appBarTheme: theme.appBarTheme.copyWith(
      titleTextStyle: AppText.heading.copyWith(fontFamily: 'Roboto'),
    ),
    filledButtonTheme:
        FilledButtonThemeData(style: withFont(theme.filledButtonTheme.style)),
    outlinedButtonTheme:
        OutlinedButtonThemeData(style: withFont(theme.outlinedButtonTheme.style)),
    textButtonTheme:
        TextButtonThemeData(style: withFont(theme.textButtonTheme.style)),
  );
}

void main() {
  setUpAll(() async {
    initializeTimezones();
    await loadRealFonts();
  });

  testWidgets('admin drawer', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: previewTheme(),
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: AppColors.sunkStrong,
          body: Align(
            alignment: Alignment.centerLeft,
            child: AdminDrawer(
              index: 0,
              profile: 'Harshit Heya',
              email: 'harshit@sarvaa.co.in',
              onSelect: (_) {},
              onSignOut: () async {},
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('preview/05_admin_drawer.png'),
    );
  });

  testWidgets('admin dashboard body', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: previewTheme(),
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          appBar: AppBar(
            title: const Text('Dashboard'),
            leading: const Icon(Icons.menu_rounded),
            shape: Border(bottom: BorderSide(color: AppColors.hairline)),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(
              Insets.gutter,
              Insets.lg,
              Insets.gutter,
              Insets.huge,
            ),
            children: const [
              PageHeader(title: 'Today', subtitle: 'Friday, 18 September 2026'),
              Row(
                children: [
                  Expanded(
                      child: StatTile(
                          label: 'In office', value: '18', emphasis: true)),
                  SizedBox(width: Insets.md),
                  Expanded(child: StatTile(label: 'From home', value: '4')),
                ],
              ),
              SizedBox(height: Insets.md),
              Row(
                children: [
                  Expanded(child: StatTile(label: 'Absent', value: '2')),
                  SizedBox(width: Insets.md),
                  Expanded(child: StatTile(label: 'Away', value: '1')),
                ],
              ),
              SizedBox(height: Insets.xl),
              GroupedList(
                title: '25 records',
                children: [
                  AppRow(
                    title: 'Harshit Heya',
                    subtitle: '9:05 AM  –  —',
                    trailing: StatusBadge(status: 'PRESENT', compact: true),
                  ),
                  AppRow(
                    title: 'Priya Nair',
                    subtitle: '9:12 AM  –  6:20 PM',
                    trailing: StatusBadge(status: 'CHECKED_OUT', compact: true),
                  ),
                  AppRow(
                    title: 'Arjun Mehta',
                    subtitle: '—  –  —',
                    trailing: StatusBadge(status: 'WFH', compact: true),
                  ),
                  AppRow(
                    title: 'Sneha Rao',
                    subtitle: '—  –  —',
                    trailing: StatusBadge(status: 'ABSENT', compact: true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('preview/06_admin_dashboard.png'),
    );
  });

  testWidgets('reports and settings', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    await tester.pumpWidget(
      MaterialApp(
        theme: previewTheme(),
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          appBar: AppBar(
            title: const Text('Reports'),
            leading: const Icon(Icons.menu_rounded),
            shape: Border(bottom: BorderSide(color: AppColors.hairline)),
          ),
          body: ListView(
            padding: AppPadding.page,
            children: [
              DateRangeBar(
                from: DateTime(2026, 8, 19),
                to: DateTime(2026, 9, 18),
                onPick: (_) {},
              ),
              const SizedBox(height: Insets.md),
              const SectionCard(
                title: 'Priya Nair',
                child: Row(
                  children: [
                    Expanded(
                        child: CountCell(
                            label: 'Present', value: 18, emphasis: true)),
                    Expanded(child: CountCell(label: 'Home', value: 4)),
                    Expanded(child: CountCell(label: 'Leave', value: 0)),
                    Expanded(child: CountCell(label: 'Holiday', value: 2)),
                    Expanded(child: CountCell(label: 'Absent', value: 1)),
                  ],
                ),
              ),
              const SizedBox(height: Insets.xxl),
              const ScreenCaption(
                'These values drive the attendance engine for everyone.',
              ),
              const Eyebrow('Working hours'),
              const SizedBox(height: Insets.sm),
              GroupedList(
                children: [
                  AppRow(
                    title: 'Workday start',
                    onTap: () {},
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('9:00 AM',
                            style: AppText.numeral.copyWith(fontSize: 15)),
                        const SizedBox(width: Insets.sm),
                        Icon(Icons.chevron_right_rounded,
                            size: 18, color: AppColors.faint),
                      ],
                    ),
                  ),
                  AppRow(
                    title: 'Absence cutoff',
                    onTap: () {},
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('12:00 PM',
                            style: AppText.numeral.copyWith(fontSize: 15)),
                        const SizedBox(width: Insets.sm),
                        Icon(Icons.chevron_right_rounded,
                            size: 18, color: AppColors.faint),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Insets.xl),
              const FieldLabel('Working days',
                  hint: 'Absence is only marked on these days.'),
              Row(
                children: [
                  for (var i = 0; i < days.length; i++) ...[
                    if (i > 0) const SizedBox(width: Insets.sm),
                    Expanded(
                      child: DayToggle(
                        label: days[i],
                        selected: i < 6,
                        onTap: () {},
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('preview/07_reports_settings.png'),
    );
  });
}
