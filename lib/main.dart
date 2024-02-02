import 'package:flutter/material.dart';

import 'app/priors.dart';

void main() async {
  await setupPriors();
  runApp(const MaterialApp(home: OriginOPerception()));
}
