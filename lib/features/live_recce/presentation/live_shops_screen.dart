import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/chat_controller.dart';
import '../data/notifications_controller.dart';
import '../data/recce_controllers.dart';
import '../data/recce_models.dart';
import '../bridge/live_saran_shop_screen.dart';
import 'live_shop_screen.dart';
import 'live_widgets.dart';

/// Opens one shop; [tab] is one of [ShopTab] (a notification about a message opens the Chat tab). Null: the shop opens on the step
/// the person is at (see [LiveShopScreen.initialTab]).
void openShop(BuildContext context, String siteId, {int? tab}) {
  // No tab asked for: the shop opens on the shop detail / board screens fed with the live data. A tab (a notification about a
  // message or a review) opens the classic tabbed screen.
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => tab == null ? LiveSaranShopScreen(siteId: siteId) : LiveShopScreen(siteId: siteId, initialTab: tab)));
}

/// Assigned Shops: search + status filter chips. Optionally limited to one project.
class LiveShopsScreen extends StatefulWidget {
  const LiveShopsScreen({super.key, this.projectId, this.title = 'Assigned shops', this.initialFilter = ShopFilter.all});

  final String? projectId;
  final String title;
  final ShopFilter initialFilter;

  @override
  State<LiveShopsScreen> createState() => _LiveShopsScreenState();
}

class _LiveShopsScreenState extends State<LiveShopsScreen> {
  final _search = TextEditingController();
  late ShopFilter _filter = widget.initialFilter;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = context.watch<ShopListController>();
    context.watch<ChatHub>(); // the unread counts on the rows
    context.watch<NotificationsController>();
    final scoped = widget.projectId == null ? list.shops : list.shops.where((s) => s.projectId == widget.projectId).toList();
    final shown = list.filtered(query: _search.text, filter: _filter, projectId: widget.projectId);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _search,
              inputFormatters: [LengthLimitingTextInputFormatter(60)],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search shop, code or address',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_search.clear)),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: [
                for (final f in ShopFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${f.label} (${scoped.where((s) => f.matches(s.status)).length})'),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _body(list, shown)),
        ],
      ),
    );
  }

  Widget _body(ShopListController list, List<ShopSummary> shown) {
    if (!list.loaded && list.loading) return const Center(child: CircularProgressIndicator());
    if (!list.loaded && list.error != null) return ErrorRetry(message: list.error!, onRetry: list.load);
    return RefreshIndicator(
      onRefresh: list.load,
      color: AdinnColors.red,
      child: shown.isEmpty
          ? ListView(children: const [
              SizedBox(height: 60),
              EmptyState(icon: Icons.storefront_outlined, title: 'No shops here', message: 'Shops assigned to you by Operations appear here.'),
            ])
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: shown.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => ShopCard(
                shop: shown[i],
                showProject: widget.projectId == null,
                unread: shopUnreadCount(context.read<ChatHub>(), context.read<NotificationsController>(), shown[i].siteId),
                onTap: () => openShop(context, shown[i].siteId),
              ),
            ),
    );
  }
}
