# ==============================
# HW1 - filelist_rx.f
# TB + RTL compile order
# ==============================

# ---- Include dirs (TB) ----
+incdir+testbench
+incdir+testbench/packages
+incdir+testbench/agent_rx/transactions
+incdir+testbench/agent_rx/sequences
+incdir+testbench/agent_rx
+incdir+testbench/tb_env
#+incdir+testbench/tests
+incdir+testbench/interfaces

# ---- Include dirs (RTL) ----
+incdir+rtl

# ---- TB interfaces & package ----
testbench/interfaces/rx_intf.sv

# Central TB package (includes all TB classes)
# First file to be compiled
testbench/packages/rxeng_vip_pkg.sv

# Test classes (compiled as standalone; they import soc_uvm_pkg inside)
testbench/tests/rx_test.sv

# TB top (module): clocks/resets, VIF publish, DUT instance
# Top Testbench is specified in Makefile
testbench/tb_env/uvmtb_rx.sv

# ---- RTL (submodules first, top last) ----
# Macro/model blocks (utility modules)
# Functional blocks
rtl/rx_eng.vp

# SoC top (must be last among RTL)
