import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/app_scope.dart';
import '../../design/app_theme.dart';
import '../../design/app_widgets.dart';
import '../../domain/models.dart';
import '../../domain/security_policy.dart';

class CapturePage extends StatefulWidget {
  const CapturePage({super.key});

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  final ImagePicker _imagePicker = ImagePicker();
  bool _importing = false;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return AppPage(
      title: '学习材料采集',
      subtitle: '卷子、书页和资料先安全存入本机，等待 OCR 与 AI 整理',
      actions: [if (_importing) const CupertinoActivityIndicator()],
      child: Column(
        children: [
          _CaptureHero(
            enabled: !_importing,
            onCamera: Platform.isAndroid
                ? () => _pickImage(ImageSource.camera)
                : null,
            onGallery: () => _pickImage(ImageSource.gallery),
            onFile: _pickFile,
          ),
          const SizedBox(height: 20),
          const _PrivacyNotice(),
          const SizedBox(height: 20),
          _CaptureHistory(captures: controller.captures),
        ],
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    setState(() => _importing = true);
    try {
      final image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 92,
        maxWidth: 3000,
      );
      if (image == null || !mounted) return;
      final stored = await _copyIntoLibrary(image.path);
      if (!mounted) return;
      await AppScope.of(context).addCapture(
        fileName: p.basename(image.path),
        filePath: stored,
        kind: source == ImageSource.camera ? '相机扫描' : '相册图片',
      );
    } catch (error) {
      if (mounted) {
        await showAppMessage(
          context,
          title: '无法导入图片',
          message: '$error',
          tone: AppMessageTone.warning,
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _pickFile() async {
    setState(() => _importing = true);
    try {
      final selected = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'txt', 'png', 'jpg', 'jpeg'],
      );
      if (selected?.path == null || !mounted) return;
      final stored = await _copyIntoLibrary(selected!.path!);
      if (!mounted) return;
      await AppScope.of(
        context,
      ).addCapture(fileName: selected.name, filePath: stored, kind: '本地文件');
    } catch (error) {
      if (mounted) {
        await showAppMessage(
          context,
          title: '无法导入文件',
          message: '$error',
          tone: AppMessageTone.warning,
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<String> _copyIntoLibrary(String sourcePath) async {
    final source = File(sourcePath);
    final sourceBytes = await source.length();
    if (sourceBytes > SecurityPolicy.maxImportBytes) {
      throw const FormatException('单个学习资料不能超过 25 MB。');
    }
    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'captures'));
    if (!directory.existsSync()) await directory.create(recursive: true);
    final extension = p.extension(sourcePath);
    final base = p
        .basenameWithoutExtension(sourcePath)
        .replaceAll(RegExp(r'[^a-zA-Z0-9_\-\u4e00-\u9fff]'), '_');
    final target = p.join(
      directory.path,
      '${DateTime.now().microsecondsSinceEpoch}_$base$extension',
    );
    return (await source.copy(target)).path;
  }
}

class _CaptureHero extends StatelessWidget {
  const _CaptureHero({
    required this.enabled,
    required this.onCamera,
    required this.onGallery,
    required this.onFile,
  });

  final bool enabled;
  final VoidCallback? onCamera;
  final VoidCallback onGallery;
  final VoidCallback onFile;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(26),
      child: Column(
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              color: AppPalette.resolve(context, AppPalette.blueSoft),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              CupertinoIcons.viewfinder,
              size: 34,
              color: AppPalette.resolve(context, AppPalette.blue),
            ),
          ),
          const SizedBox(height: 17),
          const Text(
            '把纸面内容变成可复习的知识',
            style: AppTextStyles.title,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '当前首版完成本地采集与资料库。文字识别、错题切分和 AI 总结将在接入模型后启用。',
            style: AppTextStyles.body.copyWith(
              color: AppPalette.resolve(context, AppPalette.secondaryText),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 22),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              if (onCamera != null)
                AppPrimaryButton(
                  label: '拍照扫描',
                  icon: CupertinoIcons.camera_fill,
                  onPressed: enabled ? onCamera : null,
                ),
              AppPrimaryButton(
                label: '选择图片',
                icon: CupertinoIcons.photo_fill,
                filled: false,
                onPressed: enabled ? onGallery : null,
              ),
              AppPrimaryButton(
                label: '选择文件',
                icon: CupertinoIcons.folder_fill,
                filled: false,
                onPressed: enabled ? onFile : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppPalette.greenSoft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            CupertinoIcons.lock_shield_fill,
            color: AppPalette.resolve(context, AppPalette.green),
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Local First：导入的原文件会复制到应用的本地资料库。首版不会自动上传到任何云端或第三方服务。',
              style: AppTextStyles.body,
            ),
          ),
        ],
      ),
    );
  }
}

class _CaptureHistory extends StatelessWidget {
  const _CaptureHistory({required this.captures});

  final List<CapturedDocument> captures;

  @override
  Widget build(BuildContext context) {
    if (captures.isEmpty) {
      return AppCard(
        child: Column(
          children: [
            Icon(
              CupertinoIcons.tray,
              size: 32,
              color: AppPalette.resolve(context, AppPalette.secondaryText),
            ),
            const SizedBox(height: 10),
            const Text('资料库还是空的', style: AppTextStyles.sectionTitle),
            const SizedBox(height: 4),
            Text(
              '导入第一份卷子或书页后，会显示在这里。',
              style: AppTextStyles.body.copyWith(
                color: AppPalette.resolve(context, AppPalette.secondaryText),
              ),
            ),
          ],
        ),
      );
    }

    return AppGroup(
      title: '最近采集',
      children: [
        for (final capture in captures)
          AppGroupRow(
            icon: _iconFor(capture.fileName),
            title: capture.fileName,
            subtitle: '${capture.kind} · ${capture.status}',
            tint: AppPalette.purple,
            tintBackground: AppPalette.softSurface,
            trailing: Text(
              '${capture.createdAt.month}/${capture.createdAt.day}',
              style: AppTextStyles.caption.copyWith(
                color: AppPalette.resolve(context, AppPalette.secondaryText),
              ),
            ),
          ),
      ],
    );
  }

  IconData _iconFor(String fileName) {
    final extension = p.extension(fileName).toLowerCase();
    if (extension == '.jpg' || extension == '.jpeg' || extension == '.png') {
      return CupertinoIcons.photo_fill;
    }
    if (extension == '.pdf') return CupertinoIcons.doc_richtext;
    return CupertinoIcons.doc_fill;
  }
}
