import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_loading_indicator.dart';
import 'models.dart';

String currentPlatformName() {
  if (kIsWeb) return 'web';
  if (Platform.isAndroid) return 'android';
  if (Platform.isWindows) return 'windows';
  return defaultTargetPlatform.name;
}

class DeviceUpdateGate extends StatefulWidget {
  final User user;
  final Widget child;
  const DeviceUpdateGate({super.key, required this.user, required this.child});

  @override
  State<DeviceUpdateGate> createState() => _DeviceUpdateGateState();
}

class _DeviceUpdateGateState extends State<DeviceUpdateGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    await DeviceUpdateService.registerDevice(widget.user);
    if (mounted)
      await DeviceUpdateService.checkForUpdate(context, automatic: true);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class DeviceUpdateService {
  static Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('installation_id');
    if (id == null) {
      id = '${DateTime.now().microsecondsSinceEpoch}_${Object().hashCode}';
      await prefs.setString('installation_id', id);
    }
    return id;
  }

  static Future<void> registerDevice(User user) async {
    final info = await PackageInfo.fromPlatform();
    final id = await _deviceId();
    await FirebaseFirestore.instance
        .collection('device_installations')
        .doc(id)
        .set({
          'installationId': id,
          'platform': currentPlatformName(),
          'appVersion': info.version,
          'buildNumber': info.buildNumber,
          'userId': user.id,
          'businessId': user.businessId,
          'lastSeenAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  static List<int> _parts(String value) => value
      .split('.')
      .map((part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList();

  static bool _newer(String remote, String local) {
    final a = _parts(remote), b = _parts(local);
    for (var i = 0; i < 4; i++) {
      final av = i < a.length ? a[i] : 0, bv = i < b.length ? b[i] : 0;
      if (av != bv) return av > bv;
    }
    return false;
  }

  static Future<void> checkForUpdate(
    BuildContext context, {
    bool automatic = false,
  }) async {
    final platform = currentPlatformName();
    if (platform == 'web') return;
    final doc = await FirebaseFirestore.instance
        .collection('app_updates')
        .doc(platform)
        .get();
    final data = doc.data();
    if (data == null || !context.mounted) return;
    final info = await PackageInfo.fromPlatform();
    final version = data['version']?.toString() ?? '';
    if (!_newer(version, info.version)) return;
    final prefs = await SharedPreferences.getInstance();
    if (automatic && prefs.getString('dismissed_update_$platform') == version)
      return;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: Text('Update $version available'),
        content: Text(
          '${data['releaseNotes'] ?? 'A new release is ready.'}\n\nThe file downloads in the background. Windows will launch the installer; Android will ask you to approve APK installation.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await prefs.setString('dismissed_update_$platform', version);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Later'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              downloadAndInstall(context, data);
            },
            icon: const Icon(Icons.download),
            label: const Text('Download update'),
          ),
        ],
      ),
    );
  }

  static Future<void> downloadAndInstall(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final url = data['downloadUrl']?.toString();
    if (url == null) return;
    if (kIsWeb) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }
    final progress = ValueNotifier<double?>(null);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DownloadDialog(progress: progress),
    );
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await http.Client().send(request);
      if (response.statusCode != 200)
        throw Exception('Download failed (${response.statusCode}).');
      final directory = await getApplicationSupportDirectory();
      final name =
          data['fileName']?.toString() ??
          (Platform.isAndroid ? 'pos-update.apk' : 'pos-update.exe');
      final file = File('${directory.path}${Platform.pathSeparator}$name');
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        progress.value = response.contentLength == null
            ? null
            : received / response.contentLength!;
      }
      await sink.close();
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      await OpenFilex.open(file.path);
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    } finally {
      progress.dispose();
    }
  }
}

class _DownloadDialog extends StatelessWidget {
  final ValueNotifier<double?> progress;
  const _DownloadDialog({required this.progress});
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Downloading update'),
    content: ValueListenableBuilder<double?>(
      valueListenable: progress,
      builder: (_, value, __) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: value,
            minHeight: 8,
            borderRadius: BorderRadius.circular(8),
          ),
          const SizedBox(height: 12),
          Text(value == null ? 'Downloading…' : '${(value * 100).round()}%'),
        ],
      ),
    ),
  );
}

class UpdateManagementPage extends StatefulWidget {
  final User systemOwner;
  const UpdateManagementPage({super.key, required this.systemOwner});
  @override
  State<UpdateManagementPage> createState() => _UpdateManagementPageState();
}

class _UpdateManagementPageState extends State<UpdateManagementPage> {
  String platform = 'windows';
  final version = TextEditingController();
  final notes = TextEditingController();
  bool uploading = false;

  @override
  void dispose() {
    version.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> _upload() async {
    if (version.text.trim().isEmpty) return;
    final extension = platform == 'android' ? 'apk' : 'exe';
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: platform == 'android' ? ['apk'] : ['exe', 'msi'],
      withData: true,
    );
    final file = result?.files.single;
    if (file?.bytes == null) return;
    setState(() => uploading = true);
    try {
      final ref = FirebaseStorage.instance.ref(
        'app_updates/$platform/${version.text.trim()}/${file!.name}',
      );
      await ref.putData(
        file.bytes!,
        SettableMetadata(
          contentType: platform == 'android'
              ? 'application/vnd.android.package-archive'
              : 'application/octet-stream',
        ),
      );
      final url = await ref.getDownloadURL();
      await FirebaseFirestore.instance
          .collection('app_updates')
          .doc(platform)
          .set({
            'platform': platform,
            'version': version.text.trim(),
            'releaseNotes': notes.text.trim(),
            'mandatory': false,
            'downloadUrl': url,
            'fileName': file.name,
            'publishedAt': FieldValue.serverTimestamp(),
            'publishedBy': widget.systemOwner.id,
          });
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Update uploaded and published.')),
        );
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Update Management')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('device_installations')
              .snapshots(),
          builder: (_, snapshot) {
            final docs = snapshot.data?.docs ?? const [];
            int count(String p) =>
                docs.where((d) => d.data()['platform'] == p).length;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _CountCard('All platforms', docs.length, Icons.devices),
                _CountCard('Windows', count('windows'), Icons.desktop_windows),
                _CountCard('Android', count('android'), Icons.android),
                _CountCard('Web', count('web'), Icons.web),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        const Card(
          child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('How to publish an update'),
            subtitle: Text(
              'Build the release first. Choose Windows and upload the generated setup EXE/MSI, or choose Android and upload the release APK. Enter a higher version than the installed app. Devices report their platform and will show the update prompt. Android always requires the user to approve installation.',
            ),
          ),
        ),
        const SizedBox(height: 16),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'windows',
              label: Text('Windows'),
              icon: Icon(Icons.desktop_windows),
            ),
            ButtonSegment(
              value: 'android',
              label: Text('Android'),
              icon: Icon(Icons.android),
            ),
          ],
          selected: {platform},
          onSelectionChanged: (v) => setState(() => platform = v.first),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: version,
          decoration: const InputDecoration(
            labelText: 'Release version (example 1.1.0)',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: notes,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Release notes'),
        ),
        FilledButton.icon(
          onPressed: uploading ? null : _upload,
          icon: uploading
              ? const ModernLoadingIndicator()
              : const Icon(Icons.upload_file),
          label: Text(uploading ? 'Uploading…' : 'Choose file and publish'),
        ),
      ],
    ),
  );
}

class _CountCard extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  const _CountCard(this.label, this.count, this.icon);
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 190,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(label),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
