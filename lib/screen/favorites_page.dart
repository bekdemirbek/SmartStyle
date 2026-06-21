import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../app_theme.dart';
import '../models/saved_outfit_model.dart';
import '../services/saved_outfit_service.dart';
import '../widgets/gold_gradient_button.dart';
import 'dashboard_page.dart';
import 'outfit_detail_page.dart';

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      body: SafeArea(
        child: AppTheme.auroraBackground(
          isDark: isDark,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.screenPadding,
              20,
              AppTheme.screenPadding,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Favori Kombinler", style: AppTheme.heading1(isDark)),
                const SizedBox(height: 4),
                Text(
                  "Favori kombinler",
                  style: AppTheme.caption(isDark),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: user == null
                      ? _EmptyFavorites(
                          isDark: isDark,
                          message: "Favorilerini görmek için giriş yapmalısın.",
                        )
                      : StreamBuilder<List<SavedOutfit>>(
                          stream: SavedOutfitService().watchFavoriteOutfits(
                            userId: user.uid,
                          ),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            if (snapshot.hasError) {
                              return _EmptyFavorites(
                                isDark: isDark,
                                message:
                                    "Favoriler yüklenemedi. Lütfen biraz sonra tekrar dene.",
                              );
                            }

                            final outfits = snapshot.data ?? const [];
                            if (outfits.isEmpty) {
                              return _EmptyFavorites(
                                isDark: isDark,
                                message: "Henüz favori kombin yok.",
                              );
                            }

                            return ListView.separated(
                              padding: const EdgeInsets.only(bottom: 120),
                              itemCount: outfits.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                return _FavoriteOutfitCard(
                                  outfit: outfits[index],
                                  isDark: isDark,
                                  userId: user.uid,
                                ).animate(delay: (index * 60).ms).fadeIn(
                                      duration: 280.ms,
                                      curve: Curves.easeOutCubic,
                                    ).slideY(begin: 0.1, end: 0);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FavoriteOutfitCard extends StatelessWidget {
  final SavedOutfit outfit;
  final bool isDark;
  final String userId;

  const _FavoriteOutfitCard({
    required this.outfit,
    required this.isDark,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    final firstImage = _firstImageUrl(outfit.pieces);

    return Dismissible(
      key: ValueKey(outfit.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) => _deleteFavorite(context),
      background: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFE24B4A),
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: Colors.white,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        onTap: outfit.id.isEmpty
            ? null
            : () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => OutfitDetailPage(
                      outfitId: outfit.id,
                      isFavoriteOutfit: true,
                    ),
                  ),
                );
              },
        child: Container(
          height: 120,
          padding: const EdgeInsets.all(14),
          decoration: AppTheme.panelDecoration(isDark),
          child: Row(
            children: [
              Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    colors: isDark
                        ? const [
                            Color(0xFF2B2C35),
                            Color(0xFF23242C),
                          ]
                        : const [
                            Color(0xFFF8F4EE),
                            Color(0xFFECE6DE),
                          ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withOpacity(0.05)
                        : Colors.black.withOpacity(0.05),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: firstImage.isEmpty
                        ? _FavoriteImageFallback(isDark: isDark)
                        : CachedNetworkImage(
                            imageUrl: firstImage,
                            fit: BoxFit.contain,
                            errorWidget: (_, __, ___) =>
                                _FavoriteImageFallback(isDark: isDark),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      outfit.day.isEmpty ? "Favori Kombin" : outfit.day,
                      style: AppTheme.caption(isDark).copyWith(
                        color: AppTheme.gold(isDark),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _itemsText(outfit),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.caption(isDark).copyWith(height: 1.4),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Icon(
                    Icons.favorite_rounded,
                    color: Color(0xFFE24B4A),
                    size: 18,
                  ),
                  PopupMenuButton<String>(
                    color: isDark ? const Color(0xFF23242C) : Colors.white,
                    surfaceTintColor: Colors.transparent,
                    elevation: 10,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: isDark
                            ? Colors.white.withOpacity(0.08)
                            : Colors.black.withOpacity(0.06),
                      ),
                    ),
                    icon: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF2B2C35)
                            : const Color(0xFFF4EFE7),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.more_horiz_rounded,
                        color: AppTheme.primaryText(isDark),
                        size: 18,
                      ),
                    ),
                    onSelected: (value) async {
                      if (value != 'delete') return;
                      final confirmed = await _confirmDelete(context);
                      if (confirmed == true && context.mounted) {
                        await _deleteFavorite(context);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.heart_broken_rounded,
                              color: Color(0xFFE24B4A),
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Favorilerden Kaldir',
                              style: AppTheme.bodyText(isDark).copyWith(
                                color: const Color(0xFFE24B4A),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteFavorite(BuildContext context) async {
    try {
      await SavedOutfitService().deleteFavoriteOutfit(
        userId: userId,
        favoriteId: outfit.id,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Favorilerden kaldırıldı.")),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Favori silinemedi. Lütfen tekrar dene."),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.card(isDark),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          ),
          title: Text(
            'Favoriden silinsin mi?',
            style: AppTheme.heading2(isDark).copyWith(fontSize: 18),
          ),
          content: Text(
            'Bu kombini favorilerinden kaldıracaksın.',
            style: AppTheme.caption(isDark),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Vazgeç',
                style: AppTheme.caption(isDark),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(
                'Sil',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _firstImageUrl(List<SavedOutfitPiece> pieces) {
    for (final piece in pieces) {
      if (piece.imageUrl.trim().isNotEmpty) return piece.imageUrl;
    }
    return '';
  }

  String _itemsText(SavedOutfit outfit) {
    final items = outfit.pieces
        .map((piece) => piece.subCategory)
        .where((item) => item.trim().isNotEmpty)
        .join(' + ');
    return items.isEmpty ? outfit.description : items;
  }
}

class _FavoriteImageFallback extends StatelessWidget {
  final bool isDark;

  const _FavoriteImageFallback({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.layer2(isDark),
      child: Icon(
        Icons.checkroom_rounded,
        color: AppTheme.tertiaryText(isDark),
        size: 32,
      ),
    );
  }
}

class _EmptyFavorites extends StatelessWidget {
  final bool isDark;
  final String message;

  const _EmptyFavorites({
    required this.isDark,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: AppTheme.layer2(isDark),
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.subtleBorder(isDark)),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.favorite_border_rounded,
                    color: AppTheme.gold(isDark),
                    size: 34,
                  ),
                  Positioned(
                    bottom: 22,
                    child: Icon(
                      Icons.checkroom_rounded,
                      color: AppTheme.tertiaryText(isDark),
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              "Henüz favori yok",
              style: AppTheme.heading2(isDark),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTheme.caption(isDark),
            ),
            const SizedBox(height: 18),
            GoldGradientButton(
              label: "Ana Sayfaya Dön",
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DashboardPage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
