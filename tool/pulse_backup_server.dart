import 'dart:convert';
import 'dart:io';

class PulseEntry {
  PulseEntry({
    required this.payload,
    required this.receivedAt,
    required this.source,
  });

  final Map<String, dynamic> payload;
  final DateTime receivedAt;
  final String source;

  Map<String, dynamic> toJson() => {
        'payload': payload,
        'receivedAt': receivedAt.toIso8601String(),
        'source': source,
      };
}

class PulseBackupServer {
  PulseBackupServer({this.maxEntries = 1000});

  final int maxEntries;
  final List<PulseEntry> _entries = <PulseEntry>[];
  late final File _journalFile = File('backup_pulses.jsonl');

  Future<void> start({int port = 8080}) async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    stdout.writeln('📡 Pulse backup server running on http://localhost:$port');
    stdout.writeln('   Dashboard available at http://localhost:$port/');

    await for (final request in server) {
      try {
        await _handle(request);
      } catch (error, stackTrace) {
        stderr.writeln('Error while handling ${request.method} ${request.uri}: $error');
        stderr.writeln(stackTrace);
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..write('Internal server error');
      } finally {
        await request.response.close();
      }
    }
  }

  Future<void> _handle(HttpRequest request) async {
    switch ('${request.method} ${request.uri.path}') {
      case 'POST /heartbeat':
        await _handleSinglePulse(request, source: 'live');
        break;
      case 'POST /sync-offline-pulses':
        await _handleBulkPulse(request);
        break;
      case 'GET /pulses':
        await _handleList(request);
        break;
      case 'GET /':
        await _serveDashboard(request);
        break;
      default:
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('Not found');
    }
  }

  Future<void> _handleSinglePulse(HttpRequest request, {required String source}) async {
    final data = await utf8.decoder.bind(request).join();
    if (data.isEmpty) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Missing body');
      return;
    }

    try {
      final payload = jsonDecode(data) as Map<String, dynamic>;
      _recordPulse(payload: payload, source: source);
      request.response
        ..statusCode = HttpStatus.ok
        ..write('OK');
    } catch (error) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Invalid JSON: $error');
    }
  }

  Future<void> _handleBulkPulse(HttpRequest request) async {
    final data = await utf8.decoder.bind(request).join();
    if (data.isEmpty) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Missing body');
      return;
    }

    try {
      final payload = jsonDecode(data) as Map<String, dynamic>;
      final pulses = (payload['pulses'] as List<dynamic>? ?? <dynamic>[]).cast<Map<String, dynamic>>();
      for (final pulse in pulses) {
        _recordPulse(payload: pulse, source: 'offline-sync');
      }
      request.response
        ..statusCode = HttpStatus.ok
        ..write('Received ${pulses.length} pulses');
    } catch (error) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Invalid JSON: $error');
    }
  }

  Future<void> _handleList(HttpRequest request) async {
    final latest = _entries.reversed.take(200).map((entry) => entry.toJson()).toList();
    request.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(latest));
  }

  Future<void> _serveDashboard(HttpRequest request) async {
    const html = '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>Pulse Backup Monitor</title>
  <style>
    body { font-family: system-ui, sans-serif; margin: 0; padding: 24px; background: #f4f4f7; }
    h1 { margin-top: 0; }
    table { width: 100%; border-collapse: collapse; margin-top: 16px; background: white; }
    th, td { padding: 12px; border-bottom: 1px solid #e1e1e6; text-align: left; }
    th { background: #fafafa; font-weight: 600; }
    tbody tr:hover { background: #f9fafc; }
    .pill { display: inline-block; padding: 2px 8px; border-radius: 999px; font-size: 12px; }
    .pill.live { background: #e5f6ff; color: #0468d7; }
    .pill.offline-sync { background: #fff0d6; color: #9f6000; }
    .pill.fake { background: #ffe5e5; color: #bb1a1a; }
  </style>
</head>
<body>
  <h1>Pulse Backup Monitor</h1>
  <p>Latest pulse uploads will appear below. Page refreshes every 3 seconds.</p>
  <table>
    <thead>
      <tr>
        <th>Received at</th>
        <th>Employee</th>
        <th>Location</th>
        <th>Timestamp</th>
        <th>Status</th>
        <th>Source</th>
      </tr>
    </thead>
    <tbody id="rows">
      <tr><td colspan="6">Waiting for data...</td></tr>
    </tbody>
  </table>

  <script>
    async function fetchPulses() {
      try {
        const res = await fetch('/pulses');
        if (!res.ok) throw new Error('Request failed');
        const data = await res.json();
        renderRows(data);
      } catch (error) {
        console.error('Fetch failed', error);
      }
    }

    function formatDate(value) {
      if (!value) return '-';
      try {
        return new Intl.DateTimeFormat(undefined, { hour12: false, dateStyle: 'short', timeStyle: 'medium' }).format(new Date(value));
      } catch (error) {
        return value;
      }
    }

    function renderRows(entries) {
      const tbody = document.getElementById('rows');
      if (!entries.length) {
        tbody.innerHTML = '<tr><td colspan="6">No pulses yet.</td></tr>';
        return;
      }
      tbody.innerHTML = entries.map(entry => {
        const pulse = entry.payload || {};
        const coords = (pulse.latitude !== undefined && pulse.longitude !== undefined)
          ? `\${Number(pulse.latitude).toFixed(4)}, \${Number(pulse.longitude).toFixed(4)}`
          : '-';
        const isFake = pulse.isFake ? '<span class="pill fake">Fake</span>' : '<span class="pill live">Authentic</span>';
        const source = entry.source || 'live';
        const sourcePill = `<span class="pill \${source}">\${source}</span>`;
        return `<tr>
          <td>\${formatDate(entry.receivedAt)}</td>
          <td>\${pulse.employeeId ?? '-'}</td>
          <td>\${coords}</td>
          <td>\${formatDate(pulse.timestamp)}</td>
          <td>\${isFake}</td>
          <td>\${sourcePill}</td>
        </tr>`;
      }).join('');
    }

    fetchPulses();
    setInterval(fetchPulses, 3000);
  </script>
</body>
</html>''';

    request.response
      ..headers.contentType = ContentType.html
      ..write(html);
  }

  void _recordPulse({required Map<String, dynamic> payload, required String source}) {
    final entry = PulseEntry(
      payload: payload,
      receivedAt: DateTime.now().toUtc(),
      source: source,
    );
    _entries.add(entry);
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
    _appendToJournal(entry);
    final employee = payload['employeeId'] ?? '-';
    final timestamp = payload['timestamp'] ?? '-';
    stdout.writeln('[${entry.receivedAt.toIso8601String()}] $employee $timestamp ($source)');
  }

  Future<void> _appendToJournal(PulseEntry entry) async {
    try {
      await _journalFile.writeAsString(
        '${jsonEncode(entry.toJson())}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (error) {
      stderr.writeln('Failed to append journal: $error');
    }
  }
}

Future<void> main(List<String> arguments) async {
  final portArg = arguments.isNotEmpty ? int.tryParse(arguments.first) : null;
  final port = portArg == null || portArg <= 0 ? 8080 : portArg;
  final server = PulseBackupServer();
  await server.start(port: port);
}
