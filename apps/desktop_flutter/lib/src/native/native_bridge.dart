import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Rust FFI 响应信封解析结果。
class NativeApiResult {
  const NativeApiResult({required this.ok, this.data, this.code, this.message});

  final bool ok;
  final dynamic data;
  final String? code;
  final String? message;

  factory NativeApiResult.fromJson(Map<String, dynamic> json) {
    final ok = json['ok'] == true;
    if (ok) {
      return NativeApiResult(ok: true, data: json['data']);
    }
    final error = json['error'];
    if (error is Map) {
      return NativeApiResult(
        ok: false,
        code: error['code']?.toString(),
        message: error['message']?.toString(),
      );
    }
    return const NativeApiResult(
      ok: false,
      code: 'BAD_RESPONSE',
      message: '无法解析 Rust 响应',
    );
  }
}

typedef _CdmCallNative =
    Pointer<Utf8> Function(Pointer<Utf8> method, Pointer<Utf8> request);
typedef _CdmCallDart =
    Pointer<Utf8> Function(Pointer<Utf8> method, Pointer<Utf8> request);
typedef _CdmFreeNative = Void Function(Pointer<Utf8> ptr);
typedef _CdmFreeDart = void Function(Pointer<Utf8> ptr);
typedef _CdmVersionNative = Pointer<Utf8> Function();
typedef _CdmVersionDart = Pointer<Utf8> Function();

/// 加载 c_drive_manager_ffi.dll，并以 JSON 命令方式调用 Rust Core。
class NativeBridge {
  NativeBridge._(this._call, this._free, this._version);

  final _CdmCallDart _call;
  final _CdmFreeDart _free;
  final _CdmVersionDart _version;

  static NativeBridge? _instance;
  static String? _loadError;

  /// 是否已成功加载原生引擎。
  static bool get isAvailable {
    try {
      instance;
      return true;
    } on Object {
      return false;
    }
  }

  static String? get loadError => _loadError;

  static NativeBridge get instance {
    final existing = _instance;
    if (existing != null) return existing;
    final bridge = NativeBridge._open();
    _instance = bridge;
    return bridge;
  }

  static NativeBridge _open() {
    try {
      final lib = DynamicLibrary.open(_resolveLibraryPath());
      final call = lib
          .lookupFunction<_CdmCallNative, _CdmCallDart>('cdm_call');
      final free = lib
          .lookupFunction<_CdmFreeNative, _CdmFreeDart>('cdm_free_string');
      final version = lib
          .lookupFunction<_CdmVersionNative, _CdmVersionDart>('cdm_version');
      return NativeBridge._(call, free, version);
    } on Object catch (error) {
      _loadError = '$error';
      rethrow;
    }
  }

  String version() {
    final ptr = _version();
    if (ptr == nullptr) return '';
    try {
      return ptr.toDartString();
    } finally {
      _free(ptr);
    }
  }

  /// 调用 Rust 方法；失败时抛出 [NativeApiException]。
  dynamic call(String method, [Map<String, dynamic>? request]) {
    final methodPtr = method.toNativeUtf8();
    final requestPtr = jsonEncode(request ?? const <String, dynamic>{}).toNativeUtf8();
    Pointer<Utf8> responsePtr = nullptr;
    try {
      responsePtr = _call(methodPtr, requestPtr);
      if (responsePtr == nullptr) {
        throw const NativeApiException(
          code: 'NULL_RESPONSE',
          message: 'Rust 返回空指针',
        );
      }
      final text = responsePtr.toDartString();
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw const NativeApiException(
          code: 'BAD_RESPONSE',
          message: 'Rust 响应不是对象',
        );
      }
      final result = NativeApiResult.fromJson(decoded);
      if (!result.ok) {
        throw NativeApiException(
          code: result.code ?? 'ENGINE_ERROR',
          message: result.message ?? 'Rust 引擎调用失败',
          data: result.data,
        );
      }
      return result.data;
    } finally {
      malloc.free(methodPtr);
      malloc.free(requestPtr);
      if (responsePtr != nullptr) {
        _free(responsePtr);
      }
    }
  }

  /// 解析 DLL 路径：优先可执行文件同目录，其次项目构建产物。
  static String _resolveLibraryPath() {
    const name = 'c_drive_manager_ffi.dll';
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final besideExe = '$exeDir\\$name';
    if (File(besideExe).existsSync()) return besideExe;

    final cwd = Directory.current.path;
    final candidates = <String>[
      '$cwd\\$name',
      '$cwd\\native\\$name',
      '$cwd\\build\\windows\\x64\\runner\\Debug\\$name',
      '$cwd\\build\\windows\\x64\\runner\\Release\\$name',
      '${Directory.current.parent.parent.path}\\target\\release\\$name',
      '${Directory.current.parent.parent.path}\\target\\debug\\$name',
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    // 交给系统按名称搜索，便于开发期把 DLL 放进 PATH。
    return name;
  }
}

class NativeApiException implements Exception {
  const NativeApiException({
    required this.code,
    required this.message,
    this.data,
  });

  final String code;
  final String message;
  final dynamic data;

  @override
  String toString() => 'NativeApiException($code): $message';
}
