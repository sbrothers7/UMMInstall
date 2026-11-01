import 'package:archive/archive.dart';

List<int> zip(Map<String, String> files) {
  final archive = Archive();
  files.forEach((name, content) => archive.addFile(ArchiveFile.string(name, content)));
  return ZipEncoder().encodeBytes(archive);
}
