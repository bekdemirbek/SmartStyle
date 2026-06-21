import 'dart:async';
import 'dart:io' show File;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_theme.dart';
import '../main.dart';
import '../models/wardrobe_item_model.dart';
import '../services/combination_logic.dart';
import '../services/notification_service.dart';
import '../services/outfit_recommendation_service.dart';
import 'login_screen.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final ImagePicker _picker = ImagePicker();
  bool _isUploadingPhoto = false;
  final _notificationController = UserNotificationSettingsController();

  static const List<Map<String, String>> _femaleAvatars = [
    {"label": "Kadın Avatar 1", "path": "assets/avatars/female_1.png"},
    {"label": "Kadın Avatar 2", "path": "assets/avatars/female_2.webp"},
    {"label": "Kadın Avatar 3", "path": "assets/avatars/female_3.png"},
  ];

  static const List<Map<String, String>> _maleAvatars = [
    {"label": "Erkek Avatar 1", "path": "assets/avatars/male_1.png"},
    {"label": "Erkek Avatar 2", "path": "assets/avatars/male_2.png"},
    {"label": "Erkek Avatar 3", "path": "assets/avatars/male_3.png"},
  ];

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _pickProfilePhoto({
    ImageSource source = ImageSource.gallery,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.front,
      );
      if (pickedFile == null) return;
      setState(() {
        _isUploadingPhoto = true;
      });

      final storageRef = FirebaseStorage.instance
          .ref()
          .child("profile_images")
          .child("${user.uid}.jpg");

      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        await storageRef.putData(
          bytes,
          SettableMetadata(contentType: "image/jpeg"),
        );
      } else {
        await storageRef.putFile(File(pickedFile.path));
      }

      final downloadUrl = await storageRef.getDownloadURL();
      await FirebaseFirestore.instance.collection("users").doc(user.uid).set({
        "profile_image_url": downloadUrl,
        "selected_avatar_asset": FieldValue.delete(),
      }, SetOptions(merge: true));
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingPhoto = false;
        });
      }
    }
  }

  Future<void> _selectAvatar(String avatarAssetPath) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection("users").doc(user.uid).set({
      "selected_avatar_asset": avatarAssetPath,
      "profile_image_url": FieldValue.delete(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _removeProfilePhoto() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .get();

    final data = userDoc.data() ?? {};
    final profileImageUrl = (data["profile_image_url"] ?? "").toString();

    if (profileImageUrl.isNotEmpty) {
      try {
        await FirebaseStorage.instance.refFromURL(profileImageUrl).delete();
      } catch (_) {}
    }

    await FirebaseFirestore.instance.collection("users").doc(user.uid).set({
      "profile_image_url": FieldValue.delete(),
      "selected_avatar_asset": FieldValue.delete(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    Navigator.pop(context);
  }

  void _showAvatarPicker(bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return AppTheme.frosted(
          isDark: isDark,
          radius: 28,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
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
                  Text("Avatar Seç", style: AppTheme.heading2(isDark)),
                  const SizedBox(height: 14),
                  _buildAvatarGrid("Kadın Avatarları", _femaleAvatars, isDark),
                  const SizedBox(height: 18),
                  _buildAvatarGrid("Erkek Avatarları", _maleAvatars, isDark),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAvatarGrid(
    String title,
    List<Map<String, String>> avatars,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTheme.caption(isDark).copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: avatars.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.82,
          ),
          itemBuilder: (context, index) {
            final avatar = avatars[index];
            return GestureDetector(
              onTap: () => _selectAvatar(avatar["path"]!),
              child: Container(
                decoration: AppTheme.panelDecoration(isDark, radius: 16),
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    CircleAvatar(radius: 28, backgroundImage: AssetImage(avatar["path"]!)),
                    const Spacer(),
                    Text(
                      avatar["label"]!,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.captionText(isDark),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  void _showProfileOptions({
    required bool isDark,
    required bool hasProfileVisual,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return AppTheme.frosted(
          isDark: isDark,
          radius: 28,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppTheme.tertiaryText(isDark),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 18),
                _actionTile(
                  isDark: isDark,
                  icon: Icons.photo_library_outlined,
                  title: "Galeriden Seç",
                  onTap: () {
                    Navigator.pop(context);
                    _pickProfilePhoto();
                  },
                ),
                const SizedBox(height: 12),
                _actionTile(
                  isDark: isDark,
                  icon: Icons.photo_camera_outlined,
                  title: "Fotoğraf Çek",
                  onTap: () {
                    Navigator.pop(context);
                    _pickProfilePhoto(source: ImageSource.camera);
                  },
                ),
                const SizedBox(height: 12),
                _actionTile(
                  isDark: isDark,
                  icon: Icons.face_retouching_natural_outlined,
                  title: "Hazır Avatar Seç",
                  onTap: () {
                    Navigator.pop(context);
                    _showAvatarPicker(isDark);
                  },
                ),
                if (hasProfileVisual) ...[
                  const SizedBox(height: 12),
                  _actionTile(
                    isDark: isDark,
                    icon: Icons.delete_outline_rounded,
                    title: "Profil Görselini Kaldır",
                    destructive: true,
                    onTap: _removeProfilePhoto,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _actionTile({
    required bool isDark,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final color = destructive ? const Color(0xFFE24B4A) : AppTheme.primaryText(isDark);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: AppTheme.panelDecoration(isDark, radius: 18),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: AppTheme.body(isDark).copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: AppTheme.tertiaryText(isDark),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLogoutSheet(bool isDark) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return AppTheme.frosted(
          isDark: isDark,
          radius: 28,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppTheme.tertiaryText(isDark),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  "Çıkış yapmak istediğinize emin misiniz?",
                  textAlign: TextAlign.center,
                  style: AppTheme.heading2(isDark),
                ),
                const SizedBox(height: 10),
                Text(
                  "Hesabından çıkış yapacaksın.",
                  textAlign: TextAlign.center,
                  style: AppTheme.body(isDark).copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.primaryText(isDark).withOpacity(0.88),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryText(isDark),
                          textStyle: AppTheme.body(isDark).copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1,
                          ),
                          side: BorderSide(
                            color: AppTheme.gold(isDark).withOpacity(
                              isDark ? 0.72 : 0.58,
                            ),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusButton,
                            ),
                          ),
                        ),
                        child: const Text("Vazgeç"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          await _logout(this.context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE24B4A),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text("Çıkış Yap"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Stream<_ProfileStats> _watchProfileStats(String userId) {
    final controller = StreamController<_ProfileStats>();
    final itemsByCollection = <String, List<WardrobeItem>>{};
    final subscriptions = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

    void emitStats() {
      final wardrobe = itemsByCollection.values
          .expand((items) => items)
          .toList(growable: false);
      controller.add(
        _ProfileStats(
          pieceCount: wardrobe.length,
          combinationCount: logicalCombinationCount(wardrobe),
        ),
      );
    }

    controller.onListen = () {
      emitStats();
      for (final collection in OutfitRecommendationService.wardrobeCollections.values) {
        final subscription = FirebaseFirestore.instance
            .collection(collection)
            .where('user_id', isEqualTo: userId)
            .snapshots()
            .listen(
          (snapshot) {
            itemsByCollection[collection] = snapshot.docs
                .map(
                  (doc) => WardrobeItem.fromFirestore(
                    doc: doc,
                    collection: collection,
                  ),
                )
                .toList(growable: false);
            emitStats();
          },
          onError: controller.addError,
        );
        subscriptions.add(subscription);
      }
    };

    controller.onCancel = () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    };

    return controller.stream;
  }

  void _showSuccessToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF1FAE66),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showChangePasswordSheet(bool isDark) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _ChangePasswordSheet(
        isDark: isDark,
        onSuccess: () => _showSuccessToast(
          _ProfileStrings.t('profile.password.success'),
        ),
      ),
    );
  }

  Future<void> _showChangeEmailSheet(bool isDark) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _ChangeEmailSheet(
        isDark: isDark,
        onSuccess: () => _showSuccessToast(
          _ProfileStrings.t('profile.email.success'),
        ),
      ),
    );
  }

  String _passwordChangedSubtitle(Object? value) {
    DateTime? changedAt;
    if (value is Timestamp) {
      changedAt = value.toDate();
    } else if (value is DateTime) {
      changedAt = value;
    } else if (value is String) {
      changedAt = DateTime.tryParse(value);
    }

    if (changedAt == null) {
      return _ProfileStrings.t('profile.password.neverChanged');
    }

    final diff = DateTime.now().difference(changedAt);
    if (diff.inMinutes < 1) {
      return _ProfileStrings.t('profile.password.changedNow');
    }
    if (diff.inHours < 1) {
      return 'Son değişiklik: ${diff.inMinutes} dk önce';
    }
    if (diff.inDays < 1) {
      return 'Son değişiklik: ${diff.inHours} saat önce';
    }
    if (diff.inDays == 1) {
      return _ProfileStrings.t('profile.password.changedYesterday');
    }
    if (diff.inDays < 30) {
      return 'Son değişiklik: ${diff.inDays} gün önce';
    }

    final months = diff.inDays ~/ 30;
    if (months < 12) {
      return 'Son değişiklik: $months ay önce';
    }

    final years = diff.inDays ~/ 365;
    return 'Son değişiklik: $years yıl önce';
  }

  Widget _buildProfileAvatar({
    required String? profileImageUrl,
    required String? selectedAvatarAsset,
    required bool isDark,
  }) {
    ImageProvider? imageProvider;
    if (profileImageUrl != null && profileImageUrl.isNotEmpty) {
      imageProvider = NetworkImage(profileImageUrl);
    } else if (selectedAvatarAsset != null && selectedAvatarAsset.isNotEmpty) {
      imageProvider = AssetImage(selectedAvatarAsset);
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppTheme.themeGoldGradient(isDark) as Gradient?,
      ),
      child: Stack(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: isDark ? AppTheme.surface2 : AppTheme.surface2Light,
            backgroundImage: imageProvider,
            child: imageProvider == null
                ? Icon(
                    Icons.person,
                    size: 40,
                    color: AppTheme.tertiaryText(isDark),
                  )
                : null,
          ),
          if (_isUploadingPhoto)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.38),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _settingTile({
    required bool isDark,
    required IconData icon,
    required String title,
    required String subtitle,
    Color? iconBackground,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconBackground ?? _ProfileColors.iconGoldBackground(isDark),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 17, color: _ProfileColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: _ProfileColors.rowTitle(isDark),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _ProfileColors.rowSubtitle(isDark),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              trailing ??
                  Icon(
                    Icons.chevron_right_rounded,
                    color: _ProfileColors.chevron(isDark),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String key, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Text(
        _ProfileStrings.t(key).toUpperCase(),
        style: TextStyle(
          color: _ProfileColors.sectionLabel(isDark),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _sectionCard({required bool isDark, required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: _ProfileColors.surface(isDark),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _ProfileColors.border(isDark), width: 0.7),
      ),
      child: Column(children: children),
    );
  }

  Widget _profileStat(String value, String label, bool isDark) {
    return Expanded(
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: _ProfileColors.statBackground(isDark),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _ProfileColors.accentBorder(isDark), width: 0.8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: _ProfileColors.accent,
                fontSize: 19,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: _ProfileColors.statLabel(isDark),
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authUser = FirebaseAuth.instance.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (authUser == null) {
      return Scaffold(
        backgroundColor: AppTheme.bg(isDark),
        body: Center(
          child: Text(
            "Kullanıcı bulunamadı",
            style: AppTheme.body(isDark),
          ),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection("users")
          .doc(authUser.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final userData = snapshot.data?.data() ?? {};
        final profileImageUrl = (userData["profile_image_url"] ?? "").toString().trim();
        final selectedAvatarAsset =
            (userData["selected_avatar_asset"] ?? "").toString().trim();
        final hasProfileVisual =
            profileImageUrl.isNotEmpty || selectedAvatarAsset.isNotEmpty;
        final email = authUser.email?.trim() ?? "E-posta bulunamadı";
        final fallbackName = authUser.displayName?.trim().isNotEmpty == true
            ? authUser.displayName!.trim()
            : email.split('@').first;
        final name = (userData["ad_soyad"] ?? "").toString().trim().isNotEmpty
            ? (userData["ad_soyad"]).toString().trim()
            : fallbackName;
        final settings = UserNotificationSettings.fromMap(
          userData["notification_settings"],
        );
        final hasPasswordProvider = authUser.providerData.any(
          (provider) => provider.providerId == 'password',
        );
        final authProvider = (userData["auth_provider"] ?? "")
            .toString()
            .trim()
            .toLowerCase();
        final usesPasswordAuth = hasPasswordProvider && authProvider != 'google';
        final passwordSubtitle = _passwordChangedSubtitle(
          userData["last_password_changed_at"],
        );

        return Scaffold(
          backgroundColor: _ProfileColors.background(isDark),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 22),
                    decoration: BoxDecoration(
                      color: _ProfileColors.header(isDark),
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(22),
                      ),
                    ),
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: _isUploadingPhoto
                              ? null
                              : () => _showProfileOptions(
                                    isDark: isDark,
                                    hasProfileVisual: hasProfileVisual,
                                  ),
                          child: _buildProfileAvatar(
                            profileImageUrl:
                                profileImageUrl.isEmpty ? null : profileImageUrl,
                            selectedAvatarAsset: selectedAvatarAsset.isEmpty
                                ? null
                                : selectedAvatarAsset,
                            isDark: isDark,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          name,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _ProfileColors.primaryText(isDark),
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          email,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _ProfileColors.secondaryText(isDark),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 18),
                        StreamBuilder<_ProfileStats>(
                          stream: _watchProfileStats(authUser.uid),
                          initialData: _ProfileStats.empty,
                          builder: (context, snapshot) {
                            final stats = snapshot.data!;
                            return Row(
                              children: [
                                _profileStat(
                                  '${stats.pieceCount}',
                                  _ProfileStrings.t('profile.stats.pieces'),
                                  isDark,
                                ),
                                const SizedBox(width: 8),
                                _profileStat(
                                  '${stats.combinationCount}',
                                  _ProfileStrings.t('profile.stats.outfits'),
                                  isDark,
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 36,
                          child: OutlinedButton.icon(
                            onPressed: _isUploadingPhoto
                                ? null
                                : () => _showProfileOptions(
                                      isDark: isDark,
                                      hasProfileVisual: hasProfileVisual,
                                    ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _ProfileColors.primaryText(isDark),
                              side: BorderSide(color: _ProfileColors.accentBorder(isDark)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            icon: const Icon(Icons.edit_outlined, size: 15),
                            label: Text(
                              _ProfileStrings.t('profile.editPhoto'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _sectionLabel('profile.section.appearance', isDark),
                  _sectionCard(
                    isDark: isDark,
                    children: [
                      _settingTile(
                        isDark: isDark,
                        icon: Icons.dark_mode_outlined,
                        title: _ProfileStrings.t('profile.darkMode.title'),
                        subtitle: isDark
                            ? _ProfileStrings.t('profile.darkMode.darkSubtitle')
                            : _ProfileStrings.t('profile.darkMode.lightSubtitle'),
                        trailing: Switch(
                          value: isDark,
                          activeColor: _ProfileColors.switchThumb(isDark),
                          activeTrackColor: _ProfileColors.accent,
                          inactiveThumbColor: _ProfileColors.inactiveThumb(isDark),
                          inactiveTrackColor: _ProfileColors.inactiveTrack(isDark),
                          onChanged: (value) {
                            themeNotifier.value =
                                value ? ThemeMode.dark : ThemeMode.light;
                          },
                        ),
                      ),
                    ],
                  ),
                  _sectionLabel('profile.section.security', isDark),
                  _sectionCard(
                    isDark: isDark,
                    children: [
                      _settingTile(
                        isDark: isDark,
                        icon: usesPasswordAuth
                            ? Icons.lock_outline_rounded
                            : Icons.g_mobiledata_rounded,
                        title: usesPasswordAuth
                            ? _ProfileStrings.t('profile.password.title')
                            : _ProfileStrings.t('profile.google.title'),
                        subtitle: usesPasswordAuth
                            ? passwordSubtitle
                            : _ProfileStrings.t('profile.google.subtitle'),
                        trailing: usesPasswordAuth
                            ? null
                            : Icon(
                                Icons.verified_user_outlined,
                                color: _ProfileColors.chevron(isDark),
                              ),
                        onTap: usesPasswordAuth
                            ? () => _showChangePasswordSheet(isDark)
                            : null,
                      ),
                      _settingTile(
                        isDark: isDark,
                        icon: Icons.calendar_today_outlined,
                        title: _ProfileStrings.t('profile.email.title'),
                        subtitle: email,
                        onTap: () => _showChangeEmailSheet(isDark),
                      ),
                    ],
                  ),
                  _sectionLabel('profile.section.notifications', isDark),
                  _sectionCard(
                    isDark: isDark,
                    children: [
                      _settingTile(
                        isDark: isDark,
                        icon: Icons.notifications_none_rounded,
                        title: _ProfileStrings.t('profile.notifications.daily'),
                        subtitle: settings.dailyOutfitReminder
                            ? settings.reminderTimeLabel
                            : _ProfileStrings.t('profile.notifications.closed'),
                        trailing: Switch(
                          value: settings.dailyOutfitReminder,
                          activeColor: _ProfileColors.switchThumb(isDark),
                          activeTrackColor: _ProfileColors.accent,
                          inactiveThumbColor: _ProfileColors.inactiveThumb(isDark),
                          inactiveTrackColor: _ProfileColors.inactiveTrack(isDark),
                          onChanged: (value) async {
                            var next = settings.copyWith(
                              dailyOutfitReminder: value,
                            );
                            if (value && mounted) {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay(
                                  hour: settings.reminderHour,
                                  minute: settings.reminderMinute,
                                ),
                              );
                              if (picked != null) {
                                next = next.copyWith(
                                  reminderHour: picked.hour,
                                  reminderMinute: picked.minute,
                                );
                              }
                            }
                            await _notificationController.save(
                              userId: authUser.uid,
                              settings: next,
                            );
                          },
                        ),
                      ),
                      _settingTile(
                        isDark: isDark,
                        icon: Icons.cloud_outlined,
                        title: _ProfileStrings.t('profile.notifications.weather'),
                        subtitle: _ProfileStrings.t(
                          'profile.notifications.weatherSubtitle',
                        ),
                        trailing: Switch(
                          value: settings.weatherAlerts,
                          activeColor: _ProfileColors.switchThumb(isDark),
                          activeTrackColor: _ProfileColors.accent,
                          inactiveThumbColor: _ProfileColors.inactiveThumb(isDark),
                          inactiveTrackColor: _ProfileColors.inactiveTrack(isDark),
                          onChanged: (value) async {
                            await _notificationController.save(
                              userId: authUser.uid,
                              settings: settings.copyWith(weatherAlerts: value),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: () => _showLogoutSheet(isDark),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: _ProfileColors.surface(isDark),
                        foregroundColor: const Color(0xFFFF6A67),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                        side: const BorderSide(
                          color: _ProfileColors.accent,
                          width: 1.2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(_ProfileStrings.t('profile.logout')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/*
Legacy profile body intentionally replaced by the new specification.
*/

class _ProfileColors {
  static const Color accent = Color(0xFFE6B800);

  static Color background(bool isDark) =>
      isDark ? const Color(0xFF161616) : const Color(0xFFF4F0E5);

  static Color surface(bool isDark) =>
      isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);

  static Color header(bool isDark) =>
      isDark ? const Color(0xFF201E00) : const Color(0xFFFFF3BD);

  static Color primaryText(bool isDark) =>
      isDark ? Colors.white : const Color(0xFF171717);

  static Color secondaryText(bool isDark) =>
      isDark ? const Color(0xFF8C8C8C) : const Color(0xFF6D6658);

  static Color rowTitle(bool isDark) =>
      isDark ? const Color(0xFFD8D8D8) : const Color(0xFF242424);

  static Color rowSubtitle(bool isDark) =>
      isDark ? const Color(0xFF666666) : const Color(0xFF7B7468);

  static Color sectionLabel(bool isDark) =>
      isDark ? const Color(0xFF555555) : const Color(0xFF8B8273);

  static Color border(bool isDark) =>
      isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE0D6BE);

  static Color chevron(bool isDark) =>
      isDark ? const Color(0xFF333333) : const Color(0xFFB8AE99);

  static Color accentBorder(bool isDark) =>
      isDark ? const Color(0xFF6F620F) : const Color(0xFFD6B139);

  static Color statBackground(bool isDark) =>
      isDark ? const Color(0xFF282505) : const Color(0xFFFFF7D5);

  static Color statLabel(bool isDark) =>
      isDark ? const Color(0xFF85815F) : const Color(0xFF8B7629);

  static Color iconGoldBackground(bool isDark) =>
      isDark ? const Color(0xFF221F08) : const Color(0xFFFFF4C8);

  static Color switchThumb(bool isDark) =>
      isDark ? const Color(0xFF161616) : Colors.white;

  static Color inactiveThumb(bool isDark) =>
      isDark ? const Color(0xFF777777) : const Color(0xFFAAA394);

  static Color inactiveTrack(bool isDark) =>
      isDark ? const Color(0xFF333333) : const Color(0xFFD8D0BF);

  static Color fieldBackground(bool isDark) =>
      isDark ? const Color(0xFF161616) : const Color(0xFFF8F5EC);

  static Color fieldBorder(bool isDark) =>
      isDark ? const Color(0xFF303030) : const Color(0xFFD8CFBC);
}

class _ProfileStats {
  final int pieceCount;
  final int combinationCount;

  const _ProfileStats({
    required this.pieceCount,
    required this.combinationCount,
  });

  static const empty = _ProfileStats(
    pieceCount: 0,
    combinationCount: 0,
  );
}

class _ProfileStrings {
  static const Map<String, String> _tr = {
    'profile.editPhoto': 'Profil görselini düzenle',
    'profile.stats.pieces': 'Parça',
    'profile.stats.outfits': 'Kombin',
    'profile.section.appearance': 'Görünüm',
    'profile.section.security': 'Hesap & Güvenlik',
    'profile.section.notifications': 'Bildirimler',
    'profile.darkMode.title': 'Koyu Mod',
    'profile.darkMode.darkSubtitle': 'Koyu tema aktif',
    'profile.darkMode.lightSubtitle': 'Açık tema aktif',
    'profile.password.title': 'Şifre Değiştir',
    'profile.password.neverChanged': 'Son değişiklik: kayıt yok',
    'profile.password.changedNow': 'Son değişiklik: az önce',
    'profile.password.changedYesterday': 'Son değişiklik: dün',
    'profile.password.current': 'Mevcut şifre',
    'profile.password.new': 'Yeni şifre',
    'profile.password.repeat': 'Yeni şifre tekrar',
    'profile.password.submit': 'Şifreyi güncelle',
    'profile.password.success': 'Şifre güncellendi.',
    'profile.google.title': 'Google ile giriş yapılıyor',
    'profile.google.subtitle': 'Şifre Google hesabından yönetilir',
    'profile.email.title': 'E-posta Güncelle',
    'profile.email.new': 'Yeni e-posta adresi',
    'profile.email.submit': 'Doğrulama e-postası gönder',
    'profile.email.success': 'Doğrulama e-postası gönderildi.',
    'profile.notifications.daily': 'Günlük Kombin Hatırlatması',
    'profile.notifications.closed': 'Kapalı',
    'profile.notifications.weather': 'Hava Durumu Uyarıları',
    'profile.notifications.weatherSubtitle': 'Yağmur ve soğuk için',
    'profile.logout': 'Çıkış Yap',
    'profile.error.passwordRule': 'Şifre en az 8 karakter ve 1 rakam içermeli.',
    'profile.error.passwordMismatch': 'Yeni şifreler eşleşmiyor.',
    'profile.error.email': 'Geçerli bir e-posta adresi gir.',
    'profile.error.request': 'İşlem tamamlanamadı. Lütfen tekrar dene.',
  };

  static String t(String key) => _tr[key] ?? key;
}

class UserNotificationSettings {
  final bool dailyOutfitReminder;
  final int reminderHour;
  final int reminderMinute;
  final bool weatherAlerts;

  const UserNotificationSettings({
    this.dailyOutfitReminder = true,
    this.reminderHour = 8,
    this.reminderMinute = 0,
    this.weatherAlerts = true,
  });

  factory UserNotificationSettings.fromMap(Object? value) {
    if (value is! Map) return const UserNotificationSettings();
    return UserNotificationSettings(
      dailyOutfitReminder: value['dailyOutfitReminder'] != false,
      reminderHour: _intValue(value['reminderHour'], 8),
      reminderMinute: _intValue(value['reminderMinute'], 0),
      weatherAlerts: value['weatherAlerts'] != false,
    );
  }

  UserNotificationSettings copyWith({
    bool? dailyOutfitReminder,
    int? reminderHour,
    int? reminderMinute,
    bool? weatherAlerts,
  }) {
    return UserNotificationSettings(
      dailyOutfitReminder: dailyOutfitReminder ?? this.dailyOutfitReminder,
      reminderHour: reminderHour ?? this.reminderHour,
      reminderMinute: reminderMinute ?? this.reminderMinute,
      weatherAlerts: weatherAlerts ?? this.weatherAlerts,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'dailyOutfitReminder': dailyOutfitReminder,
      'reminderHour': reminderHour,
      'reminderMinute': reminderMinute,
      'weatherAlerts': weatherAlerts,
    };
  }

  String get reminderTimeLabel {
    final hour = reminderHour.toString().padLeft(2, '0');
    final minute = reminderMinute.toString().padLeft(2, '0');
    return '$hour:$minute’de bildirim';
  }

  static int _intValue(Object? value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }
}

class UserNotificationSettingsController {
  Future<void> save({
    required String userId,
    required UserNotificationSettings settings,
  }) async {
    var settingsToSave = settings;
    if (settings.dailyOutfitReminder) {
      final scheduled = await NotificationService.instance.scheduleDailyOutfitReminder(
        hour: settings.reminderHour,
        minute: settings.reminderMinute,
      );
      if (!scheduled) {
        settingsToSave = settings.copyWith(dailyOutfitReminder: false);
      }
    } else {
      await NotificationService.instance.cancelDailyOutfitReminder();
    }

    await FirebaseFirestore.instance.collection('users').doc(userId).set({
      'notification_settings': settingsToSave.toMap(),
    }, SetOptions(merge: true));
  }
}

class ChangePasswordController {
  Future<void> submit({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email;
    if (user == null || email == null || email.isEmpty) {
      throw const ProfileApiException();
    }

    final credential = EmailAuthProvider.credential(
      email: email,
      password: currentPassword,
    );

    await user.reauthenticateWithCredential(credential);
    await user.updatePassword(newPassword);
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'last_password_changed_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

class ChangeEmailController {
  Future<void> sendVerification(String email) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const ProfileApiException();
    }

    await user.verifyBeforeUpdateEmail(email);
  }
}

class ProfileApiException implements Exception {
  const ProfileApiException();
}

class _ChangePasswordSheet extends StatefulWidget {
  final bool isDark;
  final VoidCallback onSuccess;

  const _ChangePasswordSheet({
    required this.isDark,
    required this.onSuccess,
  });

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _controller = ChangePasswordController();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _repeat = TextEditingController();
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _repeat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ProfileFormSheet(
      isDark: widget.isDark,
      title: _ProfileStrings.t('profile.password.title'),
      isSubmitting: _isSubmitting,
      error: _error,
      submitLabel: _ProfileStrings.t('profile.password.submit'),
      onSubmit: _submit,
      children: [
        _ProfileTextField(
          isDark: widget.isDark,
          controller: _current,
          label: _ProfileStrings.t('profile.password.current'),
          obscureText: true,
        ),
        _ProfileTextField(
          isDark: widget.isDark,
          controller: _next,
          label: _ProfileStrings.t('profile.password.new'),
          obscureText: true,
        ),
        _ProfileTextField(
          isDark: widget.isDark,
          controller: _repeat,
          label: _ProfileStrings.t('profile.password.repeat'),
          obscureText: true,
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final next = _next.text.trim();
    if (next.length < 8 || !RegExp(r'\d').hasMatch(next)) {
      setState(() => _error = _ProfileStrings.t('profile.error.passwordRule'));
      return;
    }
    if (next != _repeat.text.trim()) {
      setState(() => _error = _ProfileStrings.t('profile.error.passwordMismatch'));
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await _controller.submit(
        currentPassword: _current.text,
        newPassword: next,
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSuccess();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = _ProfileStrings.t('profile.error.request'));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}

class _ChangeEmailSheet extends StatefulWidget {
  final bool isDark;
  final VoidCallback onSuccess;

  const _ChangeEmailSheet({
    required this.isDark,
    required this.onSuccess,
  });

  @override
  State<_ChangeEmailSheet> createState() => _ChangeEmailSheetState();
}

class _ChangeEmailSheetState extends State<_ChangeEmailSheet> {
  final _controller = ChangeEmailController();
  final _email = TextEditingController();
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ProfileFormSheet(
      isDark: widget.isDark,
      title: _ProfileStrings.t('profile.email.title'),
      isSubmitting: _isSubmitting,
      error: _error,
      submitLabel: _ProfileStrings.t('profile.email.submit'),
      onSubmit: _submit,
      children: [
        _ProfileTextField(
          isDark: widget.isDark,
          controller: _email,
          label: _ProfileStrings.t('profile.email.new'),
          keyboardType: TextInputType.emailAddress,
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = _ProfileStrings.t('profile.error.email'));
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await _controller.sendVerification(email);
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSuccess();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = _ProfileStrings.t('profile.error.request'));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}

class _ProfileFormSheet extends StatelessWidget {
  final bool isDark;
  final String title;
  final List<Widget> children;
  final String? error;
  final bool isSubmitting;
  final String submitLabel;
  final VoidCallback onSubmit;

  const _ProfileFormSheet({
    required this.isDark,
    required this.title,
    required this.children,
    required this.error,
    required this.isSubmitting,
    required this.submitLabel,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
        decoration: BoxDecoration(
          color: _ProfileColors.surface(isDark),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
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
                    color: _ProfileColors.sectionLabel(isDark),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: TextStyle(
                  color: _ProfileColors.primaryText(isDark),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              ...children,
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error!,
                  style: const TextStyle(
                    color: Color(0xFFE24B4A),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: isSubmitting ? null : onSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _ProfileColors.accent,
                    foregroundColor: const Color(0xFF161616),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(submitLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileTextField extends StatelessWidget {
  final bool isDark;
  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final TextInputType? keyboardType;

  const _ProfileTextField({
    required this.isDark,
    required this.controller,
    required this.label,
    this.obscureText = false,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        style: TextStyle(color: _ProfileColors.primaryText(isDark)),
        decoration: InputDecoration(
          counterText: '',
          labelText: label,
          labelStyle: TextStyle(color: _ProfileColors.secondaryText(isDark)),
          filled: true,
          fillColor: _ProfileColors.fieldBackground(isDark),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _ProfileColors.fieldBorder(isDark)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _ProfileColors.accent),
          ),
        ),
      ),
    );
  }
}
/*
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.screenPadding,
                  20,
                  AppTheme.screenPadding,
                  120,
                ),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 24,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                        gradient: isDark
                            ? const LinearGradient(
                                colors: [Color(0xFF0D1117), Color(0xFF1A0D2E)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : const LinearGradient(
                                colors: [Color(0xFFFDF8F0), Color(0xFFFAE8E8)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                      ),
                      child: Column(
                        children: [
                          GestureDetector(
                            onTap: _isUploadingPhoto
                                ? null
                                : () => _showProfileOptions(
                                      isDark: isDark,
                                      hasProfileVisual: hasProfileVisual,
                                    ),
                            child: _buildProfileAvatar(
                              profileImageUrl: profileImageUrl.isEmpty
                                  ? null
                                  : profileImageUrl,
                              selectedAvatarAsset: selectedAvatarAsset.isEmpty
                                  ? null
                                  : selectedAvatarAsset,
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            name,
                            style: AppTheme.heading2(isDark).copyWith(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Colors.white
                                  : AppTheme.textPrimaryLight,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            email,
                            style: AppTheme.body(isDark).copyWith(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              height: 1.25,
                              color: isDark
                                  ? Colors.white.withOpacity(0.86)
                                  : AppTheme.textSecondaryLight,
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            height: 36,
                            child: OutlinedButton.icon(
                              onPressed: _isUploadingPhoto
                                  ? null
                                  : () => _showProfileOptions(
                                        isDark: isDark,
                                        hasProfileVisual: hasProfileVisual,
                                      ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: isDark
                                    ? Colors.white
                                    : AppTheme.textPrimaryLight,
                                textStyle: AppTheme.body(isDark).copyWith(
                                  fontSize: 12.8,
                                  fontWeight: FontWeight.w600,
                                  height: 1,
                                ),
                                side: BorderSide(
                                  color: AppTheme.gold(isDark).withOpacity(
                                    isDark ? 0.72 : 0.6,
                                  ),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppTheme.radiusPill,
                                  ),
                                ),
                              ),
                              icon: const Icon(Icons.camera_alt_outlined, size: 18),
                              label: const Text("Profil Görselini Düzenle"),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _summaryCard(
                      isDark: isDark,
                      email: email,
                      hasProfileVisual: hasProfileVisual,
                    ),
                    const SizedBox(height: 18),
                    Container(
                      decoration: AppTheme.panelDecoration(isDark),
                      child: Column(
                        children: [
                          _settingTile(
                            isDark: isDark,
                            icon: Icons.dark_mode_outlined,
                            title: "Koyu Mod",
                            trailing: Switch(
                              value: isDark,
                              onChanged: (value) {
                                themeNotifier.value = value
                                    ? ThemeMode.dark
                                    : ThemeMode.light;
                              },
                            ),
                          ),
                          _settingTile(
                            isDark: isDark,
                            icon: Icons.person_outline_rounded,
                            title: "Profil Bilgilerim",
                          ),
                          _settingTile(
                            isDark: isDark,
                            icon: Icons.favorite_border_rounded,
                            title: "Favori Kombinlerim",
                          ),
                          _settingTile(
                            isDark: isDark,
                            icon: Icons.history_rounded,
                            title: "Gardırop Geçmişi",
                          ),
                          _settingTile(
                            isDark: isDark,
                            icon: Icons.settings_outlined,
                            title: "Ayarlar",
                            trailing: const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusButton,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.gold(isDark).withOpacity(
                                isDark ? 0.2 : 0.14,
                              ),
                              blurRadius: 18,
                              spreadRadius: 0.6,
                            ),
                          ],
                        ),
                        child: OutlinedButton(
                          onPressed: () => _showLogoutSheet(isDark),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: AppTheme.layer2(isDark),
                            foregroundColor: const Color(0xFFFF6A67),
                            textStyle: AppTheme.body(isDark).copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                            side: BorderSide(
                              color: AppTheme.gold(isDark).withOpacity(
                                isDark ? 0.96 : 0.82,
                              ),
                              width: 1.3,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusButton,
                              ),
                            ),
                          ),
                          child: const Text("Çıkış Yap"),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
*/
