class Server {
  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final SecurityMode securityMode;
  final DateTime addedAt;
  final DateTime? lastConnectedAt;

  Server({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    this.securityMode = SecurityMode.mode3,
    DateTime? addedAt,
    this.lastConnectedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  factory Server.fromJson(Map<String, dynamic> json) {
    return Server(
      id: json['id'] as String,
      name: json['name'] as String,
      host: json['host'] as String,
      port: json['port'] as int? ?? 22,
      username: json['username'] as String,
      securityMode: SecurityMode.values.firstWhere(
        (e) => e.name == json['securityMode'],
        orElse: () => SecurityMode.mode3,
      ),
      addedAt: json['addedAt'] != null
          ? DateTime.parse(json['addedAt'] as String)
          : null,
      lastConnectedAt: json['lastConnectedAt'] != null
          ? DateTime.parse(json['lastConnectedAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'username': username,
      'securityMode': securityMode.name,
      'addedAt': addedAt.toIso8601String(),
      'lastConnectedAt': lastConnectedAt?.toIso8601String(),
    };
  }

  Server copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? username,
    SecurityMode? securityMode,
    DateTime? addedAt,
    DateTime? lastConnectedAt,
  }) {
    return Server(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      securityMode: securityMode ?? this.securityMode,
      addedAt: addedAt ?? this.addedAt,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
    );
  }
}

enum SecurityMode {
  mode1, // Password for all
  mode2, // Root key only, others password
  mode3, // Key only for all (recommended)
}
