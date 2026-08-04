
class PlaylistModel {
  final String id;
  String name;
  List<int> songIds;  // on_audio_query song IDs
  String? coverImagePath;  // user-picked image path, null = use first song art
  
  PlaylistModel({
    required this.id,
    required this.name,
    List<int>? songIds,
    this.coverImagePath,
  }) : songIds = songIds ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'songIds': songIds,
    'coverImagePath': coverImagePath,
  };

  factory PlaylistModel.fromJson(Map<String, dynamic> json) => PlaylistModel(
    id: json['id'] as String,
    name: json['name'] as String,
    songIds: (json['songIds'] as List<dynamic>).map((e) => (e as num).toInt()).toList(),
    coverImagePath: json['coverImagePath'] as String?,
  );
}
