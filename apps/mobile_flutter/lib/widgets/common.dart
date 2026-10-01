import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../state/theme_controller.dart';
import '../utils/attendance_logic.dart';

// ---------------------------------------------------------------- typography

/// Small uppercase label. The system's recurring accent in place of colour.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: color == null ? AppText.eyebrow : AppText.eyebrow.copyWith(color: color),
    );
  }
}

/// Screen-level title block used at the top of a scroll view.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.title),
                if (subtitle != null) ...[
                  const SizedBox(height: Insets.xs),
                  Text(subtitle!, style: AppText.bodySm),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: Insets.md), trailing!],
        ],
      ),
    );
  }
}

/// Page padding. Every scrollable view uses one of these, so gutters and
/// bottom clearance are identical everywhere.
class AppPadding {
  const AppPadding._();

  /// Standard scrollable page.
  static const EdgeInsets page = EdgeInsets.fromLTRB(
    Insets.gutter,
    Insets.lg,
    Insets.gutter,
    Insets.huge,
  );

  /// Page that sits under a floating action button.
  static const EdgeInsets pageWithFab = EdgeInsets.fromLTRB(
    Insets.gutter,
    Insets.lg,
    Insets.gutter,
    96,
  );

  /// Page whose first element is a sticky filter bar above the list.
  static const EdgeInsets pageBelowBar = EdgeInsets.fromLTRB(
    Insets.gutter,
    Insets.sm,
    Insets.gutter,
    Insets.huge,
  );

  /// The filter/search bar itself, above a list.
  static const EdgeInsets bar = EdgeInsets.fromLTRB(
    Insets.gutter,
    Insets.lg,
    Insets.gutter,
    Insets.md,
  );
}

// -------------------------------------------------------------------- status

/// Status pill. Meaning comes from fill inversion plus a glyph, not colour.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status, this.compact = false});

  final String? status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tone = toneFor(status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? Insets.sm : Insets.md,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: tone.fill,
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: tone.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(tone.glyph, size: compact ? 9 : 11, color: tone.ink),
          SizedBox(width: compact ? 4 : 6),
          Text(
            statusLabel(status),
            style: TextStyle(
              color: tone.ink,
              fontWeight: FontWeight.w600,
              fontSize: compact ? 11 : 12,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Square status marker for dense grids (the history calendar).
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.status, this.size = 6});

  final String? status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tone = toneFor(status);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tone.emphasis ? AppColors.ink : tone.fill,
        shape: BoxShape.circle,
        border: Border.all(color: tone.border, width: 1),
      ),
    );
  }
}

/// The one block that answers "where do I stand today?" at arm's length.
///
/// It inverts to white-on-ink only while the employee is actively checked in,
/// so the live state is unmistakable without using colour. Data in, no
/// fetching — which keeps it previewable and testable on its own.
class TodayHero extends StatelessWidget {
  const TodayHero({
    super.key,
    required this.status,
    required this.now,
    required this.timezone,
    this.checkInAt,
    this.checkOutAt,
    this.totalDurationSeconds,
    this.visitCount = 0,
  });

  final String? status;
  final DateTime now;
  final String timezone;
  final DateTime? checkInAt;
  final DateTime? checkOutAt;
  final int? totalDurationSeconds;

  /// How many separate office visits were recorded today.
  final int visitCount;

  /// Checked in and not yet out.
  bool get isLive => checkInAt != null && checkOutAt == null;

