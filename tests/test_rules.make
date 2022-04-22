# This is a template Makefile to simplify writing tests
ifndef AMRVAC_DIR
$(error AMRVAC_DIR is not set)
endif

# Can be needed to compile the compare_log utility
ARCH ?= debug
export ARCH

# Location of setup script
SETUP_SCRIPT := $(AMRVAC_DIR)/setup.pl

# Disable built-in rules
.SUFFIXES:

# Tool to compare test output numerically
LOG_CMP := $(AMRVAC_DIR)/tools/fortran/compare_logs

# Number of MPI processes to use
NUM_PROCS ?= 2

# force is a dummy to force re-running tests
.PHONY: all clean force

all: $(TESTS)

clean:
	$(RM) $(TESTS) amrvac makefile *.vtu *.dat *.log *.f *.mod

# Include architecture and compilation rules for the compare_log utility
include $(AMRVAC_DIR)/arch/$(ARCH).defs
include $(AMRVAC_DIR)/arch/rules.make

LIB_DIR := $(AMRVAC_DIR)/lib/$(NDIM)d_$(ARCH)
# copy amrvac.h (in order to use the std preprocessor in the main code files, e.g. twofl); create the file if it does not exist
hdr:
ifeq ("$(wildcard amrvac.h)","")
	touch amrvac.h
endif
	@mkdir -p $(LIB_DIR)	# Prevent error message
	rsync -c amrvac.h $(LIB_DIR)/amrvac.h

%.log: $(LOG_CMP) hdr  amrvac force
	@$(RM) $@		# Remove log to prevent pass when aborted
# for Intel same machine
# @mpirun -genv I_MPI_FABRICS shm  -np $(NUM_PROCS) ./amrvac -i $(filter %.par,$^) > run.log
	@mpirun   -np $(NUM_PROCS) ./amrvac -i $(filter %.par,$^) > run.log
	@if $(LOG_CMP) 1.0e-5 1.0e-8 $@ correct_output/$@ ; \
	then echo "PASSED $@" ; \
	else echo "** FAILED ** $@" ; \
	fi

amrvac: makefile force		# Always try to build
	@$(MAKE)

makefile: $(AMRVAC_DIR)/arch/amrvac.make
	@$(RM) $@
	@$(SETUP_SCRIPT) $(SETUP_FLAGS) > setup.log

# To make sure the comparison utility can be build
$(LOG_CMP): $(LOG_CMP).o
