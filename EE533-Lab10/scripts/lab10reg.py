#!/usr/bin/env python
# -*- coding: ascii -*-
#
# lab10reg.py -- Lab10 IDS inference deployment for NetFPGA NF2.1
#
# Extends lab9reg.py with IDS-specific commands for loading trained
# weights, running inference, and batch testing.
#
# Compatible with Python 2.4+ and Python 3.x (NetFPGA host).
# Uses the same regread/regwrite CLI wrappers as lab9reg.py.
#
# Usage:  python lab10reg.py <command> [args...]
#
# Commands:
#   ids_load                 Load IDS kernel + trained weights into GPU
#   ids_infer <hex_values>   Run single inference on 11 BF16 features
#   ids_test                 Run IDS test with default trained data
#   ids_batch <csv_file>     Batch inference on CSV file of features
#   ids_status               Show GPU status + last inference result
#
# Also supports all lab9reg.py commands (status, gpu_*, dma_*, etc.)

import os
import sys
import time

# Add script directory to path for lab9reg import
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)

# Import everything from lab9reg
from lab9reg import (
    regread, regwrite,
    fifo_reset, fifo_set_mode, fifo_drain,
    bram_read, bram_write,
    gpu_assert_reset, gpu_release_reset, gpu_read_status,
    gpu_write_imem, gpu_read_imem,
    gpu_write_dmem, gpu_read_dmem,
    gpu_poll_done, gpu_read_cycle_count,
    dma_transfer_and_wait,
    find_hex, parse_hex_file, load_hex, load_dmem_hex,
    STATUS_REG, FIFO_MODE_REG,
    GPU_CTRL_REG, GPU_STATUS_REG,
)

# GPU core clock period at 125 MHz target (ns). Used only to translate
# cycle counts to microseconds for display.
GPU_CORE_CLK_NS = 8.0

# ============================================================================
# IDS DMEM layout constants (must match ann_ids_11_16_8_2.asm)
# ============================================================================
L1_IN  = 11
L1_OUT = 16
L2_OUT = 8
L3_OUT = 2

X_BASE   = 0       # Input features [0..10]
W1_BASE  = 11      # Layer 1 weights
B1_BASE  = 187     # Layer 1 biases
H1_BASE  = 203     # Layer 1 output
W2_BASE  = 219     # Layer 2 weights
B2_BASE  = 347     # Layer 2 biases
H2_BASE  = 355     # Layer 2 output
W3_BASE  = 363     # Layer 3 weights
B3_BASE  = 379     # Layer 3 biases
OUT_BASE = 381     # Final output [381..382]
DMEM_SIZE = 383

# Default file paths (searched in multiple locations)
KERNEL_HEX = "ann_ids_11_16_8_2.hex"
DATA_HEX   = "data_ids_trained.hex"


def find_ids_hex(filename):
    """Search for hex file in common deployment locations."""
    candidates = [
        filename,
        os.path.join(SCRIPT_DIR, filename),
        os.path.join(".", filename),
        os.path.join(SCRIPT_DIR, "..", "programs", "gpu", filename),
        os.path.join("programs", "gpu", filename),
    ]
    for path in candidates:
        if os.path.exists(path):
            return path
    return filename

# BF16 lookup for display
BF16_TABLE = {
    0x0000: 0.0,    0x3F80: 1.0,    0x4000: 2.0,    0x3F00: 0.5,
    0x3E80: 0.25,   0x4040: 3.0,    0x4080: 4.0,    0xBF80: -1.0,
    0xC000: -2.0,
}


def bf16_to_float_approx(bf16_val):
    """Convert BF16 to float (approximate, for display). Python 2.4+ safe."""
    import struct
    bf16_val = bf16_val & 0xFFFF
    raw = struct.pack(">HH", bf16_val, 0)
    return struct.unpack(">f", raw)[0]


def show_bf16_word(hi, lo):
    """Display a 64-bit word as 4 BF16 lanes."""
    word = (hi << 32) | lo
    lanes = []
    for i in range(4):
        bf = (word >> (48 - 16 * i)) & 0xFFFF
        val = bf16_to_float_approx(bf)
        lanes.append("%.4f" % val)
    return "[%s]" % ", ".join(lanes)


# ============================================================================
# IDS commands
# ============================================================================

def cmd_ids_load(kernel_hex=None, data_hex=None):
    """Load IDS kernel and trained weights into GPU DMEM/IMEM.

    Optional arguments let callers point at specific hex files, e.g. to
    swap between the scalar and BCAST kernels for the A/B perf demo:
        cmd_ids_load("ann_ids_11_16_8_2.hex",       "data_ids_trained.hex")
        cmd_ids_load("ann_ids_11_16_8_2_bcast.hex", "data_ids_trained_bcast.hex")
    """
    print("=== Loading IDS Model ===\n")

    kernel_name = kernel_hex or KERNEL_HEX
    data_name   = data_hex   or DATA_HEX

    kernel_path = find_ids_hex(kernel_name)
    data_path   = find_ids_hex(data_name)

    print("Kernel: %s" % kernel_path)
    print("Data:   %s" % data_path)

    # Load kernel into IMEM
    print("\n1. Loading kernel into GPU IMEM...")
    n_instr = load_hex(kernel_path)

    # Load weights+data into DMEM
    print("\n2. Loading weights into GPU DMEM...")
    gpu_assert_reset()
    words = parse_hex_file(data_path)
    for i in range(len(words)):
        hi = (words[i] >> 32) & 0xFFFFFFFF
        lo = words[i] & 0xFFFFFFFF
        gpu_write_dmem(i, hi, lo)
    print("   Loaded %d DMEM words" % len(words))

    print("\nIDS model loaded. Run 'ids_infer', 'ids_test', or 'ids_perf' to classify.")


