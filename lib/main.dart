
import 'package:flutter/material.dart';
import 'package:id_verification_app/videoToText.dart';
void main() {
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    //home: VerifyDocScreen(),
    home: videoToText(),
    theme: ThemeData(
      primarySwatch: Colors.blue,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    ),
  ));
}

