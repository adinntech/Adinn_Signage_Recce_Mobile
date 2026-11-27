import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/utils/gst.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';
import '../../state/app_controller.dart';

/// Optional shop-level GST number. One value for the whole shop: every media
/// group shows (and edits) the same field. Empty never blocks completion; a
/// non-empty value is only format-checked.
class GstField extends StatefulWidget {
  const GstField({super.key, required this.shop, required this.enabled});

  final Shop shop;
  final bool enabled;

  @override
  State<GstField> createState() => _GstFieldState();
}

class _GstFieldState extends State<GstField> {
  late final TextEditingController _c = TextEditingController(
    text: widget.shop.gstNumber,
  );
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _changed(String v) {
    final err = Gst.error(v);
    setState(() => _error = err);
    // Only a valid (or empty) value is stored; an invalid draft stays in the
    // field without overwriting the saved number.
    if (err == null) context.read<AppController>().setShopGst(widget.shop, v);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      key: const Key('gst_field'),
      controller: _c,
      enabled: widget.enabled,
      textCapitalization: TextCapitalization.characters,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 ]')),
        LengthLimitingTextInputFormatter(20),
      ],
      decoration: InputDecoration(
        labelText: context.t.gstLabel,
        helperText: context.ui('Shop-level. Format check only – not a registration check.'),
        isDense: true,
        errorText: _error,
      ),
      onChanged: _changed,
    ),
  );
}
