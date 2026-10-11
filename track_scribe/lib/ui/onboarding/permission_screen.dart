import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/app_database_provider.dart';
import 'package:track_scribe/state/permission_providers.dart';
import 'package:track_scribe/theme/palette.dart';

/// Spec §7 "لا Permission": an instructions screen shown instead of a silently
/// disabled start button. R85's four rows, in order — rows 1+2 are VERIFIED from
/// the injected probes and gate the continue button; rows 3+4 are ADVISORY (no
/// such API exists in geolocator 14.1.1) and always label themselves
/// unverifiable, so the app never pretends to know.
///
/// The probes are injectable providers, so this is fully testable with `flutter
/// test` and never touches a platform channel; production leaves them on the real
/// `Geolocator` statics.
class PermissionScreen extends ConsumerWidget {
  const PermissionScreen({super.key});

  static const _granted = 'تم';
  static const _off = 'غير مُفعّل';
  static const _unverifiable = 'لا يمكن التحقق';
  static const _realmePath =
      'الإعدادات → إدارة التطبيقات → track_scribe → السماح بالتشغيل التلقائي';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permission = ref.watch(locationPermissionProvider).value;
    final serviceOn = ref.watch(locationServiceProvider).value ?? false;
    final actions = ref.watch(permissionActionsProvider);

    final granted =
        permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
    final deniedForever = permission == LocationPermission.deniedForever;
    final canContinue = granted && serviceOn;

    // A granted request re-reads the state so the row flips to `تم` without a
    // hot restart (the screen invalidates the probe after the dialog returns).
    Future<void> requestAndReread() async {
      await actions.request();
      ref.invalidate(locationPermissionProvider);
    }

    Future<void> completeOnboarding() async {
      await ref.read(activityRepositoryProvider).setFlag(kOnboardedFlag, true);
      ref.invalidate(onboardedProvider);
    }

    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(
        backgroundColor: Palette.bg,
        foregroundColor: Palette.text,
        elevation: 0,
        title: Text('الإعدادات المطلوبة', style: theme.textTheme.titleLarge),
      ),
      body: SafeArea(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'لكي يتمكّن التطبيق من تسجيل مسارك، فعّل هذه الإعدادات.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Palette.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                _row(
                  context: context,
                  title: 'إذن الموقع أثناء الاستخدام',
                  stateWord: granted ? _granted : _off,
                  stateColor: granted ? Palette.accent : Palette.textSecondary,
                  subtitle: 'يسمح للتطبيق بقراءة موقعك أثناء استخدامه.',
                  actionLabel: deniedForever ? 'فتح إعدادات التطبيق' : 'طلب الإذن',
                  actionKey: 'perm-action-1',
                  // deniedForever: the system will not raise the dialog again,
                  // so the only honest action is the app-info page.
                  onAction: deniedForever
                      ? actions.openAppSettings
                      : requestAndReread,
                ),
                _row(
                  context: context,
                  title: 'خدمة تحديد الموقع مفعّلة',
                  stateWord: serviceOn ? _granted : _off,
                  stateColor: serviceOn ? Palette.accent : Palette.textSecondary,
                  subtitle: 'موقع الجهاز (GPS) يجب أن يكون مُشغَّلًا.',
                  actionLabel: 'فتح إعدادات الموقع',
                  actionKey: 'perm-action-2',
                  onAction: actions.openLocationSettings,
                ),
                _row(
                  context: context,
                  title: 'البطارية: بلا قيود',
                  stateWord: _unverifiable,
                  stateColor: Palette.textSecondary,
                  subtitle:
                      'لا يستطيع التطبيق التحقق من هذا الإعداد — اضبطه يدويًا من '
                      'إعدادات التطبيق لتفادي إيقاف التسجيل.',
                  actionLabel: 'فتح إعدادات التطبيق',
                  actionKey: 'perm-action-3',
                  onAction: actions.openAppSettings,
                ),
                _row(
                  context: context,
                  title: 'التشغيل التلقائي في realme',
                  stateWord: _unverifiable,
                  stateColor: Palette.textSecondary,
                  subtitle: _realmePath,
                  actionLabel: 'فتح إعدادات التطبيق',
                  actionKey: 'perm-action-4',
                  onAction: actions.openAppSettings,
                ),
                const SizedBox(height: 4),
                if (!canContinue)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'أكمِل الصفّين الأوّلين للمتابعة',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Palette.textSecondary,
                      ),
                    ),
                  ),
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    key: const ValueKey('perm-continue'),
                    onPressed: canContinue ? completeOnboarding : null,
                    child: const Text('الدخول إلى التسجيل'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row({
    required BuildContext context,
    required String title,
    required String stateWord,
    required Color stateColor,
    required String subtitle,
    required String actionLabel,
    required String actionKey,
    required Future<void> Function() onAction,
  }) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Palette.text,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                stateWord,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: stateColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Flexible + softWrap so the long Arabic advisory strings reflow
          // instead of overflowing at 360 dp (the R58 lesson).
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Palette.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              key: ValueKey(actionKey),
              style: ElevatedButton.styleFrom(
                backgroundColor: Palette.surface,
                foregroundColor: Palette.text,
                side: const BorderSide(color: Palette.textSecondary),
                padding: EdgeInsets.zero,
              ),
              onPressed: () => onAction(),
              child: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}
