import 'dart:ui';

final RegExp _number = RegExp(r'[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?');
final RegExp _command = RegExp('[MmLlHhVvCcSsQqTtAaZz]');

class _Scanner {
  _Scanner(this.source);

  final String source;
  int _i = 0;

  void _skip() {
    while (_i < source.length) {
      final c = source.codeUnitAt(_i);
      if (c == 0x20 || c == 0x2C || c == 0x09 || c == 0x0A || c == 0x0D) {
        _i++;
      } else {
        break;
      }
    }
  }

  bool get atEnd {
    _skip();
    return _i >= source.length;
  }

  bool get nextIsNumber {
    _skip();
    if (_i >= source.length) {
      return false;
    }
    final c = source.codeUnitAt(_i);
    return (c >= 0x30 && c <= 0x39) || c == 0x2D || c == 0x2B || c == 0x2E;
  }

  String? readCommand() {
    _skip();
    if (_i >= source.length) {
      return null;
    }
    final c = source[_i];
    if (_command.hasMatch(c)) {
      _i++;
      return c;
    }
    return null;
  }

  double readNumber() {
    _skip();
    final match = _number.matchAsPrefix(source, _i);
    if (match == null) {
      throw FormatException('Expected a number in path data', source, _i);
    }
    _i = match.end;
    return double.parse(match.group(0)!);
  }

  bool readFlag() {
    _skip();
    if (_i >= source.length) {
      throw FormatException('Expected an arc flag', source, _i);
    }
    final c = source[_i++];
    if (c != '0' && c != '1') {
      throw FormatException('Invalid arc flag', source, _i - 1);
    }
    return c == '1';
  }
}

Path parseSvgPathData(String data) {
  final path = Path();
  final s = _Scanner(data);
  var x = 0.0;
  var y = 0.0;
  var startX = 0.0;
  var startY = 0.0;
  var ctrlX = 0.0;
  var ctrlY = 0.0;
  String? command;
  String? previous;

  while (!s.atEnd) {
    final explicit = s.readCommand();
    if (explicit != null) {
      command = explicit;
    } else if (command == null || command == 'Z' || command == 'z') {
      break;
    } else if (!s.nextIsNumber) {
      break;
    }
    final cmd = command;
    final relative = cmd == cmd.toLowerCase();
    final ox = relative ? x : 0.0;
    final oy = relative ? y : 0.0;

    switch (cmd.toUpperCase()) {
      case 'M':
        x = ox + s.readNumber();
        y = oy + s.readNumber();
        path.moveTo(x, y);
        startX = x;
        startY = y;
        command = relative ? 'l' : 'L';
      case 'L':
        x = ox + s.readNumber();
        y = oy + s.readNumber();
        path.lineTo(x, y);
      case 'H':
        x = ox + s.readNumber();
        path.lineTo(x, y);
      case 'V':
        y = oy + s.readNumber();
        path.lineTo(x, y);
      case 'C':
        final x1 = ox + s.readNumber();
        final y1 = oy + s.readNumber();
        final x2 = ox + s.readNumber();
        final y2 = oy + s.readNumber();
        x = ox + s.readNumber();
        y = oy + s.readNumber();
        path.cubicTo(x1, y1, x2, y2, x, y);
        ctrlX = x2;
        ctrlY = y2;
      case 'S':
        final smooth = previous == 'C' || previous == 'S';
        final x1 = smooth ? 2 * x - ctrlX : x;
        final y1 = smooth ? 2 * y - ctrlY : y;
        final x2 = ox + s.readNumber();
        final y2 = oy + s.readNumber();
        x = ox + s.readNumber();
        y = oy + s.readNumber();
        path.cubicTo(x1, y1, x2, y2, x, y);
        ctrlX = x2;
        ctrlY = y2;
      case 'Q':
        final x1 = ox + s.readNumber();
        final y1 = oy + s.readNumber();
        x = ox + s.readNumber();
        y = oy + s.readNumber();
        path.quadraticBezierTo(x1, y1, x, y);
        ctrlX = x1;
        ctrlY = y1;
      case 'T':
        final smooth = previous == 'Q' || previous == 'T';
        final x1 = smooth ? 2 * x - ctrlX : x;
        final y1 = smooth ? 2 * y - ctrlY : y;
        x = ox + s.readNumber();
        y = oy + s.readNumber();
        path.quadraticBezierTo(x1, y1, x, y);
        ctrlX = x1;
        ctrlY = y1;
      case 'A':
        final rx = s.readNumber().abs();
        final ry = s.readNumber().abs();
        final rotation = s.readNumber();
        final largeArc = s.readFlag();
        final sweep = s.readFlag();
        x = ox + s.readNumber();
        y = oy + s.readNumber();
        if (rx == 0 || ry == 0) {
          path.lineTo(x, y);
        } else {
          path.arcToPoint(
            Offset(x, y),
            radius: Radius.elliptical(rx, ry),
            rotation: rotation,
            largeArc: largeArc,
            clockwise: sweep,
          );
        }
      case 'Z':
        path.close();
        x = startX;
        y = startY;
    }
    previous = cmd.toUpperCase();
  }
  return path;
}
