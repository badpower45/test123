import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../theme/app_colors.dart';

class BranchLocationPickerScreen extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;
  final double initialRadius;

  const BranchLocationPickerScreen({
    Key? key,
    this.initialLatitude,
    this.initialLongitude,
    this.initialRadius = 100,
  }) : super(key: key);

  @override
  State<BranchLocationPickerScreen> createState() => _BranchLocationPickerScreenState();
}

class _BranchLocationPickerScreenState extends State<BranchLocationPickerScreen> {
  GoogleMapController? _mapController;
  late LatLng _center;
  double _radius = 100;
  bool _isLoading = false;
  
  Set<Marker> _markers = {};
  Set<Circle> _circles = {};

  @override
  void initState() {
    super.initState();
    _radius = widget.initialRadius;
    
    // Initialize with passed coordinates or default to Cairo
    _center = LatLng(
      widget.initialLatitude ?? 30.0444,
      widget.initialLongitude ?? 31.2357,
    );
    _updateMapElements();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  void _updateMapElements() {
    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('branch_marker'),
          position: _center,
          draggable: true,
          onDragEnd: (newPosition) {
            setState(() {
              _center = newPosition;
            });
            _updateMapElements();
          },
        ),
      };
      
      _circles = {
        Circle(
          circleId: const CircleId('branch_geofence'),
          center: _center,
          radius: _radius,
          fillColor: AppColors.primaryOrange.withOpacity(0.15),
          strokeColor: AppColors.primaryOrange,
          strokeWidth: 2,
        ),
      };
    });
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLoading = true);
    
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      final newCenter = LatLng(position.latitude, position.longitude);
      
      setState(() {
        _center = newCenter;
        _isLoading = false;
      });
      
      _updateMapElements();
      
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: newCenter, zoom: 16),
        ),
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم تحديد موقعك الحالي ✓\n'
              'الدقة: ${position.accuracy.toStringAsFixed(1)}م',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحديد الموقع: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onMapTap(LatLng point) {
    setState(() {
      _center = point;
    });
    _updateMapElements();
  }

  void _saveLocation() {
    Navigator.pop(context, {
      'latitude': _center.latitude,
      'longitude': _center.longitude,
      'radius': _radius,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('حدد موقع الفرع'),
        backgroundColor: AppColors.primaryOrange,
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _saveLocation,
            tooltip: 'حفظ',
          ),
        ],
      ),
      body: Stack(
        children: [
          // Google Map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _center,
              zoom: 16,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
            },
            onTap: _onMapTap,
            markers: _markers,
            circles: _circles,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: true,
          ),

          // Loading overlay
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),

          // Bottom control panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Info display
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'الإحداثيات المحددة',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'خط العرض: ${_center.latitude.toStringAsFixed(7)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        Text(
                          'خط الطول: ${_center.longitude.toStringAsFixed(7)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Radius control
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'نطاق المنطقة المسموحة',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primaryOrange,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_radius.toInt()} متر',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  Slider(
                    value: _radius,
                    min: 50,
                    max: 500,
                    divisions: 45,
                    activeColor: AppColors.primaryOrange,
                    onChanged: (value) {
                      setState(() => _radius = value);
                      _updateMapElements();
                    },
                  ),
                  
                  // Quick select buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildRadiusButton(50),
                      _buildRadiusButton(100),
                      _buildRadiusButton(200),
                      _buildRadiusButton(300),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _getCurrentLocation,
                          icon: const Icon(Icons.my_location, size: 20),
                          label: const Text('موقعي الحالي'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade200,
                            foregroundColor: Colors.black87,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _saveLocation,
                          icon: const Icon(Icons.check, size: 20),
                          label: const Text('حفظ الموقع'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryOrange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 8),
                  
                  Text(
                    'اضغط على الخريطة لتحديد الموقع أو اسحب العلامة',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),

          // Instruction overlay (top)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.primaryOrange, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'اضغط على الخريطة لتغيير الموقع',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRadiusButton(int radius) {
    final isSelected = _radius == radius.toDouble();
    return InkWell(
      onTap: () {
        setState(() => _radius = radius.toDouble());
        _updateMapElements();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryOrange : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primaryOrange : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Text(
          '${radius}م',
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey.shade700,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
