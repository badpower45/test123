import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> saveFile(List<int> bytes, String fileName) async {
  final tempDir = await getTemporaryDirectory();
  final tempFile = File('${tempDir.path}/$fileName');
  await tempFile.writeAsBytes(bytes);
  
  await Share.shareXFiles(
    [XFile(tempFile.path)],
    subject: 'تقرير المبيعات والرواتب',
  );
}
