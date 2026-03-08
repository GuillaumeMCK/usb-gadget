import 'dart:ffi' as ffi;
import 'dart:io' show OSError;

import 'package:ffi/ffi.dart';

import '../errno/errno.dart';
import 'epoll.ffi.dart' as epoll_ffi;

export 'epoll.ffi.dart'
    show
        EPOLL_CLOEXEC,
        EPOLL_CTL_ADD,
        EPOLL_CTL_DEL,
        EPOLL_CTL_MOD,
        EPOLLIN,
        EPOLLOUT,
        EPOLLERR,
        EPOLLHUP,
        EPOLLRDHUP,
        EPOLLONESHOT,
        EPOLLET,
        EFD_SEMAPHORE,
        EFD_CLOEXEC,
        EFD_NONBLOCK;

/// A ready event returned by [Epoll.wait].
///
/// Both fields are plain Dart integers copied out of native memory before
/// the internal buffer is freed — safe to hold indefinitely.
typedef EpollEvent = ({int events, int data});

final _epoll = epoll_ffi.Epoll(ffi.DynamicLibrary.process());

/// Wrapper for Linux epoll and eventfd system calls.
///
/// All methods throw [OSError] on failure unless documented otherwise.
abstract final class Epoll {
  // ---------------------------------------------------------------------------
  // epoll
  // ---------------------------------------------------------------------------

  /// Creates a new epoll instance.
  ///
  /// [closeOnExec] sets the close-on-exec flag (recommended; default: true).
  ///
  /// Returns a non-negative file descriptor.
  /// Throws [OSError] on failure.
  static int create({bool closeOnExec = true}) {
    return Errno.call(
      () => _epoll.epoll_create1(closeOnExec ? epoll_ffi.EPOLL_CLOEXEC : 0),
      isError: (r) => r < 0,
      message: 'epoll_create1',
    );
  }

  /// Adds [fd] to the epoll interest list of [epfd].
  ///
  /// [events] is a bitmask of [EPOLLIN], [EPOLLOUT], etc.
  /// [data] is an opaque 64-bit value returned with each ready event —
  /// typically the file descriptor itself or an operation identifier.
  ///
  /// Throws [OSError] on failure.
  static void add(int epfd, int fd, int events, {int data = 0}) {
    _ctl(epfd, epoll_ffi.EPOLL_CTL_ADD, fd, events, data);
  }

  /// Modifies the events watched for [fd] on [epfd].
  ///
  /// Throws [OSError] on failure.
  static void modify(int epfd, int fd, int events, {int data = 0}) {
    _ctl(epfd, epoll_ffi.EPOLL_CTL_MOD, fd, events, data);
  }

  /// Removes [fd] from the epoll interest list of [epfd].
  ///
  /// Throws [OSError] on failure.
  static void delete(int epfd, int fd) {
    _ctl(epfd, epoll_ffi.EPOLL_CTL_DEL, fd, 0, 0);
  }

  static void _ctl(int epfd, int op, int fd, int events, int data) {
    final ev = calloc<epoll_ffi.epoll_event>();
    try {
      ev.ref.events = events;
      ev.ref.data.u64 = data;
      Errno.call(
        () => _epoll.epoll_ctl(epfd, op, fd, ev),
        isError: (r) => r < 0,
        message: 'epoll_ctl',
      );
    } finally {
      calloc.free(ev);
    }
  }

  /// Waits for events on [epfd], returning at most [maxEvents] results.
  ///
  /// [timeoutMs] — milliseconds to block. Pass `-1` to block indefinitely,
  /// `0` to return immediately (non-blocking poll).
  ///
  /// Returns a list of [EpollEvent] records with the event bitmask and the
  /// opaque data value set via [add] / [modify]. Values are copied out of
  /// native memory before returning and are safe to hold indefinitely.
  ///
  /// Throws [OSError] on failure (EINTR is retried internally).
  static List<EpollEvent> wait(
    int epfd, {
    int maxEvents = 64,
    int timeoutMs = -1,
  }) {
    assert(maxEvents > 0);
    final buf = calloc<epoll_ffi.epoll_event>(maxEvents);
    try {
      int n;
      // Retry on EINTR (e.g. signal delivery during wait).
      while (true) {
        final (ret, err) = Errno.capture(
          () => _epoll.epoll_wait(epfd, buf, maxEvents, timeoutMs),
        );
        if (ret >= 0) {
          n = ret;
          break;
        }
        if (err == Errno.eintr) continue;
        throw Errno.toOSError(err, 'epoll_wait');
      }

      // Copy both fields out of native memory while buf is still alive,
      // then free the buffer. Callers receive plain Dart records.
      return List<EpollEvent>.generate(
        n,
        (i) => (events: buf[i].events, data: buf[i].data.u64),
        growable: false,
      );
    } finally {
      calloc.free(buf);
    }
  }

  // ---------------------------------------------------------------------------
  // eventfd
  // ---------------------------------------------------------------------------

  /// Creates an eventfd file descriptor with the given initial counter value.
  ///
  /// [nonBlock] sets [EFD_NONBLOCK] (returns EAGAIN instead of blocking).
  /// [closeOnExec] sets [EFD_CLOEXEC] (default: true).
  /// [semaphore] sets [EFD_SEMAPHORE] (decrement by 1 instead of resetting).
  ///
  /// Returns a non-negative file descriptor.
  /// Throws [OSError] on failure.
  static int eventfd({
    int initialValue = 0,
    bool nonBlock = false,
    bool closeOnExec = true,
    bool semaphore = false,
  }) {
    var flags = 0;
    if (nonBlock) flags |= epoll_ffi.EFD_NONBLOCK;
    if (closeOnExec) flags |= epoll_ffi.EFD_CLOEXEC;
    if (semaphore) flags |= epoll_ffi.EFD_SEMAPHORE;

    return Errno.call(
      () => _epoll.eventfd(initialValue, flags),
      isError: (r) => r < 0,
      message: 'eventfd',
    );
  }

  /// Reads and clears the eventfd counter, blocking until it is non-zero.
  ///
  /// Returns the previous counter value.
  /// Throws [OSError] on failure (including EAGAIN for non-blocking fds).
  static int eventfdRead(int fd) {
    final val = calloc<ffi.Uint64>();
    try {
      Errno.call(
        () => _epoll.eventfd_read(fd, val),
        isError: (r) => r < 0,
        message: 'eventfd_read',
      );
      return val.value;
    } finally {
      calloc.free(val);
    }
  }

  /// Adds [value] to the eventfd counter.
  ///
  /// Throws [OSError] on failure.
  static void eventfdWrite(int fd, int value) {
    Errno.call(
      () => _epoll.eventfd_write(fd, value),
      isError: (r) => r < 0,
      message: 'eventfd_write',
    );
  }
}