def cmd_ids_compare_perf():
    """A/B performance demo: scalar vs BCAST kernel, read hardware cycle counter.

    Loads each kernel with the default simple test data (all weights = 0.25,
    biases = 0, inputs = 1.0), runs it on the GPU, reads the hardware cycle
    counter, prints a side-by-side comparison.
    """
    print("=" * 60)
    print("IDS Inference Performance Comparison (Scalar vs BCAST)")
    print("Hardware cycle counter @ LAB8_GPU_CYCLE_COUNT (0x30)")
    print("=" * 60)

    variants = [
        ("Scalar (baseline)", "ann_ids_11_16_8_2.hex",
                              "data_ids_11_16_8_2.hex"),
        ("BCAST (optimized)", "ann_ids_11_16_8_2_bcast.hex",
                              "data_ids_11_16_8_2_bcast.hex"),
    ]

    results = []
    for label, kernel_hex, data_hex in variants:
        print("\n--- %s ---" % label)
        cmd_ids_load(kernel_hex, data_hex)
        elapsed, cycles = cmd_ids_run()
        if cycles < 0:
            print("FAILED: %s did not complete" % label)
            return -1
        us = cycles * GPU_CORE_CLK_NS / 1000.0
        print("  GPU cycles  : %d" % cycles)
        print("  Time @125MHz: %.2f us" % us)
        print("  Wallclk     : %.3f ms" % (elapsed * 1000))
        results.append((label, cycles, us, elapsed))

    # Summary table
    print("\n" + "=" * 60)
    print("Summary")
    print("=" * 60)
    print("%-20s %10s %14s %14s" % ("Kernel", "Cycles", "us @125MHz", "Wallclk ms"))
    print("-" * 60)
    for label, cycles, us, elapsed in results:
        print("%-20s %10d %14.2f %14.3f" % (label, cycles, us, elapsed * 1000))
    print("-" * 60)
    speedup = float(results[0][1]) / results[1][1]
    saved = results[0][1] - results[1][1]
    print("Speedup:  %.2fx  (%d -> %d cycles, %d saved)" % (
        speedup, results[0][1], results[1][1], saved))
    print("=" * 60)
    return 0


def cmd_ids_load_inputs(feature_values):
    """Load 11 input features into GPU DMEM[0..10] as replicated BF16.

    feature_values: list of 11 floats (already normalized to [0,1])
    """
    import struct

    for i in range(L1_IN):
        val = feature_values[i]
        # Convert float to BF16
        raw = struct.pack(">f", val)
        b0 = ord(raw[0])
        b1 = ord(raw[1])
        bf = (b0 << 8) | b1
        # Replicate across 4 lanes
        hi = (bf << 16) | bf
        lo = (bf << 16) | bf
        gpu_write_dmem(i, hi, lo)


def cmd_ids_run():
    """Release GPU reset, wait for kernel_done, return (wallclock_s, gpu_cycles).

    wallclock_s is dominated by PCI poll overhead (~5 ms). gpu_cycles is
    measured by the hardware counter register (LAB8_GPU_CYCLE_COUNT) and
    reflects the pure kernel runtime, e.g. 2402 cycles for the scalar IDS
    kernel and 732 cycles for the BCAST-optimized kernel. The counter
    clears automatically on gpu_assert_reset().
    """
    gpu_release_reset()
    t0 = time.time()
    if gpu_poll_done(timeout_ms=5000):
        elapsed = time.time() - t0
        cycles = gpu_read_cycle_count()
        gpu_assert_reset()
        return elapsed, cycles
    else:
        gpu_assert_reset()
        print("ERROR: GPU did not halt (timeout)")
        return -1, -1


def cmd_ids_perf():
    """One-shot performance report for the currently-loaded GPU kernel.

    Reads back the cycle counter and formats a human-friendly summary.
    Assumes the kernel has already been loaded (use cmd_ids_load first)
    and the GPU is currently in reset. Runs once and prints the numbers.
    """
    elapsed, cycles = cmd_ids_run()
    if cycles < 0:
        return -1
    us = cycles * GPU_CORE_CLK_NS / 1000.0
    print("GPU kernel:")
    print("  cycles       : %d" % cycles)
    print("  time @125MHz : %.2f us" % us)
    print("  host wallclk : %.2f ms (PCI overhead dominated)" % (elapsed * 1000.0))
    return cycles


def cmd_ids_read_output():
    """Read classification result from DMEM[381..382]."""
    hi0, lo0 = gpu_read_dmem(OUT_BASE)
    hi1, lo1 = gpu_read_dmem(OUT_BASE + 1)

    # Use lane 0 (lowest 16 bits) for the scalar value
    logit0 = bf16_to_float_approx(lo0 & 0xFFFF)
    logit1 = bf16_to_float_approx(lo1 & 0xFFFF)

    if logit0 > logit1:
        pred = 0
    else:
        pred = 1
    if pred == 0:
        label = "normal"
    else:
        label = "attack"

    return logit0, logit1, pred, label


