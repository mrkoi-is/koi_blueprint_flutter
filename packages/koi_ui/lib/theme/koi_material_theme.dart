import 'package:flutter/material.dart';
import 'package:koi_ui/theme/koi_theme_tokens.dart';

/// Material remains responsible for input, semantics, focus and dismissal.
/// This shared policy only changes presentation; apps use standard widgets.
ThemeData applyKoiMaterialTheme(ThemeData base, KoiThemeTokens tokens) {
  final colors = base.colorScheme;
  final text = base.textTheme;
  final density = tokens.density;
  final tapTarget = density == KoiDensity.compact
      ? MaterialTapTargetSize.shrinkWrap
      : MaterialTapTargetSize.padded;
  final disabled = colors.onSurface.withValues(alpha: .38);
  final disabledFill = colors.onSurface.withValues(alpha: .12);
  final foreground = WidgetStateProperty.resolveWith<Color>(
    (states) =>
        states.contains(WidgetState.disabled) ? disabled : colors.onSurface,
  );
  final interaction = WidgetStateProperty.resolveWith<Color>((states) {
    if (states.contains(WidgetState.disabled)) return Colors.transparent;
    if (states.contains(WidgetState.pressed)) {
      return colors.onSurface.withValues(alpha: .12);
    }
    if (states.contains(WidgetState.focused)) {
      return colors.onSurface.withValues(alpha: .10);
    }
    if (states.contains(WidgetState.hovered)) {
      return colors.onSurface.withValues(alpha: .06);
    }
    return Colors.transparent;
  });
  final selection = WidgetStateProperty.resolveWith<Color>((states) {
    if (states.contains(WidgetState.disabled)) return disabled;
    if (states.contains(WidgetState.error)) return colors.error;
    return states.contains(WidgetState.selected)
        ? colors.primary
        : colors.onSurfaceVariant;
  });
  BorderSide focusSide(Set<WidgetState> states) =>
      states.contains(WidgetState.focused) &&
          !states.contains(WidgetState.disabled)
      ? BorderSide(color: colors.primary, width: 2)
      : const BorderSide(color: Colors.transparent, width: 2);
  final overlayShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(KoiRadius.medium),
    side: BorderSide(color: tokens.weakBorder),
  );
  final menu = MenuStyle(
    backgroundColor: WidgetStatePropertyAll(tokens.overlayBackground),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(3),
    padding: const WidgetStatePropertyAll(EdgeInsets.all(KoiSpace.xs)),
    shape: WidgetStatePropertyAll(overlayShape),
  );
  final outline = OutlineInputBorder(
    borderRadius: BorderRadius.circular(KoiRadius.small),
    borderSide: BorderSide(color: colors.outline),
  );
  final button = ButtonStyle(
    textStyle: WidgetStatePropertyAll(text.labelLarge),
    minimumSize: WidgetStatePropertyAll(Size(0, tokens.controlHeight)),
    padding: WidgetStatePropertyAll(tokens.controlPadding),
    iconSize: WidgetStatePropertyAll(density == KoiDensity.compact ? 18 : 20),
    side: WidgetStateProperty.resolveWith(focusSide),
    animationDuration: const Duration(milliseconds: 120),
    visualDensity: VisualDensity.standard,
    tapTargetSize: density == KoiDensity.compact
        ? MaterialTapTargetSize.shrinkWrap
        : MaterialTapTargetSize.padded,
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KoiRadius.small),
      ),
    ),
  );
  final input = InputDecorationThemeData(
    filled: true,
    isDense: true,
    fillColor: colors.surfaceContainerLow,
    hintStyle: text.bodyMedium!.copyWith(color: colors.onSurfaceVariant),
    labelStyle: text.bodyMedium,
    helperStyle: text.bodySmall,
    errorStyle: text.bodySmall!.copyWith(color: colors.error),
    errorMaxLines: 3,
    border: outline,
    enabledBorder: outline,
    disabledBorder: outline.copyWith(
      borderSide: BorderSide(color: disabledFill),
    ),
    errorBorder: outline.copyWith(borderSide: BorderSide(color: colors.error)),
    focusedErrorBorder: outline.copyWith(
      borderSide: BorderSide(color: colors.error, width: 2),
    ),
    focusedBorder: outline.copyWith(
      borderSide: BorderSide(color: colors.primary, width: 2),
    ),
    contentPadding: tokens.inputPadding,
  );
  return base.copyWith(
    textTheme: text,
    extensions: [tokens],
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: tapTarget,
    splashFactory: density == KoiDensity.compact
        ? NoSplash.splashFactory
        : InkSparkle.splashFactory,
    hoverColor: colors.onSurface.withValues(alpha: .06),
    focusColor: colors.primary.withValues(alpha: .12),
    disabledColor: disabled,
    iconTheme: IconThemeData(size: 20, color: colors.onSurfaceVariant),
    scaffoldBackgroundColor: tokens.chromeBackground,
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.chromeBackground,
      foregroundColor: colors.onSurface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: text.titleSmall,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KoiRadius.medium),
        side: BorderSide(color: tokens.weakBorder),
      ),
    ),
    inputDecorationTheme: input,
    filledButtonTheme: FilledButtonThemeData(
      style: button.copyWith(
        // A contrasting inner band makes focus visible on both primary and
        // tonal fills; the outer primary stroke is shared with other buttons.
        backgroundBuilder: (context, states, child) => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KoiRadius.small),
            border: Border.all(
              color:
                  states.contains(WidgetState.focused) &&
                      !states.contains(WidgetState.disabled)
                  ? colors.onPrimary
                  : Colors.transparent,
              width: 4,
            ),
          ),
          child: child,
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: button.copyWith(
        elevation: const WidgetStatePropertyAll(0),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? disabledFill
              : tokens.overlayBackground,
        ),
        foregroundColor: foreground,
        overlayColor: interaction,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: button.copyWith(
        foregroundColor: foreground,
        overlayColor: interaction,
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return BorderSide(color: disabledFill);
          }
          if (states.contains(WidgetState.focused)) return focusSide(states);
          return BorderSide(color: colors.outline);
        }),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: button.copyWith(
        foregroundColor: foreground,
        overlayColor: interaction,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: button.copyWith(
        minimumSize: WidgetStatePropertyAll(Size.square(tokens.controlHeight)),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
        textStyle: null,
        foregroundColor: foreground,
        overlayColor: interaction,
      ),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: text.bodyMedium,
      subtitleTextStyle: text.bodySmall,
      minTileHeight: tokens.listTileHeight,
      minVerticalPadding: 6,
      contentPadding: EdgeInsets.symmetric(
        horizontal: tokens.listHorizontalPadding,
      ),
      selectedColor: colors.onSurface,
      selectedTileColor: tokens.selectedBackground,
    ),
    chipTheme: ChipThemeData(
      labelStyle: text.labelMedium,
      secondaryLabelStyle: text.labelMedium,
      backgroundColor: colors.surface,
      selectedColor: tokens.selectedBackground,
      secondarySelectedColor: tokens.selectedBackground,
      disabledColor: disabledFill,
      checkmarkColor: colors.onSurface,
      side: WidgetStateBorderSide.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return BorderSide(color: disabledFill);
        }
        if (states.contains(WidgetState.focused)) return focusSide(states);
        return BorderSide(color: colors.outline);
      }),
      padding: EdgeInsets.symmetric(
        horizontal: KoiSpace.xs,
        vertical: density == KoiDensity.compact ? 2 : KoiSpace.sm,
      ),
      elevation: 0,
      pressElevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KoiRadius.row),
      ),
    ),
    menuTheme: MenuThemeData(style: menu),
    menuBarTheme: MenuBarThemeData(
      style: menu.copyWith(elevation: const WidgetStatePropertyAll(0)),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: button.copyWith(
        textStyle: WidgetStatePropertyAll(text.bodyMedium),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? colors.onSurface.withValues(alpha: .38)
              : colors.onSurface,
        ),
        overlayColor: interaction,
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KoiRadius.row),
          ),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.overlayBackground,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: text.headlineSmall,
      contentTextStyle: text.bodyMedium,
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KoiRadius.dialog),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: tokens.chromeBackground,
      surfaceTintColor: Colors.transparent,
      indicatorColor: tokens.selectedBackground,
      labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: tokens.chromeBackground,
      useIndicator: true,
      minWidth: KoiWorkbenchMetrics.railWidth,
      indicatorColor: tokens.selectedBackground,
      selectedIconTheme: IconThemeData(size: 22, color: colors.onSurface),
      unselectedIconTheme: IconThemeData(
        size: 22,
        color: colors.onSurfaceVariant,
      ),
    ),
    dividerTheme: DividerThemeData(color: tokens.weakBorder, space: 1),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return disabledFill;
        if (states.contains(WidgetState.selected)) {
          return states.contains(WidgetState.error)
              ? colors.error
              : colors.primary;
        }
        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? disabled
            : states.contains(WidgetState.error)
            ? colors.onError
            : colors.onPrimary,
      ),
      side: WidgetStateBorderSide.resolveWith(
        (states) => BorderSide(
          color: states.contains(WidgetState.disabled)
              ? disabled
              : states.contains(WidgetState.error)
              ? colors.error
              : states.contains(WidgetState.selected)
              ? Colors.transparent
              : colors.outline,
          width: 1.5,
        ),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      materialTapTargetSize: tapTarget,
      visualDensity: VisualDensity.standard,
    ),
    radioTheme: RadioThemeData(
      fillColor: selection,
      materialTapTargetSize: tapTarget,
      visualDensity: VisualDensity.standard,
    ),
    switchTheme: SwitchThemeData(
      materialTapTargetSize: tapTarget,
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return disabledFill;
        return states.contains(WidgetState.selected)
            ? colors.primary
            : colors.surfaceContainerHighest;
      }),
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return disabled;
        return states.contains(WidgetState.selected)
            ? colors.onPrimary
            : colors.onSurfaceVariant;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return disabledFill;
        return states.contains(WidgetState.selected)
            ? Colors.transparent
            : colors.outline;
      }),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: button.copyWith(
        foregroundColor: foreground,
        overlayColor: interaction,
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? tokens.selectedBackground
              : Colors.transparent,
        ),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return BorderSide(color: disabledFill);
          }
          if (states.contains(WidgetState.focused)) return focusSide(states);
          return BorderSide(color: colors.outline);
        }),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      inputDecorationTheme: input,
      textStyle: text.bodyMedium,
      menuStyle: menu,
      disabledColor: disabled,
    ),
    searchBarTheme: SearchBarThemeData(
      backgroundColor: WidgetStatePropertyAll(colors.surfaceContainerLow),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(0),
      textStyle: WidgetStatePropertyAll(text.bodyMedium),
      hintStyle: WidgetStatePropertyAll(
        text.bodyMedium!.copyWith(color: colors.onSurfaceVariant),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KoiRadius.small),
        ),
      ),
      side: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? focusSide(states)
            : BorderSide(color: colors.outline),
      ),
    ),
    searchViewTheme: SearchViewThemeData(
      backgroundColor: tokens.overlayBackground,
      surfaceTintColor: Colors.transparent,
      headerTextStyle: text.bodyMedium,
      headerHintStyle: text.bodyMedium!.copyWith(
        color: colors.onSurfaceVariant,
      ),
      dividerColor: tokens.weakBorder,
      shape: overlayShape,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: tokens.overlayBackground,
      surfaceTintColor: Colors.transparent,
      shape: overlayShape,
      elevation: 3,
      menuPadding: const EdgeInsets.all(KoiSpace.xs),
      textStyle: text.bodyMedium,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) =>
            text.bodyMedium!.copyWith(color: foreground.resolve(states)),
      ),
      iconColor: colors.onSurfaceVariant,
      iconSize: 20,
    ),
    tabBarTheme: TabBarThemeData(
      labelStyle: text.labelLarge,
      unselectedLabelStyle: text.labelLarge,
      labelColor: colors.onSurface,
      unselectedLabelColor: colors.onSurfaceVariant,
      indicatorColor: colors.primary,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: tokens.weakBorder,
      overlayColor: interaction,
      splashBorderRadius: BorderRadius.circular(KoiRadius.row),
    ),
    dataTableTheme: DataTableThemeData(
      dataTextStyle: text.bodyMedium,
      headingTextStyle: text.labelLarge,
      dataRowMinHeight: tokens.controlHeight,
      // Finite for AnimatedTheme interpolation. Rows can grow to four lines
      // of baseline control height; unbounded document cells are host-owned.
      dataRowMaxHeight: tokens.controlHeight * 4,
      headingRowHeight: 56,
      horizontalMargin: KoiSpace.md,
      columnSpacing: KoiSpace.lg,
      dividerThickness: .5,
      headingRowColor: WidgetStatePropertyAll(tokens.panelBackground),
      dataRowColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? tokens.selectedBackground
            : null,
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colors.inverseSurface,
        borderRadius: BorderRadius.circular(KoiRadius.row),
      ),
      textStyle: text.bodySmall!.copyWith(color: colors.onInverseSurface),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      margin: const EdgeInsets.all(KoiSpace.sm),
      waitDuration: const Duration(milliseconds: 500),
      showDuration: const Duration(seconds: 3),
      exitDuration: const Duration(milliseconds: 100),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.inverseSurface,
      contentTextStyle: text.bodyMedium!.copyWith(
        color: colors.onInverseSurface,
      ),
      actionTextColor: colors.inversePrimary,
      closeIconColor: colors.onInverseSurface,
      behavior: SnackBarBehavior.floating,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KoiRadius.medium),
      ),
    ),
    bannerTheme: MaterialBannerThemeData(
      backgroundColor: tokens.panelBackground,
      surfaceTintColor: Colors.transparent,
      contentTextStyle: text.bodyMedium,
      dividerColor: tokens.weakBorder,
      padding: const EdgeInsets.all(KoiSpace.md),
      elevation: 0,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: tokens.overlayBackground,
      modalBackgroundColor: tokens.overlayBackground,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: colors.onSurfaceVariant,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KoiRadius.dialog),
        ),
      ),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: tokens.panelBackground,
      surfaceTintColor: Colors.transparent,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.dragged)
            ? 8
            : 6,
      ),
      radius: const Radius.circular(KoiRadius.row),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => colors.onSurface.withValues(
          alpha: states.contains(WidgetState.dragged)
              ? .5
              : states.contains(WidgetState.hovered)
              ? .4
              : .25,
        ),
      ),
      crossAxisMargin: 2,
      mainAxisMargin: 2,
      minThumbLength: 32,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: colors.primary,
      inactiveTrackColor: colors.surfaceContainerHighest,
      thumbColor: colors.primary,
      overlayColor: colors.primary.withValues(alpha: .12),
      valueIndicatorColor: colors.inverseSurface,
      valueIndicatorTextStyle: text.labelMedium!.copyWith(
        color: colors.onInverseSurface,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.primary,
      linearTrackColor: colors.surfaceContainerHighest,
      circularTrackColor: colors.surfaceContainerHighest,
      linearMinHeight: 4,
      borderRadius: BorderRadius.circular(KoiRadius.row),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.primary,
      selectionColor: colors.primary.withValues(alpha: .25),
      selectionHandleColor: colors.primary,
    ),
  );
}
