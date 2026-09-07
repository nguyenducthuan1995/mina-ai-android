import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../services/automotive_tool_service.dart';
import '../config/api_keys.dart';

class AutomotiveMapView extends StatefulWidget {
  final VoidCallback? onOpenExternalMaps;
  final Function(String destination)? onSelectPoi;

  const AutomotiveMapView({
    super.key,
    this.onOpenExternalMaps,
    this.onSelectPoi,
  });

  @override
  State<AutomotiveMapView> createState() => _AutomotiveMapViewState();
}

class _AutomotiveMapViewState extends State<AutomotiveMapView>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();

  // Hannover, Đức — vị trí mặc định khi chưa có GPS
  LatLng _currentPosition = const LatLng(52.3759, 9.7320);
  double _currentSpeedKmh = 0.0;
  double _zoom = 15.0;
  bool _locationPermissionGranted = false;
  bool _isFollowingGps = true;
  StreamSubscription<Position>? _positionSubscription;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    // Delay GPS init 5s để WebSocket audio hoàn toàn kết nối trước, tránh xung đột
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) _initGps();
    });
  }

  Future<void> _initGps() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      if (!mounted) return;
      setState(() => _locationPermissionGranted = true);

      // Lấy vị trí hiện tại
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low, // dùng low để nhanh hơn
          ),
        );
        if (mounted) _updatePosition(pos);
      } catch (_) {}

      // Lắng nghe cập nhật liên tục
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10, // cập nhật mỗi 10m để tiết kiệm pin
        ),
      ).listen(
        _updatePosition,
        onError: (_) {}, // ignore stream errors
      );
    } catch (_) {
      // GPS không khả dụng, bỏ qua
    }
  }

  void _updatePosition(Position pos) {
    if (!mounted) return;
    setState(() {
      _currentPosition = LatLng(pos.latitude, pos.longitude);
      _currentSpeedKmh = (pos.speed * 3.6).clamp(0, 300); // m/s → km/h
    });
    if (_isFollowingGps) {
      _mapController.move(_currentPosition, _zoom);
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          // --- Lớp bản đồ FlutterMap ---
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition,
              initialZoom: _zoom,
              minZoom: 10,
              maxZoom: 18,
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture) {
                  setState(() => _isFollowingGps = false);
                }
                _zoom = camera.zoom;
              },
            ),
            children: [
              // Layer 1: TomTom Basic Map tiles — chất lượng cao, ngôn ngữ tiếng Đức
              // Free tier: 50,000 tiles/ngày — đủ dùng thoải mái
              TileLayer(
                urlTemplate:
                    'https://api.tomtom.com/map/1/tile/basic/main/{z}/{x}/{y}.png'
                    '?key=${ApiKeys.tomtom}&language=de&tileSize=256',
                userAgentPackageName: 'com.lhht.ai_assistant',
                retinaMode: MediaQuery.of(context).devicePixelRatio > 1,
                // Dùng OSM làm fallback nếu TomTom bị giới hạn
                fallbackUrl: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              ),

              // Layer 2: TomTom Traffic Flow overlay — tình trạng tắc đường thời gian thực
              // Màu xanh = thông thoáng, vàng = chậm, đỏ = tắc đường
              TileLayer(
                urlTemplate:
                    'https://api.tomtom.com/traffic/map/4/tile/flow/absolute/{z}/{x}/{y}.png'
                    '?key=${ApiKeys.tomtom}&tileSize=256',
                userAgentPackageName: 'com.lhht.ai_assistant',
                opacity: 0.7, // trong suốt để thấy bản đồ phía dưới
              ),

              // Marker vị trí xe hiện tại
              MarkerLayer(
                markers: [
                  Marker(
                    point: _currentPosition,
                    width: 60,
                    height: 60,
                    child: _buildCarMarker(),
                  ),
                ],
              ),

              // Các POI markers
              MarkerLayer(
                markers: _buildPoiMarkerList(),
              ),
            ],
          ),

          // --- Biển báo tốc độ + tốc độ GPS thực ---
          Positioned(
            top: 14,
            left: 14,
            child: _buildSpeedPanel(),
          ),

          // --- Thanh tên đường ---
          Positioned(
            top: 14,
            right: 70,
            child: _buildStreetNameBanner(),
          ),

          // --- Nút điều khiển bản đồ ---
          Positioned(
            bottom: 14,
            right: 14,
            child: _buildMapControls(),
          ),

          // --- Cảnh báo GPS chưa được cấp phép ---
          if (!_locationPermissionGranted)
            Positioned(
              bottom: 14,
              left: 14,
              child: _buildGpsWarning(),
            ),
        ],
      ),
    );
  }

  Widget _buildCarMarker() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (_, __) {
        final pulseSize = 24.0 + 14.0 * _pulseController.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            // Vòng radar phát sóng
            Container(
              width: pulseSize,
              height: pulseSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF38BDF8)
                    .withOpacity(0.3 * (1 - _pulseController.value)),
              ),
            ),
            // Chấm vị trí xe
            Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF0284C7),
              ),
            ),
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  List<Marker> _buildPoiMarkerList() {
    final pois = [
      _PoiData(
        position: const LatLng(52.3810, 9.7380),
        name: 'Kaufland',
        distanceText: '1.8 km',
        icon: Icons.shopping_cart_rounded,
        color: const Color(0xFFEF4444),
      ),
      _PoiData(
        position: const LatLng(52.3700, 9.7450),
        name: 'Lidl',
        distanceText: '1.2 km',
        icon: Icons.shopping_basket_rounded,
        color: const Color(0xFFF59E0B),
      ),
      _PoiData(
        position: const LatLng(52.3720, 9.7220),
        name: 'Shell',
        distanceText: '800 m',
        icon: Icons.local_gas_station_rounded,
        color: const Color(0xFF10B981),
      ),
    ];

    return pois.map((poi) {
      return Marker(
        point: poi.position,
        width: 150,
        height: 44,
        child: GestureDetector(
          onTap: () {
            AutomotiveToolService.instance.openNavigation(poi.name);
            widget.onSelectPoi?.call(poi.name);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withOpacity(0.9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: poi.color, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: poi.color.withOpacity(0.4),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(poi.icon, color: poi.color, size: 14),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    '${poi.name} • ${poi.distanceText}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildSpeedPanel() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Biển giới hạn tốc độ 50 km/h kiểu Đức (StVO)
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: const Color(0xFFDC2626), width: 5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Center(
            child: Text(
              '50',
              style: TextStyle(
                color: Colors.black,
                fontSize: 17,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Tốc độ GPS thực
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withOpacity(0.85),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.speed_rounded,
                  color: Color(0xFF38BDF8), size: 16),
              const SizedBox(width: 6),
              Text(
                '${_currentSpeedKmh.toStringAsFixed(0)} km/h',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStreetNameBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withOpacity(0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.directions, color: Color(0xFF38BDF8), size: 15),
          SizedBox(width: 6),
          Text(
            'Hildesheimer Str. • Hannover',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Mở Google Maps ngoài
        GestureDetector(
          onTap: () {
            AutomotiveToolService.instance.openNavigation('');
            widget.onOpenExternalMaps?.call();
          },
          child: Container(
            padding: const EdgeInsets.all(9),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2563EB).withOpacity(0.5),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(Icons.launch_rounded,
                color: Colors.white, size: 20),
          ),
        ),

        _buildCircleButton(
          icon: Icons.add,
          onPressed: () {
            _zoom = (_zoom + 1).clamp(10, 18);
            _mapController.move(_currentPosition, _zoom);
          },
        ),
        const SizedBox(height: 6),

        _buildCircleButton(
          icon: Icons.remove,
          onPressed: () {
            _zoom = (_zoom - 1).clamp(10, 18);
            _mapController.move(_currentPosition, _zoom);
          },
        ),
        const SizedBox(height: 6),

        _buildCircleButton(
          icon: _isFollowingGps
              ? Icons.my_location_rounded
              : Icons.location_searching_rounded,
          color: _isFollowingGps ? const Color(0xFF38BDF8) : Colors.white,
          onPressed: () {
            setState(() => _isFollowingGps = true);
            _mapController.move(_currentPosition, _zoom);
          },
        ),
      ],
    );
  }

  Widget _buildGpsWarning() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF92400E).withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF59E0B), width: 1),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_off_rounded,
              color: Color(0xFFFBBF24), size: 14),
          SizedBox(width: 6),
          Text(
            'GPS chưa được cấp phép',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required VoidCallback onPressed,
    Color color = Colors.white,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B).withOpacity(0.9),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }
}

class _PoiData {
  final LatLng position;
  final String name;
  final String distanceText;
  final IconData icon;
  final Color color;

  const _PoiData({
    required this.position,
    required this.name,
    required this.distanceText,
    required this.icon,
    required this.color,
  });
}

