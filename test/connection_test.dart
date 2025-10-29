import 'dart:convert';
import 'package:http/http.dart' as http;

Future<void> testConnection() async {
  try {
    print('🔄 Testing connection to server...');
    
    final response = await http.get(
      Uri.parse('http://16.171.208.249:5000/health'),
    ).timeout(const Duration(seconds: 10));
    
    print('✅ Status Code: ${response.statusCode}');
    print('✅ Body: ${response.body}');
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      print('✅ Message: ${data['message']}');
      print('🎉 CONNECTION SUCCESS!');
    }
  } catch (e) {
    print('❌ ERROR: $e');
  }
}

void main() {
  testConnection();
}
