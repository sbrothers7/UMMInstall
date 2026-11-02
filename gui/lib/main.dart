import 'package:flutter/material.dart';

import 'src/app_state.dart';
import 'src/ui/app_scope.dart';
import 'src/ui/content_view.dart';
import 'src/updater.dart';

void main() {
  Updater.writeDesktopEntry();
  runApp(const AdofaiModInstallerApp());
}

class AdofaiModInstallerApp extends StatefulWidget {
  const AdofaiModInstallerApp({super.key});

  @override
  State<AdofaiModInstallerApp> createState() => _AppRootState();
}

class _AppRootState extends State<AdofaiModInstallerApp> {
  late final AppState _state;

  @override
  void initState() {
    super.initState();
    _state = AppState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _state.bootstrap());
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: _state,
      child: MaterialApp(
        title: 'ADOFAI Mod Installer',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          // Linux doesn't fall back to a Korean font on its own (boxes in
          // the KR strings); name the common ones. macOS ignores these.
          fontFamilyFallback: const ['Noto Sans CJK KR', 'Noto Sans KR', 'NanumGothic'],
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF5B8DEF),
            brightness: Brightness.dark,
          ),
        ),
        home: const Scaffold(body: SafeArea(child: ContentView())),
      ),
    );
  }
}
