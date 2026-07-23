import 'package:flutter/material.dart';

import '../models/feature_page_data.dart';

/// Mock feature content mirrors the V1 PRD while the native backend is still absent.
const featurePages = <FeaturePageData>[
  FeaturePageData(
    title: 'C 盘空间一目了然',
    subtitle: '扫描与清理均在本机完成',
    metricLabel: '可释放约',
    metricValue: '18.6 GB',
    actionLabel: '开始安全扫描',
    icon: Icons.cleaning_services_outlined,
    highlights: ['系统临时文件', '应用缓存', '回收站默认谨慎'],
    checks: ['高风险资料默认不选', '清理前预览', '隔离区保留 7 天'],
  ),
  FeaturePageData(
    title: '应用迁移',
    subtitle: '将兼容的桌面应用安全迁移到其他本地磁盘',
    metricLabel: '预计迁移',
    metricValue: '8.62 GB',
    actionLabel: '开始迁移',
    icon: Icons.drive_file_move_outline,
    highlights: ['Adobe Photoshop 2025', '7-Zip', 'Notepad++'],
    checks: ['目标盘空间充足', 'NTFS 文件系统', '失败自动回滚'],
  ),
  FeaturePageData(
    title: '微信专清',
    subtitle: '按账号和类型管理微信占用，所有扫描仅在本机完成',
    metricLabel: '预计释放',
    metricValue: '4.6 GB',
    actionLabel: '清理所选',
    icon: Icons.chat_bubble_outline,
    highlights: ['运行缓存', '日志与更新残留', '聊天图片默认不选'],
    checks: ['不展示消息正文', '高风险资料二次确认', '清理前提示退出微信'],
  ),
  FeaturePageData(
    title: '系统信息',
    subtitle: '快速查看 CPU、内存、磁盘、系统和显示器信息',
    metricLabel: 'C: 可用',
    metricValue: '239 GB',
    actionLabel: '刷新',
    icon: Icons.memory_outlined,
    highlights: ['Windows 11 64 位', '16 GB 内存', 'NTFS 固态硬盘'],
    checks: ['普通权限读取', '不上传设备信息', '后续支持导出报告'],
  ),
  FeaturePageData(
    title: '隔离区',
    subtitle: '可恢复项目会先移动到非 C 盘隔离区',
    metricLabel: '保留中',
    metricValue: '7 天',
    actionLabel: '查看隔离记录',
    icon: Icons.security_outlined,
    highlights: ['系统临时文件', '微信媒体文件', '迁移备份目录'],
    checks: ['恢复原路径', '记录哈希与大小', '到期前可手动清空'],
  ),
  FeaturePageData(
    title: '设置',
    subtitle: '管理常规、隔离恢复、扫描性能、隐私日志和更新策略',
    metricLabel: '隐私模式',
    metricValue: '本地',
    actionLabel: '保存设置',
    icon: Icons.settings_outlined,
    highlights: ['开机启动', '扫描强度', '规则更新'],
    checks: ['路径日志脱敏', '默认离线可用', '不显示广告推送'],
  ),
];