  @override
  Widget build(BuildContext context) {
    final live = isLive;
    final onInk = live ? AppColors.onInk : AppColors.ink;
    final quiet = live ? AppColors.faint : AppColors.muted;
    final rule = live ? const Color(0x24FFFFFF) : AppColors.hairline;

    String headline;
    var numeric = true;
    String caption;

    if (live) {
      headline = formatDuration(durationSeconds(checkInAt!, now.toUtc()));
      caption = 'Working since ${formatTime(checkInAt, timezone)}';
    } else if (checkOutAt != null) {
      headline = formatDuration(totalDurationSeconds);
      caption = '${formatTime(checkInAt, timezone)}'
          '  –  ${formatTime(checkOutAt, timezone)}';
    } else if (status != null && status != 'PRESENT' && status != 'CHECKED_OUT') {
      headline = statusLabel(status);
      numeric = false;
      caption = DateFormat('d MMMM y').format(now);
    } else {
      headline = formatTime(now.toUtc(), timezone);
      caption = 'You have not checked in today';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(
        Insets.xxl,
        Insets.xxl,
        Insets.xxl,
        Insets.xl,
      ),
      decoration: BoxDecoration(
        color: live ? AppColors.ink : AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.xl),
        border: Border.all(color: live ? AppColors.ink : AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (live) ...[const LivePulse(), const SizedBox(width: Insets.sm)],
              Expanded(
                child: Text(
                  statusLabel(status).toUpperCase(),
                  style: AppText.eyebrow.copyWith(color: quiet, fontSize: 12),
                ),
              ),
              Icon(
                live ? Icons.bolt_rounded : Icons.schedule_rounded,
                size: 18,
                color: quiet,
              ),
            ],
          ),
          const SizedBox(height: Insets.lg),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              headline,
              maxLines: 1,
              style: (numeric ? AppText.display : AppText.title).copyWith(
                color: onInk,
                fontSize: numeric ? 60 : 34,
                letterSpacing: numeric ? -2.4 : -0.8,
              ),
            ),
          ),
          const SizedBox(height: Insets.sm),
          Text(
            caption,
            style: AppText.bodySm.copyWith(color: quiet, fontSize: 14),
          ),
          if (visitCount > 1) ...[
            const SizedBox(height: Insets.xs),
            Text(
              '$visitCount visits today',
              style: AppText.bodySm.copyWith(color: quiet, fontSize: 13),
            ),
          ],
          const SizedBox(height: Insets.xl),
          Container(height: 1, color: rule),
          const SizedBox(height: Insets.lg),
          Row(
            children: [
              Expanded(child: _stat('In', formatTime(checkInAt, timezone), onInk, quiet)),
              Container(width: 1, height: 34, color: rule),
              Expanded(child: _stat('Out', formatTime(checkOutAt, timezone), onInk, quiet)),
              Container(width: 1, height: 34, color: rule),
              Expanded(
                child: _stat(
                  'Total',
                  live
                      ? formatDuration(durationSeconds(checkInAt!, now.toUtc()))
                      : formatDuration(totalDurationSeconds),
                  onInk,
                  quiet,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color ink, Color quiet) {
    return Column(
      children: [
        Eyebrow(label, color: quiet),
        const SizedBox(height: Insets.xs),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.numeral.copyWith(color: ink, fontSize: 15),
        ),
      ],
    );
  }
}

/// Slow breathing dot that marks the live checked-in state.
class LivePulse extends StatefulWidget {
  const LivePulse({super.key});

  @override
  State<LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<LivePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        height: 7,
        width: 7,
        decoration: BoxDecoration(
          color: AppColors.onInk,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ surfaces

/// White card with a hairline border. No shadows anywhere in this system —
/// separation comes from the warm canvas behind it.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(Insets.xl),
  });

  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: Eyebrow(title!)),
                ?trailing,
              ],
            ),
            const SizedBox(height: Insets.lg),
          ],
          child,
        ],
      ),
    );
  }
}

/// Rows grouped inside one bordered container with internal hairlines.
class GroupedList extends StatelessWidget {
  const GroupedList({super.key, required this.children, this.title});

  final List<Widget> children;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: Insets.xs, bottom: Insets.sm),
            child: Eyebrow(title!),
          ),
        ],
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: Insets.lg),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A tappable row for [GroupedList]. 56px minimum target.
class AppRow extends StatelessWidget {
  const AppRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      splashColor: AppColors.sunk,
      highlightColor: AppColors.sunk,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.lg,
          vertical: Insets.lg,
        ),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: Insets.md)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.subhead),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: AppText.bodySm),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: Insets.md), trailing!],
          ],
        ),
      ),
    );
  }
}

