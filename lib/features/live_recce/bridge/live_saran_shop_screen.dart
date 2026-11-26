import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/app_controller.dart';
import '../../live_auth/presentation/live_auth_controller.dart';
import '../../shop/shop_detail_screen.dart';
import '../data/live_services.dart';
import '../data/recce_controllers.dart';
import '../presentation/live_shop_screen.dart';
import '../presentation/live_widgets.dart';
import 'live_shop_bridge.dart';

/// A shop of the server shown with the shop detail / media type / board editor screens (the same ones the offline prototype uses),
/// fed with the live data by a [LiveShopBridge]. The classic tabbed screen (Chat, the site installation answers, rework) stays one
/// tap away.
class LiveSaranShopScreen extends StatefulWidget {
  const LiveSaranShopScreen({super.key, required this.siteId});

  final String siteId;

  @override
  State<LiveSaranShopScreen> createState() => _LiveSaranShopScreenState();
}

class _LiveSaranShopScreenState extends State<LiveSaranShopScreen> with WidgetsBindingObserver {
  late final ShopDetailController _ctrl;
  late final LiveShopBridge _bridge;
  late final AppController _app;

  @override
  void initState() {
    super.initState();
    final s = context.read<LiveServices>();
    final user = context.read<LiveAuthController>().user;
    _app = context.read<AppController>();
    _ctrl = ShopDetailController(s.api, s.queue, widget.siteId, catalog: s.catalog);
    _bridge = LiveShopBridge(app: _app, ctrl: _ctrl, userId: user?.id ?? 'live-user', userName: user?.name ?? 'Vendor', userPhone: user?.phone ?? '');
    unawaited(s.catalog.refresh());
    unawaited(_ctrl.load().then((_) => _bridge.hydrate()));
    WidgetsBinding.instance.addObserver(this);
  }

  /// Signed photo links run out after a few minutes: read the shop again when the app comes back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_bridge.hasPending) {
      unawaited(_ctrl.refreshIfStale().then((_) => _bridge.hydrate()));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final bridge = _bridge;
    final ctrl = _ctrl;
    // What was typed last still goes to the server before the screen lets go of the shop.
    unawaited((bridge.hasPending ? bridge.saveDraft() : Future<String?>.value()).whenComplete(() {
      bridge.dispose();
      ctrl.dispose();
    }));
    super.dispose();
  }

  void _openClassic(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LiveShopScreen(siteId: widget.siteId, initialTab: ShopTab.chat)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_ctrl, _bridge]),
      builder: (context, _) {
        final loaded = _ctrl.detail != null && _app.shop(widget.siteId) != null;
        if (!loaded) {
          return Scaffold(
            appBar: AppBar(),
            body: _ctrl.loading || _ctrl.loadError == null
                ? const Center(child: CircularProgressIndicator())
                : ErrorRetry(message: _ctrl.loadError ?? 'Could not load this shop.', onRetry: () => _ctrl.load().then((_) => _bridge.hydrate())),
          );
        }
        final err = _bridge.syncError;
        return Stack(
          children: [
            ShopDetailScreen(shopId: widget.siteId),
            Positioned(
              right: 16,
              bottom: 92,
              child: SafeArea(
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (err != null)
                        Container(
                          constraints: const BoxConstraints(maxWidth: 280),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade200), boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)]),
                          child: Text('Not saved on the server: $err', style: const TextStyle(fontSize: 12)),
                        ),
                      if (_bridge.syncing) const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                      FloatingActionButton.small(
                        heroTag: 'live-classic-${widget.siteId}',
                        tooltip: 'Chat and site installation',
                        onPressed: () => _openClassic(context),
                        child: const Icon(Icons.chat_bubble_outline),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
