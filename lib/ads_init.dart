// lib/ads_init.dart
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// AdMob を初期化
Future<void> initAds() async {
  // アプリIDは AndroidManifest.xml / Info.plist に記載するので、ここでは initialize だけでOK
  await MobileAds.instance.initialize();
  // もしテスト端末を追加したい場合（本番は不要）
  // await MobileAds.instance.updateRequestConfiguration(RequestConfiguration(
  //   testDeviceIds: ['YOUR_TEST_DEVICE_ID'],
  // ));
}