def cmd_ids_infer(feature_hex_str=None):
    """Run single IDS inference.

    feature_hex_str: 11 BF16 hex values separated by underscores,
                     e.g. "0000_0000_3F80_3E80_..."
                     If None, uses whatever is already in DMEM.
    """
    print("=== IDS Inference ===\n")

    if feature_hex_str:
        parts = feature_hex_str.split("_")
        if len(parts) != L1_IN:
            print("ERROR: Expected %d features, got %d" % (L1_IN, len(parts)))
            return
        print("Loading input features...")
        for i in range(L1_IN):
            bf = int(parts[i], 16)
            hi = (bf << 16) | bf
            lo = (bf << 16) | bf
            gpu_write_dmem(i, hi, lo)
            val = bf16_to_float_approx(bf)
            print("  x[%2d] = 0x%04x (%.4f)" % (i, bf, val))

    print("\nRunning GPU kernel...")
    elapsed, cycles = cmd_ids_run()

    if elapsed < 0:
        return

    print("  GPU cycles  : %d (%.2f us @125MHz)" % (
        cycles, cycles * GPU_CORE_CLK_NS / 1000.0))
    print("  Wallclk     : %.3f ms (PCI polling)" % (elapsed * 1000))

    logit0, logit1, pred, label = cmd_ids_read_output()

    print("\nResult:")
    print("  Logit[0] (normal): %.4f" % logit0)
    print("  Logit[1] (attack): %.4f" % logit1)
    print("  Classification:    %s (class %d)" % (label.upper(), pred))

    # Show layer outputs for debugging
    print("\nLayer outputs:")
    print("  L1 (h1[0..15]):")
    for i in range(L1_OUT):
        hi, lo = gpu_read_dmem(H1_BASE + i)
        print("    h1[%2d] = %s" % (i, show_bf16_word(hi, lo)))
    print("  L2 (h2[0..7]):")
    for i in range(L2_OUT):
        hi, lo = gpu_read_dmem(H2_BASE + i)
        print("    h2[%2d] = %s" % (i, show_bf16_word(hi, lo)))
    print("  L3 (out[0..1]):")
    for i in range(L3_OUT):
        hi, lo = gpu_read_dmem(OUT_BASE + i)
        print("    out[%d] = %s" % (i, show_bf16_word(hi, lo)))


def cmd_ids_test():
    """Run IDS inference with the default trained test data."""
    print("=== IDS Test (default trained data) ===\n")

    # Load kernel + weights + default test input
    cmd_ids_load()

    print("\n--- Running inference ---")
    elapsed, cycles = cmd_ids_run()

    if elapsed < 0:
        return

    print("  GPU cycles : %d (%.2f us @125MHz)" % (
        cycles, cycles * GPU_CORE_CLK_NS / 1000.0))
    print("  Wallclk    : %.3f ms" % (elapsed * 1000))

    logit0, logit1, pred, label = cmd_ids_read_output()
    print("\nResult:")
    print("  Logit[0] (normal): %.4f" % logit0)
    print("  Logit[1] (attack): %.4f" % logit1)
    print("  Classification:    %s" % label.upper())

    # Verify against known expected output
    # Default test sample is an attack (from train_ids.py)
    if pred == 1:
        print("\n!!! PASS !!! (correctly classified as attack)")
    else:
        print("\n*** FAIL *** (expected attack, got normal)")


def cmd_ids_batch(csv_path):
    """Batch inference: read normalized features from CSV, classify each.

    CSV format: one sample per line, 11 comma-separated floats (normalized).
    First line may be a header (skipped if non-numeric).
    """
    import struct

    print("=== IDS Batch Inference ===\n")

    # Load kernel + weights once
    cmd_ids_load()

    # Read CSV
    if not os.path.exists(csv_path):
        csv_path = find_hex(csv_path)
    f = open(csv_path, "r")
    lines = f.readlines()
    f.close()

    # Skip header
    start = 0
    try:
        float(lines[0].strip().split(",")[0])
    except (ValueError, IndexError):
        start = 1

    results = []
    total = 0
    t_start = time.time()

    for line_idx in range(start, len(lines)):
        line = lines[line_idx].strip()
        if not line:
            continue
        parts = line.split(",")
        if len(parts) < L1_IN:
            continue

        features = []
        for p in parts[:L1_IN]:
            features.append(float(p.strip()))

        # Load inputs
        cmd_ids_load_inputs(features)

        # Run
        elapsed, _cycles = cmd_ids_run()
        if elapsed < 0:
            print("ERROR at sample %d" % total)
            continue

        logit0, logit1, pred, label = cmd_ids_read_output()
        results.append(pred)
        total += 1

        # Print progress every 10 samples
        if total % 10 == 0 or total <= 5:
            print("  [%4d] %s  logits=(%.2f, %.2f)" % (total, label, logit0, logit1))

    t_total = time.time() - t_start
    print("\n--- Batch Results ---")
    print("  Samples:  %d" % total)
    print("  Normal:   %d" % results.count(0))
    print("  Attack:   %d" % results.count(1))
    if total > 0:
        print("  Time:     %.2f s (%.1f ms/sample)" % (t_total, t_total / total * 1000))

    # Write results CSV
    out_path = csv_path.replace(".csv", "_results.csv")
    f = open(out_path, "w")
    f.write("sample_idx,prediction,label\n")
    for i in range(len(results)):
        if results[i] == 0:
            lbl = "normal"
        else:
            lbl = "attack"
        f.write("%d,%d,%s\n" % (i, results[i], lbl))
    f.close()
    print("  Results saved to: %s" % out_path)