/// Someone's initials in a rounded square. One implementation, so the
/// employee list and the profile header cannot drift apart.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({
    super.key,
    required this.name,
    this.size = 36,
    this.inverted = false,
  });

  final String name;
  final double size;

  /// Ink fill with white initials, for the signed-in person's own header.
  final bool inverted;

  static String initialsOf(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed
        .split(RegExp(r'\s+'))
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: inverted ? AppColors.ink : AppColors.sunk,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(
          color: inverted ? AppColors.ink : AppColors.hairline,
        ),
      ),
      child: Text(
        initialsOf(name),
        style: AppText.subhead.copyWith(
          fontSize: size * 0.35,
          letterSpacing: 0.3,
          color: inverted ? AppColors.onInk : AppColors.ink2,
        ),
      ),
    );
  }
}

/// A bordered square holding a single icon — the leading slot of a list row.
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.size = 36});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.sunk,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Icon(icon, size: size * 0.47, color: AppColors.ink2),
    );
  }
}

/// Mutually exclusive choices drawn as one bordered strip. The selected
/// segment is the only inverted element, matching the status system.
class Segmented extends StatelessWidget {
  const Segmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final Map<String, String> options;
  final String value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final keys = options.keys.toList();
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          for (var i = 0; i < keys.length; i++) ...[
            if (i > 0) Container(width: 1, height: 44, color: AppColors.hairline),
            Expanded(
              child: InkWell(
                onTap: onChanged == null ? null : () => onChanged!(keys[i]),
                child: Container(
                  height: 46,
                  alignment: Alignment.center,
                  color: value == keys[i] ? AppColors.ink : Colors.transparent,
                  child: Text(
                    options[keys[i]]!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.subhead.copyWith(
                      fontSize: 14,
                      color: value == keys[i] ? AppColors.onInk : AppColors.muted,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Label above a value, used in stat rows and summary grids.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.emphasis = false,
  });

  final String label;
  final String value;

  /// Inverts the tile (ink fill) to mark the headline figure.
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.lg,
        vertical: Insets.lg,
      ),
      decoration: BoxDecoration(
        color: emphasis ? AppColors.ink : AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: emphasis ? AppColors.ink : AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // One line only, so tiles sitting in a row stay the same height.
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.eyebrow.copyWith(
              color: emphasis ? AppColors.faint : AppColors.muted,
            ),
          ),
          const SizedBox(height: Insets.sm),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.numeralLg.copyWith(
              color: emphasis ? AppColors.onInk : AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// One figure in a dense row of counts. Sits inside a [Row] as an [Expanded]
/// so several share the width evenly; a zero reads greyed, not absent.
class CountCell extends StatelessWidget {
  const CountCell({
    super.key,
    required this.label,
    required this.value,
    this.emphasis = false,
  });

  final String label;
  final int value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          maxLines: 1,
          style: AppText.numeral.copyWith(
            fontSize: 22,
            color: value == 0 ? AppColors.faint : AppColors.ink,
            fontWeight: emphasis ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.bodySm.copyWith(fontSize: 11.5),
        ),
      ],
    );
  }
}

/// One square in a week-wide day selector. Selected days invert to ink.
class DayToggle extends StatelessWidget {
  const DayToggle({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.ink : AppColors.surface,
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(
              color: selected ? AppColors.ink : AppColors.hairline,
            ),
          ),
          child: Text(
            label,
            style: AppText.subhead.copyWith(
              fontSize: 14,
              color: selected ? AppColors.onInk : AppColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Label/value line. Values use tabular figures so columns align.
class DetailRow extends StatelessWidget {
  const DetailRow(this.label, this.value, {super.key, this.dense = false});

  final String label;
  final String value;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 5 : 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: AppText.bodySm)),
          const SizedBox(width: Insets.lg),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppText.numeral.copyWith(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- notices

enum NoticeTone { info, success, alert }

/// Inline message. Severity reads from the glyph and the fill, not colour.
class Notice extends StatelessWidget {
  const Notice(this.message, {super.key, this.tone = NoticeTone.info});

  final String message;
  final NoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final alert = tone == NoticeTone.alert;
    final icon = switch (tone) {
      NoticeTone.info => Icons.info_outlined,
      NoticeTone.success => Icons.check_circle_outlined,
      NoticeTone.alert => Icons.error_outline_rounded,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.lg,
        vertical: Insets.md,
      ),
      decoration: BoxDecoration(
        color: alert ? AppColors.ink : AppColors.sunk,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: alert ? AppColors.ink : AppColors.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: alert ? AppColors.onInk : AppColors.ink),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: alert ? AppColors.onInk : AppColors.ink2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Centred placeholder for empty and error states, with an optional retry.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Insets.huge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 52,
              width: 52,
              decoration: BoxDecoration(
                color: AppColors.sunk,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.hairline),
              ),
              child: Icon(icon, size: 22, color: AppColors.muted),
            ),
            const SizedBox(height: Insets.lg),
            Text(title, textAlign: TextAlign.center, style: AppText.subhead),
            if (message != null) ...[
              const SizedBox(height: Insets.sm),
              Text(message!, textAlign: TextAlign.center, style: AppText.bodySm),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: Insets.xl),
              SizedBox(
                width: 180,
                child: OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Quiet placeholder blocks shown while a screen's first load is in flight.
class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({super.key, this.height = 16, this.width, this.radius = Radii.sm});

  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: AppColors.sunkStrong,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A few skeleton cards. Better than a lone spinner: the layout does not jump.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 4});

  final int count;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(Insets.gutter),
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(height: Insets.md),
      itemBuilder: (context, _) => Container(
        padding: const EdgeInsets.all(Insets.xl),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: AppColors.hairline),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBlock(height: 12, width: 90),
            SizedBox(height: Insets.md),
            SkeletonBlock(height: 18, width: 170),
          ],
        ),
      ),
    );
  }
}

