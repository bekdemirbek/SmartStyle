import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/saved_outfit_model.dart';
import '../services/saved_outfit_service.dart';

class OutfitDetailPage extends StatefulWidget {
  final String outfitId;
  final bool isFavoriteOutfit;

  const OutfitDetailPage({
    super.key,
    required this.outfitId,
    this.isFavoriteOutfit = false,
  });

  @override
  State<OutfitDetailPage> createState() => _OutfitDetailPageState();
}

class _OutfitDetailPageState extends State<OutfitDetailPage> {
  final SavedOutfitService _savedOutfitService = SavedOutfitService();
  late Future<SavedOutfit?> _outfitFuture;
  SavedOutfit? _outfit;
  bool _isFavoriteUpdating = false;
  String? _resolvedFavoriteId;

  @override
  void initState() {
    super.initState();
    _outfitFuture = _loadOutfit();
  }

  Future<SavedOutfit?> _loadOutfit() async {
    if (widget.isFavoriteOutfit) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      _resolvedFavoriteId = widget.outfitId;
      final outfit = await _savedOutfitService.fetchFavoriteOutfitById(
        userId: user.uid,
        favoriteId: widget.outfitId,
      );
      _outfit = outfit;
      return outfit;
    }

    final outfit = await _savedOutfitService.fetchOutfitById(widget.outfitId);
    _outfit = outfit;
    return outfit;
  }

  Future<void> _toggleFavorite() async {
    final outfit = _outfit;
    if (outfit == null || _isFavoriteUpdating) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Favorilere eklemek için giriş yapmalısın.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final nextValue = !outfit.favorite;
    setState(() {
      _isFavoriteUpdating = true;
      _outfit = outfit.copyWith(favorite: nextValue);
    });

    try {
      if (widget.isFavoriteOutfit && !nextValue) {
        await _savedOutfitService.deleteFavoriteOutfit(
          userId: user.uid,
          favoriteId: _resolvedFavoriteId ?? widget.outfitId,
        );
        if (!mounted) return;
        Navigator.of(context).pop();
        return;
      } else {
        if (nextValue) {
          _resolvedFavoriteId = await _savedOutfitService.saveFavoriteOutfit(
            userId: user.uid,
            outfit: outfit,
            favoriteId: widget.outfitId,
          );
        } else {
          await _savedOutfitService.deleteFavoriteOutfit(
            userId: user.uid,
            favoriteId: _resolvedFavoriteId ?? widget.outfitId,
          );
        }

        if (!widget.isFavoriteOutfit && widget.outfitId.isNotEmpty) {
          await _savedOutfitService.toggleFavorite(
            outfitId: widget.outfitId,
            isFavorite: nextValue,
          );
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextValue ? 'Favorilere eklendi.' : 'Favorilerden kaldırıldı.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _outfit = outfit;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Favori durumu güncellenemedi.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isFavoriteUpdating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        isDark ? const Color(0xFF07131D) : const Color(0xFFF6F4F0);
    final textColor = isDark ? Colors.white : const Color(0xFF232323);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        foregroundColor: textColor,
        title: const Text('Kombin Detayı'),
        actions: [
          IconButton(
            onPressed: _isFavoriteUpdating ? null : _toggleFavorite,
            icon: Icon(
              (_outfit?.favorite ?? false)
                  ? Icons.favorite
                  : Icons.favorite_border,
              color: (_outfit?.favorite ?? false)
                  ? Colors.redAccent
                  : textColor,
            ),
          ),
        ],
      ),
      body: FutureBuilder<SavedOutfit?>(
        future: _outfitFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final outfit = _outfit ?? snapshot.data;
          if (snapshot.hasError || outfit == null) {
            return _EmptyDetailState(
              textColor: textColor,
              message: 'Kombin detayı bulunamadı.',
            );
          }

          return _OutfitDetailContent(
            outfit: outfit,
            isDark: isDark,
          );
        },
      ),
    );
  }
}