def _wait_for_udp_packet(timeout_s=30):
    """Reset FIFO and wait for a UDP (IPv4) packet, skipping ARP and other traffic.

    Returns True if UDP packet is ready in FIFO, False on timeout.
    EtherType is at BRAM[2] lo[31:16]: 0x0800=IPv4, 0x0806=ARP.
    """
    # Mode 0 needed to receive packets; mode 2 needed for PCI BRAM reads
    # (Port B mux: mode 0 = rd_ptr, mode 1/2 = proc_addr)
    fifo_set_mode(0)
    fifo_reset()
    time.sleep(0.1)
    print("Waiting for UDP packet (skipping ARP)... send from node0 now")
    deadline = time.time() + timeout_s
    skipped = 0

    while time.time() < deadline:
        # Poll in mode 0 (FIFO receives packets)
        s = regread(STATUS_REG)
        if not (s & 1):
            time.sleep(0.05)
            continue

        # Packet arrived -- switch to mode 2 to read BRAM via PCI
        fifo_set_mode(2)

        # Check EtherType at BRAM[2]
        ctrl2, hi2, lo2 = bram_read(2)
        ethertype = (lo2 >> 16) & 0xFFFF

        if ethertype == 0x0800:
            # IPv4 (UDP) -- stay in mode 2 for further reads
            print("  Got IPv4/UDP packet (skipped %d non-UDP)" % skipped)
            return True
        else:
            # ARP or other -- discard
            skipped += 1
            if skipped <= 10:
                ctrl0, h0, l0 = bram_read(0)
                if ethertype == 0x0806:
                    ptype = "ARP"
                else:
                    ptype = "0x%04X" % ethertype
                print("  Skipped %s (hdr=0x%08x_%08x)" % (ptype, h0, l0))
            # Back to mode 0 to receive next packet
            fifo_set_mode(0)
            fifo_reset()
            time.sleep(0.05)

    print("Timeout waiting for UDP packet (%d non-UDP skipped)" % skipped)
    return False


def cmd_ids_from_packet(bram_start=7):
    """Run IDS inference on features received via UDP packet.

    Resets FIFO, waits for a UDP packet (filters out ARP), then reads
    11 BF16 features from FIFO BRAM, replicates to SIMD lanes, runs kernel.

    Packet layout (from send_ids.py):
      BRAM[7]: features x[0..3]  (4 x BF16)
      BRAM[8]: features x[4..7]  (4 x BF16)
      BRAM[9]: features x[8..10] (3 x BF16 + 1 padding)
    """
    print("=== IDS Inference from Packet ===\n")

    if not _wait_for_udp_packet():
        return

    print("UDP packet ready in FIFO")

    # Read 3 BRAM words containing 11 BF16 features
    features_bf16 = []
    for word_idx in range(3):
        ctrl, hi, lo = bram_read(bram_start + word_idx)
        # Extract 4 BF16 values per word: [63:48], [47:32], [31:16], [15:0]
        word64 = (hi << 32) | lo
        for lane in range(4):
            bf = (word64 >> (48 - 16 * lane)) & 0xFFFF
            features_bf16.append(bf)

    # Trim to 11 features (12th is padding)
    features_bf16 = features_bf16[:L1_IN]

    print("Extracted %d BF16 features from BRAM[%d..%d]:" % (
        L1_IN, bram_start, bram_start + 2))
    for i in range(L1_IN):
        val = bf16_to_float_approx(features_bf16[i])
        print("  x[%2d] = 0x%04X (%.4f)" % (i, features_bf16[i], val))

    # Switch to GPU mode
    print("\nSwitching to GPU mode...")
    fifo_set_mode(2)

    # Replicate each feature to 4 SIMD lanes and write to GPU DMEM[0..10]
    print("Writing features to GPU DMEM[0..10] (replicated)...")
    for i in range(L1_IN):
        bf = features_bf16[i]
        hi = (bf << 16) | bf
        lo = (bf << 16) | bf
        gpu_write_dmem(i, hi, lo)

    # Run GPU kernel
    print("Running GPU kernel...")
    t0 = time.time()
    gpu_release_reset()
    if not gpu_poll_done(timeout_ms=5000):
        print("ERROR: GPU timeout")
        gpu_assert_reset()
        fifo_set_mode(0)
        return
    elapsed = time.time() - t0
    gpu_assert_reset()

    print("  Completed in %.3f ms" % (elapsed * 1000))

    # Read result
    logit0, logit1, pred, label = cmd_ids_read_output()

    print("\nClassification Result:")
    print("  Logit[0] (normal): %.4f" % logit0)
    print("  Logit[1] (attack): %.4f" % logit1)
    print("  ==> %s <==" % label.upper())

    # Form response packet and drain back to node0
    print("\nSending response packet to node0...")
    _form_and_drain_response()


