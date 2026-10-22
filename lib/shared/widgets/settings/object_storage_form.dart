// 职责: 对象存储连接表单 — 编辑 S3 兼容配置，测试连接通过后保存；桌面设置页与生成前的配置弹窗共用。
// 关联文件:
//   lib/shared/models/object_storage_config.dart
//   lib/shared/services/object_storage/service.dart
//   lib/shared/providers/object_storage.dart
//   lib/shared/widgets/settings/object_storage_settings_section.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
// 遵循的 Rules:
//   .agents/rules/form.md
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../components/reveric_button.dart';
import '../../components/reveric_select.dart';
import '../../components/reveric_switch.dart';
import '../../form/form.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../models/object_storage_config.dart';
import '../../providers/object_storage.dart';
import '../../services/object_storage/service.dart';
import '../../theme/theme.dart';

enum ObjectStorageField implements FieldSchema {
  provider,
  endpoint,
  region,
  bucket,
  accessKeyId,
  secretAccessKey,
  keyPrefix,
  pathStyle,
  publicBaseUrl;

  @override
  List<Validator<dynamic>>? get validators => null;
}

class ObjectStorageForm extends HookConsumerWidget {
  const ObjectStorageForm({super.key, required this.config, this.onSaved});

  final ObjectStorageConfig config;

  /// 测试通过并保存后调用。
  final VoidCallback? onSaved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final saving = useState(false);
    final feedback = useState<(String, bool)?>(null);
    final obscureSecret = useState(true);
    final form = useForm<ObjectStorageField>(
      initialValues: <ObjectStorageField, dynamic>{
        ObjectStorageField.provider: config.provider,
        ObjectStorageField.endpoint: config.endpoint,
        ObjectStorageField.region: config.region,
        ObjectStorageField.bucket: config.bucket,
        ObjectStorageField.accessKeyId: config.accessKeyId,
        ObjectStorageField.secretAccessKey: config.secretAccessKey,
        ObjectStorageField.keyPrefix: config.keyPrefix,
        ObjectStorageField.pathStyle: config.pathStyle,
        ObjectStorageField.publicBaseUrl: config.publicBaseUrl,
      },
      keys: <Object?>[config.encode()],
    );

    String text(ObjectStorageField field) =>
        form.getValue<String>(field)?.trim() ?? '';

    Future<void> save() async {
      if (saving.value) {
        return;
      }
      feedback.value = null;
      form.clearForcedErrors();
      final next = ObjectStorageConfig(
        provider:
            form.getValue<ObjectStorageProvider>(ObjectStorageField.provider) ??
            ObjectStorageProvider.s3,
        endpoint: text(ObjectStorageField.endpoint),
        region: text(ObjectStorageField.region),
        bucket: text(ObjectStorageField.bucket),
        accessKeyId: text(ObjectStorageField.accessKeyId),
        secretAccessKey: text(ObjectStorageField.secretAccessKey),
        keyPrefix: text(ObjectStorageField.keyPrefix),
        pathStyle: form.getValue<bool>(ObjectStorageField.pathStyle) ?? false,
        publicBaseUrl: text(ObjectStorageField.publicBaseUrl),
      ).normalized();
      final issue = next.validate();
      if (issue != null) {
        final (field, key) = switch (issue) {
          ObjectStorageConfigIssue.invalid_endpoint => (
            ObjectStorageField.endpoint,
            LocaleKeys.settingsObjectStorageInvalidUrl,
          ),
          ObjectStorageConfigIssue.missing_region => (
            ObjectStorageField.region,
            LocaleKeys.commonRequired,
          ),
          ObjectStorageConfigIssue.missing_bucket => (
            ObjectStorageField.bucket,
            LocaleKeys.commonRequired,
          ),
          ObjectStorageConfigIssue.missing_access_key_id => (
            ObjectStorageField.accessKeyId,
            LocaleKeys.commonRequired,
          ),
          ObjectStorageConfigIssue.missing_secret_access_key => (
            ObjectStorageField.secretAccessKey,
            LocaleKeys.commonRequired,
          ),
          ObjectStorageConfigIssue.invalid_key_prefix => (
            ObjectStorageField.keyPrefix,
            LocaleKeys.settingsObjectStorageInvalidKeyPrefix,
          ),
          ObjectStorageConfigIssue.invalid_public_base_url => (
            ObjectStorageField.publicBaseUrl,
            LocaleKeys.settingsObjectStorageInvalidUrl,
          ),
        };
        form.setError(field, context.t(key));
        return;
      }
      saving.value = true;
      final service = ref.read(objectStorageServiceProvider);
      try {
        final failure = await service.test(next);
        if (!context.mounted) {
          return;
        }
        if (failure != null) {
          feedback.value = (context.t(_failureKey(failure)), true);
          return;
        }
        await service.save(next);
        if (!context.mounted) {
          return;
        }
        feedback.value = (
          context.t(LocaleKeys.settingsObjectStorageSaved),
          false,
        );
        onSaved?.call();
      } catch (_) {
        if (context.mounted) {
          feedback.value = (
            context.t(LocaleKeys.settingsObjectStorageSaveFailed),
            true,
          );
        }
      } finally {
        if (context.mounted) {
          saving.value = false;
        }
      }
    }