/// Uniform loading / error / empty / content switch.
///
/// Every screen routes through this, so a failure always offers a retry and
/// never leaves a stuck spinner.
class ScreenState extends StatelessWidget {
  const ScreenState({
    super.key,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.child,
    this.isEmpty = false,
    this.empty,
    this.skeleton,
    this.skeletonCount = 4,
  });

  final bool loading;
  final String? error;
  final Future<void> Function() onRetry;
  final Widget child;

  /// Loaded successfully but there is nothing to show.
  final bool isEmpty;
  final Widget? empty;

  /// Placeholder matching this screen's shape; defaults to a card list.
  final Widget? skeleton;
  final int skeletonCount;

  @override
  Widget build(BuildContext context) {
    if (loading) return skeleton ?? SkeletonList(count: skeletonCount);
    if (error != null) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load',
        message: error,
        actionLabel: 'Try again',
        onAction: onRetry,
      );
    }
    if (isEmpty && empty != null) return empty!;
    return child;
  }
}

/// Wraps scrollable content in the app's pull-to-refresh, so the gesture and
/// its colours are identical on every screen.
class Refreshable extends StatelessWidget {
  const Refreshable({super.key, required this.onRefresh, required this.child});

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.ink,
      backgroundColor: AppColors.surface,
      child: child,
    );
  }
}

// -------------------------------------------------------------------- inputs

/// Two tappable date fields, used by every admin screen that filters a range.
class DateRangeBar extends StatelessWidget {
  const DateRangeBar({
    super.key,
    required this.from,
    required this.to,
    required this.onPick,
  });

  final DateTime from;
  final DateTime to;