def cmd_ids_from_packet_loop(count=0, bram_start=7):
    """Continuously process incoming packets. count=0 means infinite."""
    print("=== IDS Packet Processing Loop ===")
    print("Waiting for packets... (Ctrl+C to stop)\n")

    # Load kernel + weights once
    cmd_ids_load()
    fifo_set_mode(0)
    fifo_reset()

    processed = 0
    normal_count = 0
    attack_count = 0
    total_time = 0.0
    skipped_arp = 0

    try:
        while count == 0 or processed < count:
            # Poll for packet in mode 0
            s = regread(STATUS_REG)
            if not (s & 1):
                time.sleep(0.05)
                continue

            # Packet arrived -- switch to mode 2 for PCI BRAM reads
            fifo_set_mode(2)

            # Filter non-IPv4 (ARP etc.)
            ctrl2, hi2, lo2 = bram_read(2)
            ethertype = (lo2 >> 16) & 0xFFFF
            if ethertype != 0x0800:
                skipped_arp += 1
                fifo_set_mode(0)
                fifo_reset()
                time.sleep(0.05)
                continue

            # Read 11 BF16 features from BRAM[7..9]
            features_bf16 = []
            for word_idx in range(3):
                ctrl, hi, lo = bram_read(bram_start + word_idx)
                word64 = (hi << 32) | lo
                for lane in range(4):
                    bf = (word64 >> (48 - 16 * lane)) & 0xFFFF
                    features_bf16.append(bf)
            features_bf16 = features_bf16[:L1_IN]

            # Load features into GPU DMEM[0..10]
            for i in range(L1_IN):
                bf = features_bf16[i]
                hi_val = (bf << 16) | bf
                lo_val = (bf << 16) | bf
                gpu_write_dmem(i, hi_val, lo_val)

            # Run GPU kernel
            t0 = time.time()
            gpu_release_reset()
            if not gpu_poll_done(timeout_ms=5000):
                print("[%4d] ERROR: GPU timeout" % (processed + 1))
                gpu_assert_reset()
                fifo_set_mode(0)
                fifo_reset()
                continue
            elapsed = time.time() - t0
            gpu_assert_reset()
            total_time += elapsed

            # Read result and send response packet
            logit0, logit1, pred, label = _form_and_drain_response()
            processed += 1
            if pred == 0:
                normal_count += 1
            else:
                attack_count += 1

            print("[%4d] %-6s  logits=(%.2f, %.2f)  %.1f ms" % (
                processed, label.upper(), logit0, logit1, elapsed * 1000))

            # Reset FIFO for next packet (drain already switched to mode 0)
            fifo_reset()

    except KeyboardInterrupt:
        print("\n\nStopped by user.")

    print("\n--- Summary ---")
    print("  Processed: %d" % processed)
    print("  Normal:    %d" % normal_count)
    print("  Attack:    %d" % attack_count)
    if skipped_arp > 0:
        print("  ARP skipped: %d" % skipped_arp)
    if processed > 0:
        print("  Avg time:  %.1f ms/inference" % (total_time / processed * 1000))


def cmd_ids_status():
    """Show GPU status and last inference result."""
    print("=== IDS Status ===\n")

    s = gpu_read_status()
    kernel_done = s & 1
    dma_busy = (s >> 1) & 1
    print("GPU STATUS: 0x%08x" % s)
    print("  kernel_done: %d" % kernel_done)
    print("  dma_busy:    %d" % dma_busy)

    if kernel_done:
        logit0, logit1, pred, label = cmd_ids_read_output()
        print("\nLast inference result:")
        print("  Logit[0] (normal): %.4f" % logit0)
        print("  Logit[1] (attack): %.4f" % logit1)
        print("  Classification:    %s" % label.upper())
    else:
        print("\nNo inference result available (kernel not done)")


# ============================================================================
# Batch packet inference helpers
# ============================================================================

def _load_labels_from_csv(csv_path):
    """Load ground truth labels from CSV or plain text file.

    Supports two formats:
      - CSV with 'true_label' column header (e.g. from gen_test_csv.py)
      - Plain text, one integer label per line
    """
    f = open(csv_path, "r")
    lines = f.readlines()
    f.close()

    if not lines:
        return []

    # Check for true_label column in header
    header = lines[0].strip().split(",")
    label_idx = -1
    for i in range(len(header)):
        if header[i].strip() == "true_label":
            label_idx = i
            break

    if label_idx >= 0:
        labels = []
        for i in range(1, len(lines)):
            line = lines[i].strip()
            if not line:
                continue
            parts = line.split(",")
            if len(parts) > label_idx:
                labels.append(int(parts[label_idx].strip()))
        return labels

    # Fallback: one label per line
    labels = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            labels.append(int(line))
        except ValueError:
            continue
    return labels


