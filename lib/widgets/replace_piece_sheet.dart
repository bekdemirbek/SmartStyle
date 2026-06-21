import 'package:flutter/material.dart';

import '../models/outfit_recommendation_models.dart';

class ReplacePieceRequest {
  final ClothingCategory category;
  final String replaceItem;
  final String selectedPiece;
  final String reason;
  final String intent;

  const ReplacePieceRequest({
    required this.category,
    required this.replaceItem,
    required this.selectedPiece,
    required this.reason,
    required this.intent,
  });
}

class ReplacePieceSheet extends StatefulWidget {
  final OutfitRecommendation recommendation;
  final ValueChanged<ReplacePieceRequest>? onSuggestionRequested;

  const ReplacePieceSheet({
    super.key,
    required this.recommendation,
    this.onSuggestionRequested,
  });

  @override
  State<ReplacePieceSheet> createState() => _ReplacePieceSheetState();
}

class _ReplacePieceSheetState extends State<ReplacePieceSheet> {
  _ReplaceCategoryOption? _selectedCategory;
  _ReplaceReasonOption? _selectedReason;
  int _step = 0;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        minChildSize: 0.52,
        maxChildSize: 0.92,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: _ReplacePieceColors.background,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _step == 0
                      ? _buildCategoryStep()
                      : _buildReasonStep(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCategoryStep() {
    final categories = _categoryOptions(widget.recommendation);

    return Column(
      key: const ValueKey('category-step'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepIndicator(activeStep: 0),
        const SizedBox(height: 18),
        Text(
          'Parçayı değiştir',
          style: _ReplacePieceText.title,
        ),
        const SizedBox(height: 4),
        const Text(
          'Hangi parçayı değiştirmek istiyorsun?',
          style: _ReplacePieceText.subtitle,
        ),
        const SizedBox(height: 20),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: categories.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.08,
          ),
          itemBuilder: (context, index) {
            final option = categories[index];
            return _CategoryCard(
              option: option,
              isSelected: option.category == _selectedCategory?.category,
              onTap: () => setState(() {
                _selectedCategory = option;
                _selectedReason = null;
              }),
            );
          },
        ),
        const SizedBox(height: 18),
        const _SheetDivider(),
        const SizedBox(height: 14),
        _PrimarySheetButton(
          label: 'Devam et',
          enabled: _selectedCategory != null,
          onPressed: () => setState(() => _step = 1),
        ),
        const SizedBox(height: 12),
        _SheetLink(
          label: 'Vazgeç',
          onTap: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _buildReasonStep() {
    final selected = _selectedCategory!;
    final reasons = _reasonOptions(selected.replaceItem);

    return Column(
      key: const ValueKey('reason-step'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepIndicator(activeStep: 1),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BackCircleButton(onTap: () => setState(() => _step = 0)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Parçayı değiştir', style: _ReplacePieceText.title),
                  const SizedBox(height: 4),
                  Text(
                    '${selected.label} · ${selected.currentPiece}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _ReplacePieceText.subtitle,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _SheetDivider(isActive: true),
        const SizedBox(height: 12),
        _InlineBackButton(onTap: () => setState(() => _step = 0)),
        const SizedBox(height: 14),
        const Text(
          'NASIL BIR PARCA OLSUN?',
          style: _ReplacePieceText.sectionLabel,
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: reasons.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.05,
          ),
          itemBuilder: (context, index) {
            final option = reasons[index];
            return _ReasonTile(
              option: option,
              isSelected: option.intent == _selectedReason?.intent,
              onTap: () => setState(() => _selectedReason = option),
            );
          },
        ),
        const SizedBox(height: 18),
        const _SheetDivider(),
        const SizedBox(height: 14),
        _PrimarySheetButton(
          label: 'Öneri getir',
          enabled: _selectedReason != null,
          onPressed: _submit,
        ),
        const SizedBox(height: 12),
        _SheetLink(
          label: 'Değişiklik istemiyorum',
          onTap: () => Navigator.pop(context),
        ),
      ],
    );
  }

  void _submit() {
    final category = _selectedCategory;
    final reason = _selectedReason;
    if (category == null || reason == null) return;

    final request = ReplacePieceRequest(
      category: category.category,
      replaceItem: category.replaceItem,
      selectedPiece: category.currentPiece,
      reason: reason.label,
      intent: reason.intent,
    );

    widget.onSuggestionRequested?.call(request);
    Navigator.pop(context, request);
  }

  List<_ReplaceCategoryOption> _categoryOptions(
    OutfitRecommendation recommendation,
  ) {
    return [
      _ReplaceCategoryOption(
        category: ClothingCategory.top,
        replaceItem: 'top',
        icon: Icons.checkroom,
        label: 'Üst giyim',
        currentPiece: _pieceName(recommendation.top),
      ),
      _ReplaceCategoryOption(
        category: ClothingCategory.bottom,
        replaceItem: 'bottom',
        icon: Icons.format_align_center,
        label: 'Alt giyim',
        currentPiece: _pieceName(recommendation.bottom),
      ),
      _ReplaceCategoryOption(
        category: ClothingCategory.shoes,
        replaceItem: 'shoes',
        icon: Icons.hiking,
        label: 'Ayakkabı',
        currentPiece: _pieceName(recommendation.shoes),
      ),
      _ReplaceCategoryOption(
        category: ClothingCategory.outerwear,
        replaceItem: 'outerwear',
        icon: Icons.dry_cleaning,
        label: 'Dış giyim',
        currentPiece: recommendation.outerwear == null
            ? 'Parça yok'
            : _pieceName(recommendation.outerwear!),
      ),
    ];
  }

  List<_ReplaceReasonOption> _reasonOptions(String replaceItem) {
    switch (replaceItem) {
      case 'top':
        return const [
          _ReplaceReasonOption(Icons.auto_awesome, 'Daha şık',
              'Gömlek, blazer, polo', 'smarter'),
          _ReplaceReasonOption(
              Icons.wb_sunny, 'Daha yazlık', 'İnce kumaş, kısa kol', 'lighter'),
          _ReplaceReasonOption(
              Icons.ac_unit, 'Daha kışlık', 'Kalın, kaşmir, örgü', 'warmer'),
          _ReplaceReasonOption(Icons.directions_run, 'Daha spor',
              'Dry-fit, performans', 'sport'),
          _ReplaceReasonOption(Icons.sentiment_satisfied, 'Daha günlük',
              'Basic, rahat kesim', 'casual'),
          _ReplaceReasonOption(
              Icons.palette, 'Farklı renk', 'Aynı model, yeni ton', 'color'),
        ];
      case 'bottom':
        return const [
          _ReplaceReasonOption(
              Icons.auto_awesome, 'Daha şık', 'Kumaş, formal kesim', 'smarter'),
          _ReplaceReasonOption(
              Icons.wb_sunny, 'Daha yazlık', 'Şort, keten, ince', 'lighter'),
          _ReplaceReasonOption(Icons.ac_unit, 'Daha kışlık',
              'Yün karışım, kalın', 'warmer'),
          _ReplaceReasonOption(
              Icons.directions_run, 'Daha spor', 'Jogger, şort', 'sport'),
          _ReplaceReasonOption(Icons.sentiment_satisfied, 'Daha günlük',
              'Chino, relaxed fit', 'casual'),
          _ReplaceReasonOption(
              Icons.palette, 'Farklı renk', 'Aynı model, yeni ton', 'color'),
        ];
      case 'shoes':
        return const [
          _ReplaceReasonOption(Icons.auto_awesome, 'Daha şık',
              'Loafer, derby, oxford', 'smarter'),
          _ReplaceReasonOption(Icons.wb_sunny, 'Daha yazlık',
              'Sandalet, espadrille', 'lighter'),
          _ReplaceReasonOption(Icons.ac_unit, 'Daha kışlık',
              'Bot, kışlık ayakkabı', 'warmer'),
          _ReplaceReasonOption(Icons.directions_run, 'Daha spor',
              'Koşu, antrenman', 'sport'),
          _ReplaceReasonOption(Icons.sentiment_satisfied, 'Daha günlük',
              'Sneaker, babet', 'casual'),
          _ReplaceReasonOption(
              Icons.palette, 'Farklı renk', 'Aynı model, yeni ton', 'color'),
        ];
      case 'outerwear':
        return const [
          _ReplaceReasonOption(
              Icons.auto_awesome, 'Daha şık', 'Blazer, trençkot', 'smarter'),
          _ReplaceReasonOption(Icons.wb_sunny, 'Daha yazlık',
              'İnce ceket, kimono', 'lighter'),
          _ReplaceReasonOption(
              Icons.ac_unit, 'Daha kışlık', 'Kaban, şişme mont', 'warmer'),
          _ReplaceReasonOption(Icons.water_drop, 'Yağmura uygun',
              'Su geçirmez kumaş', 'weather'),
          _ReplaceReasonOption(Icons.sentiment_satisfied, 'Daha casual',
              'Bomber, hoodie', 'casual'),
          _ReplaceReasonOption(
              Icons.palette, 'Farklı renk', 'Aynı model, yeni ton', 'color'),
        ];
      default:
        return const [];
    }
  }

  String _pieceName(ClothingItem item) {
    return item.subCategory.trim().isEmpty ? item.id : item.subCategory;
  }
}

class _StepIndicator extends StatelessWidget {
  final int activeStep;

  const _StepIndicator({required this.activeStep});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _StepLine(isActive: activeStep >= 0)),
        const SizedBox(width: 6),
        Expanded(child: _StepLine(isActive: activeStep >= 1)),
      ],
    );
  }
}

