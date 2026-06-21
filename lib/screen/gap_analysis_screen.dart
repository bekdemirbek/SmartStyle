import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../app_theme.dart';
import '../models/gap_suggestion.dart';
import '../models/purchase_preference_profile.dart';
import '../models/wardrobe_item_model.dart';
import '../services/gap_analysis_service.dart';
import '../services/purchase_ai_service.dart';
import '../services/purchase_preference_service.dart';

// UPDATED: öneri filtreleri
const _filterOptions = [
  ('all', 'Tümü'),
  ('missing', 'Eksik kategori'),
  ('impact', 'Yüksek etki'),
  ('match', 'Dolabınla uyumlu'),
];

class GapAnalysisScreen extends StatefulWidget {
  final List<WardrobeItem> wardrobe;
  final List<GapSuggestion> suggestions;
  final int currentCombos;
  final bool? isMaleUser;

  const GapAnalysisScreen({
    super.key,
    required this.wardrobe,
    required this.suggestions,
    required this.currentCombos,
    this.isMaleUser,
  });

  @override
  State<GapAnalysisScreen> createState() => _GapAnalysisScreenState();
}

class _GapAnalysisScreenState extends State<GapAnalysisScreen> {
  final GapAnalysisService _gapAnalysisService = GapAnalysisService();
  final PurchasePreferenceService _preferenceService =
      PurchasePreferenceService();
  final PurchaseAiService _purchaseAiService = PurchaseAiService();
  final TextEditingController _contextController = TextEditingController();

  late List<GapSuggestion> _suggestions;
  PurchasePreferenceProfile _preferenceProfile =
      const PurchasePreferenceProfile();
  bool _isLoadingTasteProfile = true;
  bool _isLoadingAiSuggestions = false;
  bool _usingLocalFallback = true;
  String? _savingFeedbackId;
  String? _selectedOccasion;
  String? _selectedCategory;
  String _activeFilter = 'all'; // UPDATED

  @override
  void dispose() {
    _contextController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _suggestions = widget.suggestions;
    _loadTasteProfile();
  }