  /// Called with `true` for the start date, `false` for the end date.
  final ValueChanged<bool> onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Expanded(child: _field('From', from, () => onPick(true))),
          Container(width: 1, height: 44, color: AppColors.hairline),
          Expanded(child: _field('To', to, () => onPick(false))),
        ],
      ),
    );
  }

  Widget _field(String label, DateTime value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.lg,
          vertical: Insets.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Eyebrow(label),
            const SizedBox(height: 3),
            Text(
              DateFormat('d MMM yyyy').format(value),
              style: AppText.numeral.copyWith(fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

/// Light / dark / follow-the-device, as a section card.
///
/// Appearance is a personal preference, so it sits in each person's own
/// settings — including an admin's, separate from the company settings that
/// screen otherwise holds.
class AppearanceCard extends StatelessWidget {
  const AppearanceCard({super.key, required this.controller});

  final ThemeController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => SectionCard(
        title: 'Appearance',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Segmented(
              options: {
                for (final mode in AppThemeMode.values) mode.storageKey: mode.label,
              },
              value: controller.mode.storageKey,
              onChanged: (key) =>
                  controller.setMode(AppThemeMode.fromStorage(key)),
            ),
            const SizedBox(height: Insets.md),
            Row(
              children: [
                Icon(
                  controller.isDark
                      ? Icons.dark_mode_outlined
                      : Icons.light_mode_outlined,
                  size: 16,
                  color: AppColors.muted,
                ),
                const SizedBox(width: Insets.sm),
                Expanded(
                  child: Text(
                    controller.mode == AppThemeMode.system
                        ? 'Following your device, currently '
                            '${controller.isDark ? 'dark' : 'light'}.'
                        : 'Always ${controller.isDark ? 'dark' : 'light'}.',
                    style: AppText.bodySm.copyWith(fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Search input. One implementation, so every list filters the same way.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hintText,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Insets.lg,
          vertical: Insets.md,
        ),
        prefixIcon: const Icon(Icons.search_rounded, size: 19),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: 'Clear',
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
      ),
    );
  }
}

/// One-line context under an app bar. Admin screens take their title from the
/// app bar, so they never repeat it as a [PageHeader].
class ScreenCaption extends StatelessWidget {
  const ScreenCaption(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.lg),
      child: Text(text, style: AppText.bodySm),
    );
  }
}

/// Field caption used above bare inputs inside sheets.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.hint});

  final String text;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow(text),
          if (hint != null) ...[
            const SizedBox(height: 3),
            Text(hint!, style: AppText.bodySm.copyWith(fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

/// Filled button that shows progress in place of its label while working.
class BusyButton extends StatelessWidget {
  const BusyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    this.large = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  /// Taller, bolder treatment for a screen's single primary action.
  final bool large;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      style: large
          ? FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(60),
              textStyle: AppText.button.copyWith(fontSize: 17),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Radii.lg),
              ),
            )
          : null,
      child: busy
          ? SizedBox(
              height: large ? 22 : 19,
              width: large ? 22 : 19,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.faint),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: large ? 21 : 18),
                  SizedBox(width: large ? Insets.md : Insets.sm),
                ],
                Flexible(
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
    );
  }
}

// -------------------------------------------------------------------- sheets

/// Opens a bottom sheet with the app's chrome: safe area, keyboard inset and
/// scroll handling. Pair with [SheetShell] for the standard layout.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: const Color(0x59000000),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: SingleChildScrollView(child: builder(sheetContext)),
    ),
  );
}

