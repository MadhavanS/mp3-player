/// Web / non-IO: cannot inspect the file system; never prune based on disk.
bool localFileStillPresent(String path) => true;