class _StepLine extends StatelessWidget {
  final bool isActive;

  const _StepLine({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 3,
      decoration: BoxDecoration(
        color: isActive
            ? _ReplacePieceColors.gold
            : _ReplacePieceColors.inactiveStep,
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final _ReplaceCategoryOption option;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _SelectableTileShell(
      isSelected: isSelected,
      borderRadius: 14,
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconBox(icon: option.icon, isSelected: isSelected, size: 36),
          const Spacer(),
          Text(
            option.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _ReplacePieceText.cardTitle(isSelected),
          ),
          const SizedBox(height: 6),
          Text(
            option.currentPiece,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _ReplacePieceText.cardSubtitle(isSelected),
          ),
        ],
      ),
    );
  }
}

class _ReasonTile extends StatelessWidget {
  final _ReplaceReasonOption option;
  final bool isSelected;
  final VoidCallback onTap;

  const _ReasonTile({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _SelectableTileShell(
      isSelected: isSelected,
      borderRadius: 13,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconBox(icon: option.icon, isSelected: isSelected, size: 32),
          const Spacer(),
          Text(
            option.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _ReplacePieceText.cardTitle(isSelected),
          ),
          const SizedBox(height: 6),
          Text(
            option.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _ReplacePieceText.cardSubtitle(isSelected),
          ),
        ],
      ),
    );
  }
}