/// Standard sheet body: grab handle, title, content, and a two-button footer.
class SheetShell extends StatelessWidget {
  const SheetShell({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel = 'Cancel',
    this.busy = false,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String secondaryLabel;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.gutter,
        Insets.md,
        Insets.gutter,
        Insets.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        // Stretch, not start: a bare TextField handed to [children] has no
        // intrinsic width and would otherwise overflow the sheet.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              height: 4,
              width: 36,
              decoration: BoxDecoration(
                color: AppColors.line,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
            ),
          ),
          const SizedBox(height: Insets.xl),
          Text(title, style: AppText.title.copyWith(fontSize: 22)),
          if (subtitle != null) ...[
            const SizedBox(height: Insets.xs),
            Text(subtitle!, style: AppText.bodySm),
          ],
          const SizedBox(height: Insets.xxl),
          ...children,
          if (primaryLabel != null) ...[
            const SizedBox(height: Insets.xxl),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : () => Navigator.of(context).pop(),
                    child: Text(
                      secondaryLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  flex: 2,
                  child: BusyButton(
                    label: primaryLabel!,
                    busy: busy,
                    onPressed: onPrimary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Collects the mandatory work summary (minimum 3 characters).
Future<String?> showCheckoutSheet(
  BuildContext context, {
  required String initialSummary,
  bool isUpdate = false,
}) {
  return showAppSheet<String>(
    context,
    builder: (context) => _CheckoutSheet(
      initialSummary: initialSummary,
      isUpdate: isUpdate,
    ),
  );
}

class _CheckoutSheet extends StatefulWidget {
  const _CheckoutSheet({required this.initialSummary, required this.isUpdate});

  final String initialSummary;
  final bool isUpdate;

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialSummary);
  String? _error;
  int _length = 0;

  @override
  void initState() {
    super.initState();
    _length = _controller.text.trim().length;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final summary = _controller.text.trim();
    if (summary.length < 3) {
      setState(() => _error = 'Add at least a few words about what you worked on.');
      return;
    }
    Navigator.of(context).pop(summary);
  }

  @override
  Widget build(BuildContext context) {
    return SheetShell(
      title: widget.isUpdate ? 'Update summary' : 'Check out',
      subtitle: widget.isUpdate
          ? 'Revise what you recorded for today.'
          : 'A short note on today’s work is required to check out.',
      primaryLabel: widget.isUpdate ? 'Save summary' : 'Confirm check-out',
      onPrimary: _submit,
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (value) => setState(() {
            _length = value.trim().length;
            _error = null;
          }),
          decoration: const InputDecoration(
            hintText: 'Shipped the attendance API, reviewed two PRs, ran standup.',
          ),
        ),
        const SizedBox(height: Insets.sm),
        Row(
          children: [
            Expanded(
              child: Text(
                _length < 3 ? 'Minimum 3 characters' : 'Looks good',
                style: AppText.bodySm.copyWith(fontSize: 12),
              ),
            ),
            Text('$_length', style: AppText.bodySm.copyWith(fontSize: 12)),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: Insets.md),
          Notice(_error!, tone: NoticeTone.alert),
        ],
      ],
    );
  }
}

/// Collects a date and an optional reason for a work-from-home request.
///
/// Returns `(date, reason)` or null. Only future dates are offered, because
/// the database refuses a backdated request outright.
Future<({DateTime date, String? reason})?> showWfhRequestSheet(
  BuildContext context,
) {
  return showAppSheet<({DateTime date, String? reason})>(
    context,
    builder: (context) => const _WfhRequestSheet(),
  );
}

class _WfhRequestSheet extends StatefulWidget {
  const _WfhRequestSheet();

  @override
  State<_WfhRequestSheet> createState() => _WfhRequestSheetState();
}

class _WfhRequestSheetState extends State<_WfhRequestSheet> {
  final _reason = TextEditingController();
  late DateTime _date = DateTime.now().add(const Duration(days: 1));

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    return SheetShell(
      title: 'Work from home',
      subtitle: 'Your manager approves this. Until then the day is unchanged.',
      primaryLabel: 'Send request',
      onPrimary: () => Navigator.of(context).pop(
        (
          date: _date,
          reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
        ),
      ),
      children: [
        const FieldLabel('Date'),
        InkWell(
          onTap: _pickDate,
          borderRadius: BorderRadius.circular(Radii.md),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.lg,
              vertical: Insets.lg,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    DateFormat('EEEE, d MMMM y').format(_date),
                    style: AppText.numeral.copyWith(fontSize: 15),
                  ),
                ),
                Icon(Icons.calendar_today_outlined,
                    size: 17, color: AppColors.muted),
              ],
            ),
          ),
        ),
        const SizedBox(height: Insets.xl),
        const FieldLabel('Reason', hint: 'Optional, but it helps.'),
        TextField(
          controller: _reason,
          textCapitalization: TextCapitalization.sentences,
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: 'Deliveries at home all day.',
          ),
        ),
      ],
    );
  }
}