def _print_batch_summary(results, true_labels, skipped_arp):
    """Print summary statistics and optional confusion matrix."""
    total = len(results)
    if total == 0:
        print("\nNo samples processed.")
        return

    preds = [r[2] for r in results]
    normal_count = len([p for p in preds if p == 0])
    attack_count = len([p for p in preds if p == 1])
    times = [r[3] for r in results]
    avg_ms = sum(times) / len(times)

    print("\n" + "=" * 50)
    print("BATCH RESULTS SUMMARY")
    print("=" * 50)
    print("  Samples processed: %d" % total)
    print("  Predicted normal:  %d" % normal_count)
    print("  Predicted attack:  %d" % attack_count)
    if skipped_arp > 0:
        print("  ARP packets skipped: %d" % skipped_arp)
    print("")
    print("  Inference timing:")
    print("    Average: %.1f ms" % avg_ms)
    print("    Min:     %.1f ms" % min(times))
    print("    Max:     %.1f ms" % max(times))
    print("    Total:   %.1f ms" % sum(times))

    if true_labels is not None and len(true_labels) >= total:
        tp = 0  # true positive: attack predicted as attack
        tn = 0  # true negative: normal predicted as normal
        fp = 0  # false positive: normal predicted as attack
        fn = 0  # false negative: attack predicted as normal
        for i in range(total):
            pred = results[i][2]
            true = true_labels[i]
            if true == 1 and pred == 1:
                tp += 1
            elif true == 0 and pred == 0:
                tn += 1
            elif true == 0 and pred == 1:
                fp += 1
            else:
                fn += 1

        correct = tp + tn
        accuracy = 100.0 * correct / total

        print("")
        print("  Accuracy: %d / %d = %.1f%%" % (correct, total, accuracy))
        print("")
        print("  Confusion Matrix:")
        print("                    Predicted")
        print("                    Normal  Attack")
        print("    Actual Normal    %4d    %4d" % (tn, fp))
        print("    Actual Attack    %4d    %4d" % (fn, tp))

        if tp + fp > 0:
            precision = 100.0 * tp / (tp + fp)
            print("\n  Precision (attack): %.1f%%" % precision)
        if tp + fn > 0:
            recall = 100.0 * tp / (tp + fn)
            print("  Recall (attack):    %.1f%%" % recall)


def _save_results_csv(results, true_labels, out_path):
    """Save per-sample results to CSV."""
    has_labels = true_labels is not None and len(true_labels) >= len(results)
    f = open(out_path, "w")
    if has_labels:
        f.write("sample,logit_normal,logit_attack,prediction,label,"
                "true_label,correct,inference_ms\n")
    else:
        f.write("sample,logit_normal,logit_attack,prediction,label,"
                "inference_ms\n")

    for i in range(len(results)):
        logit0, logit1, pred, ms = results[i]
        if pred == 0:
            lbl = "normal"
        else:
            lbl = "attack"
        if has_labels:
            tl = true_labels[i]
            if pred == tl:
                correct = 1
            else:
                correct = 0
            f.write("%d,%.4f,%.4f,%d,%s,%d,%d,%.1f\n" % (
                i, logit0, logit1, pred, lbl, tl, correct, ms))
        else:
            f.write("%d,%.4f,%.4f,%d,%s,%.1f\n" % (
                i, logit0, logit1, pred, lbl, ms))
    f.close()
    print("  Results saved to: %s" % out_path)


def _form_and_drain_response(bram_start=7):
    """Form response packet with inference result and drain to node0.

    Reads GPU DMEM output logits, swaps incoming packet's src/dst
    addresses in FIFO BRAM, writes classification result at BRAM[bram_start],
    and drains the packet out via MAC0.

    Must be called in mode 2 with inference complete (gpu_assert_reset done).
    Incoming packet headers must still be in BRAM[1..6].

    Response payload at BRAM[bram_start]:
      hi = {logit0_bf16, logit1_bf16}
      lo = {prediction_u16, 0x0000}

    Returns (logit0_float, logit1_float, pred, label).
    """
    # Read raw BF16 logits from GPU DMEM
    dm_hi0, dm_lo0 = gpu_read_dmem(OUT_BASE)
    dm_hi1, dm_lo1 = gpu_read_dmem(OUT_BASE + 1)
    logit0_bf16 = dm_lo0 & 0xFFFF
    logit1_bf16 = dm_lo1 & 0xFFFF
    logit0 = bf16_to_float_approx(logit0_bf16)
    logit1 = bf16_to_float_approx(logit1_bf16)
    if logit0 > logit1:
        pred = 0
        label = "normal"
    else:
        pred = 1
        label = "attack"

    # --- Swap Ethernet MAC addresses (BRAM[1..2]) ---
    # BRAM[1] = {DstMAC[0:5], SrcMAC[0:1]}
    # BRAM[2] = {SrcMAC[2:5], EtherType[0:1], IP_ver_IHL, IP_TOS}
    c1, hi1_v, lo1_v = bram_read(1)
    c2, hi2_v, lo2_v = bram_read(2)
    new_hi1 = ((lo1_v & 0xFFFF) << 16) | ((hi2_v >> 16) & 0xFFFF)
    new_lo1 = ((hi2_v & 0xFFFF) << 16) | ((hi1_v >> 16) & 0xFFFF)
    new_hi2 = ((hi1_v & 0xFFFF) << 16) | ((lo1_v >> 16) & 0xFFFF)
    bram_write(1, 0x00, new_hi1, new_lo1)
    bram_write(2, 0x00, new_hi2, lo2_v)  # lo2 unchanged (EtherType + IP start)

    # --- Swap IP src/dst addresses (BRAM[4..5]) ---
    # BRAM[4] = {IP_checksum[0:1], SrcIP[0:3], DstIP[0:1]}
    # BRAM[5] = {DstIP[2:3], UDP_srcPort[0:1], UDP_dstPort[0:1], UDP_len[0:1]}
    # IP checksum unchanged (swapping src/dst doesn't change the sum)
    c4, hi4_v, lo4_v = bram_read(4)
    c5, hi5_v, lo5_v = bram_read(5)
    new_hi4 = (hi4_v & 0xFFFF0000) | (lo4_v & 0xFFFF)
    new_lo4 = (hi5_v & 0xFFFF0000) | (hi4_v & 0xFFFF)
    # Swap UDP ports: old srcPort->dstPort, old dstPort->srcPort
    new_hi5 = (lo4_v & 0xFFFF0000) | ((lo5_v >> 16) & 0xFFFF)
    new_lo5 = ((hi5_v & 0xFFFF) << 16) | (lo5_v & 0xFFFF)
    bram_write(4, 0x00, new_hi4, new_lo4)
    bram_write(5, 0x00, new_hi5, new_lo5)

    # --- Zero UDP checksum + padding (BRAM[6]) ---
    bram_write(6, 0x00, 0x00000000, 0x00000000)

    # --- Write result data at BRAM[bram_start] ---
    res_hi = ((logit0_bf16 & 0xFFFF) << 16) | (logit1_bf16 & 0xFFFF)
    res_lo = ((pred & 0xFFFF) << 16)
    bram_write(bram_start, 0x00, res_hi, res_lo)

    # --- Zero remaining feature data (BRAM[bram_start+1..+3]) ---
    for i in range(1, 4):
        bram_write(bram_start + i, 0x00, 0, 0)

    # --- Update NF2.1 header: dst_port=MAC0, src_port=CPU0 ---
    c0, hi0_v, lo0_v = bram_read(0)
    new_hi0 = (0x0001 << 16) | (hi0_v & 0xFFFF)   # dst=MAC0, keep word_len
    new_lo0 = (0x0002 << 16) | (lo0_v & 0xFFFF)   # src=CPU0, keep byte_len
    bram_write(0, 0xFF, new_hi0, new_lo0)

    # --- Switch to mode 0 and drain ---
    fifo_set_mode(0)
    fifo_drain()
    # Wait for drain to complete (pkt_ready clears when done)
    deadline = time.time() + 0.5
    while time.time() < deadline:
        s = regread(STATUS_REG)
        if not (s & 1):
            break
        time.sleep(0.01)

    return logit0, logit1, pred, label


