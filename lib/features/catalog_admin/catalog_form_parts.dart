import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../live_recce/data/catalog_data.dart';

/// Pieces shared by the media, installation and question forms of the admin: the page with its save bar, the icon picker and the colour field.

/// One form page: title, the fields, a banner for the answer of the server (the page scrolls up to it), and a Save button that stays in view.
/// The fields sit in one scroll view (not a lazy list), so every field exists while the page is open.
class CatalogFormPage extends StatefulWidget {
  const CatalogFormPage({super.key, required this.title, required this.formKey, required this.children, required this.busy, required this.onSave, this.error, this.saveLabel = 'Save'});

  final String title;
  final GlobalKey<FormState> formKey;
  final List<Widget> children;
  final bool busy;
  final VoidCallback onSave;
  final String? error;
  final String saveLabel;

  @override
  State<CatalogFormPage> createState() => _CatalogFormPageState();
}

class _CatalogFormPageState extends State<CatalogFormPage> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(CatalogFormPage old) {
    super.didUpdateWidget(old);
    // A new message sits at the top of the page: bring it into view.
    if (widget.error != null && widget.error != old.error && _scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.error;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: Form(
        key: widget.formKey,
        child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (error != null)
                Container(
                  key: const Key('form-error'),
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AdinnColors.redLight, borderRadius: BorderRadius.circular(12), border: Border.all(color: AdinnColors.red.withValues(alpha: 0.4))),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.error_outline, color: AdinnColors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(error, style: const TextStyle(color: AdinnColors.redDark, fontWeight: FontWeight.w600))),
                  ]),
                ),
              ...widget.children,
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            key: const Key('form-save'),
            onPressed: widget.busy ? null : widget.onSave,
            icon: widget.busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check),
            label: Text(widget.saveLabel),
          ),
        ),
      ),
    );
  }
}

class FormLabel extends StatelessWidget {
  const FormLabel(this.text, {super.key, this.hint});
  final String text;
  final String? hint;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
          if (hint != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(hint!, style: const TextStyle(color: AdinnColors.muted, fontSize: 12.5))),
        ]),
      );
}

/// The icon list the server accepts (`catalogIcons`): one tap picks one.
class CatalogIconPicker extends StatelessWidget {
  const CatalogIconPicker({super.key, required this.selected, required this.onChanged, this.color = AdinnColors.red});

  final String selected;
  final ValueChanged<String> onChanged;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in catalogIcons.entries)
          Semantics(
            button: true,
            selected: e.key == selected,
            label: e.key.replaceAll('_', ' '),
            child: InkWell(
              key: Key('icon-${e.key}'),
              borderRadius: BorderRadius.circular(12),
              onTap: () => onChanged(e.key),
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: e.key == selected ? color.withValues(alpha: 0.12) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: e.key == selected ? color : AdinnColors.line, width: e.key == selected ? 2 : 1),
                ),
                child: Icon(e.value, color: e.key == selected ? color : AdinnColors.muted),
              ),
            ),
          ),
      ],
    );
  }
}

const catalogSwatches = ['#D71920', '#E37400', '#C2185B', '#7B1FA2', '#283593', '#1A73E8', '#00838F', '#1E8E3E', '#6D4C41', '#455A64'];

final _hex = RegExp(r'^#[0-9A-Fa-f]{6}$');
bool isHexColor(String v) => _hex.hasMatch(v.trim());

/// Colour of a media type: ten swatches and a `#RRGGBB` box (checked as typed).
class CatalogColorField extends StatelessWidget {
  const CatalogColorField({super.key, required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final current = controller.text.trim().toUpperCase();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in catalogSwatches)
          InkWell(
            key: Key('swatch-$s'),
            customBorder: const CircleBorder(),
            onTap: () {
              controller.text = s;
              onChanged();
            },
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: hexColor(s), shape: BoxShape.circle, border: Border.all(color: current == s ? AdinnColors.ink : Colors.transparent, width: 3)),
              child: current == s ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
            ),
          ),
      ]),
      const SizedBox(height: 10),
      TextFormField(
        key: const Key('f-color'),
        controller: controller,
        textCapitalization: TextCapitalization.characters,
        autocorrect: false,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp('[#0-9A-Fa-f]')),
          TextInputFormatter.withFunction((o, n) => n.copyWith(text: n.text.toUpperCase())),
          LengthLimitingTextInputFormatter(7),
        ],
        decoration: InputDecoration(
          labelText: 'Colour (#RRGGBB) *',
          prefixIcon: Padding(padding: const EdgeInsets.all(12), child: Container(width: 22, height: 22, decoration: BoxDecoration(color: isHexColor(controller.text) ? hexColor(controller.text) : AdinnColors.line, shape: BoxShape.circle))),
        ),
        validator: (v) => isHexColor(v ?? '') ? null : 'Use a colour like #D71920',
        onChanged: (_) => onChanged(),
      ),
    ]);
  }
}
