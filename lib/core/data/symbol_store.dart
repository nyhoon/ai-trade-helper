import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SymbolStore {
  static const String _key = 'symbol_store_map_v1';

  Map<String, String> _map = {};
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_key);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        _map = Map<String, String>.from(jsonDecode(jsonStr) as Map);
      } catch (_) {
        _map = {};
      }
    }
    _loaded = true;
  }

  Future<String?> getName(String code) async {
    await _ensureLoaded();
    return _map[code];
  }

  Future<void> setName(String code, String name) async {
    await _ensureLoaded();
    _map[code] = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_map));
  }

  Future<void> setMany(Map<String, String> entries) async {
    await _ensureLoaded();
    _map.addAll(entries);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_map));
  }

  Future<Map<String, String>> export() async {
    await _ensureLoaded();
    return Map<String, String>.from(_map);
  }
}


