import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_ui/koi_ui.dart';

void main() {
  test('neutral workspace surfaces reserve chroma for brand actions', () {
    for (final brightness in Brightness.values) {
      final theme = AppTheme.build(brightness: brightness);
      final tokens = theme.extension<KoiThemeTokens>()!;
      for (final color in [
        tokens.chromeBackground,
        tokens.contentBackground,
        tokens.panelBackground,
        tokens.overlayBackground,
        tokens.selectedBackground,
        tokens.hoverBackground,
        theme.colorScheme.surfaceContainerLow,
      ]) {
        final rgb = color.toARGB32();
        expect((rgb >> 16) & 255, (rgb >> 8) & 255);
        expect((rgb >> 8) & 255, rgb & 255);
      }
      expect(tokens.panelBackground, isNot(tokens.contentBackground));
      expect(
        theme.navigationRailTheme.selectedIconTheme!.color,
        theme.colorScheme.onSurface,
      );
      expect(theme.colorScheme.primary, isNot(theme.colorScheme.onSurface));
    }
  });

  for (final brightness in Brightness.values) {
    test(
      '$brightness readable foregrounds and necessary control boundaries',
      () {
        final theme = AppTheme.build(brightness: brightness);
        final colors = theme.colorScheme;
        final tokens = theme.extension<KoiThemeTokens>()!;
        final textPairs = <String, (Color, Color)>{
          'primary': (colors.onPrimary, colors.primary),
          'primary container': (
            colors.onPrimaryContainer,
            colors.primaryContainer,
          ),
          'secondary': (colors.onSecondary, colors.secondary),
          'secondary container': (
            colors.onSecondaryContainer,
            colors.secondaryContainer,
          ),
          'tertiary': (colors.onTertiary, colors.tertiary),
          'tertiary container': (
            colors.onTertiaryContainer,
            colors.tertiaryContainer,
          ),
          'error': (colors.onError, colors.error),
          'error container': (colors.onErrorContainer, colors.errorContainer),
          'inverse surface': (colors.onInverseSurface, colors.inverseSurface),
        };
        final surfaces = <String, Color>{
          'chrome': tokens.chromeBackground,
          'content': tokens.contentBackground,
          'sidebar and inspector': tokens.panelBackground,
          'input': colors.surfaceContainerLow,
          'overlay': tokens.overlayBackground,
          'selected': tokens.selectedBackground,
          'hover': tokens.hoverBackground,
        };
        for (final surface in surfaces.entries) {
          textPairs['body on ${surface.key}'] = (
            colors.onSurface,
            surface.value,
          );
          textPairs['support on ${surface.key}'] = (
            colors.onSurfaceVariant,
            surface.value,
          );
          textPairs['action on ${surface.key}'] = (
            colors.primary,
            surface.value,
          );
        }
        for (final pair in textPairs.entries) {
          expect(
            _contrast(pair.value.$1, pair.value.$2),
            greaterThanOrEqualTo(4.5),
            reason: pair.key,
          );
        }
        final border = theme.inputDecorationTheme.enabledBorder!.borderSide;
        for (final background in [colors.surface, colors.surfaceContainerLow]) {
          expect(_contrast(border.color, background), greaterThanOrEqualTo(3));
        }
        for (final surface in surfaces.values) {
          expect(_contrast(colors.primary, surface), greaterThanOrEqualTo(3));
        }
        // Structural dividers stay quiet; they are not the input affordance.
        expect(theme.dividerTheme.color, tokens.weakBorder);
        expect(border.color, isNot(tokens.weakBorder));
      },
    );
  }

  for (final density in KoiDensity.values) {
    for (final direction in TextDirection.values) {
      testWidgets(
        '$density $direction selected marker preserves row geometry',
        (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            final focus = FocusNode();
            addTearDown(focus.dispose);
            var activations = 0;
            Widget host(bool selected) => MaterialApp(
              theme: AppTheme.build(density: density),
              home: Directionality(
                textDirection: direction,
                child: Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: KoiSelectableListTile(
                      title: const Text('中文资料'),
                      leading: const Icon(Icons.description_outlined),
                      trailing: const Icon(Icons.more_horiz),
                      selected: selected,
                      focusNode: focus,
                      onTap: () => activations++,
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpWidget(host(false));
            final titleBefore = tester.getRect(find.text('中文资料'));
            final rowBefore = tester.getRect(
              find.byType(KoiSelectableListTile),
            );
            await tester.pumpWidget(host(true));
            await tester.pumpAndSettle();
            final marker = find.byKey(
              const ValueKey('koi-list-selection-indicator'),
            );
            expect(marker, findsOneWidget);
            expect(tester.getRect(find.text('中文资料')), titleBefore);
            expect(
              tester.getRect(find.byType(KoiSelectableListTile)),
              rowBefore,
            );
            expect(find.byIcon(Icons.description_outlined), findsOneWidget);
            expect(find.byIcon(Icons.more_horiz), findsOneWidget);
            final markerRect = tester.getRect(marker);
            expect(markerRect.size, const Size(3, 18));
            final markerDecoration =
                tester.widget<Container>(marker).decoration! as BoxDecoration;
            expect(
              _contrast(
                markerDecoration.color!,
                AppTheme.light.extension<KoiThemeTokens>()!.selectedBackground,
              ),
              greaterThanOrEqualTo(3),
            );
            if (direction == TextDirection.ltr) {
              expect(markerRect.left - rowBefore.left, 3);
            } else {
              expect(rowBefore.right - markerRect.right, 3);
            }
            expect(
              tester.getSemantics(find.byType(ListTile)),
              matchesSemantics(
                label: '中文资料',
                hasSelectedState: true,
                isSelected: true,
                isButton: true,
                isFocusable: true,
                hasEnabledState: true,
                isEnabled: true,
                hasTapAction: true,
                hasFocusAction: true,
              ),
            );
            // The marker is decorative: clicking it reaches the original row.
            await tester.tapAt(markerRect.center);
            expect(activations, 1);
            focus.requestFocus();
            await tester.pumpAndSettle();
            final tile = tester.widget<ListTile>(find.byType(ListTile));
            expect(
              (tile.shape! as RoundedRectangleBorder).side.color,
              AppTheme.light.colorScheme.primary,
            );
            expect(marker, findsOneWidget);
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.sendKeyEvent(LogicalKeyboardKey.space);
            expect(activations, 3);
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }

  testWidgets(
    'disabled selected Material fallback remains inert and announced',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        var activated = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: KoiSelectableListTile(
                title: const Text('禁用资料'),
                leading: const Icon(Icons.description_outlined),
                selected: true,
                enabled: false,
                onTap: () => activated = true,
              ),
            ),
          ),
        );
        expect(
          find.byKey(const ValueKey('koi-list-selection-indicator')),
          findsOneWidget,
        );
        await tester.tap(find.text('禁用资料'));
        expect(activated, isFalse);
        expect(
          tester.getSemantics(find.byType(ListTile)),
          matchesSemantics(
            label: '禁用资料',
            hasSelectedState: true,
            isSelected: true,
            hasEnabledState: true,
            hasTapAction: false,
          ),
        );
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );
}

double _contrast(Color foreground, Color background) {
  final painted = Color.alphaBlend(foreground, background).computeLuminance();
  final behind = background.computeLuminance();
  return (math.max(painted, behind) + .05) / (math.min(painted, behind) + .05);
}
