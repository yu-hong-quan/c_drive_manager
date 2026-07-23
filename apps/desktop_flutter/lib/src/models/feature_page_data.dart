import 'package:flutter/material.dart';

/// Static page model used before FFI, SQLite, and task repositories are wired in.
class FeaturePageData {
  const FeaturePageData({
    required this.title,
    required this.subtitle,
    required this.metricLabel,
    required this.metricValue,
    required this.actionLabel,
    required this.icon,
    required this.highlights,
    required this.checks,
  });

  final String title;
  final String subtitle;
  final String metricLabel;
  final String metricValue;
  final String actionLabel;
  final IconData icon;
  final List<String> highlights;
  final List<String> checks;
}