class _SelectableTileShell extends StatelessWidget {
  final bool isSelected;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final Widget child;
  final VoidCallback onTap;

  const _SelectableTileShell({
    required this.isSelected,
    required this.borderRadius,
    required this.padding,
    required this.child,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: isSelected
            ? _ReplacePieceColors.selectedBackground
            : _ReplacePieceColors.card,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: isSelected
              ? _ReplacePieceColors.gold
              : _ReplacePieceColors.border,
          width: 0.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(borderRadius),
          onTap: onTap,
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  final IconData icon;
  final bool isSelected;
  final double size;

  const _IconBox({
    required this.icon,
    required this.isSelected,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isSelected
            ? _ReplacePieceColors.selectedIconBackground
            : _ReplacePieceColors.iconBackground,
        borderRadius: BorderRadius.circular(size == 36 ? 9 : 8),
      ),
      child: Icon(
        icon,
        size: size == 36 ? 18 : 16,
        color: isSelected
            ? _ReplacePieceColors.gold
            : _ReplacePieceColors.iconMuted,
      ),
    );
  }
}

class _PrimarySheetButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  const _PrimarySheetButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: _ReplacePieceColors.gold,
          foregroundColor: _ReplacePieceColors.background,
          disabledBackgroundColor: _ReplacePieceColors.disabledBackground,
          disabledForegroundColor: _ReplacePieceColors.disabledText,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class _SheetLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SheetLink({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: _ReplacePieceColors.disabledText,
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class _BackCircleButton extends StatelessWidget {
  final VoidCallback onTap;

  const _BackCircleButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _ReplacePieceColors.card,
      shape: const CircleBorder(
        side: BorderSide(color: _ReplacePieceColors.border, width: 0.5),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 32,
          height: 32,
          child: Icon(
            Icons.arrow_back,
            size: 16,
            color: _ReplacePieceColors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _InlineBackButton extends StatelessWidget {
  final VoidCallback onTap;

  const _InlineBackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.arrow_back,
              size: 14,
              color: _ReplacePieceColors.textMuted,
            ),
            SizedBox(width: 5),
            Text(
              'Parça seçimine dön',
              style: TextStyle(
                fontSize: 12,
                color: _ReplacePieceColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetDivider extends StatelessWidget {
  final bool isActive;

  const _SheetDivider({this.isActive = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: isActive ? 2 : 1,
      color: isActive
          ? _ReplacePieceColors.gold
          : _ReplacePieceColors.divider,
    );
  }
}

class _ReplaceCategoryOption {
  final ClothingCategory category;
  final String replaceItem;
  final IconData icon;
  final String label;
  final String currentPiece;

  const _ReplaceCategoryOption({
    required this.category,
    required this.replaceItem,
    required this.icon,
    required this.label,
    required this.currentPiece,
  });
}

class _ReplaceReasonOption {
  final IconData icon;
  final String label;
  final String description;
  final String intent;

  const _ReplaceReasonOption(
    this.icon,
    this.label,
    this.description,
    this.intent,
  );
}

class _ReplacePieceColors {
  static const Color gold = Color(0xFFC8A84B);
  static const Color background = Color(0xFF151515);
  static const Color card = Color(0xFF242424);
  static const Color border = Color(0xFF353535);
  static const Color inactiveStep = Color(0xFF2B2B2B);
  static const Color iconBackground = Color(0xFF303030);
  static const Color iconMuted = Color(0xFFA0A0A0);
  static const Color selectedBackground = Color(0xFF2A2312);
  static const Color selectedIconBackground = Color(0xFF3A2E13);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textCard = Color(0xFFF1F1F1);
  static const Color textSelected = Color(0xFFFFD86A);
  static const Color textMuted = Color(0xFF9A9A9A);
  static const Color textSelectedMuted = Color(0xFFD1A83B);
  static const Color disabledBackground = Color(0xFF2A2A2A);
  static const Color disabledText = Color(0xFF777777);
  static const Color divider = Color(0xFF303030);
}

class _ReplacePieceText {
  static const TextStyle title = TextStyle(
    fontSize: 17,
    color: _ReplacePieceColors.textPrimary,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle subtitle = TextStyle(
    fontSize: 12,
    color: _ReplacePieceColors.textMuted,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle sectionLabel = TextStyle(
    fontSize: 11,
    color: _ReplacePieceColors.textMuted,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.8,
  );

  static TextStyle cardTitle(bool selected) {
    return TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: selected
          ? _ReplacePieceColors.textSelected
          : _ReplacePieceColors.textCard,
    );
  }

  static TextStyle cardSubtitle(bool selected) {
    return TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      color: selected
          ? _ReplacePieceColors.textSelectedMuted
          : _ReplacePieceColors.textMuted,
    );
  }
}
