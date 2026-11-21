import 'package:flutter/material.dart';

import 'app.dart';
import 'data/storage/local_store.dart';
import 'data/storage/media_storage.dart';
import 'state/app_controller.dart';

//demo commit
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController(
    store: FileLocalStore(),
    media: MediaStorage(),
  );
  runApp(AdinnRecceApp(controller: controller));
}
