/// User preferences, persisted in the settings table.
library;

import 'package:flutter/foundation.dart';

import 'db.dart';
import 'stats.dart';

const _kConfidenceKey = 'confidence';
const _kWindowKey = 'window';
const _kShowEstimatesKey = 'show_estimates';

class Settings extends ChangeNotifier {
  Settings._();

  static final Settings instance = Settings._();

  ConfidenceLevel _confidence = ConfidenceLevel.eighty;
  ConfidenceLevel get confidence => _confidence;

  /// Number of most recent gaps used for estimates. 0 means "use everything".
  int _window = 0;
  int get window => _window;
  int? get windowOrNull => _window <= 0 ? null : _window;

  bool _showEstimates = true;
  bool get showEstimates => _showEstimates;

  Future<void> load() async {
    final db = AppDb.instance;
    final conf = await db.getSetting(_kConfidenceKey);
    if (conf != null) {
      _confidence = ConfidenceLevel.fromValue(double.tryParse(conf) ?? 0.80);
    }
    final win = await db.getSetting(_kWindowKey);
    if (win != null) _window = int.tryParse(win) ?? 0;

    final show = await db.getSetting(_kShowEstimatesKey);
    if (show != null) _showEstimates = show == '1';

    notifyListeners();
  }

  Future<void> setConfidence(ConfidenceLevel level) async {
    _confidence = level;
    notifyListeners();
    await AppDb.instance.setSetting(_kConfidenceKey, level.value.toString());
  }

  Future<void> setWindow(int value) async {
    _window = value;
    notifyListeners();
    await AppDb.instance.setSetting(_kWindowKey, value.toString());
  }

  Future<void> setShowEstimates(bool value) async {
    _showEstimates = value;
    notifyListeners();
    await AppDb.instance.setSetting(_kShowEstimatesKey, value ? '1' : '0');
  }
}
