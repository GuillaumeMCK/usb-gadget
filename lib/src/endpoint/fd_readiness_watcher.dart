import 'dart:isolate';

import 'package:using/using.dart';

import '/src/platform/epoll/epoll.dart';
import '/src/platform/unistd/unistd.dart';

/// Arguments handed to [_watcherEntry] when the background isolate is spawned.
final class _WatcherArgs {
  const _WatcherArgs({
    required this.epfd,
    required this.fd,
    required this.shutdownFd,
    required this.sendPort,
  });

  final int epfd;
  final int fd;
  final int shutdownFd;
  final SendPort sendPort;
}

/// Background isolate entry-point.
///
/// Blocks on `epoll_wait` and posts a token to the owning isolate whenever the
/// watched fd becomes readable. Exits when the shutdown eventfd fires, or
/// quietly if the fds are closed from under it during teardown.
void _watcherEntry(_WatcherArgs args) {
  try {
    while (true) {
      // Bounded timeout (not -1): readable fds still return immediately, but a
      // finite wait leaves a yield point between blocking syscalls so the VM
      // can pause/kill this isolate. An indefinite FFI wait would hang process
      // and `dart test` shutdown ("waiting for isolate to check in").
      final ready = Epoll.wait(args.epfd, maxEvents: 2, timeoutMs: 1000);
      for (final (:data, events: _) in ready) {
        if (data == args.shutdownFd) {
          try {
            Epoll.eventfdRead(args.shutdownFd);
          } catch (_) {}
          return;
        }
        if (data == args.fd) args.sendPort.send(null);
      }
    }
  } catch (_) {
    // epfd / shutdownFd closed by the owner during teardown (EBADF) — exit.
  }
}

/// Event-driven readiness notifier for a single file descriptor.
///
/// Registers [fd] with `epoll` as `EPOLLONESHOT` on a background isolate and
/// invokes `onReadable` (back on the owning isolate) each time it becomes
/// readable. The owner performs all reads and writes on [fd] itself, then
/// calls [rearm] to receive the next notification.
///
/// One-shot delivery suits control state machines such as FunctionFS EP0, where
/// exactly one read must happen per wake and reading again before answering a
/// pending request would corrupt kernel state.
final class FdReadinessWatcher with Releasable {
  FdReadinessWatcher(this.fd, {required void Function() onReadable})
    : _shutdownFd = Epoll.eventfd(closeOnExec: true),
      _epfd = Epoll.create() {
    Epoll.add(_epfd, _shutdownFd, EPOLLIN, data: _shutdownFd);
    Epoll.add(_epfd, fd, EPOLLIN | EPOLLONESHOT, data: fd);

    _port = ReceivePort()..listen((_) => onReadable());
    Isolate.spawn(
      _watcherEntry,
      _WatcherArgs(
        epfd: _epfd,
        fd: fd,
        shutdownFd: _shutdownFd,
        sendPort: _port.sendPort,
      ),
      debugName: 'FdReadinessWatcher',
    ).then((iso) => _isolate = iso);
  }

  /// The watched file descriptor.
  final int fd;

  final int _epfd;
  final int _shutdownFd;
  late final ReceivePort _port;
  Isolate? _isolate;

  /// Re-arms the one-shot watch to deliver the next readiness notification.
  ///
  /// `epoll` only re-fires once [fd] is actually readable again, so calling
  /// this while a reply is still pending (fd writable, not readable) is safe.
  void rearm() {
    if (isReleased) return;
    try {
      Epoll.modify(_epfd, fd, EPOLLIN | EPOLLONESHOT, data: fd);
    } catch (_) {}
  }

  @override
  void release() {
    if (isReleased) return;
    super.release();
    // Signal a clean exit, then kill as a backstop if the handle is ready.
    try {
      Epoll.eventfdWrite(_shutdownFd, 1);
    } catch (_) {}
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _isolate = null;
    _port.close();
    Unistd.close(_epfd);
    Unistd.close(_shutdownFd);
  }
}
