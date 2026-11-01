import 'package:http/http.dart' as http;

/// Shared HTTP client; tests replace it with a MockClient.
http.Client httpClient = http.Client();
