/// Serializes agent settings writes so older keystrokes cannot finish last.
class SerialAgentWrites {
  Future<void> _pending = Future.value();

  Future<void> enqueue(Future<void> Function() action) {
    final write = _pending.then((_) => action());
    _pending = write.catchError((Object error) {});
    return write;
  }
}