/// Collects a date, a leave type and a mandatory reason for a leave request.
///
/// Returns `(date, type, reason)` or null. Only today and future dates are
/// offered, because the database refuses a backdated request outright.
Future<({DateTime date, LeaveType type, String reason})?> showLeaveRequestSheet(
  BuildContext context,
) {
  return showAppSheet<({DateTime date, LeaveType type, String reason})>(
    context,
    builder: (context) => const _LeaveRequestSheet(),
  );
}

class _LeaveRequestSheet extends StatefulWidget {
  const _LeaveRequestSheet();

  @override
  State<_LeaveRequestSheet> createState() => _LeaveRequestSheetState();
}

class _LeaveRequestSheetState extends State<_LeaveRequestSheet> {
  final _reason = TextEditingController();
  LeaveType _type = LeaveType.sick;
  late DateTime _date = DateTime.now().add(const Duration(days: 1));
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _submit() {
    final reason = _reason.text.trim();
    if (reason.length < 3) {
      setState(() => _error = 'Tell your manager why you need the day off.');
      return;
    }
    Navigator.of(context).pop((date: _date, type: _type, reason: reason));
  }

  @override
  Widget build(BuildContext context) {
    return SheetShell(
      title: 'Request leave',
      subtitle: 'Your manager approves this. A reason is required.',
      primaryLabel: 'Send request',
      onPrimary: _submit,
      children: [
        const FieldLabel('Date'),
        InkWell(
          onTap: _pickDate,
          borderRadius: BorderRadius.circular(Radii.md),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.lg,
              vertical: Insets.lg,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    DateFormat('EEEE, d MMMM y').format(_date),
                    style: AppText.numeral.copyWith(fontSize: 15),
                  ),
                ),
                Icon(Icons.calendar_today_outlined,
                    size: 17, color: AppColors.muted),
              ],
            ),
          ),
        ),
        const SizedBox(height: Insets.xl),
        const FieldLabel('Type'),
        Segmented(
          options: {for (final type in LeaveType.values) type.value: type.label},
          value: _type.value,
          onChanged: (value) => setState(() => _type = LeaveType.fromValue(value)),
        ),
        const SizedBox(height: Insets.xl),
        const FieldLabel('Reason', hint: 'Required. They will see this.'),
        TextField(
          controller: _reason,
          textCapitalization: TextCapitalization.sentences,
          maxLines: 3,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          decoration: const InputDecoration(
            hintText: 'Recovering from a fever and resting at home.',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: Insets.md),
          Notice(_error!, tone: NoticeTone.alert),
        ],
      ],
    );
  }
}

/// The full detail of one recorded day, as a bottom sheet. Shared by Today and
/// History so both tell the same story.
void showDayDetailSheet(
  BuildContext context,
  Attendance record,
  String timezone,
) {
  showAppSheet<void>(
    context,
    builder: (context) => SheetShell(
      title: formatBusinessDate(record.date, 'EEEE, d MMMM'),
      subtitle: formatBusinessDate(record.date, 'y'),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: StatusBadge(status: record.status),
        ),
        const SizedBox(height: Insets.xl),
        DetailRow('Check-in', formatTime(record.checkInAt, timezone)),
        const Divider(height: Insets.lg),
        DetailRow('Check-out', formatTime(record.checkOutAt, timezone)),
        const Divider(height: Insets.lg),
        DetailRow('Duration', formatDuration(record.totalDurationSeconds)),
        const Divider(height: Insets.lg),
        DetailRow(
          'Recorded by',
          record.source == 'manual' ? 'Admin correction' : 'Automatic',
        ),
        if (record.workSummary != null &&
            record.workSummary!.trim().isNotEmpty) ...[
          const SizedBox(height: Insets.xxl),
          const Eyebrow('Work summary'),
          const SizedBox(height: Insets.sm),
          Text(record.workSummary!, style: AppText.body),
        ],
      ],
    ),
  );
}

/// Confirmation dialog for destructive actions.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message, style: AppText.body),
      actionsPadding: const EdgeInsets.fromLTRB(Insets.lg, 0, Insets.lg, Insets.lg),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Brief confirmation, so an action never completes silently.
void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.all(Insets.lg),
      ),
    );
}
