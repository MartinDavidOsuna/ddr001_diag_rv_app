import 'package:ddr001diag/core/assets/app_assets.dart';
import 'package:ddr001diag/core/widgets/app_brand_logo.dart';
import 'package:ddr001diag/features/auth/auth_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('horizontal variant uses the institutional horizontal asset', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppBrandLogo(variant: AppBrandLogoVariant.horizontal),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, AppAssets.logoHorizontal);
    expect(image.fit, BoxFit.contain);
  });

  testWidgets('symbol variant uses the compact institutional asset', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppBrandLogo(variant: AppBrandLogoVariant.symbol),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, AppAssets.logoSymbol);
  });

  testWidgets('login uses the horizontal logo when enough width is available', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: SizedBox(width: 420, child: LoginBrandHeader())),
    );

    expect(
      find.byKey(const ValueKey('app-brand-logo-horizontal')),
      findsOneWidget,
    );
  });

  testWidgets('narrow login uses the symbol without horizontal overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(240, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LoginBrandHeader())),
    );

    expect(find.byKey(const ValueKey('app-brand-logo-symbol')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing assets render the safe fallback', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultAssetBundle(
          bundle: _MissingAssetBundle(),
          child: const AppBrandLogo(variant: AppBrandLogoVariant.symbol),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('app-brand-logo-fallback')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

class _MissingAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) =>
      Future<ByteData>.error(StateError('Synthetic missing asset: $key'));
}
