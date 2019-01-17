import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:poly_museum/global.dart';
import 'package:poly_museum/model/plugin.dart';
import 'package:path_provider/path_provider.dart';
import 'package:poly_museum/test_class.dart';
import 'package:poly_museum/plugin_dao.dart';
import 'package:poly_museum/db_structure.dart';

class PluginService {
  final MethodChannel _pluginChannel = const MethodChannel('channel:polytech.al.imh/plugin');
  final HttpClient _httpClient = HttpClient();

  List<Plugin> _plugins = [];
  DocumentReference _configRef;
  Map<String, Map<String, dynamic>> _configs = {};

  ///
  ///  Adds for each type of plugin the configurations for each plugins corresponding to the type
  ///
  Future streamConfig() async {
    _configRef.snapshots().listen((snap) async {
      DocumentSnapshot config = await _configRef.get();

      Map<String, dynamic> configMap = {};

      for (String key in config.data.keys) {
        configMap.putIfAbsent(key, () => config.data[key]);
      }

      _configs.putIfAbsent("THEME_PLUGIN", () => configMap);

      await _pluginChannel.invokeMethod('addConfigs', _configs);
      await processThemePlugins();
    });
  }

  ///
  /// Gets from FireBase database all the plugins activated for the corresponding museum
  ///
  Future streamPluginsData() async {
    QuerySnapshot querySnapshot;
    querySnapshot = await museumReference.collection("plugins").getDocuments();

    for (DocumentSnapshot doc in querySnapshot.documents) {
      // Getting plugin file
      if(!doc.data["activated"]) continue;

      DocumentSnapshot ref = await doc.data["ref"].get();

      var plugin = Plugin.fromSnapshot(ref);
      _plugins.add(plugin);
      print(_plugins);
      // Getting plugin config

      _configRef = doc.reference.collection('config').document('current');
      DocumentSnapshot config = await _configRef.get();

      Map<String, dynamic> configMap = {};

      for (String key in config.data.keys) {
        configMap.putIfAbsent(key, () => config.data[key]);
      }

      _configs.putIfAbsent(plugin.type, () => configMap);
    }
  }

  ///
  /// Downloads a file with the given URL, putting the filename on this file to identify it
  /// Used for downloading the plugins for the application
  ///
  Future<File> downloadFile(String url, String filename) async {
    var request = await _httpClient.getUrl(Uri.parse(url));
    var response = await request.close();
    var bytes = await consolidateHttpClientResponseBytes(response);
    String dir = (await getTemporaryDirectory()).path;
    File file = new File('$dir/$filename');
    await file.writeAsBytes(bytes);
    return file;
  }

  ///
  /// Loads the activated plugins in the application
  ///
  initPlugins() async {
    for (Plugin plugin in _plugins) {
      File file = await downloadFile(plugin.downloadUrl, plugin.pluginName);
      plugin.fullLocalPath = file.path;
    }

    Map<String, List<String>> map = {
      'paths': _plugins.map((p) => p.fullLocalPath).toList(),
      'types': _plugins.map((p) => p.type).toList(),
      'qualifiedClassNames': _plugins.map((p) => p.qualifiedName).toList(),
      'pluginNames': _plugins.map((p) => p.type).toList(),
    };

    await _pluginChannel.invokeMethod('addConfigs', _configs);

    await _pluginChannel.invokeMethod('loadPlugins', map);
  }

  ///
  /// Invokes the methods from the plugins precedently loaded plugins in the application
  ///
  processThemePlugins() async {
    Map<dynamic, dynamic> res = await _pluginChannel.invokeMethod('processThemePlugins');

    int primary = res['getPrimaryColor()'];
    int secondary = res['getSecondaryColor()'];
    int background = res['getBackground()'];
    bool darkTheme = res['isDarkTheme()'];

    globalTheme = (darkTheme ?? false) ? ThemeData.dark() : ThemeData.light();

    if (res.containsKey('getPrimaryColor()'))
      globalTheme = globalTheme.copyWith(primaryColor: Color(primary).withOpacity(1.0));

    if (res.containsKey('getSecondaryColor()'))
      globalTheme = globalTheme.copyWith(accentColor: Color(secondary).withOpacity(1.0));

    if (res.containsKey('getBackground()'))
      globalTheme = globalTheme.copyWith(backgroundColor: Color(background).withOpacity(1.0));

    appBuilder.state.rebuild();
  }

  void testPluginService() async {
    TestCase(
      setUp : () {
        changeMuseumTarget(DBStructure.test_museum_document);
        
        PluginDAO pluginDAO = new PluginDAO();
        pluginDAO.insert(new Plugin(
            'pa.ck.age.PluginClass',
            'u.rl/plugin.jar',
            'foo',
            'plugin.jar',
            false,
            'plugin',
            DBStructure.test_museum_document));
        
      pluginDAO.insert(new Plugin(
            'pa.ck.age.Plugin2Class',
            'u.rl/plugin2.jar',
            'bar',
            'plugin2.jar',
            false,
            'plugin2',
            DBStructure.test_museum_document));
      
},
      body : () async {
        await streamPluginsData();
        TestCase.assertSame(2, _plugins.length);
      },
      after : () {
        print('AFTER');
      }
    ).start();
  }
}