enum _OutfitPreviewMode { collage, mannequin }

class _OutfitDetailContent extends StatefulWidget {
  final SavedOutfit outfit;
  final bool isDark;

  const _OutfitDetailContent({
    required this.outfit,
    required this.isDark,
  });

  @override
  State<_OutfitDetailContent> createState() => _OutfitDetailContentState();
}

class _OutfitDetailContentState extends State<_OutfitDetailContent> {
  _OutfitPreviewMode _previewMode = _OutfitPreviewMode.collage;

  @override
  Widget build(BuildContext context) {
    final outfit = widget.outfit;
    final isDark = widget.isDark;
    final textColor = isDark ? Colors.white : const Color(0xFF232323);
    final subTextColor = isDark ? Colors.white70 : const Color(0xFF616161);
    final top = _findPiece(outfit.pieces, 'ust', 'top');
    final bottom = _findPiece(outfit.pieces, 'alt', 'bottom');
    final shoes = _findPiece(outfit.pieces, 'ayakkabi', 'shoe');
    final outerwear = _findPiece(outfit.pieces, 'dis', 'outer');
    final visiblePieces = [
      if (top != null) top,
      if (bottom != null) bottom,
      if (shoes != null) shoes,
      if (outerwear != null) outerwear,
    ];
    final piecesForList =
        visiblePieces.isEmpty ? outfit.pieces : visiblePieces;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      children: [
        _PreviewModeSelector(
          value: _previewMode,
          isDark: isDark,
          onChanged: (value) {
            setState(() {
              _previewMode = value;
            });
          },
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _previewMode == _OutfitPreviewMode.collage
              ? _SavedOutfitCollage(
                  key: const ValueKey('collage-preview'),
                  top: top,
                  bottom: bottom,
                  shoes: shoes,
                  outerwear: outerwear,
                  fallbackPieces: outfit.pieces,
                  isDark: isDark,
                  onTap: () => _openZoomView(
                    context,
                    mode: _OutfitPreviewMode.collage,
                    top: top,
                    bottom: bottom,
                    shoes: shoes,
                    outerwear: outerwear,
                    fallbackPieces: outfit.pieces,
                  ),
                )
              : _SavedOutfitMannequin(
                  key: const ValueKey('mannequin-preview'),
                  top: top,
                  bottom: bottom,
                  shoes: shoes,
                  outerwear: outerwear,
                  fallbackPieces: outfit.pieces,
                  isDark: isDark,
                  onTap: () => _openZoomView(
                    context,
                    mode: _OutfitPreviewMode.mannequin,
                    top: top,
                    bottom: bottom,
                    shoes: shoes,
                    outerwear: outerwear,
                    fallbackPieces: outfit.pieces,
                  ),
                ),
          ),
        const SizedBox(height: 20),
        Text(
          outfit.day.isEmpty ? 'Haftalık Kombin' : outfit.day,
          style: TextStyle(
            color: textColor,
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (outfit.dailyPlan.isNotEmpty)
              _InfoPill(label: _planText(outfit.dailyPlan), isDark: isDark),
            _InfoPill(label: _weatherText(outfit.weather), isDark: isDark),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          outfit.description.isEmpty
              ? 'Bu kombin dolabındaki seçili parçalarla hazırlandı.'
              : outfit.description,
          style: TextStyle(
            color: subTextColor,
            fontSize: 15,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 26),
        Text(
          'Parçalar',
          style: TextStyle(
            color: textColor,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        ...piecesForList.map(
          (piece) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _PieceTile(piece: piece, isDark: isDark),
          ),
        ),
      ],
    );
  }

  SavedOutfitPiece? _findPiece(
    List<SavedOutfitPiece> pieces,
    String turkishNeedle,
    String englishNeedle,
  ) {
    for (final piece in pieces) {
      final category = _normalize(piece.category);
      if (category.contains(turkishNeedle) ||
          category.contains(englishNeedle)) {
        return piece;
      }
    }
    return null;
  }

  String _planText(String dailyPlan) {
    switch (_normalize(dailyPlan)) {
      case 'normal day':
      case 'normal gun':
      case 'normal gün':
        return 'Normal Gün';
      case 'office':
      case 'ofis':
        return 'Ofis';
      case 'date':
        return 'Date';
      case 'gym':
      case 'spor':
        return 'Spor';
      case 'dinner':
      case 'aksam yemegi':
      case 'akşam yemeği':
        return 'Akşam Yemeği';
      case 'travel':
      case 'seyahat':
        return 'Seyahat';
      case 'special event':
      case 'specialevent':
      case 'ozel etkinlik':
      case 'özel etkinlik':
        return 'Özel Etkinlik';
    }

    return dailyPlan;
  }

  String _weatherText(Map<String, dynamic> weather) {
    final temp = weather['sicaklik'];
    final condition = (weather['durum'] ?? '').toString();
    final description = (weather['aciklama'] ?? '').toString();
    final tempText = temp is num ? '${temp.round()}°C' : '';
    final conditionText = description.isNotEmpty ? description : condition;

    return [tempText, conditionText]
        .where((part) => part.trim().isNotEmpty)
        .join(' · ');
  }

  void _openZoomView(
    BuildContext context, {
    required _OutfitPreviewMode mode,
    required SavedOutfitPiece? top,
    required SavedOutfitPiece? bottom,
    required SavedOutfitPiece? shoes,
    required SavedOutfitPiece? outerwear,
    required List<SavedOutfitPiece> fallbackPieces,
  }) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.82),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 0.9,
                    child: mode == _OutfitPreviewMode.collage
                        ? _SavedOutfitCollage(
                            top: top,
                            bottom: bottom,
                            shoes: shoes,
                            outerwear: outerwear,
                            fallbackPieces: fallbackPieces,
                            isDark: false,
                          )
                        : _SavedOutfitMannequin(
                            top: top,
                            bottom: bottom,
                            shoes: shoes,
                            outerwear: outerwear,
                            fallbackPieces: fallbackPieces,
                            isDark: false,
                          ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PreviewModeSelector extends StatelessWidget {
  final _OutfitPreviewMode value;
  final bool isDark;
  final ValueChanged<_OutfitPreviewMode> onChanged;

  const _PreviewModeSelector({
    required this.value,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selectedColor = isDark ? const Color(0xFFD8C38A) : const Color(0xFF7A5C22);
    final unselectedColor = isDark ? Colors.white70 : const Color(0xFF5F5A52);

    return SegmentedButton<_OutfitPreviewMode>(
      segments: const [
        ButtonSegment(
          value: _OutfitPreviewMode.collage,
          icon: Icon(Icons.grid_view_rounded),
          label: Text('Kolaj'),
        ),
        ButtonSegment(
          value: _OutfitPreviewMode.mannequin,
          icon: Icon(Icons.accessibility_new_rounded),
          label: Text('Manken'),
        ),
      ],
      selected: {value},
      onSelectionChanged: (selection) => onChanged(selection.first),
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? selectedColor
              : unselectedColor;
        }),
        side: WidgetStatePropertyAll(
          BorderSide(
            color: isDark ? Colors.white12 : const Color(0xFFDCD3C3),
          ),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

class _SavedOutfitCollage extends StatelessWidget {
  final SavedOutfitPiece? top;
  final SavedOutfitPiece? bottom;
  final SavedOutfitPiece? shoes;
  final SavedOutfitPiece? outerwear;
  final List<SavedOutfitPiece> fallbackPieces;
  final bool isDark;
  final VoidCallback? onTap;

  const _SavedOutfitCollage({
    super.key,
    required this.top,
    required this.bottom,
    required this.shoes,
    required this.outerwear,
    required this.fallbackPieces,
    required this.isDark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 0.9,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? Colors.white10 : const Color(0xFFE6E1D8),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.28 : 0.08),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ColoredBox(
              color: isDark ? const Color(0xFFFBFCFD) : const Color(0xFFFFFEFC),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (top == null || bottom == null || shoes == null) {
                    return _FallbackPieceGrid(pieces: fallbackPieces);
                  }

                  return Stack(
                    children: [
                      Positioned(
                        top: constraints.maxHeight * 0.06,
                        left: constraints.maxWidth * 0.24,
                        width: constraints.maxWidth * 0.5,
                        height: constraints.maxHeight * 0.32,
                        child: _PieceImage(
                          piece: top!,
                          semanticLabel: 'Üst',
                          framed: false,
                        ),
                      ),
                      if (outerwear != null)
                        Positioned(
                          top: constraints.maxHeight * 0.05,
                          right: constraints.maxWidth * 0.05,
                          width: constraints.maxWidth * 0.34,
                          height: constraints.maxHeight * 0.38,
                          child: _PieceImage(
                            piece: outerwear!,
                            semanticLabel: 'Dış giyim',
                            framed: false,
                          ),
                        ),
                      Positioned(
                        top: constraints.maxHeight * 0.39,
                        left: constraints.maxWidth * 0.22,
                        width: constraints.maxWidth * 0.56,
                        height: constraints.maxHeight * 0.34,
                        child: _PieceImage(
                          piece: bottom!,
                          semanticLabel: 'Alt',
                          framed: false,
                        ),
                      ),
                      Positioned(
                        left: constraints.maxWidth * 0.28,
                        right: constraints.maxWidth * 0.28,
                        bottom: constraints.maxHeight * 0.06,
                        height: constraints.maxHeight * 0.18,
                        child: _PieceImage(
                          piece: shoes!,
                          semanticLabel: 'Ayakkabı',
                          framed: false,
                        ),
                      ),
                      if (onTap != null)
                        Positioned(
                          right: 10,
                          bottom: 10,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(
                                Icons.zoom_in_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SavedOutfitMannequin extends StatelessWidget {
  static const String _mannequinAsset =
      'assets/images/outfit_mannequin_male.png';

  final SavedOutfitPiece? top;
  final SavedOutfitPiece? bottom;
  final SavedOutfitPiece? shoes;
  final SavedOutfitPiece? outerwear;
  final List<SavedOutfitPiece> fallbackPieces;
  final bool isDark;
  final VoidCallback? onTap;

  const _SavedOutfitMannequin({
    super.key,
    required this.top,
    required this.bottom,
    required this.shoes,
    required this.outerwear,
    required this.fallbackPieces,
    required this.isDark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 0.9,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? Colors.white10 : const Color(0xFFE6E1D8),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.28 : 0.08),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ColoredBox(
              color: isDark ? const Color(0xFFFBFCFD) : const Color(0xFFFFFEFC),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (top == null || bottom == null || shoes == null) {
                    return _FallbackPieceGrid(pieces: fallbackPieces);
                  }

                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: Image.asset(
                          _mannequinAsset,
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          semanticLabel: 'Manken',
                        ),
                      ),
                      Positioned(
                        top: constraints.maxHeight * 0.19,
                        left: constraints.maxWidth * 0.205,
                        width: constraints.maxWidth * 0.59,
                        height: constraints.maxHeight * 0.315,
                        child: _MannequinPieceImage(
                          piece: top!,
                          semanticLabel: 'Manken üzerinde üst',
                        ),
                      ),
                      if (outerwear != null)
                        Positioned(
                          top: constraints.maxHeight * 0.16,
                          left: constraints.maxWidth * 0.135,
                          width: constraints.maxWidth * 0.73,
                          height: constraints.maxHeight * 0.395,
                          child: _MannequinPieceImage(
                            piece: outerwear!,
                            semanticLabel: 'Manken üzerinde dış giyim',
                          ),
                        ),
                      Positioned(
                        top: constraints.maxHeight * 0.445,
                        left: constraints.maxWidth * 0.245,
                        width: constraints.maxWidth * 0.51,
                        height: constraints.maxHeight * 0.33,
                        child: _MannequinPieceImage(
                          piece: bottom!,
                          semanticLabel: 'Manken üzerinde alt',
                        ),
                      ),
                      Positioned(
                        left: constraints.maxWidth * 0.28,
                        right: constraints.maxWidth * 0.28,
                        bottom: constraints.maxHeight * 0.005,
                        height: constraints.maxHeight * 0.16,
                        child: _MannequinPieceImage(
                          piece: shoes!,
                          semanticLabel: 'Manken üzerinde ayakkabı',
                        ),
                      ),
                      Positioned(
                        left: 10,
                        bottom: 10,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.52),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Text(
                              'Manken önizleme',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (onTap != null)
                        Positioned(
                          right: 10,
                          bottom: 10,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(
                                Icons.zoom_in_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MannequinPieceImage extends StatelessWidget {
  final SavedOutfitPiece piece;
  final String semanticLabel;

  const _MannequinPieceImage({
    required this.piece,
    required this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (piece.imageUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.network(
        piece.imageUrl,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        semanticLabel: semanticLabel,
        errorBuilder: (context, error, stackTrace) {
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _FallbackPieceGrid extends StatelessWidget {
  final List<SavedOutfitPiece> pieces;

  const _FallbackPieceGrid({required this.pieces});

  @override
  Widget build(BuildContext context) {
    if (pieces.isEmpty) {
      return const Center(child: Icon(Icons.checkroom, size: 42));
    }

    return GridView.count(
      padding: const EdgeInsets.all(18),
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      children: pieces
          .take(4)
          .map((piece) => _PieceImage(piece: piece, semanticLabel: piece.category))
          .toList(),
    );
  }
}

class _PieceTile extends StatelessWidget {
  final SavedOutfitPiece piece;
  final bool isDark;

  const _PieceTile({
    required this.piece,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : const Color(0xFF232323);
    final subTextColor = isDark ? Colors.white70 : const Color(0xFF656565);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF112231) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2DDD3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            SizedBox(
              width: 74,
              height: 74,
              child: _PieceImage(
                piece: piece,
                semanticLabel: piece.category,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    piece.category.isEmpty ? 'Parça' : piece.category,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    piece.subCategory.isEmpty ? 'Tür belirtilmedi' : piece.subCategory,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: subTextColor, fontSize: 13),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    piece.color.isEmpty ? 'Renk belirtilmedi' : piece.color,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: subTextColor, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PieceImage extends StatelessWidget {
  final SavedOutfitPiece piece;
  final String semanticLabel;
  final bool framed;

  const _PieceImage({
    required this.piece,
    required this.semanticLabel,
    this.framed = true,
  });

  @override
  Widget build(BuildContext context) {
    if (piece.imageUrl.isEmpty) {
      return _PieceImageFallback(framed: framed);
    }

    final image = Image.network(
      piece.imageUrl,
      fit: BoxFit.contain,
      semanticLabel: semanticLabel,
      errorBuilder: (context, error, stackTrace) {
        return _PieceImageFallback(framed: framed);
      },
    );

    if (!framed) {
      return Padding(
        padding: const EdgeInsets.all(4),
        child: image,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.88),
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

class _PieceImageFallback extends StatelessWidget {
  final bool framed;

  const _PieceImageFallback({
    this.framed = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!framed) {
      return Center(
        child: Icon(
          Icons.checkroom,
          color: Colors.grey.shade500,
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.72),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Icon(
          Icons.checkroom,
          color: Colors.grey.shade500,
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  final bool isDark;

  const _InfoPill({
    required this.label,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF122838) : const Color(0xFFEDE7DC),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Text(
          label.isEmpty ? 'Detay' : label,
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF3A3329),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _EmptyDetailState extends StatelessWidget {
  final Color textColor;
  final String message;

  const _EmptyDetailState({
    required this.textColor,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: textColor, fontSize: 16),
        ),
      ),
    );
  }
}

String _normalize(String value) {
  return value
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ş', 's')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c');
}
