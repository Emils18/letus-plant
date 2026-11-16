import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class MspReply {
  const MspReply(this.command, this.payload);

  final int command;
  final Uint8List payload;
}

/// Read-only MSP v1 transport for the project's UDP/TCP ESP32 bridge.
/// The bridge protocol and command path must still be confirmed on hardware.
class InavDiagnosticsService {
  static const int discoveryPort = 4210;
  static const int tcpPort = 5000;
  static const String discoveryMessage = 'DRONE_DISCOVER';

  RawDatagramSocket? _discoverySocket;
  Socket? _socket;
  StreamSubscription<Uint8List>? _subscription;
  Completer<MspReply>? _pendingReply;
  int? _pendingCommand;
  final List<int> _buffer = <int>[];
  bool _disposed = false;

  bool get connected => _socket != null;

  static Uint8List encodeRequest(int command, [List<int> payload = const []]) {
    if (command < 0 || command > 255 || payload.length > 255) {
      throw ArgumentError('MSP v1 command/payload is out of range.');
    }
    final bytes = <int>[0x24, 0x4d, 0x3c, payload.length, command, ...payload];
    var checksum = 0;
    for (final byte in bytes.skip(3)) {
      checksum ^= byte;
    }
    bytes.add(checksum);
    return Uint8List.fromList(bytes);
  }

  /// Returns the first valid MSP v1 response parsed from a TCP byte stream.
  /// Invalid checksums and unrelated frames are ignored.
  static MspReply? takeReply(List<int> bytes, int expectedCommand) {
    for (var start = 0; start + 5 < bytes.length; start++) {
      if (bytes[start] != 0x24 || bytes[start + 1] != 0x4d) continue;
      final direction = bytes[start + 2];
      if (direction != 0x3e && direction != 0x21) continue;
      final length = bytes[start + 3];
      final end = start + 6 + length;
      if (end > bytes.length) return null;
      var checksum = 0;
      for (var i = start + 3; i < end - 1; i++) {
        checksum ^= bytes[i];
      }
      if (checksum != bytes[end - 1]) continue;
      final command = bytes[start + 4];
      if (command != expectedCommand) continue;
      if (direction == 0x21) {
        throw const FormatException(
          'Flight controller rejected the MSP request.',
        );
      }
      return MspReply(
        command,
        Uint8List.fromList(bytes.sublist(start + 5, end - 1)),
      );
    }
    return null;
  }

  Future<String> discover({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    _ensureOpen();
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _discoverySocket = socket;
    socket.broadcastEnabled = true;
    final result = Completer<String>();
    late StreamSubscription<RawSocketEvent> listener;
    listener = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? datagram;
      while ((datagram = socket.receive()) != null) {
        final message = utf8
            .decode(datagram!.data, allowMalformed: true)
            .trim();
        if (!message.startsWith('DRONE_ESP32:')) continue;
        final announced = message.substring('DRONE_ESP32:'.length).trim();
        final host = announced.isNotEmpty
            ? announced
            : datagram.address.address;
        if (!result.isCompleted) result.complete(host);
      }
    });
    try {
      socket.send(
        utf8.encode(discoveryMessage),
        InternetAddress('255.255.255.255'),
        discoveryPort,
      );
      return await result.future.timeout(timeout);
    } finally {
      await listener.cancel();
      socket.close();
      if (identical(_discoverySocket, socket)) _discoverySocket = null;
    }
  }

  Future<void> connect(
    String host, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    _ensureOpen();
    await disconnect();
    final socket = await Socket.connect(host, tcpPort, timeout: timeout);
    _socket = socket;
    _subscription = socket.listen(
      _onBytes,
      onError: (Object error, StackTrace stack) => _failPending(error),
      onDone: () =>
          _failPending(const SocketException('ESP32 connection closed.')),
      cancelOnError: false,
    );
  }

  Future<MspReply> request(
    int command, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    _ensureOpen();
    final socket = _socket;
    if (socket == null) throw const SocketException('ESP32 is disconnected.');
    if (_pendingReply != null) {
      throw StateError('An MSP request is already in progress.');
    }

    final completer = Completer<MspReply>();
    _pendingReply = completer;
    _pendingCommand = command;
    socket.add(encodeRequest(command));
    await socket.flush();
    try {
      return await completer.future.timeout(timeout);
    } finally {
      if (identical(_pendingReply, completer)) {
        _pendingReply = null;
        _pendingCommand = null;
      }
    }
  }

  void _onBytes(Uint8List bytes) {
    _buffer.addAll(bytes);
    if (_buffer.length > 4096) _buffer.removeRange(0, _buffer.length - 512);
    final command = _pendingCommand;
    final completer = _pendingReply;
    if (command == null || completer == null || completer.isCompleted) return;
    try {
      final reply = takeReply(_buffer, command);
      if (reply != null) completer.complete(reply);
      _buffer.clear();
    } on Object catch (error, stack) {
      completer.completeError(error, stack);
      _buffer.clear();
    }
  }

  void _failPending(Object error) {
    final pending = _pendingReply;
    if (pending != null && !pending.isCompleted) pending.completeError(error);
    _pendingReply = null;
    _pendingCommand = null;
  }

  Future<void> disconnect() async {
    _failPending(const SocketException('ESP32 connection closed.'));
    await _subscription?.cancel();
    _subscription = null;
    _socket?.destroy();
    _socket = null;
    _buffer.clear();
  }

  void _ensureOpen() {
    if (_disposed) throw StateError('Diagnostics service is disposed.');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _discoverySocket?.close();
    _discoverySocket = null;
    await disconnect();
  }
}
