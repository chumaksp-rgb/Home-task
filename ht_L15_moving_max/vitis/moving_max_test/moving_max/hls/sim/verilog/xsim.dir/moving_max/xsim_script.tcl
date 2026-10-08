set_param project.enableReportConfiguration 0
load_feature core
current_fileset
xsim {moving_max} -testplusarg UVM_VERBOSITY=UVM_NONE -testplusarg UVM_TESTNAME=moving_max_test_lib -testplusarg UVM_TIMEOUT=20000000000000 -view {{moving_max_dataflow_ana.wcfg}} -tclbatch {moving_max.tcl} -protoinst {moving_max.protoinst}
