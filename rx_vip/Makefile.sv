DUT                         = rx
.DEFAULT_GOAL := $(DUT)

# ------------------------------------------------------------------
# Set Path variables
# ------------------------------------------------------------------
PROGRAM_DIR = .
TB_DIR      = ./testbench
RTL_DIR     = ./rtl

# ------------------------------------------------------------------
# Set Files variables
# ------------------------------------------------------------------
# uvm test case name
TEST_NAME   = $(DUT)_test
FILELIST    ?= ./filelist_$(DUT).f

# ------------------------------------------------------------------
# Set Simulator variables
# ------------------------------------------------------------------
VCS         ?= vcs
SIMV        ?= ./simv
UVM_VER     ?= uvm-1.2
COMPLOG     ?= comp.log
RUNLOG      ?= simv.log
VERBOSITY   ?= UVM_MEDIUM
SEED        ?= $(shell 'echo $$RANDOM')
DEFINES     ?=

# Enable compile-time UVM coverage macro
UVM_DEFINES ?= UVM_NO_DEPRECATED+UVM_OBJECT_MUST_HAVE_CONSTRUCTOR+UVM_COVERAGE_ON

# Runtime coverage switch (type-override removed)
PLUS        ?= +UVM_COVERAGE

# Extend coverage metrics for functional coverage
COVERAGE    ?= line+tgl+fsm+cond+branch+assert

OPTION      ?= UVM_TR_RECORD +UVM_LOG_RECORD
#TRACE      ?= UVM_PHASE_TRACE
TRACE       ?=

# ------------------------------------------------------------------
# UVM Library Setup
# ------------------------------------------------------------------
UVM_OPTS    ?= -ntb_opts $(UVM_VER)

# ------------------------------------------------------------------
# Set Simulator variables
# ------------------------------------------------------------------
# Compile with -cm for coverage, include TB/DUT, and force 64-bit build
# Always enforce 64-bit architecture
COMPFLAGS   = -full64 -sverilog +v2k -lca \
              -timescale="1ns/100ps" \
              -debug_access+all+reverse -kdb -l comp.log \
              +define+$(UVM_DEFINES)+$(DEFINES) \
              -cm $(COVERAGE) \
              $(UVM_OPTS)

# Common runtime switches (we'll append to log instead of using "-l")
RUNFLAGS    = +UVM_VERBOSITY=$(VERBOSITY) \
              +$(PLUS) +$(TRACE) +$(OPTION) -l simv.log
# ------------------------------------------------------------------
# Phony targets
# ------------------------------------------------------------------
.PHONY: all simv compile run run_all random clean help

# Default: compile then run all tests
rx:     comp run

gui:    comp run_gui

# Compile only
compile: comp

# ------------------------------------------------------------------
# Invoke VCS compilation (always 64-bit)
# ------------------------------------------------------------------
# ----- SoC
comp: $(FILELIST)
        # Announce start of 64-bit compilation
        @echo "=== Compile SoC with 64-bit VCS ==="
        $(VCS) $(COMPFLAGS) -f $(FILELIST)
        @echo ">>> Compilation complete (64-bit mode)"   # Notify that the build has finished

# ------------------------------------------------------------------
# Run UVM Simulation
# ------------------------------------------------------------------
# Single-test alias (default behavior)
run:
        # echo header and tee into log
        @echo "=== Running default test $(TEST_NAME) ===" | tee $(log)
        $(SIMV) +UVM_TESTNAME=$(TEST_NAME) $(RUNFLAGS) +DUMP=uvmtb_$(DUT).fsdb 2>&1 | tee -a simv.log

# Use Verdi to Debug UVM by adding -gui and +UVM_VERDI_TRACE options
run_gui:
        # echo header and tee into log
        @echo "=== Running default test $(TEST_NAME) ===" | tee make_gui.log
        $(SIMV) +UVM_TESTNAME=$(TEST_NAME) -gui=verdi \
                +UVM_VERDI_TRACE="UVM_AWARE+RAL+HIER+COMPWAVE" \
                $(RUNFLAGS) 2>&1 | tee -a sim_gui.log

# random seed run, also tee both
#random: simv
#       $(SIMV) +ntb_random_seed automatic +UVM_TESTNAME=$(TEST_NAME) \
#               $(RUNFLAGS) 2>&1 | tee -a $(log)
random: simv
        $(SIMV) +ntb_random_seed=$(SEED) +UVM_TESTNAME=$(TEST_NAME) \
                $(RUNFLAGS) 2>&1 | tee -a sim_random.log

clean:
        rm -rf simv* csrc* *.tmp *.vpd *.key log *.h temp *.log \
               vcs* *.txt DVE* *.hvp urg* *.inter.vpd uvm \
               .restart* .synopsys* novas.* *.dat* *.fsdb verdi*

help:
        @echo "=============================================================="
        @echo " USAGE: make <target> <seed=XXX> <verbosity=YYY>              "
        @echo "                                                              "
        @echo " XXX is the random seed. Defaults to 1                        "
        @echo " YYY sets the verbosity filter. Defaults to UVM_MEDIUM        "
        @echo "                                                              "
        @echo " Test TARGETS                                                 "
        @echo " all        => Compile TB/DUT and run all tests               "
@echo "  compile      => Compile TB and DUT files              "
@echo "  comp         => Compile TB/DUT                        "
@echo "  run          => Run default UVM_TESTNAME              "
@echo "  random       => Run default test with random seed     "
@echo "  clean        => Remove all intermediate files         "
@echo " EMBEDDED SETTINGS                                      "
@echo "  -timescale=\"1ns/100ps\"                               "
@echo "  -debug_all                                          "
@echo "========================================================"
