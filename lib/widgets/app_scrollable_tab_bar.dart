import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Scrollable tab bar shared by Library, Online search, and similar screens.
///
/// Ivy uses a segmented control; other palettes use the underline style.
class AppScrollableTabBar extends StatelessWidget {
  const AppScrollableTabBar({
    required this.controller,
    required this.tabs,
    super.key,
  });

  final TabController controller;
  final List<Widget> tabs;

  @override
  Widget build(BuildContext context) {
    if (context.appliedThemePalette == AppThemePalette.ivy) {
      return AppIvySegmentedTabBar(controller: controller, tabs: tabs);
    }
    return _AppUnderlineTabBar(controller: controller, tabs: tabs);
  }
}

/// Default palette: matches [LibraryScreen] tab styling.
class _AppUnderlineTabBar extends StatelessWidget {
  const _AppUnderlineTabBar({
    required this.controller,
    required this.tabs,
  });

  final TabController controller;
  final List<Widget> tabs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: TabBar(
        key: ObjectKey(controller),
        controller: controller,
        isScrollable: true,
        padding: const EdgeInsets.only(left: 2, right: 8),
        labelPadding: const EdgeInsets.symmetric(horizontal: 14),
        tabAlignment: TabAlignment.start,
        indicatorColor: pal.onScaffold,
        indicatorWeight: 2.8,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: pal.onScaffold,
        unselectedLabelColor: pal.textMuted.withValues(alpha: 0.76),
        dividerColor: pal.onScaffold.withValues(alpha: 0.14),
        dividerHeight: 1,
        labelStyle: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          fontSize: 15,
        ),
        unselectedLabelStyle: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w500,
          letterSpacing: -0.2,
          fontSize: 15,
        ),
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStateProperty.all<Color>(Colors.transparent),
        tabs: tabs,
      ),
    );
  }
}

/// Ivy palette: pill segmented tab bar (library look).
class AppIvySegmentedTabBar extends StatelessWidget {
  const AppIvySegmentedTabBar({
    required this.controller,
    required this.tabs,
    super.key,
  });

  final TabController controller;
  final List<Widget> tabs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 42,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFC8C8D2).withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(21),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 0.8,
        ),
      ),
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: const Color(0xFF1C1C1E),
        unselectedLabelColor: const Color(0xFF48484A),
        indicator: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: 18),
        labelStyle: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
        unselectedLabelStyle: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStateProperty.all<Color>(Colors.transparent),
        tabs: tabs,
      ),
    );
  }
}
