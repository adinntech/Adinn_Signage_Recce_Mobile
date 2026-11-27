import '../../l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/common_widgets.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import '../shop/shop_tile.dart';
import '../../core/widgets/adinn_app_bar.dart';

/// Reviewers: pending queue + history. Vendors: their submitted recces.
class ApprovalsScreen extends StatelessWidget {
  const ApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    return c.isVendor ? const _VendorSubmissions() : const _ReviewerQueue();
  }
}

class _ReviewerQueue extends StatelessWidget {
  const _ReviewerQueue();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final pending = c.pendingReviews;
    final reviewed = c.reviewedByMe;
    final stage = c.reviewStage == ReviewStage.business
        ? 'Business Team'
        : 'Recce Operations';

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AdinnAppBar(
          title: Text(context.uf('{0} Approvals', [context.ui(stage)])),
          bottom: TabBar(
            tabs: [
              Tab(text: context.uf('Pending ({0})', [pending.length])),
              Tab(text: context.uf('Reviewed ({0})', [reviewed.length])),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ShopList(
              shops: pending,
              empty: EmptyState(
                icon: Icons.inbox_outlined,
                title: context.ui('All caught up'),
                message: context.ui('No recce is waiting for your approval.'),
              ),
            ),
            _ShopList(
              shops: reviewed,
              empty: EmptyState(
                icon: Icons.history,
                title: context.ui('Nothing reviewed yet'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _VendorFilter { all, pending, rejected, approved }

class _VendorSubmissions extends StatefulWidget {
  const _VendorSubmissions();

  @override
  State<_VendorSubmissions> createState() => _VendorSubmissionsState();
}

class _VendorSubmissionsState extends State<_VendorSubmissions> {
  _VendorFilter _filter = _VendorFilter.all;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final all = c.mySubmissions;
    bool match(Shop s) => switch (_filter) {
      _VendorFilter.all => true,
      _VendorFilter.pending => s.status.isPending,
      _VendorFilter.rejected => s.status.isRejected,
      _VendorFilter.approved => s.status == RecceStatus.approved,
    };
    final shops = all.where(match).toList();
    int count(_VendorFilter f) {
      final prev = _filter;
      _filter = f;
      final n = all.where(match).length;
      _filter = prev;
      return n;
    }

    return Scaffold(
      appBar: AdinnAppBar(title: Text(context.ui('My Submissions'))),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                for (final f in _VendorFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        context.uf('{0} ({1})', [
                          context.ui(switch (f) {
                            _VendorFilter.all => 'All',
                            _VendorFilter.pending => 'In approval',
                            _VendorFilter.rejected => 'Rejected',
                            _VendorFilter.approved => 'Approved',
                          }),
                          count(f),
                        ]),
                      ),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _ShopList(
              shops: shops,
              empty: EmptyState(
                icon: Icons.outbox_outlined,
                title: context.ui('No submissions here'),
                message:
                    context.ui('Submitted recces and their approval status show here.'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShopList extends StatelessWidget {
  const _ShopList({required this.shops, required this.empty});

  final List<Shop> shops;
  final Widget empty;

  @override
  Widget build(BuildContext context) {
    if (shops.isEmpty) return empty;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: shops.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => ShopTile(shop: shops[i], showProject: true),
    );
  }
}
