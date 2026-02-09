import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CodeSyncApp());
}

class CodeSyncApp extends StatelessWidget {
  const CodeSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CodeSync',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF10B981)),
        useMaterial3: true,
      ),
      home: const WebContainer(),
    );
  }
}

class WebContainer extends StatefulWidget {
  const WebContainer({super.key});

  @override
  State<WebContainer> createState() => _WebContainerState();
}

class _WebContainerState extends State<WebContainer> {
  static const String appUrl = String.fromEnvironment(
    'APP_URL',
    defaultValue: 'https://codesyncioo.netlify.app/',
  );

  InAppWebViewController? _controller;
  bool _isLoading = true;

  final InAppWebViewSettings _settings = InAppWebViewSettings(
    javaScriptEnabled: true,
    supportZoom: false,
    builtInZoomControls: false,
    displayZoomControls: false,
    useWideViewPort: true,
    allowFileAccessFromFileURLs: false,
    allowUniversalAccessFromFileURLs: false,
    mediaPlaybackRequiresUserGesture: false,
    disableHorizontalScroll: false,
    disableVerticalScroll: false,
  );

  String _buildCreateRoomUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return 'https://codesyncioo.netlify.app/create-room';
    }
    final cleaned = trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
    return cleaned.endsWith('/create-room') ? cleaned : '$cleaned/create-room';
  }

  Future<void> _loadUrl(String url) async {
    final target = _buildCreateRoomUrl(url);
    await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(target)));
  }

  Future<bool> _ensureStoragePermission() async {
    if (!Platform.isAndroid) return true;
    final storage = await Permission.storage.request();
    if (storage.isGranted) return true;
    final manage = await Permission.manageExternalStorage.request();
    return manage.isGranted;
  }

  Future<String> _defaultDownloadDir() async {
    return (await getApplicationDocumentsDirectory()).path;
  }

  Future<void> _exitApp() async {
    if (Platform.isAndroid) {
      await SystemNavigator.pop();
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri(_buildCreateRoomUrl(appUrl)),
              ),
              initialSettings: _settings,
              onWebViewCreated: (controller) {
                _controller = controller;
                controller.addJavaScriptHandler(
                  handlerName: 'pickDownloadPath',
                  callback: (args) async {
                    try {
                      if (Platform.isIOS) {
                        final path = await _defaultDownloadDir();
                        return {
                          'success': true,
                          'path': path,
                          'warning': 'iOS uses the app documents folder.'
                        };
                      }
                      final permissionOk = await _ensureStoragePermission();
                      if (!permissionOk) {
                        return {'success': false, 'error': 'Storage permission denied'};
                      }
                      final path = await FilePicker.platform.getDirectoryPath();
                      if (path == null || path.isEmpty) {
                        return {'success': false, 'error': 'No folder selected'};
                      }
                      return {'success': true, 'path': path};
                    } catch (err) {
                      return {'success': false, 'error': err.toString()};
                    }
                  },
                );

                controller.addJavaScriptHandler(
                  handlerName: 'saveProject',
                  callback: (args) async {
                    if (args.isEmpty || args.first is! Map) {
                      return {'success': false, 'error': 'Invalid payload'};
                    }
                    final payload = Map<String, dynamic>.from(args.first as Map);
                    final basePath = (payload['basePath'] ?? '').toString();
                    final upserts = (payload['upserts'] as List?) ?? [];
                    final deletes = (payload['deletes'] as List?) ?? [];

                    try {
                      if (Platform.isAndroid) {
                        final permissionOk = await _ensureStoragePermission();
                        if (!permissionOk) {
                          return {'success': false, 'error': 'Storage permission denied'};
                        }
                      }

                      Directory directory;
                      if (basePath.isNotEmpty) {
                        directory = Directory(basePath);
                        if (!await directory.exists()) {
                          await directory.create(recursive: true);
                        }
                      } else {
                        directory = await getApplicationDocumentsDirectory();
                      }

                      String rootPath = directory.path;
                      if (Platform.isIOS) {
                        final roomFolder = payload['roomName']?.toString().trim() ?? 'codesync';
                        rootPath = p.join(rootPath, roomFolder.isEmpty ? 'codesync' : roomFolder);
                        final roomDir = Directory(rootPath);
                        if (!await roomDir.exists()) {
                          await roomDir.create(recursive: true);
                        }
                      }

                      debugPrint('[CodeSync] Saving to: $rootPath');
                      debugPrint('[CodeSync] Upserts: ${upserts.length}, Deletes: ${deletes.length}');

                      for (final item in deletes) {
                        final relPath = item.toString();
                        if (relPath.isEmpty) continue;
                        final file = File(p.normalize(p.join(rootPath, relPath)));
                        if (await file.exists()) {
                          await file.delete();
                        }
                      }

                      for (final item in upserts) {
                        if (item is! Map) continue;
                        final pathValue = (item['path'] ?? '').toString();
                        final contentValue = (item['content'] ?? '').toString();
                        if (pathValue.isEmpty) continue;

                        final filePath = p.normalize(p.join(rootPath, pathValue));
                        final fileDir = Directory(p.dirname(filePath));
                        if (!await fileDir.exists()) {
                          await fileDir.create(recursive: true);
                        }
                        final file = File(filePath);
                        await file.writeAsString(contentValue);
                      }

                      return {
                        'success': true,
                        'path': rootPath,
                        'debug': {
                          'upserts': upserts.length,
                          'deletes': deletes.length,
                        }
                      };
                    } catch (err) {
                      return {'success': false, 'error': err.toString()};
                    }
                  },
                );
              },
              onLoadStart: (controller, url) {
                setState(() {
                  _isLoading = true;
                });
              },
              onLoadStop: (controller, url) async {
                setState(() {
                  _isLoading = false;
                });
                if (url != null) {
                  final path = url.path.toLowerCase();
                  if (path == '/' || path.endsWith('/index') || path.endsWith('/index.html')) {
                    await _loadUrl(appUrl);
                  }
                }
              },
              onLoadError: (controller, url, code, message) {
                setState(() {
                  _isLoading = false;
                });
              },
              onLoadHttpError: (controller, url, statusCode, description) {
                setState(() {
                  _isLoading = false;
                });
              },
            ),
            if (_isLoading)
              Positioned.fill(
                child: Container(
                  color: Colors.black,
                  child: const Center(
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFF10B981),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
