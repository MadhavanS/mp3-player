import 'folder_browser_stub.dart'
    if (dart.library.io) 'folder_browser_io.dart' as impl;

Future<({List<String> dirs, List<String> mp3Paths})> listFolderChildrenSorted(
        String absolutePath) =>
    impl.listFolderChildrenSorted(absolutePath);

Future<int> totalMp3CountUnderFolder(String folderPath) =>
    impl.totalMp3CountUnderFolder(folderPath);

Future<int> recursiveSubfolderCount(String folderPath) =>
    impl.recursiveSubfolderCount(folderPath);

bool pathIsInsideAllowedRoots(String candidate, Iterable<String> roots) =>
    impl.pathIsInsideAllowedRoots(candidate, roots);
