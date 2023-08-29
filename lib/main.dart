import 'package:flutter/material.dart';

import 'priors.dart';

void main() async {
  await setupPriors();
  runApp(const MaterialApp(home: AstroBase()));
}
