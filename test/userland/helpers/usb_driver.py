#!/usr/bin/env python3
"""
JSON-RPC USB host driver for Dart integration tests.

Each line on stdin is a JSON object with a "cmd" field.
Each response is a JSON object written to stdout, always containing "ok".

Protocol
--------
find        {"cmd":"find","vid":…,"pid":…}
             → {"ok":true,"mps":…}          (mps = EP_IN max packet size)
claim       {"cmd":"claim"}
             → {"ok":true}
release     {"cmd":"release"}
             → {"ok":true}
dispose     {"cmd":"dispose"}              (release + dispose resources)
             → {"ok":true}
echo        {"cmd":"echo","hex":"…","pkt_size":…}
             → {"ok":true,"hex":"…"}        (echoed bytes as hex)
write       {"cmd":"write","ep":…,"hex":"…"}
             → {"ok":true,"sent":…}
read        {"cmd":"read","ep":…,"size":…,"timeout":…}
             → {"ok":true,"hex":"…"}        (may be "" for ZLP)
control_in  {"cmd":"control_in","bm":…,"br":…,"wv":…,"wi":…,"wl":…}
             → {"ok":true,"hex":"…"}
control_out {"cmd":"control_out","bm":…,"br":…,"wv":…,"wi":…,"hex":"…"}
             → {"ok":true}
set_halt    {"cmd":"set_halt","ep":…}
             → {"ok":true}
clear_halt  {"cmd":"clear_halt","ep":…}
             → {"ok":true}
get_status  {"cmd":"get_status","ep":…}
             → {"ok":true,"halted":…}
"""

import json
import sys
import time
import usb.core
import usb.util


_dev: usb.core.Device | None = None
INTERFACE = 0
IO_TIMEOUT = 2_000   # ms

# Cached wMaxPacketSize for the IN endpoint, set by cmd_find.
# Used as a minimum read-buffer size to prevent EOVERFLOW when the host
# issues a read with a buffer smaller than one full USB packet.
_ep_in_mps: int = 512

# How long to retry usb.core.find() after awaitState(configured) reports
# ready — the kernel USB host driver needs a few extra milliseconds to finish
# enumeration after the device-side sysfs state changes.
_FIND_RETRY_INTERVAL = 0.05   # seconds between attempts
_FIND_RETRY_TOTAL    = 3.0    # total seconds to keep trying


def _ok(**kwargs) -> None:
    print(json.dumps({"ok": True, **kwargs}), flush=True)

def _err(msg: str) -> None:
    print(json.dumps({"ok": False, "error": msg}), flush=True)

def _h2b(hex_str: str) -> bytes:
    return bytes.fromhex(hex_str) if hex_str else b""

def _b2h(data: bytes) -> str:
    return data.hex()

def _mps(dev: usb.core.Device, ep_addr: int) -> int:
    cfg  = dev.get_active_configuration()
    intf = cfg[(INTERFACE, 0)]
    for ep in intf.endpoints():
        if ep.bEndpointAddress == ep_addr:
            return ep.wMaxPacketSize
    raise RuntimeError(f"Endpoint 0x{ep_addr:02x} not found")

def cmd_find(msg: dict) -> None:
    """
    Locate the device by VID/PID.
    """
    global _dev, _ep_in_mps
    vid = int(msg["vid"], 16) if isinstance(msg["vid"], str) else msg["vid"]
    pid = int(msg["pid"], 16) if isinstance(msg["pid"], str) else msg["pid"]

    ep_in_addr = msg.get("ep_in", 0x81)
    if isinstance(ep_in_addr, str):
        ep_in_addr = int(ep_in_addr, 16)

    deadline = time.monotonic() + _FIND_RETRY_TOTAL
    dev = None
    while True:
        dev = usb.core.find(idVendor=vid, idProduct=pid)
        if dev is not None:
            break
        if time.monotonic() >= deadline:
            _err(f"Device not found VID=0x{vid:04x} PID=0x{pid:04x} "
                 f"(retried for {_FIND_RETRY_TOTAL:.1f} s)")
            return
        time.sleep(_FIND_RETRY_INTERVAL)

    _dev = dev
    mps = _mps(dev, ep_in_addr)
    _ep_in_mps = mps
    _ok(mps=mps)

