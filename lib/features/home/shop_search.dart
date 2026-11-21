import 'package:flutter/material.dart';

import '../../core/widgets/common_widgets.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import '../shop/shop_tile.dart';

/// Shops visible to the user matching [query] (name, owner, area, city,
/// pincode, project or task).
List<Shop> searchShops(AppController c, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  return c.visibleShops.where((s) {
    final project = c.project(s.projectId);
    final task = c.task(s.taskId);
    return [
      s.name,
      s.ownerName,
      s.area,
      s.city,
      s.pincode,
      s.landmark,
      project?.name ?? '',
      project?.code ?? '',
      task?.title ?? '',
    ].any((f) => f.toLowerCase().contains(q));
  }).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
}

/// Search across every shop of every visible task.
class ShopSearchDelegate extends SearchDelegate<void> {
  ShopSearchDelegate(this.controller)
    : super(searchFieldLabel: 'Shop, owner, area, project…');

  final AppController controller;

  @override
  List<Widget> buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        tooltip: 'Clear',
        icon: const Icon(Icons.clear),
        onPressed: () => query = '',
      ),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    tooltip: 'Back',
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );

  Widget _list(BuildContext context) {
    if (query.trim().isEmpty) {
      return const EmptyState(
        icon: Icons.search,
        title: 'Search shops',
        message: 'Type a shop name, owner, area, city or project.',
      );
    }
    final shops = searchShops(controller, query);
    if (shops.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: 'No shops match "$query"',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: shops.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => ShopTile(shop: shops[i], showProject: true),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _list(context);

  @override
  Widget buildSuggestions(BuildContext context) => _list(context);
}
