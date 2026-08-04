import 'dart:convert';
import 'dart:io';

/// 按需启动提权 Helper，执行目录联接等需要管理员权限的操作。
class ElevationHelper {
  ElevationHelper({String? helperPath}) : _helperPath = helperPath;

  final String? _helperPath;

  /// 创建目录联接。优先普通权限；失败后尝试 UAC 提权 Helper。
  Future<void> createJunction({
    required String linkPath,
    required String targetPath,
  }) async {
    final direct = await _runMklink(linkPath, targetPath);
    if (direct == 0 && await Directory(linkPath).exists()) {
      return;
    }

    final helper = _resolveHelperPath();
    if (helper == null) {
      throw ElevationHelperException(
        code: 'ELEVATION_REQUIRED',
        message: '目录联接失败，且未找到 c_manager_helper.exe',
      );
    }

    // 先以当前权限调用 Helper；仍失败再弹 UAC。
    final normal = await _runHelper(
      helperPath: helper,
      request: {
        'method': 'create_junction',
        'linkPath': linkPath,
        'targetPath': targetPath,
      },
      elevate: false,
    );
    if (normal['ok'] == true) return;

    final elevated = await _runHelper(
      helperPath: helper,
      request: {
        'method': 'create_junction',
        'linkPath': linkPath,
        'targetPath': targetPath,
      },
      elevate: true,
    );
    if (elevated['ok'] == true) return;

    final error = elevated['error'];
    final code = error is Map ? error['code']?.toString() : 'HELPER_JUNCTION_FAILED';
    final message = error is Map
        ? error['message']?.toString()
        : '提权 Helper 创建目录联接失败';
    throw ElevationHelperException(
      code: code ?? 'ELEVATION_REQUIRED',
      message: message ?? '提权 Helper 创建目录联接失败',
    );
  }

  Future<int> _runMklink(String linkPath, String targetPath) async {
    final result = await Process.run('cmd', [
      '/C',
      'mklink',
      '/J',
      linkPath,
      targetPath,
    ]);
    return result.exitCode;
  }

  Future<Map<String, dynamic>> _runHelper({
    required String helperPath,
    required Map<String, dynamic> request,
    required bool elevate,
  }) async {
    final payload = jsonEncode(request);
    if (!elevate) {
      final result = await Process.run(helperPath, ['--request', payload]);
      return _decode(result.stdout);
    }

    // 通过 PowerShell RunAs 触发 UAC；输出写入临时文件再回读。
    final outFile = File(
      '${Directory.systemTemp.path}\\cdm_helper_${DateTime.now().millisecondsSinceEpoch}.json',
    );
    final script =
        "Start-Process -FilePath '${helperPath.replaceAll("'", "''")}' "
        "-ArgumentList '--request','${payload.replaceAll("'", "''")}' "
        "-Verb RunAs -Wait -RedirectStandardOutput '${outFile.path.replaceAll("'", "''")}'";
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      script,
    ]);
    if (result.exitCode != 0 && !await outFile.exists()) {
      return {
        'ok': false,
        'error': {
          'code': 'ELEVATION_REQUIRED',
          'message': '用户取消了 UAC，或提权启动失败',
        },
      };
    }
    try {
      if (!await outFile.exists()) {
        return {
          'ok': false,
          'error': {
            'code': 'HELPER_NO_OUTPUT',
            'message': '提权 Helper 无输出',
          },
        };
      }
      final text = await outFile.readAsString();
      await outFile.delete();
      return _decode(text);
    } on Object {
      return {
        'ok': false,
        'error': {
          'code': 'HELPER_OUTPUT_INVALID',
          'message': '无法读取提权 Helper 输出',
        },
      };
    }
  }

  Map<String, dynamic> _decode(Object? stdout) {
    final text = '$stdout'.trim();
    if (text.isEmpty) {
      return {
        'ok': false,
        'error': {'code': 'HELPER_EMPTY', 'message': 'Helper 返回空响应'},
      };
    }
    // Helper 可能夹杂其他输出，取最后一行 JSON。
    final line = text.split(RegExp(r'\r?\n')).lastWhere(
      (item) => item.trim().startsWith('{'),
      orElse: () => text,
    );
    try {
      return Map<String, dynamic>.from(jsonDecode(line) as Map);
    } on Object {
      return {
        'ok': false,
        'error': {'code': 'HELPER_BAD_JSON', 'message': line},
      };
    }
  }

  String? _resolveHelperPath() {
    final configured = _helperPath;
    if (configured != null && File(configured).existsSync()) {
      return configured;
    }
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = <String>[
      '$exeDir\\c_manager_helper.exe',
      '${Directory.current.path}\\c_manager_helper.exe',
      '${Directory.current.parent.parent.path}\\target\\release\\c_manager_helper.exe',
      '${Directory.current.parent.parent.path}\\target\\debug\\c_manager_helper.exe',
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }
}

class ElevationHelperException implements Exception {
  ElevationHelperException({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => 'ElevationHelperException($code): $message';
}
