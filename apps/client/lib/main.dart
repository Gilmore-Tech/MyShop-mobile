import 'package:flutter/material.dart';
import 'src/app/client_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // TODO: Initialize Firebase, secure storage, etc.
  runApp(const ClientApp());
}
