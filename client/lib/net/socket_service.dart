import 'dart:async';
import 'dart:convert';
import 'dart:io';

// 薄封裝:JSON編解碼 + 收訊事件流。連線細節(identify/重連)交給上層 GameController,
// 這裡只負責「送得出去、收得到」。
class SocketService {
  WebSocket? _ws;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  final _doneController = StreamController<void>.broadcast();

  Stream<Map<String, dynamic>> get messages => _controller.stream;
  Stream<void> get onDone => _doneController.stream;
  bool get isConnected => _ws != null;

  Future<void> connect(String url) async {
    final ws = await WebSocket.connect(url).timeout(const Duration(seconds: 8));
    _ws = ws;
    ws.listen(
      (raw) {
        if (_controller.isClosed) return; // dispose() 後可能還有殘留訊息飛進來
        try {
          final decoded = jsonDecode(raw as String);
          if (decoded is Map<String, dynamic>) _controller.add(decoded);
        } catch (_) {
          // 忽略無法解析的訊息
        }
      },
      onDone: () {
        _ws = null;
        if (!_doneController.isClosed) _doneController.add(null);
      },
      onError: (_) {
        _ws = null;
        if (!_doneController.isClosed) _doneController.add(null);
      },
      cancelOnError: true,
    );
  }

  void send(String type, [Map<String, dynamic> payload = const {}]) {
    final ws = _ws;
    if (ws == null) return;
    ws.add(jsonEncode({"type": type, ...payload}));
  }

  void close() {
    _ws?.close();
    _ws = null;
  }

  void dispose() {
    close();
    _controller.close();
    _doneController.close();
  }
}
