import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saole/src/services/platform/wifi_connect.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('saole/wifi');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test('connect 把 ssid/password/security/hidden 传给原生', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return true;
    });

    final ok = await const WifiConnect().connect(
      ssid: 'Net', password: 'pw', security: 'WPA', hidden: false,
    );

    expect(ok, true);
    expect(received?.method, 'connect');
    expect(received?.arguments, {
      'ssid': 'Net', 'password': 'pw', 'security': 'WPA', 'hidden': false,
    });
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('原生抛 PlatformException 时返回 false，不抛', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'ERR');
    });
    final ok = await const WifiConnect()
        .connect(ssid: 'N', password: '', security: 'nopass', hidden: false);
    expect(ok, false);
    messenger.setMockMethodCallHandler(channel, null);
  });
}
