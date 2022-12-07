import 'dart:io';

class DiskManager {
  final Directory targetPath;
  DiskManager(this.targetPath);

  Future<int> getSize() async {
    FileStat fileStat = await targetPath.stat();
    return fileStat.size;
  }
}
