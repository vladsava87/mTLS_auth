/// Enum for HTTP methods used in API requests
enum HttpMethod {
  get('GET'),
  post('POST'),
  put('PUT'),
  patch('PATCH'),
  delete('DELETE'),
  head('HEAD'),
  options('OPTIONS');

  const HttpMethod(this.value);

  final String value;

  @override
  String toString() => value;
}

