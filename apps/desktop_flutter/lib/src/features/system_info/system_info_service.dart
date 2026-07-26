import 'dart:convert';
import 'dart:io';

/// Snapshot of non-sensitive device data shown on the system information page.
class SystemInfoSnapshot {
  const SystemInfoSnapshot({
    required this.system,
    required this.cpu,
    required this.memory,
    required this.disks,
    required this.displays,
    required this.generatedAt,
  });

  final SystemInfoGroup system;
  final SystemInfoGroup cpu;
  final MemoryInfo memory;
  final List<DiskInfo> disks;
  final List<DisplayInfo> displays;
  final DateTime generatedAt;
}

/// Label/value collection used by compact information cards.
class SystemInfoGroup {
  const SystemInfoGroup({required this.title, required this.values});

  final String title;
  final Map<String, String> values;
}

/// Physical memory usage in bytes.
class MemoryInfo {
  const MemoryInfo({
    required this.totalBytes,
    required this.freeBytes,
    required this.usedBytes,
  });

  final int totalBytes;
  final int freeBytes;
  final int usedBytes;

  double get usageRatio => totalBytes == 0 ? 0 : usedBytes / totalBytes;
}

/// Local fixed disk usage in bytes.
class DiskInfo {
  const DiskInfo({
    required this.name,
    required this.fileSystem,
    required this.totalBytes,
    required this.freeBytes,
  });

  final String name;
  final String fileSystem;
  final int totalBytes;
  final int freeBytes;

  int get usedBytes => totalBytes - freeBytes;

  double get usageRatio => totalBytes == 0 ? 0 : usedBytes / totalBytes;
}

/// Display adapter information that is safe to show in the app UI.
class DisplayInfo {
  const DisplayInfo({
    required this.name,
    required this.resolution,
    required this.refreshRate,
  });

  final String name;
  final String resolution;
  final String refreshRate;
}

/// Reads Windows system information using ordinary user permissions only.
class SystemInfoService {
  Future<SystemInfoSnapshot> load() async {
    final data = await _loadPowerShellSnapshot();
    final os = _asMap(data['os']);
    final cpu = _asMap(data['cpu']);
    final memory = _memoryFrom(os);
    final disks = _asList(data['disks']).map(_diskFrom).toList();
    final displays = _asList(data['displays']).map(_displayFrom).toList();

    return SystemInfoSnapshot(
      system: SystemInfoGroup(
        title: '系统',
        values: {
          'Windows 版本': _string(os['Caption'], Platform.operatingSystemVersion),
          '版本号': _string(os['Version'], '未知'),
          '架构': _string(os['OSArchitecture'], '未知'),
          '设备名称': Platform.localHostname,
          '启动时间': _formatCimDate(_string(os['LastBootUpTime'], '未知')),
        },
      ),
      cpu: SystemInfoGroup(
        title: 'CPU',
        values: {
          '型号': _string(cpu['Name'], '未知'),
          '核心 / 线程':
              '${_string(cpu['NumberOfCores'], '--')} / '
              '${_string(cpu['NumberOfLogicalProcessors'], '--')}',
          '当前频率': '${_string(cpu['CurrentClockSpeed'], '--')} MHz',
          '实时使用率': '${_string(cpu['LoadPercentage'], '--')}%',
        },
      ),
      memory: memory,
      disks: disks,
      displays: displays,
      generatedAt: DateTime.now(),
    );
  }

  Future<Map<String, dynamic>> _loadPowerShellSnapshot() async {
    const script = r'''
$os = Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,OSArchitecture,LastBootUpTime,TotalVisibleMemorySize,FreePhysicalMemory
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1 Name,NumberOfCores,NumberOfLogicalProcessors,CurrentClockSpeed,LoadPercentage
$disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Select-Object DeviceID,FileSystem,Size,FreeSpace
$displays = Get-CimInstance Win32_VideoController | Select-Object Name,CurrentHorizontalResolution,CurrentVerticalResolution,CurrentRefreshRate
[pscustomobject]@{ os=$os; cpu=$cpu; disks=@($disks); displays=@($displays) } | ConvertTo-Json -Depth 4 -Compress
''';
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      script,
    ]);
    if (result.exitCode != 0) {
      throw const SystemInfoException('系统信息读取失败');
    }
    return jsonDecode(result.stdout as String) as Map<String, dynamic>;
  }

  MemoryInfo _memoryFrom(Map<String, dynamic> os) {
    final total = _parseInt(os['TotalVisibleMemorySize']) * 1024;
    final free = _parseInt(os['FreePhysicalMemory']) * 1024;
    return MemoryInfo(
      totalBytes: total,
      freeBytes: free,
      usedBytes: total - free,
    );
  }

  DiskInfo _diskFrom(dynamic value) {
    final disk = _asMap(value);
    return DiskInfo(
      name: _string(disk['DeviceID'], '未知'),
      fileSystem: _string(disk['FileSystem'], '未知'),
      totalBytes: _parseInt(disk['Size']),
      freeBytes: _parseInt(disk['FreeSpace']),
    );
  }

  DisplayInfo _displayFrom(dynamic value) {
    final display = _asMap(value);
    final width = _parseInt(display['CurrentHorizontalResolution']);
    final height = _parseInt(display['CurrentVerticalResolution']);
    final refresh = _parseInt(display['CurrentRefreshRate']);
    return DisplayInfo(
      name: _string(display['Name'], '未知显示设备'),
      resolution: width > 0 && height > 0 ? '${width}x$height' : '未知',
      refreshRate: refresh > 0 ? '$refresh Hz' : '未知',
    );
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    return const {};
  }

  List<dynamic> _asList(dynamic value) {
    if (value is List) return value;
    if (value == null) return const [];
    return [value];
  }

  int _parseInt(dynamic value) => int.tryParse('$value') ?? 0;

  String _string(dynamic value, String fallback) {
    final text = '$value'.trim();
    return text.isEmpty || text == 'null' ? fallback : text;
  }

  String _formatCimDate(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    return '${parsed.year}-${_two(parsed.month)}-${_two(parsed.day)} '
        '${_two(parsed.hour)}:${_two(parsed.minute)}';
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}

/// User-facing error when Windows system information cannot be collected.
class SystemInfoException implements Exception {
  const SystemInfoException(this.message);

  final String message;

  @override
  String toString() => message;
}

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final precision = unit <= 1 ? 0 : 1;
  return '${size.toStringAsFixed(precision)} ${units[unit]}';
}
