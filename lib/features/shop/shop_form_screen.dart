import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import '../location/gps_widgets.dart';

/// Add a new shop to a task, or edit an existing shop's details.
class ShopFormScreen extends StatefulWidget {
  const ShopFormScreen({super.key, required this.taskId, this.shopId});

  final String taskId;
  final String? shopId;

  @override
  State<ShopFormScreen> createState() => _ShopFormScreenState();
}

class _ShopFormScreenState extends State<ShopFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _f;

  static const _keys = [
    'name',
    'owner',
    'phone',
    'address',
    'area',
    'city',
    'pincode',
    'landmark',
    'remarks',
  ];

  @override
  void initState() {
    super.initState();
    final c = context.read<AppController>();
    final shop = widget.shopId == null ? null : c.shop(widget.shopId!);
    final task = c.task(widget.taskId);
    final values = <String, String>{
      'name': shop?.name ?? '',
      'owner': shop?.ownerName ?? '',
      'phone': shop?.phone ?? '',
      'address': shop?.address ?? '',
      'area': shop?.area ?? task?.location ?? '',
      'city': shop?.city ?? task?.city ?? '',
      'pincode': shop?.pincode ?? '',
      'landmark': shop?.landmark ?? '',
      'remarks': shop?.remarks ?? '',
    };
    _f = {for (final k in _keys) k: TextEditingController(text: values[k])};
    _geo = shop?.geo;
  }

  /// GPS captured in this form (saved with the shop).
  GeoFix? _geo;

  Future<void> _captureGps() async {
    final fix = await captureGps(context);
    if (fix != null && mounted) setState(() => _geo = fix);
  }

  @override
  void dispose() {
    for (final c in _f.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _v(String k) => _f[k]!.text.trim();

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final c = context.read<AppController>();
    final task = c.task(widget.taskId)!;
    if (widget.shopId == null) {
      final created = c.createShop(
        task,
        Shop(
          id: '',
          projectId: task.projectId,
          taskId: task.id,
          name: _v('name'),
          ownerName: _v('owner'),
          phone: _v('phone'),
          address: _v('address'),
          area: _v('area'),
          city: _v('city'),
          pincode: _v('pincode'),
          landmark: _v('landmark'),
          remarks: _v('remarks'),
          geo: _geo,
        ),
      );
      showSnack(context, '${created.name} added');
      Navigator.of(context).pop(created);
    } else {
      final shop = c.shop(widget.shopId!)!;
      shop
        ..name = _v('name')
        ..ownerName = _v('owner')
        ..phone = _v('phone')
        ..address = _v('address')
        ..area = _v('area')
        ..city = _v('city')
        ..pincode = _v('pincode')
        ..landmark = _v('landmark')
        ..remarks = _v('remarks')
        ..geo = _geo;
      c.touchShop(
        shop,
        title: 'Shop details updated',
        message: '${shop.name} details edited.',
      );
      showSnack(context, 'Shop details saved');
      Navigator.of(context).pop(shop);
    }
  }

  Widget _field(
    String key,
    String label, {
    IconData? icon,
    bool required = false,
    TextInputType? keyboard,
    int? maxLength,
    int maxLines = 1,
    String? Function(String)? extra,
    List<TextInputFormatter>? formatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        key: Key('shop_$key'),
        controller: _f[key],
        keyboardType: keyboard,
        maxLength: maxLength,
        maxLines: maxLines,
        inputFormatters: formatters,
        textCapitalization: keyboard == null
            ? TextCapitalization.words
            : TextCapitalization.none,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          prefixIcon: icon == null ? null : Icon(icon),
          counterText: '',
        ),
        validator: (raw) {
          final v = (raw ?? '').trim();
          if (required && v.isEmpty) return '$label is required';
          if (v.isNotEmpty && extra != null) return extra(v);
          return null;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.shopId != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit Shop' : 'Add Shop')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _field(
                'name',
                'Shop name',
                icon: Icons.storefront,
                required: true,
              ),
              _field(
                'owner',
                'Owner / contact person',
                icon: Icons.person_outline,
              ),
              _field(
                'phone',
                'Contact number',
                icon: Icons.phone_outlined,
                required: true,
                keyboard: TextInputType.phone,
                maxLength: 10,
                formatters: [FilteringTextInputFormatter.digitsOnly],
                extra: (v) =>
                    v.length == 10 ? null : 'Enter a 10-digit mobile number',
              ),
              _field(
                'address',
                'Door no. & street',
                icon: Icons.home_work_outlined,
                required: true,
                maxLines: 2,
              ),
              _field('area', 'Area / locality', icon: Icons.map_outlined),
              _field('city', 'City', icon: Icons.location_city_outlined),
              _field(
                'pincode',
                'Pincode',
                icon: Icons.pin_drop_outlined,
                keyboard: TextInputType.number,
                maxLength: 6,
                formatters: [FilteringTextInputFormatter.digitsOnly],
                extra: (v) => v.length == 6 ? null : 'Pincode must be 6 digits',
              ),
              _field('landmark', 'Landmark', icon: Icons.flag_outlined),
              _field(
                'remarks',
                'General remarks',
                icon: Icons.notes_outlined,
                maxLines: 3,
              ),
              Card(
                child: ListTile(
                  leading: Icon(
                    _geo == null ? Icons.location_searching : Icons.my_location,
                    color: _geo == null
                        ? AdinnColors.muted
                        : AdinnColors.success,
                  ),
                  title: Text(
                    _geo == null ? 'Shop GPS location' : _geo!.coordinates,
                  ),
                  subtitle: Text(
                    _geo == null
                        ? 'Required before submission – capture at the shop'
                        : '±${_geo!.accuracyM.round()} m • '
                              '${fmtDateTime(_geo!.capturedAt)}',
                  ),
                  trailing: TextButton(
                    key: const Key('form_capture_gps'),
                    onPressed: _captureGps,
                    child: Text(_geo == null ? 'CAPTURE' : 'RECAPTURE'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                key: const Key('shop_save'),
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(editing ? 'SAVE CHANGES' : 'ADD SHOP'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