    Widget field(
      ObjectStorageField field,
      String labelKey, {
      String? hintKey,
      String? helperKey,
      bool url = false,
      bool secret = false,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: RevericSpacing.md),
      child: HookedTextFormField<ObjectStorageField>(
        key: ValueKey('object_storage_${field.name}_field'),
        fieldHook: field,
        enabled: !saving.value,
        keyboardType: url ? TextInputType.url : null,
        autocorrect: false,
        enableSuggestions: false,
        obscureText: secret && obscureSecret.value,
        label: context.t(labelKey),
        hintText: hintKey == null ? null : context.t(hintKey),
        helperText: helperKey == null ? null : context.t(helperKey),
        suffixIcon: secret
            ? IconButton(
                onPressed: () => obscureSecret.value = !obscureSecret.value,
                icon: RevericIcon(
                  obscureSecret.value
                      ? RevericIcons.visibility
                      : RevericIcons.visibility_off,
                  size: 18,
                ),
              )
            : null,
      ),
    );

    return HookedForm<ObjectStorageField>(
      form: form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: RevericSpacing.md),
            child: HookedFormField<ObjectStorageField, ObjectStorageProvider>(
              fieldHook: ObjectStorageField.provider,
              builder: (value, onChanged, _) => RevericSelect(
                value: value,
                label: context.t(LocaleKeys.settingsObjectStorageProvider),
                enabled: !saving.value,
                items: [
                  RevericSelectItem(
                    value: ObjectStorageProvider.s3,
                    label: context.t(
                      LocaleKeys.settingsObjectStorageProviderS3,
                    ),
                    subtitle: context.t(
                      LocaleKeys.settingsObjectStorageProviderS3Hint,
                    ),
                  ),
                ],
                onChanged: (v) => onChanged?.call(v),
              ),
            ),
          ),
          field(
            ObjectStorageField.endpoint,
            LocaleKeys.settingsObjectStorageEndpoint,
            hintKey: LocaleKeys.settingsObjectStorageEndpointHint,
            url: true,
          ),
          field(
            ObjectStorageField.region,
            LocaleKeys.settingsObjectStorageRegion,
            helperKey: LocaleKeys.settingsObjectStorageRegionHint,
          ),
          field(
            ObjectStorageField.bucket,
            LocaleKeys.settingsObjectStorageBucket,
          ),
          field(
            ObjectStorageField.accessKeyId,
            LocaleKeys.settingsObjectStorageAccessKeyId,
          ),
          field(
            ObjectStorageField.secretAccessKey,
            LocaleKeys.settingsObjectStorageSecretAccessKey,
            secret: true,
          ),
          field(
            ObjectStorageField.keyPrefix,
            LocaleKeys.settingsObjectStorageKeyPrefix,
          ),
          field(
            ObjectStorageField.publicBaseUrl,
            LocaleKeys.settingsObjectStoragePublicBaseUrl,
            helperKey: LocaleKeys.settingsObjectStoragePublicBaseUrlHint,
            url: true,
          ),
          HookedFormField<ObjectStorageField, bool>(
            fieldHook: ObjectStorageField.pathStyle,
            builder: (value, onChanged, _) => Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.t(LocaleKeys.settingsObjectStoragePathStyle),
                        style: typo.uiSemibold.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: RevericSpacing.xxs),
                      Text(
                        context.t(
                          LocaleKeys.settingsObjectStoragePathStyleHint,
                        ),
                        style: typo.uiSmall.copyWith(color: colors.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: RevericSpacing.lg),
                RevericSwitch(
                  value: value ?? false,
                  onChanged: saving.value ? null : (v) => onChanged?.call(v),
                ),
              ],
            ),
          ),
          const SizedBox(height: RevericSpacing.lg),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: RevericButton.primary(
              key: const ValueKey('object_storage_save_button'),
              label: context.t(
                saving.value
                    ? LocaleKeys.settingsObjectStorageTesting
                    : LocaleKeys.settingsObjectStorageSaveAndTest,
              ),
              icon: RevericIcons.cloud_upload,
              loading: saving.value,
              onPressed: save,
            ),
          ),
          if (feedback.value case (final message, final isError)) ...[
            const SizedBox(height: RevericSpacing.md),
            _Feedback(message: message, isError: isError),
          ],
        ],
      ),
    );
  }
}

String _failureKey(ObjectStorageFailure failure) => switch (failure) {
  ObjectStorageFailure.connection_failed =>
    LocaleKeys.settingsObjectStorageConnectionFailed,
  ObjectStorageFailure.unauthorized =>
    LocaleKeys.settingsObjectStorageUnauthorized,
  ObjectStorageFailure.bucket_not_found =>
    LocaleKeys.settingsObjectStorageBucketNotFound,
  ObjectStorageFailure.upload_failed =>
    LocaleKeys.settingsObjectStorageUploadFailed,
  ObjectStorageFailure.read_failed =>
    LocaleKeys.settingsObjectStorageReadFailed,
  ObjectStorageFailure.invalid_configuration =>
    LocaleKeys.settingsObjectStorageSaveFailed,
};

class _Feedback extends StatelessWidget {
  const _Feedback({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final color = isError ? colors.deletionBorder : colors.additionBorder;
    return Container(
      padding: const EdgeInsets.all(RevericSpacing.md),
      decoration: BoxDecoration(
        color: isError ? colors.deletionBg : colors.additionBg,
        borderRadius: BorderRadius.circular(RevericRadius.medium),
      ),
      child: Row(
        children: [
          RevericIcon(
            isError ? RevericIcons.error_outline : RevericIcons.check_circle,
            size: 18,
            color: color,
          ),
          const SizedBox(width: RevericSpacing.sm),
          Expanded(
            child: Text(message, style: typo.uiSmall.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}
