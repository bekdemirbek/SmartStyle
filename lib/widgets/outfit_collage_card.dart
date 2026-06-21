import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/outfit_recommendation_models.dart';

class OutfitCollageCard extends StatelessWidget {
  final OutfitRecommendation recommendation;
  final bool isDark;
  final bool isHighlighted;
  final VoidCallback? onTap;

  const OutfitCollageCard({
    super.key,
    required this.recommendation,
    required this.isDark,
    this.isHighlighted = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final titleColor = isDark ? const Color(0xFF17212B) : const Color(0xFF2F2F2F);
    final metaColor = isDark ? const Color(0xFF344252) : const Color(0xFF4B5563);
    final isOnePiece = recommendation.top.id == recommendation.bottom.id;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isHighlighted
                  ? (isDark ? const Color(0xFFD8C38A) : const Color(0xFF8B6B2E))
                  : (isDark ? Colors.white10 : const Color(0xFFE8DFCF)),
              width: isHighlighted ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.16 : 0.06),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ColoredBox(
                    color: isDark
                        ? const Color(0xFFFBFCFD)
                        : const Color(0xFFFFFEFC),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        if (isOnePiece) {
                          return Stack(
                            children: [
                              Positioned(
                                top: constraints.maxHeight * 0.04,
                                left: constraints.maxWidth * 0.16,
                                width: constraints.maxWidth * 0.68,
                                height: constraints.maxHeight * 0.68,
                                child: _OutfitPieceImage(
                                  item: recommendation.top,
                                  semanticLabel: 'Tek parça kombin',
                                  framed: false,
                                ),
                              ),
                              Positioned(
                                left: constraints.maxWidth * 0.27,
                                right: constraints.maxWidth * 0.27,
                                bottom: constraints.maxHeight * 0.04,
                                height: constraints.maxHeight * 0.2,
                                child: _OutfitPieceImage(
                                  item: recommendation.shoes,
                                  semanticLabel: 'Ayakkabı',
                                  framed: false,
                                ),
                              ),
                            ],
                          );
                        }

                        return Stack(
                          children: [
                            Positioned(
                              top: constraints.maxHeight * 0.05,
                              left: constraints.maxWidth * 0.25,
                              width: constraints.maxWidth * 0.48,
                              height: constraints.maxHeight * 0.34,
                              child: _OutfitPieceImage(
                                item: recommendation.top,
                                semanticLabel: 'Üst giyim',
                                framed: false,
                              ),
                            ),
                            if (recommendation.outerwear != null)
                              Positioned(
                                top: constraints.maxHeight * 0.04,
                                right: constraints.maxWidth * 0.03,
                                width: constraints.maxWidth * 0.36,
                                height: constraints.maxHeight * 0.38,
                                child: _OutfitPieceImage(
                                  item: recommendation.outerwear!,
                                  semanticLabel: 'Dış giyim',
                                  framed: false,
                                ),
                              ),
                            Positioned(
                              top: constraints.maxHeight * 0.36,
                              left: constraints.maxWidth * 0.22,
                              width: constraints.maxWidth * 0.56,
                              height: constraints.maxHeight * 0.36,
                              child: _OutfitPieceImage(
                                item: recommendation.bottom,
                                semanticLabel: 'Alt giyim',
                                framed: false,
                              ),
                            ),
                            Positioned(
                              left: constraints.maxWidth * 0.27,
                              right: constraints.maxWidth * 0.27,
                              bottom: constraints.maxHeight * 0.04,
                              height: constraints.maxHeight * 0.2,
                              child: _OutfitPieceImage(
                                item: recommendation.shoes,
                                semanticLabel: 'Ayakkabı',
                                framed: false,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  gradient: AppTheme.themeGoldGradient(isDark) as Gradient?,
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                ),
                child: Text(
                  recommendation.day.toUpperCase(),
                  style: AppTheme.label(isDark).copyWith(
                    color: isDark
                        ? AppTheme.backgroundPrimary
                        : AppTheme.textPrimaryLight,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${_planTitle(recommendation.planType)} Kombin',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: titleColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _metadataText(recommendation),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: metaColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _metadataText(OutfitRecommendation recommendation) {
    final pieces = [
      recommendation.top.subCategory,
      if (recommendation.bottom.id != recommendation.top.id)
        recommendation.bottom.subCategory,
      recommendation.shoes.subCategory,
      if (recommendation.outerwear != null) recommendation.outerwear!.subCategory,
      if (recommendation.socks != null)
        'Opsiyonel: ${recommendation.socks!.subCategory}',
    ].where((name) => name.trim().isNotEmpty).join(' + ');

    return pieces.isEmpty ? recommendation.description : pieces;
  }

  String _planTitle(DayPlanType planType) {
    switch (planType) {
      case DayPlanType.normalDay:
        return 'Normal Gün';
      case DayPlanType.office:
        return 'Ofis';
      case DayPlanType.date:
        return 'Date';
      case DayPlanType.gym:
        return 'Spor';
      case DayPlanType.dinner:
        return 'Akşam Yemeği';
      case DayPlanType.travel:
        return 'Seyahat';
      case DayPlanType.specialEvent:
        return 'Özel Etkinlik';
    }
  }
}

class _OutfitPieceImage extends StatelessWidget {
  final ClothingItem item;
  final String semanticLabel;
  final bool framed;

  const _OutfitPieceImage({
    required this.item,
    required this.semanticLabel,
    this.framed = true,
  });

  @override
  Widget build(BuildContext context) {
    if (item.imageUrl.isEmpty) {
      return _ImageFallback(
        semanticLabel: semanticLabel,
        framed: framed,
      );
    }

    final image = Image.network(
      item.imageUrl,
      fit: BoxFit.contain,
      semanticLabel: semanticLabel,
      errorBuilder: (context, error, stackTrace) {
        return _ImageFallback(
          semanticLabel: semanticLabel,
          framed: framed,
        );
      },
    );

    if (!framed) {
      return Padding(
        padding: const EdgeInsets.all(3),
        child: image,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.82),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: image,
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  final String semanticLabel;
  final bool framed;

  const _ImageFallback({
    required this.semanticLabel,
    this.framed = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!framed) {
      return Center(
        child: Icon(
          Icons.checkroom,
          color: Colors.grey.shade500,
          semanticLabel: semanticLabel,
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Icon(
          Icons.checkroom,
          color: Colors.grey.shade500,
          semanticLabel: semanticLabel,
        ),
      ),
    );
  }
}
