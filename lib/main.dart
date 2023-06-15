import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_pwa_wrapper/push_notifications_manager.dart';

import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';

class SETTINGS {
  static const title = '깔로';
  static const url = 'https://kaloidea.com';
  // static const url = 'http://localhost:3000';
  static const shouldAskForPushPermission = true;

  static const nativeAppKey = "f420060fc11b4a95b51b8fb80681b6ad";
}

Future<void> main() async {
  KakaoSdk.init(nativeAppKey: SETTINGS.nativeAppKey);
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    return MaterialApp(
      theme: ThemeData(
        brightness: Brightness.light,
        // primaryColor: const Color(0xff4798ff),
        primaryColor: const Color(0xffffffff),
      ),
      title: SETTINGS.title,
      home: Scaffold(
        appBar: AppBar(
          // backgroundColor: const Color(0xff4798ff),
          // foregroundColor: const Color(0xff4798ff),
          backgroundColor: const Color(0xffffffff),
          foregroundColor: const Color(0xffffffff),
          elevation: 0,
          toolbarHeight: 0,
        ),
        body: const SafeArea(child: MyHomePage()),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late WebViewController webviewController;

  @override
  Widget build(BuildContext context) {
    /**
     * How to use in JS:
     * function setPushToken(token) { ... } // returns the device token
     * Notification.requestPermission()
     */
    void javaScriptFunction(JavaScriptMessage message) async {
      if (message.message == 'getPushToken') {
        var pnm = PushNotificationsManager.getInstance();
        if (SETTINGS.shouldAskForPushPermission) {
          await pnm.requestPermission();
        }
        final pushToken = await pnm.getToken();

        final script = "setPushToken(\"$pushToken\")";
        webviewController.runJavaScript(script);
      } else if (message.message == 'kakaoLogin') {
        debugPrint("카카오톡으로 로그인 성공");

        try {
          if (await isKakaoTalkInstalled()) {
            await UserApi.instance.loginWithKakaoTalk();
          } else {
            await UserApi.instance.loginWithKakaoAccount();
          }

          debugPrint("카카오톡으로 로그인 성공");
          User user = await UserApi.instance.me();

          Map<String, dynamic> data = {
            "id": user.id,
            "email": user.kakaoAccount?.email,
          };
          final script = """setKakaoUser({
            id: \"${user.id}\",
            email: \"${user.kakaoAccount?.email}\"
          })""";
          webviewController.runJavaScript(script);
          debugPrint(script);
        } catch (error) {
          debugPrint("카카오톡으로 로그인 실패 $error");
          final script = "setKakaoUser(\"$error\")";
          webviewController.runJavaScript(script);
        }
      }
    }

    launchURL(Uri uri) async {
      if (await canLaunchUrl(uri)) {
        try {
          await launchUrl(uri);
          // ignore: empty_catches
        } catch (e) {}
      }
    }

    webviewController = WebViewController()
      ..loadRequest(Uri.parse(SETTINGS.url))
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('flutterChannel',
          onMessageReceived: javaScriptFunction)
      ..setNavigationDelegate(NavigationDelegate(onPageFinished: (String url) {
        webviewController.runJavaScript("""
            window.Notification = {
              requestPermission: (callback) => {
                window.flutterChannel.postMessage('getPushToken');
                return callback ? callback('granted') : true;
              }
            };
          """);
      }, onNavigationRequest: (NavigationRequest request) {
        Uri uri = Uri.parse(request.url);

        if (request.isMainFrame && uri.host.contains("notion")) {
          launchURL(uri);
          return NavigationDecision.prevent;
        }

        // if (request.isMainFrame && uri.host.contains("kakao")) {
        //   launchURL(uri);
        //   return NavigationDecision.prevent;
        // }

        // if (!request.isMainFrame && uri.host.contains("kakao")) {
        //   return NavigationDecision.prevent;
        // }

        return NavigationDecision.navigate;
      }));

    PushNotificationsManager.getInstance()
        .init(webviewController, SETTINGS.shouldAskForPushPermission);

    return WebViewWidget(controller: webviewController);
  }
}
