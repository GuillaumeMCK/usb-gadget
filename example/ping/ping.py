#!/usr/bin/env python3
import usb.core
import usb.util
import sys
import time

VID = 0x1d6b
PID = 0x0104
INTERFACE = 0
EP_IN = 0x81
EP_OUT = 0x01

def prepare_device(dev):
    try:
        if dev.is_kernel_driver_active(INTERFACE):
            dev.detach_kernel_driver(INTERFACE)
    except (NotImplementedError, usb.core.USBError):
        pass

    usb.util.claim_interface(dev, INTERFACE)

def endpoint_config(dev) -> int:
    cfg = dev.get_active_configuration()
    intf = cfg[(INTERFACE, 0)]
    pack_size = 0

    for ep in intf.endpoints():
        ep_addr = ep.bEndpointAddress
        ep_type = usb.util.endpoint_type(ep.bmAttributes)
        print(f"> Endpoint 0x{ep_addr:02x}")
        print(f" Type:            {ep_type}")
        print(f" Max Packet Size: {ep.wMaxPacketSize}")
        print(f" Interval:        {ep.bInterval}")
        if ep_addr == EP_IN:
            pack_size = ep.wMaxPacketSize
    return pack_size

def send_and_receive(dev, payload: bytes, pkt_size: int) -> bytes:
    print(f"PING -> {payload}", end=' ')
    bytes_sent = dev.write(EP_OUT, payload, INTERFACE)
    if bytes_sent != len(payload):
        raise RuntimeError(f"Sent {bytes_sent} bytes, expected {len(payload)} bytes.")
    received = dev.read(EP_IN, pkt_size, INTERFACE)
    print(f"-> PONG {bytes(received)}")
    return bytes(received)

def main():
    dev = usb.core.find(idVendor=VID, idProduct=PID)
    if dev is None:
        print("ERROR: Device not found.")
        sys.exit(1)

    prepare_device(dev)
    pkt_size = endpoint_config(dev)
    tests = [
        ("Text",               b"Hello USB!"),
        ("Digits",             b"1234567890"),
        ("Binary",             b"\x00\x01\x02\x03\x04"),
        ("String with NULL",   b"ABC\x00DEF"),
        ("pkt_size-1 bytes",   b"A" * (pkt_size - 1)), # ZLP not handled by pong device
    ]

    for name, data in tests:
        response = send_and_receive(dev, data, pkt_size)
        if response != data:
            print(f"ERROR: Mismatch in {name} test.")

    usb.util.release_interface(dev, INTERFACE)

if __name__ == "__main__":
    main()
    exit(0)
