import 'dart:math';
import 'package:flutter/material.dart';
import '../services/automotive_tool_service.dart';

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
  // Tọa độ trung tâm: Hannover, Đức (52.3759° N, 9.7320° E)
  int _zoom = 13;
  int _centerTileX = 4317;
  int _centerTileY = 2692;

  Offset _panOffset = Offset.zero;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _zoomIn() {
    if (_zoom < 16) {
      setState(() {
        _zoom++;
        _centerTileX = _centerTileX * 2;
        _centerTileY = _centerTileY * 2;
      });
    }
  }

  void _zoomOut() {
    if (_zoom > 11) {
      setState(() {
        _zoom--;
        _centerTileX = (_centerTileX / 2).floor();
        _centerTileY = (_centerTileY / 2).floor();
      });
    }
  }

  void _resetCenter() {
    setState(() {
      _zoom = 13;
      _centerTileX = 4317;
      _centerTileY = 2692;
      _panOffset = Offset.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          // 1. Lớp gạch bản đồ (Map Tiles Grid) có thể kéo rê (Pan)
          GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _panOffset += details.delta;
              });
            },
            child: Container(
              color: const Color(0xFF0F172A),
              child: Transform.translate(
                offset: _panOffset,
                child: _buildTileGrid(),
              ),
            ),
          ),

          // 2. Lớp vẽ tuyến đường dẫn đường neon & mũi tên xe
          IgnorePointer(
            child: CustomPaint(
              size: Size.infinite,
              painter: _NavigationRoutePainter(
                pulseValue: _pulseController.value,
                panOffset: _panOffset,
              ),
            ),
          ),

          // 3. Các điểm tiện ích trên bản đồ (POIs: Kaufland, Lidl, Shell)
          _buildPoiMarkers(),

          // 4. Biển báo tốc độ kiểu Đức (StVO 50 km/h) & La bàn
          Positioned(
            top: 14,
            left: 14,
            child: _buildSpeedLimitAndCompass(),
          ),

          // 5. Thanh hiển thị tên đường hiện tại
          Positioned(
            top: 14,
            right: 70,
            child: _buildStreetNameBanner(),
          ),

          // 6. Nút điều khiển bản đồ (+ / - / Vị trí / Mở Google Maps)
          Positioned(
            bottom: 14,
            right: 14,
            child: _buildMapControls(),
          ),
        ],
      ),
    );
  }

  Widget _buildTileGrid() {
    // Lưới 5x4 gạch bản đồ (mỗi ô 256x256 px)
    const int cols = 5;
    const int rows = 4;
    final int startX = _centerTileX - (cols ~/ 2);
    final int startY = _centerTileY - (rows ~/ 2);

    return SizedBox(
      width: cols * 256.0,
      height: rows * 256.0,
      child: Stack(
        children: [
          for (int r = 0; r < rows; r++)
            for (int c = 0; c < cols; c++)
              Positioned(
                left: c * 256.0,
                top: r * 256.0,
                width: 256.0,
                height: 256.0,
                child: Image.network(
                  'https://a.basemaps.cartocdn.com/dark_all/$_zoom/${startX + c}/${startY + r}.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        border: Border.all(color: Colors.white12, width: 0.5),
                      ),
                      child: const Center(
                        child: Icon(Icons.map_outlined, color: Colors.white24),
                      ),
                    );
                  },
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildPoiMarkers() {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Stack(
          children: [
            // Kaufland POI
            Positioned(
              left: 280 + _panOffset.dx,
              top: 120 + _panOffset.dy,
              child: _buildPoiBadge(
                name: 'Kaufland (1.8 km)',
                icon: Icons.shopping_cart_rounded,
                color: const Color(0xFFEF4444),
                onTap: () {
                  AutomotiveToolService.instance.openNavigation('Kaufland');
                  widget.onSelectPoi?.call('Kaufland');
                },
              ),
            ),

            // Lidl POI
            Positioned(
              left: 120 + _panOffset.dx,
              top: 220 + _panOffset.dy,
              child: _buildPoiBadge(
                name: 'Lidl Asia (1.2 km)',
                icon: Icons.shopping_basket_rounded,
                color: const Color(0xFFF59E0B),
                onTap: () {
                  AutomotiveToolService.instance.openNavigation('Lidl');
                  widget.onSelectPoi?.call('Lidl');
                },
              ),
            ),

            // Shell Tankstelle POI
            Positioned(
              left: 360 + _panOffset.dx,
              top: 240 + _panOffset.dy,
              child: _buildPoiBadge(
                name: 'Shell Cây xăng (800m)',
                icon: Icons.local_gas_station_rounded,
                color: const Color(0xFF10B981),
                onTap: () {
                  AutomotiveToolService.instance.openNavigation('Shell Tankstelle');
                  widget.onSelectPoi?.call('Shell Tankstelle');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPoiBadge({
    required String name,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A).withOpacity(0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.4),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeedLimitAndCompass() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Biển báo tốc độ 50 km/h của Đức (Vòng đỏ nền trắng)
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: const Color(0xFFDC2626), width: 4.5),
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
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Thẻ tốc độ & La bàn
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withOpacity(0.8),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.navigation_rounded, color: Color(0xFF38BDF8), size: 16),
              SizedBox(width: 6),
              Text(
                '0 km/h',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(width: 8),
              Text(
                '• NW',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withOpacity(0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.directions, color: Color(0xFF38BDF8), size: 16),
          SizedBox(width: 8),
          Text(
            'Hildesheimer Straße • Hannover',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12.5,
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
        // Nút Mở Google Maps app ngoài
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
            child: const Icon(Icons.launch_rounded, color: Colors.white, size: 20),
          ),
        ),

        // Nút Phóng to
        _buildCircleButton(
          icon: Icons.add,
          onPressed: _zoomIn,
        ),
        const SizedBox(height: 6),

        // Nút Thu nhỏ
        _buildCircleButton(
          icon: Icons.remove,
          onPressed: _zoomOut,
        ),
        const SizedBox(height: 6),

        // Nút Định vị về tâm
        _buildCircleButton(
          icon: Icons.my_location_rounded,
          onPressed: _resetCenter,
        ),
      ],
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required VoidCallback onPressed,
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
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

class _NavigationRoutePainter extends CustomPainter {
  final double pulseValue;
  final Offset panOffset;

  _NavigationRoutePainter({
    required this.pulseValue,
    required this.panOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.45 + panOffset.dx, size.height * 0.55 + panOffset.dy);

    // 1. Vẽ tuyến đường dẫn đường (Route line màu xanh ngọc phát sáng)
    final routePaintGlow = Paint()
      ..color = const Color(0xFF06B6D4).withOpacity(0.35)
      ..strokeWidth = 14
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final routePaint = Paint()
      ..color = const Color(0xFF22D3EE)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(center.dx, center.dy);
    path.lineTo(center.dx + 40, center.dy - 80);
    path.lineTo(center.dx + 120, center.dy - 130);
    path.lineTo(center.dx + 220, center.dy - 170);

    canvas.drawPath(path, routePaintGlow);
    canvas.drawPath(path, routePaint);

    // 2. Vòng radar phát sóng từ vị trí xe
    final pulsePaint = Paint()
      ..color = const Color(0xFF38BDF8).withOpacity(0.3 * (1 - pulseValue))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 24 + 18 * pulseValue, pulsePaint);

    // 3. Vòng tròn vị trí xe
    final puckPaint = Paint()
      ..color = const Color(0xFF0284C7)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 12, puckPaint);

    final innerPuck = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 5, innerPuck);

    // 4. Mũi tên hướng xe (3D Navigation Arrow)
    final arrowPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final arrowPath = Path();
    arrowPath.moveTo(center.dx, center.dy - 11);
    arrowPath.lineTo(center.dx - 6, center.dy + 7);
    arrowPath.lineTo(center.dx, center.dy + 3);
    arrowPath.lineTo(center.dx + 6, center.dy + 7);
    arrowPath.close();

    canvas.drawPath(arrowPath, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _NavigationRoutePainter oldDelegate) {
    return oldDelegate.pulseValue != pulseValue || oldDelegate.panOffset != panOffset;
  }
}
