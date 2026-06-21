import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/wardrobe_item_model.dart';
import '../services/wardrobe_item_service.dart';

class ClothingDetailPage extends StatefulWidget {
  final String collection;
  final String documentId;

  const ClothingDetailPage({
    super.key,
    required this.collection,
    required this.documentId,
  });

  @override
  State<ClothingDetailPage> createState() => _ClothingDetailPageState();
}

class _ClothingDetailPageState extends State<ClothingDetailPage> {
  final WardrobeItemService _wardrobeItemService = WardrobeItemService();
  late Future<WardrobeItem?> _itemFuture;
  WardrobeItem? _item;
  bool _isFavoriteUpdating = false;

  @override
  void initState() {
    super.initState();
    _itemFuture = _loadItem();
  }

  Future<WardrobeItem?> _loadItem() async {
    final item = await _wardrobeItemService.fetchItem(
      collection: widget.collection,
      documentId: widget.documentId,
    );
    _item = item;
    return item;
  }

  Future<void> _toggleFavorite() async {
    final item = _item;
    if (item == null || _isFavoriteUpdating) return;

    final nextValue = !item.favorite;
    setState(() {
      _isFavoriteUpdating = true;
      _item = item.copyWith(favorite: nextValue);
    });

    try {
      await _wardrobeItemService.toggleFavorite(
        collection: widget.collection,
        documentId: widget.documentId,
        isFavorite: nextValue,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _item = item;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Favori durumu güncellenemedi.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isFavoriteUpdating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        isDark ? AppTheme.darkBackground : AppTheme.lightBackground;
    final textColor = isDark ? Colors.white : AppTheme.lightText;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        foregroundColor: textColor,
        title: const Text('Kıyafet Detayı'),
        actions: [
          IconButton(
            onPressed: _isFavoriteUpdating ? null : _toggleFavorite,
            icon: Icon(
              (_item?.favorite ?? false)
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: (_item?.favorite ?? false) ? Colors.redAccent : textColor,
            ),
          ),
        ],
      ),
      body: FutureBuilder<WardrobeItem?>(
        future: _itemFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final item = _item ?? snapshot.data;
          if (snapshot.hasError || item == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Kıyafet detayı bulunamadı.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: textColor, fontSize: 16),
                ),
              ),
            );
          }

          return _ClothingDetailContent(
            item: item,
            isDark: isDark,
          );
        },
      ),
    );
  }
}

class _ClothingDetailContent extends StatelessWidget {
  final WardrobeItem item;
  final bool isDark;

  const _ClothingDetailContent({
    required this.item,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : AppTheme.lightText;
    final subTextColor = isDark ? Colors.white70 : AppTheme.lightSubText;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      children: [
        _HeroImage(item: item, isDark: isDark),
        const SizedBox(height: 22),
        Text(
          item.type.isEmpty ? 'Kıyafet' : item.type,
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
            _InfoPill(label: _displayValue(item.category), isDark: isDark),
            _InfoPill(label: 'Renk: ${_displayValue(item.color)}', isDark: isDark),
            if (item.favorite) _InfoPill(label: 'Favori', isDark: isDark),
          ],
        ),
        const SizedBox(height: 24),
        _DetailPanel(
          isDark: isDark,
          rows: [
            _DetailRowData('Kategori', _displayValue(item.category)),
            _DetailRowData('Tür', _displayValue(item.type)),
            _DetailRowData('Renk', _displayValue(item.color)),
            _DetailRowData('Kumaş', _displayValue(item.fabricType)),
            if (item.buttoned != null)
              _DetailRowData('Düğmeli mi?', item.buttoned! ? 'Evet' : 'Hayır'),
            if (item.zippered != null)
              _DetailRowData('Fermuarlı mı?', item.zippered! ? 'Evet' : 'Hayır'),
            if (item.createdAt != null)
              _DetailRowData('Eklenme Tarihi', _formatDate(item.createdAt!)),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          'Bu parça dolabındaki kayıtlı kıyafet verilerinden getirildi. Favori durumunu buradan güncelleyebilirsin.',
          style: TextStyle(
            color: subTextColor,
            fontSize: 14,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  String _displayValue(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'Belirtilmedi' : trimmed;
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day.$month.${date.year}';
  }
}

class _HeroImage extends StatelessWidget {
  final WardrobeItem item;
  final bool isDark;

  const _HeroImage({
    required this.item,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 360,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFFDFE7ED) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2DDD3),
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
          color: isDark ? const Color(0xFFEAF0F4) : const Color(0xFFF7F4EE),
          child: item.imageUrl.isEmpty
              ? const Center(
                  child: Icon(Icons.checkroom_rounded, size: 54),
                )
              : Image.network(
                  item.imageUrl,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  errorBuilder: (context, error, stackTrace) {
                    return const Center(
                      child: Icon(Icons.checkroom_rounded, size: 54),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _DetailPanel extends StatelessWidget {
  final bool isDark;
  final List<_DetailRowData> rows;

  const _DetailPanel({
    required this.isDark,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF112231) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2DDD3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: rows
              .map(
                (row) => _DetailRow(
                  label: row.label,
                  value: row.value,
                  isDark: isDark,
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;

  const _DetailRow({
    required this.label,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isDark ? Colors.white60 : const Color(0xFF747474),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF232323),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRowData {
  final String label;
  final String value;

  const _DetailRowData(this.label, this.value);
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
          label,
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