def cmd_claim(_msg: dict) -> None:
    if _dev is None:
        _err("no device — call find first")
        return
    try:
        if _dev.is_kernel_driver_active(INTERFACE):
            _dev.detach_kernel_driver(INTERFACE)
    except (NotImplementedError, usb.core.USBError):
        pass
    usb.util.claim_interface(_dev, INTERFACE)
    _ok()

def cmd_release(_msg: dict) -> None:
    if _dev is None:
        _err("no device")
        return
    usb.util.release_interface(_dev, INTERFACE)
    _ok()

def cmd_dispose(_msg: dict) -> None:
    global _dev
    if _dev is not None:
        try:
            usb.util.release_interface(_dev, INTERFACE)
        except Exception:
            pass
        usb.util.dispose_resources(_dev)
        _dev = None
    _ok()

def cmd_echo(msg: dict) -> None:
    """
    Write payload to EP_OUT then read the echo back from EP_IN.
    """
    if _dev is None:
        _err("no device")
        return
    payload  = _h2b(msg.get("hex", ""))
    pkt_size = int(msg.get("pkt_size", 512))
    ep_out   = int(msg.get("ep_out", 0x02))
    ep_in    = int(msg.get("ep_in",  0x81))
    timeout  = int(msg.get("timeout", IO_TIMEOUT))

    # The read buffer must be ≥ wMaxPacketSize to avoid EOVERFLOW.
    read_buf = max(pkt_size, _ep_in_mps)

    try:
        if payload:
            sent = _dev.write(ep_out, payload, timeout)
            if sent != len(payload):
                _err(f"short write {sent}/{len(payload)} B")
                return
        else:
            _dev.write(ep_out, b"", timeout)

        expected = len(payload)

        if expected == 0:
            try:
                received = bytes(_dev.read(ep_in, max(read_buf, 1), timeout))
            except usb.core.USBTimeoutError:
                received = b""
        else:
            received = b""
            while len(received) < expected:
                try:
                    chunk = bytes(_dev.read(ep_in, read_buf, timeout))
                except usb.core.USBTimeoutError:
                    _err(
                        f"read timeout after {len(received)}/{expected} B "
                        f"(read_buf={read_buf})"
                    )
                    return
                received += chunk

        _ok(hex=_b2h(received))
    except Exception as exc:
        _err(str(exc))

def cmd_write(msg: dict) -> None:
    if _dev is None:
        _err("no device")
        return
    ep      = int(msg["ep"])
    payload = _h2b(msg.get("hex", ""))
    timeout = int(msg.get("timeout", IO_TIMEOUT))
    try:
        sent = _dev.write(ep, payload, timeout)
        # pyusb can return None for zero-byte writes on some backends.
        _ok(sent=sent if sent is not None else 0)
    except Exception as exc:
        _err(str(exc))

def cmd_read(msg: dict) -> None:
    if _dev is None:
        _err("no device")
        return
    ep      = int(msg["ep"])
    size    = int(msg.get("size", 512))
    timeout = int(msg.get("timeout", IO_TIMEOUT))
    # Buffer must be ≥ wMaxPacketSize for IN endpoints to avoid EOVERFLOW.
    buf = max(size, _ep_in_mps)
    try:
        data = bytes(_dev.read(ep, max(buf, 1), timeout))
        _ok(hex=_b2h(data))
    except usb.core.USBTimeoutError:
        _ok(hex="")   # treat timeout as ZLP
    except Exception as exc:
        _err(str(exc))

