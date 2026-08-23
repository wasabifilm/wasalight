#!/usr/bin/env python3
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
import importlib.machinery
import importlib.util
import io
import pathlib
import socket
import struct
import sys
import unittest
from contextlib import redirect_stdout

sys.dont_write_bytecode = True
PROJECT = pathlib.Path(__file__).resolve().parents[2]
CAPTURE = PROJECT / "installer/templates/rootfs/usr/local/sbin/wasalight-artnet-capture"
loader = importlib.machinery.SourceFileLoader("osc_capture", str(CAPTURE))
spec = importlib.util.spec_from_loader(loader.name, loader)
osc_capture = importlib.util.module_from_spec(spec)
loader.exec_module(osc_capture)


def osc_string(value):
    encoded = value.encode() + b"\0"
    return encoded + b"\0" * ((-len(encoded)) % 4)


class OscCaptureTest(unittest.TestCase):
    def test_decodes_common_argument_types(self):
        payload = (
            osc_string("/magicq/playback/1") + osc_string(",ifsTFN")
            + struct.pack("!if", 7, 0.5) + osc_string("go")
        )
        self.assertEqual(
            osc_capture.parse_osc_message(payload),
            ("/magicq/playback/1", [7, 0.5, "go", True, False, None]),
        )

    def test_decodes_bundle_messages(self):
        message = osc_string("/cue") + osc_string(",i") + struct.pack("!i", 42)
        bundle = b"#bundle\0" + b"\0" * 8 + struct.pack("!I", len(message)) + message
        self.assertEqual(list(osc_capture.osc_messages(bundle)), [("/cue", [42])])

    def test_rejects_non_osc_udp_payload(self):
        self.assertEqual(list(osc_capture.osc_messages(b"ordinary UDP payload")), [])

    def test_extracts_ipv4_udp_packet(self):
        payload = osc_string("/go") + osc_string(",T")
        ethernet = b"\0" * 12 + struct.pack("!H", 0x0800)
        ip = bytearray(20)
        ip[0] = 0x45
        ip[9] = 17
        ip[12:16] = socket.inet_aton("192.0.2.10")
        ip[16:20] = socket.inet_aton("192.0.2.20")
        udp = struct.pack("!HHHH", 9001, 8000, 8 + len(payload), 0)
        packet = osc_capture.udp_packet(ethernet + bytes(ip) + udp + payload)
        self.assertEqual(packet[:4], ("192.0.2.10", 9001, "192.0.2.20", 8000))
        self.assertEqual(packet[4], payload)

    def test_preserves_artnet_output_for_existing_monitor(self):
        payload = b"Art-Net\0" + struct.pack("<H", 0x5000) + b"\0" * 4
        payload += struct.pack("<H", 2) + struct.pack("!H", 32) + b"\0" * 32
        output = io.StringIO()
        with redirect_stdout(output):
            osc_capture.output_packet(("192.0.2.1", 6454, "192.0.2.2", 6454, payload))
        fields = output.getvalue().strip().split("\t")
        self.assertEqual(len(fields), 6)
        self.assertEqual(fields[3:], ["0x5000", "2", "32"])

    def test_prefixes_osc_output_for_protocol_filtering(self):
        payload = osc_string("/go") + osc_string(",T")
        output = io.StringIO()
        with redirect_stdout(output):
            osc_capture.output_packet(("192.0.2.1", 9001, "192.0.2.2", 8000, payload))
        fields = output.getvalue().strip().split("\t")
        self.assertEqual(len(fields), 8)
        self.assertEqual(fields[0], "OSC")
        self.assertEqual(fields[2:7], ["192.0.2.1", "9001", "192.0.2.2", "8000", "/go"])


if __name__ == "__main__":
    unittest.main()
