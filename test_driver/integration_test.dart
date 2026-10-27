import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

// Writes each PNG the capture test reports to build/captures/<name>.
Future<void> main() => integrationDriver(
  writeResponseOnFailure: true,
  responseDataCallback: (data) async {
    if (data == null) return;
    final dir = Directory('build/captures')..createSync(recursive: true);
    data.forEach((name, value) {
      if (value is String) {
        File('${dir.path}/$name').writeAsBytesSync(base64Decode(value));
      }
    });
  },
);
