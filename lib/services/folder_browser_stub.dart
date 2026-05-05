Future<({List<String> dirs, List<String> mp3Paths})> listFolderChildrenSorted(
        String _) async =>
    (dirs: <String>[], mp3Paths: <String>[]);

Future<int> totalMp3CountUnderFolder(String _) async => 0;

Future<int> recursiveSubfolderCount(String _) async => 0;

bool pathIsInsideAllowedRoots(String candidate, Iterable<String> roots) => false;
