import 'package:flutter/services.dart';

/// The Android runner's channel for handing a web address to the browser the
/// user has chosen.
const MethodChannel androidBrowserChannel = MethodChannel(
  'cn.hnasct.local_transfer/browser',
);

/// The one method that channel implements.
const String openUrlMethod = 'openUrl';

/// Opens [url] with Android's default browser, answering whether anything
/// took it.
///
/// Every failure — a platform that never registered the channel, a malformed
/// address, no browser installed — is false, because the caller's answer to
/// all of them is the same: the address stays on screen to be copied by hand.
Future<bool> openAndroidLink(String url) async {
  try {
    final answer = await androidBrowserChannel.invokeMethod<bool>(
      openUrlMethod,
      <String, Object?>{'url': url},
    );
    return answer ?? false;
  } on Object {
    return false;
  }
}