def cmd_control_in(msg: dict) -> None:
    if _dev is None:
        _err("no device")
        return
    bm = int(msg["bm"])
    br = int(msg["br"])
    wv = int(msg["wv"])
    wi = int(msg["wi"])
    wl = int(msg["wl"])
    try:
        data = _dev.ctrl_transfer(bm, br, wv, wi, wl, IO_TIMEOUT)
        _ok(hex=_b2h(bytes(data)))
    except usb.core.USBError as exc:
        _ok(hex="", stall=True, error=str(exc))
    except Exception as exc:
        _err(str(exc))

def cmd_control_out(msg: dict) -> None:
    if _dev is None:
        _err("no device")
        return
    bm   = int(msg["bm"])
    br   = int(msg["br"])
    wv   = int(msg["wv"])
    wi   = int(msg["wi"])
    data = _h2b(msg.get("hex", ""))
    try:
        sent = _dev.ctrl_transfer(bm, br, wv, wi, data, IO_TIMEOUT)
        _ok(sent=sent)
    except usb.core.USBError as exc:
        _ok(sent=0, stall=True, error=str(exc))
    except Exception as exc:
        _err(str(exc))

def cmd_set_halt(msg: dict) -> None:
    if _dev is None:
        _err("no device")
        return
    ep = int(msg["ep"])
    # SET_FEATURE(ENDPOINT_HALT) — bmRequestType=0x02, bRequest=0x03, wValue=0, wIndex=ep
    try:
        _dev.ctrl_transfer(0x02, 0x03, 0x0000, ep, None, IO_TIMEOUT)
        _ok()
    except Exception as exc:
        _err(str(exc))

def cmd_clear_halt(msg: dict) -> None:
    if _dev is None:
        _err("no device")
        return
    ep = int(msg["ep"])
    # CLEAR_FEATURE(ENDPOINT_HALT) — bmRequestType=0x02, bRequest=0x01, wValue=0, wIndex=ep
    try:
        _dev.ctrl_transfer(0x02, 0x01, 0x0000, ep, None, IO_TIMEOUT)
        _ok()
    except Exception as exc:
        _err(str(exc))

def cmd_get_status(msg: dict) -> None:
    if _dev is None:
        _err("no device")
        return
    ep = int(msg["ep"])
    # GET_STATUS(endpoint) — bmRequestType=0x82, bRequest=0x00, wValue=0, wIndex=ep, wLength=2
    try:
        data = _dev.ctrl_transfer(0x82, 0x00, 0x0000, ep, 2, IO_TIMEOUT)
        status = int.from_bytes(bytes(data), "little")
        _ok(halted=bool(status & 0x01))
    except Exception as exc:
        _err(str(exc))

def cmd_sleep(msg: dict) -> None:
    time.sleep(float(msg.get("seconds", 1.0)))
    _ok()


_COMMANDS = {
    "find":        cmd_find,
    "claim":       cmd_claim,
    "release":     cmd_release,
    "dispose":     cmd_dispose,
    "echo":        cmd_echo,
    "write":       cmd_write,
    "read":        cmd_read,
    "control_in":  cmd_control_in,
    "control_out": cmd_control_out,
    "set_halt":    cmd_set_halt,
    "clear_halt":  cmd_clear_halt,
    "get_status":  cmd_get_status,
    "sleep":       cmd_sleep,
}

def main() -> None:
    for raw in sys.stdin:
        raw = raw.strip()
        if not raw:
            continue
        try:
            msg = json.loads(raw)
            cmd = msg.get("cmd", "")
            handler = _COMMANDS.get(cmd)
            if handler is None:
                _err(f"unknown command: {cmd!r}")
            else:
                handler(msg)
        except json.JSONDecodeError as exc:
            _err(f"JSON parse error: {exc}")
        except Exception as exc:
            _err(f"unhandled exception: {exc}")

if __name__ == "__main__":
    main()