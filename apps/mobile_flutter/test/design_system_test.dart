import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoattend/app.dart';
import 'package:geoattend/core/theme.dart';
import 'package:geoattend/models/models.dart';
import 'package:geoattend/services/permissions_service.dart';
import 'package:geoattend/utils/attendance_logic.dart';
import 'package:geoattend/widgets/common.dart';
import 'package:geoattend/widgets/month_calendar.dart';

/// A phone-sized surface. Anything that overflows here throws during the test,
/// which is what keeps the 360px standard honest.
Future<void> pumpPhone(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  setUpAll(initializeTimezones);

  group('palette', () {
    tearDown(() => AppColors.palette = AppPalette.light);

    double ratio(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      final high = la > lb ? la : lb;
      final low = la > lb ? lb : la;
      return (high + 0.05) / (low + 0.05);
    }

    for (final entry in {
      'light': AppPalette.light,
      'dark': AppPalette.dark,
    }.entries) {
      final name = entry.key;
      final palette = entry.value;

      test('$name: every colour token is a near-neutral grey', () {
        AppColors.palette = palette;
        final tokens = <Color>[
          AppColors.canvas,
          AppColors.surface,
          AppColors.sunk,
          AppColors.sunkStrong,
          AppColors.hairline,
          AppColors.line,
          AppColors.ink,
          AppColors.inkSoft,
          AppColors.ink2,
          AppColors.muted,
          AppColors.faint,
          AppColors.onInk,
        ];
        for (final color in tokens) {
          // Channel spread, not HSL saturation: near-black neutrals report a
          // high saturation from a one-step channel difference.
          final channels = [color.r, color.g, color.b];
          final spread = channels.reduce((a, b) => a > b ? a : b) -
              channels.reduce((a, b) => a < b ? a : b);
          expect(spread, lessThan(0.05),
              reason: '$color carries too much hue to be a neutral');
        }
      });

      test('$name: text clears the WCAG AA contrast bar', () {
        AppColors.palette = palette;
        expect(ratio(AppColors.ink, AppColors.surface), greaterThan(4.5));
        expect(ratio(AppColors.ink, AppColors.canvas), greaterThan(4.5));
        expect(ratio(AppColors.muted, AppColors.surface), greaterThan(4.5));
        expect(ratio(AppColors.onInk, AppColors.ink), greaterThan(4.5));
      });

      test('$name: hairlines stay visible against their surfaces', () {
        AppColors.palette = palette;
        // A border that matches its background erases the whole system.
        expect(AppColors.hairline, isNot(AppColors.surface));
        expect(AppColors.hairline, isNot(AppColors.canvas));
        expect(ratio(AppColors.line, AppColors.surface), greaterThan(1.1));
      });

      test('$name: only the live state is inverted', () {
        AppColors.palette = palette;
        final inverted =
            statusTones.entries.where((e) => e.value.emphasis).toList();
        expect(inverted.length, 1);
        expect(inverted.single.key, 'PRESENT');
        // Inverted means "fill is the text colour", in either theme.
        expect(inverted.single.value.fill, AppColors.ink);
        expect(inverted.single.value.ink, AppColors.onInk);
      });
    }

    test('the two palettes are genuinely opposite', () {
      expect(AppPalette.light.brightness, Brightness.light);
      expect(AppPalette.dark.brightness, Brightness.dark);
      expect(AppPalette.light.canvas.computeLuminance(),
          greaterThan(AppPalette.dark.canvas.computeLuminance()));
      expect(AppPalette.light.ink.computeLuminance(),
          lessThan(AppPalette.dark.ink.computeLuminance()));
    });

    test('every status has its own tone and glyph', () {
      final glyphs = <IconData>{};
      for (final status in statusLabels.keys) {
        expect(statusTones.containsKey(status), isTrue, reason: status);
        glyphs.add(toneFor(status).glyph);
      }
      expect(glyphs.length, statusLabels.length,
          reason: 'statuses must not share a glyph');
    });
  });

  group('components render at 360px', () {
    testWidgets('status badges for every status', (tester) async {
      await pumpPhone(
        tester,
        SingleChildScrollView(
          child: Column(
            children: [
              for (final status in statusLabels.keys) ...[
                StatusBadge(status: status),
                StatusBadge(status: status, compact: true),
              ],
              const StatusBadge(status: null),
            ],
          ),
        ),
      );
      expect(find.text('Present'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cards, rows, tiles and notices', (tester) async {
      await pumpPhone(
        tester,
        ListView(
          padding: const EdgeInsets.all(Insets.gutter),
          children: const [
            PageHeader(title: 'Today', subtitle: 'Thursday, 18 September'),
            SectionCard(title: 'Work summary', child: Text('Shipped the API.')),
            SizedBox(height: Insets.lg),
            Row(
              children: [
                Expanded(child: StatTile(label: 'Present', value: '18', emphasis: true)),
                SizedBox(width: Insets.md),
                Expanded(child: StatTile(label: 'Absent', value: '2')),
              ],
            ),
            SizedBox(height: Insets.lg),
            GroupedList(
              title: 'Account',
              children: [
                AppRow(title: 'Employee ID', subtitle: 'ENG-0142'),
                AppRow(title: 'Email', subtitle: 'someone@company.com'),
              ],
            ),
            SizedBox(height: Insets.lg),
            DetailRow('Duration', '8h 30m'),
            Notice('Saved.', tone: NoticeTone.success),
            SizedBox(height: Insets.sm),
            Notice('Could not reach the server.', tone: NoticeTone.alert),
          ],
        ),
      );
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('ENG-0142'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty state, skeletons and date range bar', (tester) async {
      await pumpPhone(
        tester,
        Column(
          children: [
            DateRangeBar(
              from: DateTime(2026, 9, 1),
              to: DateTime(2026, 9, 18),
              onPick: (_) {},
            ),
            const Expanded(
              child: EmptyState(
                icon: Icons.inbox_outlined,
                title: 'Nothing recorded yet',
                message: 'Attendance will appear here as it comes in.',
              ),
            ),
          ],
        ),
      );
      expect(find.text('1 Sep 2026'), findsOneWidget);
      expect(find.text('Nothing recorded yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sheet shell lays out title, fields and actions', (tester) async {
      await pumpPhone(
        tester,
        const SheetShell(
          title: 'Check out',
          subtitle: 'A short note is required.',
          primaryLabel: 'Confirm check-out',
          children: [FieldLabel('Summary'), TextField()],
        ),
      );
      expect(find.text('Check out'), findsOneWidget);
      expect(find.text('Confirm check-out'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('five counts share a row without cramping', (tester) async {
      await pumpPhone(
        tester,
        const SectionCard(
          title: 'Priyadarshini Venkataraman',
          child: Row(
            children: [
              Expanded(child: CountCell(label: 'Present', value: 18, emphasis: true)),
              Expanded(child: CountCell(label: 'Home', value: 4)),
              Expanded(child: CountCell(label: 'Leave', value: 0)),
              Expanded(child: CountCell(label: 'Holiday', value: 2)),
              Expanded(child: CountCell(label: 'Absent', value: 11)),
            ],
          ),
        ),
      );
      expect(find.text('Present'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('seven day toggles fit one row', (tester) async {
      const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
      await pumpPhone(
        tester,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Insets.gutter),
          child: Row(
            children: [
              for (var i = 0; i < labels.length; i++) ...[
                if (i > 0) const SizedBox(width: Insets.sm),
                Expanded(
                  child: DayToggle(
                    label: labels[i],
                    selected: i < 6,
                    onTap: () {},
                  ),
                ),
              ],
            ],
          ),
        ),
      );
      expect(find.byType(DayToggle), findsNWidgets(7));
      expect(tester.takeException(), isNull);
    });

    testWidgets('avatars, icon tiles, segmented and search', (tester) async {
      final controller = TextEditingController(text: 'nair');
      addTearDown(controller.dispose);
      await pumpPhone(
        tester,
        ListView(
          padding: AppPadding.page,
          children: [
            Row(
              children: [
                const InitialsAvatar(name: 'Harshit Heya'),
                const SizedBox(width: Insets.md),
                const InitialsAvatar(name: 'Priya Nair', size: 56, inverted: true),
                const SizedBox(width: Insets.md),
                const IconTile(Icons.wb_sunny_outlined),
                const SizedBox(width: Insets.md),
                const InitialsAvatar(name: ''),
              ],
            ),
            const SizedBox(height: Insets.lg),
            Segmented(
              options: const {'employee': 'Employee', 'admin': 'Admin'},
              value: 'admin',
              onChanged: (_) {},
            ),
            const SizedBox(height: Insets.lg),
            SearchField(
              controller: controller,
              hintText: 'Search name, ID or department',
              onChanged: (_) {},
            ),
            const SizedBox(height: Insets.lg),
            const ScreenCaption('Friday, 18 September 2026'),
          ],
        ),
      );
      expect(find.text('HH'), findsOneWidget);
      expect(find.text('PN'), findsOneWidget);
      expect(find.text('?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('busy button swaps its label for a spinner', (tester) async {
      await pumpPhone(
        tester,
        const BusyButton(label: 'Check in', busy: true, onPressed: null),
      );
      expect(find.text('Check in'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('today hero renders live and idle states at 360px',
        (tester) async {
      final now = DateTime(2026, 9, 18, 14, 30);
      await pumpPhone(
        tester,
        SingleChildScrollView(
          padding: AppPadding.page,
          child: Column(
            children: [
              TodayHero(
                status: 'PRESENT',
                now: now,
                timezone: 'Asia/Kolkata',
                checkInAt: DateTime.utc(2026, 9, 18, 9),
              ),
              const SizedBox(height: Insets.lg),
              TodayHero(status: null, now: now, timezone: 'Asia/Kolkata'),
            ],
          ),
        ),
      );
      expect(find.text('PRESENT'), findsOneWidget);
      expect(find.text('NOT CHECKED IN'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('month calendar fits 360px and marks recorded days',
        (tester) async {
      final records = [
        Attendance(
          id: '1',
          userId: 'u',
          date: '2026-09-18',
          status: 'PRESENT',
          source: 'automatic',
          totalDurationSeconds: 8 * 3600,
        ),
        Attendance(
          id: '2',
          userId: 'u',
          date: '2026-09-10',
          status: 'WFH',
          source: 'automatic',
        ),
        Attendance(
          id: '3',
          userId: 'u',
          date: '2026-09-05',
          status: 'LEAVE',
          source: 'manual',
        ),
      ];
      await pumpPhone(
        tester,
        Padding(
          padding: AppPadding.page,
          child: MonthCalendar(
            month: DateTime(2026, 9),
            records: records,
            timezone: 'Asia/Kolkata',
            onSelect: (_) {},
          ),
        ),
      );
      expect(find.text('18'), findsOneWidget);
      expect(find.byType(CalendarDayCell), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('shared helpers', () {
    test('isoDate pads month and day', () {
      expect(isoDate(DateTime(2026, 9, 8)), '2026-09-08');
      expect(isoDate(DateTime(2026, 12, 25)), '2026-12-25');
    });

    test('describeError strips the Exception prefix', () {
      expect(describeError(Exception('Location services are off.')),
          'Location services are off.');
      expect(describeError('plain message'), 'plain message');
    });

    test('formatBusinessDate never throws on bad input', () {
      expect(formatBusinessDate('', 'd MMM y'), '');
      expect(formatBusinessDate('not-a-date', 'd MMM y'), 'not-a-date');
      expect(formatBusinessDate('2026-09-18', 'd MMM y'), '18 Sep 2026');
    });

    test('initials take at most two words', () {
      expect(InitialsAvatar.initialsOf('Harshit Heya'), 'HH');
      expect(InitialsAvatar.initialsOf('  priya  nair  kumar '), 'PN');
      expect(InitialsAvatar.initialsOf('Cher'), 'C');
      expect(InitialsAvatar.initialsOf('   '), '?');
    });
  });

  group('background readiness', () {
    test('every state explains itself', () {
      for (final state in BackgroundReadiness.values) {
        expect(state.title, isNotEmpty, reason: '$state has no title');
        expect(state.message, isNotEmpty, reason: '$state has no message');
      }
    });

    test('only "always" counts as ready, and only it has nothing to do', () {
      for (final state in BackgroundReadiness.values) {
        final ready = state == BackgroundReadiness.always;
        expect(state.isReady, ready, reason: '$state readiness');
        // A blocked state with no action would strand the user.
        expect(state.actionLabel == null, ready,
            reason: '$state should ${ready ? 'not offer' : 'offer'} an action');
      }
    });

    test('foreground-only is treated as not ready', () {
      // The regression that matters: whileInUse looks fine but delivers no
      // background transitions, so it must never report as ready.
      expect(BackgroundReadiness.foregroundOnly.isReady, isFalse);
      expect(BackgroundReadiness.foregroundOnly.actionLabel, isNotNull);
    });
  });

  group('app shells', () {
    testWidgets('splash renders', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(theme: buildAppTheme(), home: const BrandSplash()),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('configuration screen explains the missing dart-defines',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const ConfigMissingApp());
      await tester.pump();
      expect(find.text('Not configured'), findsOneWidget);
      expect(find.textContaining('SUPABASE_URL'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
