import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/models/models.dart';
import '../../data/services/location_service.dart';
import '../../state/app_controller.dart';

LocationService locationServiceOf(BuildContext context) {
  try {
    return context.read<LocationService>();
  } on ProviderNotFoundException {
    return DeviceLocationService();
  }
}

/// Gets a GPS fix with a blocking progress dialog. Shows a snack (with a
/// Settings action where useful) and returns null when it fails.
Future<GeoFix?> captureGps(BuildContext context) async {
  final service = locationServiceOf(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(width: 16),
            Expanded(child: Text('Getting GPS location…')),
          ],
        ),
      ),
    ),
  );
  try {
    final fix = await service.currentFix();
    navigator.pop();
    return fix;
  } on LocationException catch (e) {
    navigator.pop();
    if (context.mounted) _showLocationError(context, service, e);
    return null;
  } catch (e) {
    navigator.pop();
    if (context.mounted) {
      showSnack(context, 'Could not read GPS: $e', error: true);
    }
    return null;
  }
}

void _showLocationError(
  BuildContext context,
  LocationService service,
  LocationException e,
) {
  final settings =
      e.issue == LocationIssue.serviceDisabled ||
      e.issue == LocationIssue.permissionDeniedForever;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(e.message),
        backgroundColor: AdinnColors.redDark,
        action: settings
            ? SnackBarAction(
                label: 'SETTINGS',
                textColor: Colors.white,
                onPressed: () => service.openSettings(
                  appSettings: e.issue == LocationIssue.permissionDeniedForever,
                ),
              )
            : null,
      ),
    );
}

/// Opens the location in the phone's maps app (no maps SDK / API key used).
Future<void> openInMaps(BuildContext context, GeoFix g, String label) async {
  final lat = g.latitude.toStringAsFixed(6);
  final lng = g.longitude.toStringAsFixed(6);
  final q = Uri.encodeComponent('$lat,$lng($label)');
  final geoUri = Uri.parse('geo:$lat,$lng?q=$q');
  final webUri = Uri.parse(
    'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
  );
  var ok = false;
  try {
    ok = await launchUrl(geoUri);
  } catch (_) {
    ok = false;
  }
  if (!ok) {
    try {
      ok = await launchUrl(webUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
  }
  if (!ok && context.mounted) {
    showSnack(context, 'No maps app available on this device', error: true);
  }
}

/// Card showing a shop's GPS location with capture / open-in-maps actions.
class ShopLocationCard extends StatelessWidget {
  const ShopLocationCard({
    super.key,
    required this.shop,
    required this.editable,
  });

  final Shop shop;
  final bool editable;

  Future<void> _capture(BuildContext context) async {
    final fix = await captureGps(context);
    if (fix == null || !context.mounted) return;
    context.read<AppController>().setShopLocation(shop, fix);
    showSnack(
      context,
      'GPS captured: ${fix.coordinates} (±${fix.accuracyM.round()} m)',
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = shop.geo;
    final warnings = context.read<AppController>().shopWarnings(shop);
    return SectionCard(
      title: 'Shop location (GPS)',
      icon: Icons.my_location,
      trailing: g == null
          ? const TagChip(
              'Required',
              color: AdinnColors.red,
              icon: Icons.error_outline,
            )
          : const TagChip(
              'Captured',
              color: AdinnColors.success,
              icon: Icons.check_circle,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (g == null)
            Text(
              editable
                  ? 'Stand at the shop front and capture the GPS location. '
                        'It is required before submission.'
                  : 'GPS location not captured.',
              style: const TextStyle(color: AdinnColors.muted, fontSize: 13),
            )
          else
            GeoDetails(geo: g),
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 6),
            IssueList(items: warnings, warning: true),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (editable)
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('capture_gps'),
                    onPressed: () => _capture(context),
                    icon: const Icon(Icons.gps_fixed),
                    label: Text(g == null ? 'Capture GPS' : 'Recapture'),
                  ),
                ),
              if (editable && g != null) const SizedBox(width: 8),
              if (g != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => openInMaps(context, g, shop.name),
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Open in Maps'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Coordinates, accuracy and capture time of a GPS fix.
class GeoDetails extends StatelessWidget {
  const GeoDetails({super.key, required this.geo});

  final GeoFix geo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoRow('Coordinates', geo.coordinates, icon: Icons.place_outlined),
        InfoRow(
          'Accuracy',
          '±${geo.accuracyM.round()} m',
          icon: Icons.gps_not_fixed,
        ),
        InfoRow(
          'Captured at',
          fmtDateTime(geo.capturedAt),
          icon: Icons.schedule,
        ),
      ],
    );
  }
}