def cmd_ids_batch_packets(count, labels_csv=None, out_path=None,
                          send_response=True, bram_start=7):
    """Process N packets from network with IDS inference and analysis.

    Waits for UDP packets, extracts BF16 features from FIFO BRAM,
    runs GPU inference, and collects results with per-sample timing.
    Optionally compares against ground truth labels for accuracy
    and confusion matrix.

    Args:
        count: Number of packets to process (0 = use label count or infinite)
        labels_csv: CSV with 'true_label' column, or one label per line
        out_path: Output results CSV (default: ids_batch_results.csv)
        send_response: If True, form and drain response packet per inference
    """
    print("=== IDS Batch Packet Inference ===\n")

    # Load kernel + weights once
    cmd_ids_load()

    # Load ground truth labels if provided
    true_labels = None
    if labels_csv:
        true_labels = _load_labels_from_csv(labels_csv)
        print("\nLoaded %d ground truth labels from %s" % (
            len(true_labels), labels_csv))
        if count == 0 and len(true_labels) > 0:
            count = len(true_labels)
            print("Will process %d packets (matching label count)" % count)

    fifo_set_mode(0)
    fifo_reset()

    results = []  # list of (logit0, logit1, pred, inference_ms)
    skipped_arp = 0

    if count > 0:
        print("\nReady for %d packets. Send from node0 now.\n" % count)
    else:
        print("\nReady for packets (Ctrl+C to stop). Send from node0 now.\n")

    try:
        while count == 0 or len(results) < count:
            # Poll for packet in mode 0 (FIFO receives)
            s = regread(STATUS_REG)
            if not (s & 1):
                time.sleep(0.05)
                continue

            # Packet arrived -- switch to mode 2 for PCI BRAM reads
            fifo_set_mode(2)

            # Filter non-IPv4 (ARP etc.)
            ctrl2, hi2, lo2 = bram_read(2)
            ethertype = (lo2 >> 16) & 0xFFFF
            if ethertype != 0x0800:
                skipped_arp += 1
                if skipped_arp <= 10:
                    if ethertype == 0x0806:
                        ptype = "ARP"
                    else:
                        ptype = "0x%04X" % ethertype
                    print("  (skipped %s packet)" % ptype)
                fifo_set_mode(0)
                fifo_reset()
                time.sleep(0.05)
                continue

            # Read 11 BF16 features from BRAM[7..9]
            features_bf16 = []
            for word_idx in range(3):
                ctrl, hi, lo = bram_read(bram_start + word_idx)
                word64 = (hi << 32) | lo
                for lane in range(4):
                    bf = (word64 >> (48 - 16 * lane)) & 0xFFFF
                    features_bf16.append(bf)
            features_bf16 = features_bf16[:L1_IN]

            # Load features into GPU DMEM[0..10] (replicated across 4 lanes)
            for i in range(L1_IN):
                bf = features_bf16[i]
                hi_val = (bf << 16) | bf
                lo_val = (bf << 16) | bf
                gpu_write_dmem(i, hi_val, lo_val)

            # Run GPU kernel and time it
            t0 = time.time()
            gpu_release_reset()
            if not gpu_poll_done(timeout_ms=5000):
                print("[%4d] ERROR: GPU timeout" % (len(results) + 1))
                gpu_assert_reset()
                fifo_set_mode(0)
                fifo_reset()
                continue
            elapsed_ms = (time.time() - t0) * 1000
            gpu_assert_reset()

            # Read result (and optionally send response packet)
            if send_response:
                logit0, logit1, pred, label = _form_and_drain_response()
            else:
                logit0, logit1, pred, label = cmd_ids_read_output()
                fifo_set_mode(0)
            results.append((logit0, logit1, pred, elapsed_ms))

            n = len(results)
            true_str = ""
            if true_labels is not None and n <= len(true_labels):
                tl = true_labels[n - 1]
                if pred == tl:
                    match = "OK"
                else:
                    match = "MISS"
                true_str = "  true=%d %s" % (tl, match)
            print("[%4d] %-6s  logits=(%.2f, %.2f)  %.1f ms%s" % (
                n, label.upper(), logit0, logit1, elapsed_ms, true_str))

            # Reset FIFO for next packet
            fifo_reset()

    except KeyboardInterrupt:
        print("\n\nStopped by user.")

    # Print summary with optional confusion matrix
    _print_batch_summary(results, true_labels, skipped_arp)

    # Save results CSV
    if out_path is None:
        out_path = "ids_batch_results.csv"
    _save_results_csv(results, true_labels, out_path)


