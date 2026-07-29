import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../assets/app_assets.dart';

enum AppBrandLogoVariant { horizontal, symbol, splash }

class AppBrandLogo extends StatelessWidget {
  const AppBrandLogo({
    required this.variant,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.borderRadius = BorderRadius.zero,
    this.semanticLabel = 'DDR001 Diagnóstico de Hidrantes',
    super.key,
  });

  final AppBrandLogoVariant variant;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius borderRadius;
  final String semanticLabel;

  static String assetFor(AppBrandLogoVariant variant) => switch (variant) {
    AppBrandLogoVariant.horizontal => AppAssets.logoHorizontal,
    AppBrandLogoVariant.symbol => AppAssets.logoSymbol,
    AppBrandLogoVariant.splash => AppAssets.splashLogo,
  };

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: semanticLabel,
    child: ClipRRect(
      borderRadius: borderRadius,
      child: Image.asset(
        assetFor(variant),
        key: ValueKey('app-brand-logo-${variant.name}'),
        width: width,
        height: height,
        fit: fit,
        excludeFromSemantics: true,
        errorBuilder: (context, error, stackTrace) {
          if (kDebugMode) {
            debugPrint(
              '[BRANDING] No se pudo cargar ${assetFor(variant)}: $error',
            );
          }
          return SizedBox(
            key: const ValueKey('app-brand-logo-fallback'),
            width: width,
            height: height,
            child: variant == AppBrandLogoVariant.symbol
                ? const Center(
                    child: Icon(
                      Icons.water_drop_outlined,
                      semanticLabel: 'Identidad institucional',
                    ),
                  )
                : null,
          );
        },
      ),
    ),
  );
}
