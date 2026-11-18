import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_ui/koi_ui.dart';

void main() {
  final policy = KoiLocalePolicy(
    supportedLocales: KoiUiLocalizations.supportedLocales,
    fallbackLocale: const Locale('zh'),
    nativeNames: const {'zh-Hant': '繁體中文'},
  );

  test('all available locales round-trip without a separate language list', () {
    for (final locale in policy.supportedLocales) {
      expect(policy.fromTag(locale.toLanguageTag()), locale);
      expect(policy.fromTag(locale.toString()), locale);
    }
    expect(policy.fromTag('ZH_hant')?.scriptCode, 'Hant');
    for (final tag in <Object?>[null, 'system', 'removed', 3]) {
      expect(policy.fromTag(tag), isNull);
    }
    expect(policy.label(policy.fromTag('zh-Hant')!), '繁體中文');
    expect(policy.label(const Locale('en')), 'en');
  });

  test('fallback belongs to the host and must be supported', () {
    final english = KoiLocalePolicy(
      supportedLocales: policy.supportedLocales,
      fallbackLocale: const Locale('en'),
    );
    expect(
      english.resolve([const Locale('fr')], english.supportedLocales),
      const Locale('en'),
    );
    expect(english.resolve(null, english.supportedLocales), const Locale('en'));
    expect(
      () => KoiLocalePolicy(
        supportedLocales: [],
        fallbackLocale: const Locale('en'),
      ),
      throwsArgumentError,
    );
    expect(
      () => KoiLocalePolicy(
        supportedLocales: [const Locale('zh')],
        fallbackLocale: const Locale('en'),
      ),
      throwsArgumentError,
    );
  });

  test(
    'explicit Chinese script wins over region, independent of ARB order',
    () {
      const hant = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
      const hans = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');
      const regional = Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hant',
        countryCode: 'HK',
      );
      const supported = [hant, Locale('zh'), hans, regional, Locale('en')];
      expect(resolveKoiLocale([regional], supported), regional);
      expect(resolveKoiLocale([const Locale('zh', 'MO')], supported), hant);
      expect(
        resolveKoiLocale([
          const Locale.fromSubtags(
            languageCode: 'zh',
            scriptCode: 'Hans',
            countryCode: 'TW',
          ),
        ], supported),
        hans,
      );
      expect(
        resolveKoiLocale([
          const Locale.fromSubtags(
            languageCode: 'zh',
            scriptCode: 'Hans',
            countryCode: 'TW',
          ),
        ], policy.supportedLocales),
        const Locale('zh'),
      );
      expect(
        resolveKoiLocale([
          const Locale.fromSubtags(
            languageCode: 'zh',
            scriptCode: 'Hant',
            countryCode: 'CN',
          ),
        ], supported),
        hant,
      );
    },
  );

  test('matching handles other scripts, regions, and preference order', () {
    const latin = Locale.fromSubtags(languageCode: 'sr', scriptCode: 'Latn');
    const supported = [
      Locale('en', 'US'),
      Locale('en', 'GB'),
      latin,
      Locale('sr'),
    ];
    expect(
      resolveKoiLocale([
        const Locale.fromSubtags(
          languageCode: 'sr',
          scriptCode: 'Latn',
          countryCode: 'RS',
        ),
      ], supported),
      latin,
    );
    expect(
      resolveKoiLocale([
        const Locale.fromSubtags(
          languageCode: 'en',
          scriptCode: 'Latn',
          countryCode: 'GB',
        ),
      ], supported),
      const Locale('en', 'GB'),
    );
    expect(
      resolveKoiLocale([
        const Locale('fr'),
        const Locale('en', 'AU'),
      ], supported),
      const Locale('en', 'US'),
    );
  });
}
