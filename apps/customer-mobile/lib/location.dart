import 'package:geolocator/geolocator.dart';

/// Resolves the customer's location automatically (browser/device GPS) with a
/// graceful Sydney fallback, so the home never asks the user to type coordinates.
class GmLocation {
  GmLocation._();
  static final GmLocation instance = GmLocation._();

  static const double sydneyLat = -33.8688;
  static const double sydneyLng = 151.2093;

  double lat = sydneyLat;
  double lng = sydneyLng;
  String label = 'Sydney NSW';
  bool resolved = false;

  /// Resolve once. The WHOLE flow (permission + fix) is time-boxed so a stalled
  /// permission prompt can never block the home from loading; we fall back to Sydney.
  Future<void> ensure({bool force = false}) async {
    if (resolved && !force) return;
    try {
      await _resolve().timeout(const Duration(seconds: 6));
    } catch (_) {
      _fallback();
    }
  }

  Future<void> _resolve() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      _fallback();
      return;
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
    );
    lat = pos.latitude;
    lng = pos.longitude;
    label = 'Your location';
    resolved = true;
  }

  void _fallback() {
    lat = sydneyLat;
    lng = sydneyLng;
    label = 'Sydney NSW';
    resolved = true;
  }
}
