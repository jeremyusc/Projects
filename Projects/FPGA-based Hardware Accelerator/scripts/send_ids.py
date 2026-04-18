#!/usr/bin/env python
# -*- coding: ascii -*-
#
# send_ids.py -- Send IDS feature vectors as UDP packets to NetFPGA
#
# Sends 11 BF16 feature values to the NetFPGA FIFO via UDP.
# Uses the same 6-byte padding trick as send_bf16.py to align data
# to BRAM[7] in the NetFPGA FIFO.
#
# Packet layout in FIFO BRAM after arrival:
#   BRAM[0]:     NF2.1 header (ctrl=0xFF)
#   BRAM[1-6]:   Eth + IP + UDP headers (42 bytes + 6 padding = 48 bytes)
#   BRAM[7]:     Features x[0..3]  (4 x BF16 = 8 bytes)
#   BRAM[8]:     Features x[4..7]  (4 x BF16 = 8 bytes)
#   BRAM[9]:     Features x[8..10] (3 x BF16 = 6 bytes, 2 bytes padding)
#
# Usage:
#   python send_ids.py                              # default attack sample
#   python send_ids.py 0.1 0.2 0.3 ... (11 floats)  # normalized features
#   python send_ids.py --csv features.csv            # batch from CSV
#   python send_ids.py --raw 0 0 0.04 ... --norm     # raw + auto-normalize
#
# Compatible with Python 2.4+ and Python 3.x (for NetFPGA node0).

import socket
import sys
import os
import struct
import time

FPGA_IP = '10.0.7.255'    # Broadcast on 10.0.4.0/22 (nf7 port0 subnet, bypasses ARP)
FPGA_PORT = 9999

# 6 bytes padding aligns BF16 data to BRAM[7]
PADDING = '\x00\x00\x00\x00\x00\x00'

N_FEATURES = 11

# Default test sample: attack from NSL-KDD (normalized, from train_ids.py)
DEFAULT_FEATURES = [0.0, 0.0, 0.04, 0.06, 0.04, 0.0, 0.039, 0.06, 0.0, 0.0, 0.448]


def float_to_bf16(f):
    """Convert float to 16-bit BF16 (truncation, matching hardware)."""
    raw = struct.pack('>f', f)
    return (ord(raw[0]) << 8) | ord(raw[1])


def bf16_to_float(b):
    """Convert 16-bit BF16 to float."""
    b = b & 0xFFFF
    raw = struct.pack('>HH', b, 0)
    return struct.unpack('>f', raw)[0]


def hex_to_bytes_compat(hex_str):
    """Convert hex string to bytes. Python 2.4 compatible."""
    hex_str = hex_str.replace('_', '').replace(' ', '')
    result = ''
    for i in range(0, len(hex_str), 2):
        result += chr(int(hex_str[i:i + 2], 16))
    return result


def pack_features(features):
    """Pack 11 float features as BF16 bytes (22 bytes, padded to 32).

    Padding to 32 bytes ensures total frame = 42+6+32 = 80 bytes,
    giving word_length=10 in NF2.1 header, so FIFO stores 9 data words
    (BRAM[1..9] = 72 bytes) which covers features at BRAM[7..9].
    """
    data = ''
    for f in features:
        bf = float_to_bf16(f)
        data += struct.pack('>H', bf)
    # Pad from 22 to 32 bytes (5 zero BF16 values)
    while len(data) < 32:
        data += struct.pack('>H', 0x0000)
    return data


def send_features(features, verbose=True):
    """Send 11 features as a UDP packet to the NetFPGA."""
    if len(features) != N_FEATURES:
        print("ERROR: expected %d features, got %d" % (N_FEATURES, len(features)))
        return False

    data = pack_features(features)
    payload = PADDING + data  # 6 + 24 = 30 bytes

    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    s.sendto(payload, (FPGA_IP, FPGA_PORT))
    s.close()

    if verbose:
        bfs = []
        for f in features:
            bf = float_to_bf16(f)
            bfs.append(bf)

        print("Sent %d features to %s:%d" % (N_FEATURES, FPGA_IP, FPGA_PORT))
        for i in range(N_FEATURES):
            print("  x[%2d] = %8.4f -> BF16 0x%04X" % (i, features[i], bfs[i]))
        print("  BRAM[7]: 0x%04X%04X%04X%04X" % (bfs[0], bfs[1], bfs[2], bfs[3]))
        print("  BRAM[8]: 0x%04X%04X%04X%04X" % (bfs[4], bfs[5], bfs[6], bfs[7]))
        print("  BRAM[9]: 0x%04X%04X%04X0000" % (bfs[8], bfs[9], bfs[10]))

    return True


