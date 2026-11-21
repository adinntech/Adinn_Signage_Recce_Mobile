import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'app.dart';
import 'data/storage/local_store.dart';
import 'data/storage/media_storage.dart';
import 'features/live_recce/data/live_services.dart';
import 'state/app_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController(
    // path_provider has no web implementation: the offline demo keeps its data in memory on Chrome.
    store: kIsWeb ? MemoryLocalStore() : FileLocalStore(),
    media: MediaStorage(),
  );
  runApp(AdinnRecceApp(controller: controller, live: LiveServices.create()));
}