# ============================================================================
# Help
# ============================================================================

def print_help():
    print("lab10reg.py -- Lab10 IDS inference deployment")
    print("")
    print("IDS commands:")
    print("  ids_load                     Load IDS kernel + trained weights")
    print("  ids_infer [hex_vals]         Run single inference (BF16 hex, underscore-sep)")
    print("  ids_test                     Run test with default trained data")
    print("  ids_from_packet              Run inference on features from UDP packet")
    print("  ids_packet_loop [N]          Continuously process packets (N=0: infinite)")
    print("  ids_batch <csv_file>         Batch inference on CSV (PCI-only, no network)")
    print("  ids_batch_packets N [labels] [out] [--no-response]")
    print("                               Batch inference from N UDP packets")
    print("                               labels: CSV with true_label column (optional)")
    print("                               out: results CSV path (default: ids_batch_results.csv)")
    print("                               --no-response: skip response drain (faster)")
    print("  ids_status                   Show GPU status + last result")
    print("  ids_perf                     Run currently-loaded kernel, print GPU cycle count")
    print("  ids_compare_perf             A/B demo: run scalar vs BCAST kernel,")
    print("                               print side-by-side cycle counts + speedup")
    print("")
    print("Batch packet workflow (end-to-end with analysis):")
    print("  1. (nf5)  python lab10reg.py ids_batch_packets 20 test_features.csv")
    print("  2. (node0) python send_ids.py --csv test_features.csv --delay 0.5")
    print("  -> Receiver processes each packet, prints per-sample results,")
    print("     then prints confusion matrix and saves ids_batch_results.csv")
    print("")
    print("Single packet workflow:")
    print("  1. (nf5)  python lab10reg.py ids_from_packet")
    print("  2. (node0) python send_ids.py")
    print("")
    print("All lab9reg.py commands also supported (status, gpu_*, dma_*, etc.)")


# ============================================================================
# Command dispatch
# ============================================================================

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print_help()
        sys.exit(0)

    cmd = sys.argv[1].lower()

    # IDS-specific commands
    if cmd == "ids_load":
        if len(sys.argv) > 2:
            kernel_arg = sys.argv[2]
        else:
            kernel_arg = None
        if len(sys.argv) > 3:
            data_arg = sys.argv[3]
        else:
            data_arg = None
        cmd_ids_load(kernel_arg, data_arg)
    elif cmd == "ids_infer":
        if len(sys.argv) > 2:
            hex_vals = sys.argv[2]
        else:
            hex_vals = None
        cmd_ids_infer(hex_vals)
    elif cmd == "ids_test":
        cmd_ids_test()
    elif cmd == "ids_batch":
        if len(sys.argv) < 3:
            print("Usage: lab10reg.py ids_batch <csv_file>")
            sys.exit(1)
        cmd_ids_batch(sys.argv[2])
    elif cmd == "ids_from_packet":
        if len(sys.argv) > 2:
            bram = int(sys.argv[2])
        else:
            bram = 7
        cmd_ids_from_packet(bram)
    elif cmd == "ids_packet_loop":
        if len(sys.argv) > 2:
            n = int(sys.argv[2])
        else:
            n = 0
        cmd_ids_from_packet_loop(n)
    elif cmd == "ids_batch_packets":
        bp_count = 0
        bp_labels = None
        bp_out = None
        bp_respond = True
        positionals = []
        for ai in range(2, len(sys.argv)):
            arg = sys.argv[ai]
            if arg == "--no-response":
                bp_respond = False
            else:
                positionals.append(arg)
        if len(positionals) > 0:
            bp_count = int(positionals[0])
        if len(positionals) > 1:
            bp_labels = positionals[1]
        if len(positionals) > 2:
            bp_out = positionals[2]
        cmd_ids_batch_packets(bp_count, bp_labels, bp_out, bp_respond)
    elif cmd == "ids_status":
        cmd_ids_status()
    elif cmd == "ids_perf":
        cmd_ids_perf()
    elif cmd == "ids_compare_perf":
        cmd_ids_compare_perf()
    elif cmd in ("help", "-h", "--help"):
        print_help()
    else:
        # Fall through to lab9reg command dispatch
        # Re-import and use lab9reg's main dispatch
        print("Forwarding to lab9reg: %s" % cmd)
        # Remove our script name, replace with lab9reg
        sys.argv[0] = os.path.join(SCRIPT_DIR, "lab9reg.py")
        exec(open(os.path.join(SCRIPT_DIR, "lab9reg.py")).read())
