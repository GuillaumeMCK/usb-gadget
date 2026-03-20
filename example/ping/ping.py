#!/usr/bin/env python3
"""USB loopback benchmark — send payload, verify echo, report timing."""

import struct
import sys
import time

import usb.core
import usb.util

VID       = 0x1d6b
PID       = 0x0104
INTERFACE = 0
EP_IN     = 0x81
EP_OUT    = 0x02
BUF       = 512 * 1024


def fmt_size(n):
    for unit in ("B", "KB", "MB"):
        if n < 1024 or unit == "MB":
            return f"{n:.1f} {unit}" if unit != "B" else f"{n} B"
        n /= 1024


def fmt_time(ms):
    if ms < 1:    return f"{ms*1000:.1f} us"
    if ms < 1000: return f"{ms:.2f} ms"
    return f"{ms/1000:.3f} s"


def fmt_rate(bps):
    kbps = bps / 1024
    return f"{kbps:.1f} KB/s" if kbps < 1024 else f"{kbps/1024:.2f} MB/s"


def open_device():
    dev = usb.core.find(idVendor=VID, idProduct=PID)
    if dev is None:
        sys.exit(f"device not found  VID=0x{VID:04x}  PID=0x{PID:04x}")
    try:
        if dev.is_kernel_driver_active(INTERFACE):
            dev.detach_kernel_driver(INTERFACE)
    except (NotImplementedError, usb.core.USBError):
        pass
    usb.util.claim_interface(dev, INTERFACE)
    return dev


def packet_size(dev):
    intf = dev.get_active_configuration()[(INTERFACE, 0)]
    for ep in intf.endpoints():
        if ep.bEndpointAddress == EP_IN:
            return ep.wMaxPacketSize
    raise RuntimeError("EP_IN not found")


def roundtrip(dev, pkt, payload):
    frame = struct.pack(">I", len(payload)) + payload

    t0 = time.perf_counter()
    dev.write(EP_OUT, frame, INTERFACE)
    if len(frame) % pkt == 0:          # ZLP signals end-of-transfer
        dev.write(EP_OUT, b"", INTERFACE)
    t1 = time.perf_counter()

    buf = bytearray()
    while len(buf) < len(frame):
        buf += dev.read(EP_IN, BUF, INTERFACE)
    t2 = time.perf_counter()

    write_ms = (t1 - t0) * 1000
    read_ms  = (t2 - t1) * 1000
    total_ms = (t2 - t0) * 1000
    return bytes(buf[4:]), write_ms, read_ms, total_ms


def run(dev, pkt, name, payload):
    print(f"\n  {name}  ({fmt_size(len(payload))})")
    echo, w, r, total = roundtrip(dev, pkt, payload)
    rate = len(payload) / (total / 1000)
    ok   = echo == payload
    print(f"    write {fmt_time(w)}  read {fmt_time(r)}  total {fmt_time(total)}  {fmt_rate(rate)}")
    print(f"    {'PASS' if ok else 'FAIL — data mismatch'}")
    return ok


def main():
    dev = open_device()
    pkt = packet_size(dev)

    MB4 = 4 * 1024 * 1024
    tests = [
        ("tiny",            b"Hello USB!"),
        ("single packet",   b"A" * pkt),
        ("64 packets",      b"." * pkt * 64),
        ("4 MB stress",     bytes(range(256)) * (MB4 // 256)),
    ]

    print(f"USB loopback  pkt={fmt_size(pkt)}  buf={fmt_size(BUF)}")
    results = [run(dev, pkt, name, payload) for name, payload in tests]
    passed, total = sum(results), len(results)
    print(f"\n  {passed}/{total} passed")

    usb.util.release_interface(dev, INTERFACE)
    sys.exit(0 if passed == total else 1)

if __name__ == "__main__":
    main()