def load_normalization_params():
    """Load normalization parameters from trained weights JSON."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    json_path = os.path.join(script_dir, '..', 'programs', 'gpu',
                             'data_ids_trained_weights.json')
    if not os.path.exists(json_path):
        return None

    try:
        import json
        f = open(json_path, 'r')
        data = json.load(f)
        f.close()
        return data.get('norm_params', None)
    except Exception:
        return None


def normalize_features(raw_features, norm_params):
    """Normalize raw features to [0, 1] using training min/max."""
    mins = norm_params['mins']
    maxs = norm_params['maxs']
    normalized = []
    for i in range(len(raw_features)):
        r = maxs[i] - mins[i]
        if r == 0:
            r = 1.0
        val = (raw_features[i] - mins[i]) / r
        val = max(0.0, min(1.0, val))  # clamp
        normalized.append(val)
    return normalized


def send_batch(csv_path, delay=0.5, do_normalize=False):
    """Send batch of feature vectors from CSV."""
    norm_params = None
    if do_normalize:
        norm_params = load_normalization_params()
        if norm_params is None:
            print("ERROR: cannot load normalization params")
            return

    f = open(csv_path, 'r')
    lines = f.readlines()
    f.close()

    # Skip header if present
    start = 0
    try:
        float(lines[0].strip().split(',')[0])
    except (ValueError, IndexError):
        start = 1

    count = 0
    for i in range(start, len(lines)):
        line = lines[i].strip()
        if not line:
            continue
        parts = line.split(',')
        if len(parts) < N_FEATURES:
            continue

        features = [float(p.strip()) for p in parts[:N_FEATURES]]

        if do_normalize and norm_params:
            features = normalize_features(features, norm_params)

        count += 1
        print("\n--- Sample %d ---" % count)
        send_features(features)

        if delay > 0:
            time.sleep(delay)

    print("\nSent %d samples (delay=%.2fs)" % (count, delay))

    # Hint: if CSV has true_label column, it can be used on nf5 for accuracy
    if lines and "true_label" in lines[0]:
        print("\nFor accuracy comparison on nf6:")
        print("  scp %s nf6:~/zil_testing_folder/" % csv_path)
        print("  python lab10reg.py ids_batch_packets %d %s" % (
            count, os.path.basename(csv_path)))


def main():
    args = sys.argv[1:]

    if not args:
        # Default: send attack sample
        print("Sending default attack sample (normalized features)")
        send_features(DEFAULT_FEATURES)
        return

    if args[0] == '--csv':
        if len(args) < 2:
            print("Usage: send_ids.py --csv <file.csv> [--delay <seconds>] [--norm]")
            return
        csv_path = args[1]
        delay = 0.5
        do_norm = False
        for i in range(2, len(args)):
            if args[i] == '--delay' and i + 1 < len(args):
                delay = float(args[i + 1])
            if args[i] == '--norm':
                do_norm = True
        send_batch(csv_path, delay, do_norm)
        return

    if args[0] in ('--help', '-h', 'help'):
        print("send_ids.py -- Send IDS feature vectors to NetFPGA")
        print("")
        print("Usage:")
        print("  send_ids.py                              Send default attack sample")
        print("  send_ids.py <f0> <f1> ... <f10>           Send 11 normalized floats")
        print("  send_ids.py --csv <file> [--delay 0.5]    Batch from CSV (0.5s default)")
        print("  send_ids.py --csv <file> --norm           Batch + auto-normalize")
        print("")
        print("Use with ids_batch_packets on nf5 for end-to-end batch testing.")
        print("")
        print("Features (11, normalized to [0,1]):")
        print("  src_bytes, dst_bytes, same_srv_rate, diff_srv_rate,")
        print("  dst_host_same_srv_rate, logged_in, dst_host_srv_count,")
        print("  dst_host_diff_srv_rate, dst_host_srv_serror_rate,")
        print("  dst_host_same_src_port_rate, count")
        return

    # Direct feature values from command line
    if len(args) == N_FEATURES:
        features = [float(a) for a in args]
        send_features(features)
    else:
        print("ERROR: expected %d feature values, got %d" % (N_FEATURES, len(args)))
        print("Use --help for usage information")


if __name__ == '__main__':
    main()