  Future<void> _loadTasteProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoadingTasteProfile = false);
      return;
    }

    try {
      final profile = await _preferenceService.fetchProfile(user.uid);
      if (!mounted) return;

      setState(() {
        _preferenceProfile = profile;
        _suggestions = _gapAnalysisService.analyze(
          widget.wardrobe,
          preferenceProfile: profile,
          contextText: _contextController.text,
          selectedOccasion: _selectedOccasion,
          selectedCategory: _selectedCategory,
          isMaleUser: widget.isMaleUser,
        );
        _isLoadingTasteProfile = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingTasteProfile = false);
    }
  }

  Future<void> _recordFeedback({
    required GapSuggestion suggestion,
    required PurchaseFeedbackReaction reaction,
    required PurchaseFeedbackReason reason,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnackBar("Zevkini hatırlamam için giriş yapmalısın.", isError: true);
      return;
    }

    setState(() => _savingFeedbackId = suggestion.candidateItem.id);

    try {
      await _preferenceService.recordFeedback(
        userId: user.uid,
        suggestion: suggestion,
        reaction: reaction,
        reason: reason,
      );
      final profile = await _preferenceService.fetchProfile(user.uid);
      if (!mounted) return;

      setState(() {
        _preferenceProfile = profile;
        _suggestions = _gapAnalysisService.analyze(
          widget.wardrobe,
          preferenceProfile: profile,
          contextText: _contextController.text,
          selectedOccasion: _selectedOccasion,
          selectedCategory: _selectedCategory,
          isMaleUser: widget.isMaleUser,
        );
      });

      _showSnackBar(
        reaction == PurchaseFeedbackReaction.like
            ? "Bunu sevdiğini not aldım."
            : "Tamam, sonraki önerilerde bunu hesaba katacağım.",
      );
    } catch (_) {
      if (!mounted) return;
      _showSnackBar("Geri bildirim kaydedilemedi.", isError: true);
    } finally {
      if (!mounted) return;
      setState(() => _savingFeedbackId = null);
    }
  }

  Future<void> _applyContext() async {
    FocusScope.of(context).unfocus();

    if (_shouldAskCategory) {
      setState(() {});
      return;
    }

    setState(() {
      _isLoadingAiSuggestions = true;
      _usingLocalFallback = false;
    });

    final localSuggestions = _gapAnalysisService.analyze(
      widget.wardrobe,
      preferenceProfile: _preferenceProfile,
      contextText: _contextController.text,
      selectedOccasion: _selectedOccasion,
      selectedCategory: _selectedCategory,
      isMaleUser: widget.isMaleUser,
    );

    try {
      final aiSuggestions = await _purchaseAiService.generateSuggestions(
        wardrobe: widget.wardrobe,
        currentCombos: widget.currentCombos,
        contextText: _contextController.text,
        userGender: _userGender,
        selectedOccasion: _selectedOccasion,
        selectedCategory: _selectedCategory,
      );
      final filteredAiSuggestions =
          _gapAnalysisService.filterExistingSuggestions(
        aiSuggestions,
        widget.wardrobe,
        contextText: _contextController.text,
        selectedOccasion: _selectedOccasion,
        selectedCategory: _selectedCategory,
        isMaleUser: widget.isMaleUser,
      );
      final nextSuggestions = _mergeSuggestions(
        localSuggestions,
        filteredAiSuggestions,
      );
      if (!mounted) return;
      setState(() {
        _suggestions = nextSuggestions;
        _usingLocalFallback = filteredAiSuggestions.isEmpty;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _usingLocalFallback = true;
        _suggestions = localSuggestions;
      });
    } finally {
      if (!mounted) return;
      setState(() => _isLoadingAiSuggestions = false);
    }
  }

  void _refreshLocalSuggestions() {
    setState(() {
      _usingLocalFallback = true;
      _suggestions = _gapAnalysisService.analyze(
        widget.wardrobe,
        preferenceProfile: _preferenceProfile,
        contextText: _contextController.text,
        selectedOccasion: _selectedOccasion,
        selectedCategory: _selectedCategory,
        isMaleUser: widget.isMaleUser,
      );
    });
  }

  void _clearContext() {
    _contextController.clear();
    _selectedOccasion = null;
    _selectedCategory = null;
    _refreshLocalSuggestions();
  }

  void _selectOccasion(String occasion) {
    setState(() => _selectedOccasion = occasion);
  }

  void _selectCategory(String category) {
    setState(() => _selectedCategory = category);
    _applyContext();
  }

  List<GapSuggestion> _mergeSuggestions(
    List<GapSuggestion> localSuggestions,
    List<GapSuggestion> aiSuggestions,
  ) {
    final merged = <GapSuggestion>[];
    final keys = <String>{};

    void add(GapSuggestion suggestion) {
      final item = suggestion.candidateItem;
      final key =
          '${item.category.toLowerCase()}|${item.type.toLowerCase()}|${item.color.toLowerCase()}';
      if (keys.add(key)) merged.add(suggestion);
    }

    for (final suggestion in localSuggestions) {
      add(suggestion);
    }
    for (final suggestion in aiSuggestions) {
      add(suggestion);
    }

    return merged.take(8).toList();
  }

  Future<void> _showDislikeReason(GapSuggestion suggestion) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final reason = await showModalBottomSheet<PurchaseFeedbackReason>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return AppTheme.frosted(
          isDark: isDark,
          radius: 24,
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppTheme.tertiaryText(isDark),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text("Neyi sevmedin?", style: AppTheme.heading2(isDark)),
                const SizedBox(height: 12),
                _ReasonTile(
                  icon: Icons.block_rounded,
                  title: "Parça bana göre değil",
                  isDark: isDark,
                  onTap: () => Navigator.pop(
                    context,
                    PurchaseFeedbackReason.item,
                  ),
                ),
                _ReasonTile(
                  icon: Icons.palette_outlined,
                  title: "Rengi sevmiyorum",
                  isDark: isDark,
                  onTap: () => Navigator.pop(
                    context,
                    PurchaseFeedbackReason.color,
                  ),
                ),
                _ReasonTile(
                  icon: Icons.auto_awesome_mosaic_outlined,
                  title: "Tarzı bana uymuyor",
                  isDark: isDark,
                  onTap: () => Navigator.pop(
                    context,
                    PurchaseFeedbackReason.style,
                  ),
                ),
                _ReasonTile(
                  icon: Icons.category_outlined,
                  title: "Bu kategoriden istemiyorum",
                  isDark: isDark,
                  onTap: () => Navigator.pop(
                    context,
                    PurchaseFeedbackReason.category,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (reason == null) return;
    await _recordFeedback(
      suggestion: suggestion,
      reaction: PurchaseFeedbackReaction.dislike,
      reason: reason,
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? const Color(0xFFE24B4A) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filterSource = _activeFilter == 'missing'
        ? _mergeSuggestions(
            _suggestions,
            _gapAnalysisService.missingCategorySuggestions(
              widget.wardrobe,
              isMaleUser: widget.isMaleUser,
            ),
          )
        : _suggestions;
    final filteredSuggestions = _activeFilter == 'all'
        ? filterSource
        : filterSource
            .where((suggestion) => _matchesActiveFilter(suggestion))
            .toList();
    final listLabel = _activeFilter == 'all'
        ? 'EN YÜKSEK ETKİYE GÖRE'
        : 'FİLTRELENMİŞ SONUÇLAR';

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF111114) : AppTheme.bg(isDark),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppTheme.primaryText(isDark),
        title: const Text("Ne Alsam?"),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            Text(
              "Ne alsam?",
              style: AppTheme.heading1(isDark).copyWith(fontSize: 24),
            ),
            const SizedBox(height: 4),
            Text(
              "Mevcut dolabına göre en çok kombin çıkaracak parçalar",
              style: AppTheme.body(isDark).copyWith(
                color: AppTheme.secondaryText(isDark),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: "Mevcut parça",
                    value: "${widget.wardrobe.length}",
                    isDark: isDark,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatCard(
                    label: "Gerçek kombin",
                    value: "${widget.currentCombos}",
                    isDark: isDark,
                    color: const Color(0xFF3DDEA2),
                    tooltip:
                        "Sadece üst x alt x ayakkabı çarpımı değil; formality, kullanım alanı ve mevsim uyumu geçen kombinler sayılır.",
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _ContextCard(
              controller: _contextController,
              isDark: isDark,
              selectedOccasion: _selectedOccasion,
              onOccasionSelected: _selectOccasion,
              onApply: _applyContext,
              onClear: _clearContext,
              isLoading: _isLoadingAiSuggestions,
            ),
            if (_usingLocalFallback && _suggestions.isNotEmpty) ...[
              const SizedBox(height: 12),
              _FallbackNotice(isDark: isDark),
            ],
            if (_shouldAskCategory) ...[
              const SizedBox(height: 12),
              _CategoryQuestionCard(
                selectedCategory: _selectedCategory,
                isDark: isDark,
                onSelected: _selectCategory,
              ),
            ] else if (_suggestions.isNotEmpty &&
                _suggestions.first.followUpQuestion != null) ...[
              const SizedBox(height: 12),
              _QuestionCard(
                question: _suggestions.first.followUpQuestion!,
                isDark: isDark,
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _filterOptions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final (value, label) = _filterOptions[i];
                  final isActive = _activeFilter == value;
                  final activeColor = AppTheme.gold(isDark);
                  return GestureDetector(
                    onTap: () => setState(() => _activeFilter = value),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isActive
                            ? activeColor
                            : (isDark
                                ? const Color(0xFF1F1F25)
                                : AppTheme.layer2(false)),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: isActive
                              ? activeColor
                              : (isDark
                                  ? const Color(0xFF2A2A32)
                                  : AppTheme.borderMediumLight),
                          width: .5,
                        ),
                      ),
                      child: Text(
                        label,
                        style: AppTheme.caption(isDark).copyWith(
                          color: isActive
                              ? AppTheme.textOnGold
                              : AppTheme.secondaryText(isDark),
                          fontWeight:
                              isActive ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _isLoadingAiSuggestions
                  ? "GEMINI ÖNERİ HAZIRLIYOR"
                  : _isLoadingTasteProfile
                  ? "ZEVK HAFIZASI YÜKLENİYOR"
                  : listLabel,
              style: AppTheme.label(isDark).copyWith(
                color: AppTheme.secondaryText(isDark),
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 10),
            if (_suggestions.isEmpty)
              _EmptyState(isDark: isDark)
            else if (filteredSuggestions.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Text(
                    'Bu filtreye uygun öneri bulunamadı.',
                    style: AppTheme.caption(isDark).copyWith(
                      color: AppTheme.secondaryText(isDark),
                    ),
                  ),
                ),
              )
            else
              for (var i = 0; i < filteredSuggestions.length; i++) ...[
                _GapSuggestionCard(
                  suggestion: filteredSuggestions[i],
                  rank: i,
                  isDark: isDark,
                  isSavingFeedback:
                      _savingFeedbackId ==
                      filteredSuggestions[i].candidateItem.id,
                  onLike: () => _recordFeedback(
                    suggestion: filteredSuggestions[i],
                    reaction: PurchaseFeedbackReaction.like,
                    reason: PurchaseFeedbackReason.item,
                  ),
                  onDislike: () => _showDislikeReason(filteredSuggestions[i]),
                ),
                const SizedBox(height: 12),
              ],
            const SizedBox(height: 12),
            if (_suggestions.isNotEmpty) ...[
              Divider(color: AppTheme.subtleBorder(isDark)),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.gold(isDark),
                    foregroundColor: AppTheme.textOnGold,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => _copyShoppingList(context),
                  icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                  label: const Text(
                    "Alışveriş listesi oluştur",
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool get _shouldAskCategory {
    if (_selectedCategory != null) return false;
    if (_contextHasCategorySignal(_contextController.text)) return false;
    return _selectedOccasion != null || _contextController.text.trim().isNotEmpty;
  }

  String get _userGender {
    if (widget.isMaleUser == true) return 'male';
    if (widget.isMaleUser == false) return 'female';
    return 'unspecified';
  }

  bool _matchesActiveFilter(GapSuggestion suggestion) {
    return suggestion.badgeType == _activeFilter;
  }

  bool _contextHasCategorySignal(String value) {
    final text = value.toLowerCase();
    return text.contains('gömlek') ||
        text.contains('gomlek') ||
        text.contains('tişört') ||
        text.contains('tisort') ||
        text.contains('üst') ||
        text.contains('ust') ||
        text.contains('pantolon') ||
        text.contains('jean') ||
        text.contains('chino') ||
        text.contains('alt') ||
        text.contains('ayakkabı') ||
        text.contains('ayakkabi') ||
        text.contains('sneaker') ||
        text.contains('bot') ||
        text.contains('ceket') ||
        text.contains('blazer') ||
        text.contains('mont');
  }

  Future<void> _copyShoppingList(BuildContext context) async {
    final text = _suggestions.map((suggestion) {
      final badgeLabel = suggestion.badgeLabel.isEmpty
          ? _fallbackBadgeLabel(suggestion.gain)
          : suggestion.badgeLabel;
      return "- ${suggestion.candidateItem.displayName}: "
          "${suggestion.candidateItem.color}, ${suggestion.style}, "
          "${suggestion.formality}, güven ${(suggestion.confidence * 100).round()}%. "
          "$badgeLabel: ${_badgeSubtitle(suggestion.badgeType)}. ${suggestion.reason}";
    }).join("\n");

    await Clipboard.setData(ClipboardData(text: "Ne Alsam?\n$text"));
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Alışveriş listesi panoya kopyalandı.")),
    );
  }
}

class _ContextCard extends StatelessWidget {
  final TextEditingController controller;
  final bool isDark;
  final String? selectedOccasion;
  final ValueChanged<String> onOccasionSelected;
  final Future<void> Function() onApply;
  final VoidCallback onClear;
  final bool isLoading;

  const _ContextCard({
    required this.controller,
    required this.isDark,
    required this.selectedOccasion,
    required this.onOccasionSelected,
    required this.onApply,
    required this.onClear,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.panelDecoration(isDark, radius: 14).copyWith(
        color: AppTheme.layer2(isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.tune_rounded,
                color: AppTheme.gold(isDark),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Ne için alıyorsun?",
                  style: AppTheme.body(isDark).copyWith(
                    color: AppTheme.primaryText(isDark),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FilterChip(
                label: "Günlük",
                value: "daily",
                selectedValue: selectedOccasion,
                isDark: isDark,
                onSelected: onOccasionSelected,
              ),
              _FilterChip(
                label: "İş",
                value: "work",
                selectedValue: selectedOccasion,
                isDark: isDark,
                onSelected: onOccasionSelected,
              ),
              _FilterChip(
                label: "Özel Gün",
                value: "wedding",
                selectedValue: selectedOccasion,
                isDark: isDark,
                onSelected: onOccasionSelected,
              ),
              _FilterChip(
                label: "Spor",
                value: "sport",
                selectedValue: selectedOccasion,
                isDark: isDark,
                onSelected: onOccasionSelected,
              ),
              _FilterChip(
                label: "Seyahat",
                value: "travel",
                selectedValue: selectedOccasion,
                isDark: isDark,
                onSelected: onOccasionSelected,
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            onSubmitted: (_) {
              onApply();
            },
            textInputAction: TextInputAction.done,
            style: AppTheme.body(isDark).copyWith(
              color: AppTheme.primaryText(isDark),
            ),
            decoration: InputDecoration(
              hintText: "Örn: Düğünüm var, ofis için, günlük rahat...",
              hintStyle: AppTheme.caption(isDark).copyWith(
                color: AppTheme.secondaryText(isDark),
              ),
              filled: true,
              fillColor: isDark ? const Color(0xFF17181E) : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppTheme.subtleBorder(isDark)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppTheme.subtleBorder(isDark)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppTheme.gold(isDark)),
              ),
              suffixIcon: IconButton(
                tooltip: "Temizle",
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isLoading
                  ? null
                  : () {
                      onApply();
                    },
              icon: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text(
                isLoading ? "Gemini düşünüyor..." : "Gemini ile öner",
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.gold(isDark),
                foregroundColor: AppTheme.textOnGold,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  final String question;
  final bool isDark;

  const _QuestionCard({
    required this.question,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF201E18) : const Color(0xFFFFF6DF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.gold(isDark).withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.help_outline_rounded,
            color: AppTheme.gold(isDark),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              question,
              style: AppTheme.body(isDark).copyWith(
                color: AppTheme.primaryText(isDark),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FallbackNotice extends StatelessWidget {
  final bool isDark;

  const _FallbackNotice({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF201E18) : const Color(0xFFFFF6DF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.gold(isDark).withOpacity(0.28)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: AppTheme.gold(isDark),
            size: 18,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              "Gemini önerisi alınamazsa yerel stil motoru devreye girer.",
              style: AppTheme.caption(isDark).copyWith(
                color: AppTheme.primaryText(isDark),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryQuestionCard extends StatelessWidget {
  final String? selectedCategory;
  final bool isDark;
  final ValueChanged<String> onSelected;

  const _CategoryQuestionCard({
    required this.selectedCategory,
    required this.isDark,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.panelDecoration(isDark, radius: 14).copyWith(
        color: AppTheme.layer2(isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Hangi parçayı arıyorsun?",
            style: AppTheme.body(isDark).copyWith(
              color: AppTheme.primaryText(isDark),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Seçince öneriler sadece o kategoriye göre daralır.",
            style: AppTheme.caption(isDark).copyWith(
              color: AppTheme.secondaryText(isDark),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FilterChip(
                label: "Üst Giyim",
                value: "upper",
                selectedValue: selectedCategory,
                isDark: isDark,
                onSelected: onSelected,
              ),
              _FilterChip(
                label: "Alt Giyim",
                value: "lower",
                selectedValue: selectedCategory,
                isDark: isDark,
                onSelected: onSelected,
              ),
              _FilterChip(
                label: "Ayakkabı",
                value: "shoes",
                selectedValue: selectedCategory,
                isDark: isDark,
                onSelected: onSelected,
              ),
              _FilterChip(
                label: "Dış Giyim",
                value: "outerwear",
                selectedValue: selectedCategory,
                isDark: isDark,
                onSelected: onSelected,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String value;
  final String? selectedValue;
  final bool isDark;
  final ValueChanged<String> onSelected;

  const _FilterChip({
    required this.label,
    required this.value,
    required this.selectedValue,
    required this.isDark,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == selectedValue;

    return Material(
      color: selected
          ? AppTheme.gold(isDark)
          : (isDark ? const Color(0xFF17181E) : Colors.white),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: () => onSelected(value),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : AppTheme.subtleBorder(isDark),
            ),
          ),
          child: Text(
            label,
            style: AppTheme.caption(isDark).copyWith(
              color: selected
                  ? AppTheme.textOnGold
                  : AppTheme.primaryText(isDark),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReasonTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isDark;
  final VoidCallback onTap;

  const _ReasonTile({
    required this.icon,
    required this.title,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppTheme.layer2(isDark),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: AppTheme.gold(isDark), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: AppTheme.body(isDark).copyWith(
                      color: AppTheme.primaryText(isDark),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.tertiaryText(isDark),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;
  final Color color;
  final String? tooltip;

  const _StatCard({
    required this.label,
    required this.value,
    required this.isDark,
    required this.color,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.panelDecoration(isDark, radius: 12)
          .copyWith(color: AppTheme.layer2(isDark)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppTheme.heading2(isDark).copyWith(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: AppTheme.caption(isDark).copyWith(
                    color: AppTheme.secondaryText(isDark),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (tooltip != null) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: tooltip!,
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: AppTheme.tertiaryText(isDark),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _GapSuggestionCard extends StatelessWidget {
  final GapSuggestion suggestion;
  final int rank;
  final bool isDark;
  final bool isSavingFeedback;
  final VoidCallback onLike;
  final VoidCallback onDislike;

  const _GapSuggestionCard({
    required this.suggestion,
    required this.rank,
    required this.isDark,
    required this.isSavingFeedback,
    required this.onLike,
    required this.onDislike,
  });

  @override
  Widget build(BuildContext context) {
    final accent = _badgeColor(suggestion.badgeType, isDark);
    final badgeLabel = suggestion.badgeLabel.isEmpty
        ? _fallbackBadgeLabel(suggestion.gain)
        : suggestion.badgeLabel;
    final progress = suggestion.confidence.clamp(0.12, 1.0).toDouble();
    final chips = suggestion.compatibleItems.take(4).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.panelDecoration(isDark, radius: 14).copyWith(
        color: AppTheme.layer2(isDark),
        border: Border.all(
          color: rank == 0 ? accent.withOpacity(0.85) : Colors.transparent,
          width: rank == 0 ? 1 : 0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  suggestion.candidateItem.displayName,
                  style: AppTheme.body(isDark).copyWith(
                    color: AppTheme.primaryText(isDark),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _badgeColor(suggestion.badgeType, isDark)
                      .withOpacity(0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badgeLabel,
                  textAlign: TextAlign.center,
                  style: AppTheme.caption(isDark).copyWith(
                    color: _badgeColor(suggestion.badgeType, isDark),
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _MetaChip(
                label: suggestion.candidateItem.color,
                isDark: isDark,
                accent: accent,
              ),
              _MetaChip(
                label: suggestion.style,
                isDark: isDark,
                accent: accent,
              ),
              _MetaChip(
                label: _formalityLabel(suggestion.formality),
                isDark: isDark,
                accent: accent,
              ),
              _MetaChip(
                label:
                    "Güven ${(suggestion.confidence * 100).round().clamp(0, 100)}%",
                isDark: isDark,
                accent: accent,
              ),
              for (final occasion in suggestion.occasion.take(2))
                _MetaChip(
                  label: _occasionLabel(occasion),
                  isDark: isDark,
                  accent: accent,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            suggestion.reason,
            style: AppTheme.body(isDark).copyWith(
              color: isDark ? const Color(0xFFD9DCE4) : AppTheme.secondaryText(isDark),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final item in chips)
                  _CompatibleChip(
                    label: item.displayName,
                    isDark: isDark,
                    accent: accent,
                  ),
                if (suggestion.compatibleItems.length > 4)
                  _CompatibleChip(
                    label: "+${suggestion.compatibleItems.length - 4}",
                    isDark: isDark,
                    accent: accent,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Divider(color: AppTheme.subtleBorder(isDark)),
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton(
                tooltip: "İlgimi çekti",
                onPressed: isSavingFeedback ? null : onLike,
                icon: isSavingFeedback
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.thumb_up_alt_outlined, size: 18),
                color: accent,
              ),
              IconButton(
                tooltip: "Bana göre değil",
                onPressed: isSavingFeedback ? null : onDislike,
                icon: const Icon(Icons.thumb_down_alt_outlined, size: 18),
                color: AppTheme.secondaryText(isDark),
              ),
              const SizedBox(width: 6),
              Text(
                badgeLabel,
                style: AppTheme.heading2(isDark).copyWith(
                  color: _badgeColor(suggestion.badgeType, isDark),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _badgeSubtitle(suggestion.badgeType),
                      style: AppTheme.caption(isDark).copyWith(
                        color: AppTheme.secondaryText(isDark),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 5,
                        value: progress.clamp(0.08, 1.0).toDouble(),
                        backgroundColor:
                            isDark ? Colors.white10 : const Color(0xFFE8E1D6),
                        valueColor: AlwaysStoppedAnimation<Color>(accent),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formalityLabel(String value) {
    switch (value) {
      case 'formal':
        return 'Formal';
      case 'semi-formal':
        return 'Yarı formal';
      case 'smart casual':
        return 'Smart casual';
      default:
        return 'Günlük';
    }
  }

  String _occasionLabel(String value) {
    switch (value) {
      case 'wedding':
        return 'Düğün';
      case 'work':
        return 'Ofis';
      case 'semi-formal':
        return 'Yarı formal';
      case 'date':
        return 'Akşam planı';
      case 'sport':
        return 'Spor';
      case 'smart casual':
        return 'Smart casual';
      default:
        return 'Günlük';
    }
  }
}

// UPDATED: rozet renk ve alt başlık helper'ları
Color _badgeColor(String type, bool isDark) {
  switch (type) {
    case 'missing':
      return const Color(0xFFF0A500);
    case 'match':
      return const Color(0xFF4DB8FF);
    case 'other':
      return isDark ? const Color(0xFFC7CAD1) : const Color(0xFF6E7380);
    default:
      return AppTheme.gold(isDark);
  }
}

String _badgeSubtitle(String type) {
  switch (type) {
    case 'missing':
      return 'eksik kategorini kapatır';
    case 'match':
      return 'dolabınla en uyumlu';
    case 'other':
      return 'dolabına göre öneri';
    default:
      return 'yüksek dolap etkisi';
  }
}

String _fallbackBadgeLabel(int gain) {
  if (gain >= 8) return 'Yüksek etki';
  if (gain >= 3) return 'Orta etki';
  return 'Düşük etki';
}

class _MetaChip extends StatelessWidget {
  final String label;
  final bool isDark;
  final Color accent;

  const _MetaChip({
    required this.label,
    required this.isDark,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withOpacity(0.18)),
      ),
      child: Text(
        label,
        style: AppTheme.caption(isDark).copyWith(
          color: isDark ? const Color(0xFFECEEF4) : AppTheme.primaryText(isDark),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CompatibleChip extends StatelessWidget {
  final String label;
  final bool isDark;
  final Color accent;

  const _CompatibleChip({
    required this.label,
    required this.isDark,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: AppTheme.caption(isDark).copyWith(
          color: isDark ? const Color(0xFFECEEF4) : AppTheme.primaryText(isDark),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isDark;

  const _EmptyState({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.panelDecoration(isDark, radius: 14)
          .copyWith(color: AppTheme.layer2(isDark)),
      child: Text(
        "Bu dolapta denediğim aday parçalar yeterince güçlü bir etki yaratmadı. Yeni renk, stil etiketi veya farklı kategori ekledikçe daha fazla öneri çıkar.",
        style: AppTheme.body(isDark).copyWith(
          color: AppTheme.secondaryText(isDark),
          height: 1.45,
        ),
      ),
    );
  }
}
