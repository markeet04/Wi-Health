import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

/// Plays a Lottie animation from assets/lottie/ if the file exists,
/// otherwise renders [fallback]. This lets the team drop animations from
/// lottiefiles.com into assets/lottie/ without touching code:
///
///   assets/lottie/onboard_breathe.json
///   assets/lottie/onboard_family.json
///   assets/lottie/onboard_alerts.json
///   assets/lottie/auth.json
class LottieBox extends StatelessWidget {
  const LottieBox({
    super.key,
    required this.asset,
    required this.fallback,
    this.size = 200,
  });

  /// e.g. 'assets/lottie/onboard_breathe.json'
  final String asset;
  final Widget fallback;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: FutureBuilder<ByteData?>(
        future: _tryLoad(context),
        builder: (context, snap) {
          if (snap.hasData && snap.data != null) {
            return Lottie.memory(
              snap.data!.buffer.asUint8List(),
              fit: BoxFit.contain,
              repeat: true,
            );
          }
          return Center(child: fallback);
        },
      ),
    );
  }

  Future<ByteData?> _tryLoad(BuildContext context) async {
    try {
      return await DefaultAssetBundle.of(context).load(asset);
    } catch (_) {
      return null; // Asset not bundled — use the fallback.
    }
  }
}
