VCS = vcs +v2k -override_timescale=100ps/1ps -full64 -debug_acc+all -sverilog +vcs+flush+all +lint=TFIPC-L -notice +notimingcheck -o simv -l compile.log +incdir+../rtl/pkgs


MODULE_NAME = nnlut_sqrt_neg2_log # change here
TB_NAME = $(MODULE_NAME)_tb
FILES = ./filelist/filelist_$(MODULE_NAME).f

all: vcs sim verdi

vcs:
	$(VCS) -f $(FILES)

sim:
	./simv -l simulation_$(TB_NAME).log

verdi:
	verdi -top $(TB_NAME) -sv -f $(FILES) -ssf $(TB_NAME).fsdb +define+IS_SIM &

clean:
	rm -rf ./csrc *.daidir ./csrc \
    *.log *.vpd *.vdb simv* *.key stack* vc_hdrs.h novas.rc \
	+race.out* novas.conf novas_dump.log verdi* *fsdb* apb2apb_asyno \
	ddr_addr.txt ddr_data.txt

#clean:
#	rm -rf csrc DVEfiles simv.daidir ddr_addr.txt ddr_data.txt inter.vpd simv ucli.key
#
#vcs:
#	#cp ../verif/file.F ./src/filelist.f
#	#sed -ie '/tb/d' ./src/filelist.f 
#	#vcs -full64 +define+UNIT_DELAY +define+IS_SIM +define+SRAM_INPUT  -sverilog -debug_access+all -kdb -lca -f list.F -LDFLAGS -Wl,--no-as-needed
#	vcs -full64 +define+UNIT_DELAY +define+IS_SIM -sverilog -debug_access+all -kdb -lca -f list.F -LDFLAGS -Wl,--no-as-needed
