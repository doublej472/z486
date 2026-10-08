// paging_unit.sv pretrans_present without its mem_req term.
// old: idle_data_req (= s_idle && mem_req && !mem_servicing) && pretrans_valid && ...
// new: s_idle && !mem_servicing && pretrans_valid && ...
// Exact because z486.sv drives mem_req = mem_req_to_paging, which ORs both
// slow-submit terms past its fault gate, and pretrans_valid is those same two
// terms each ANDed with a phys-ok flag (z486.sv mem_req_to_paging and the
// paging_unit instance's .pretrans_valid).  MUTANT=1 drops vipt_slow_submit
// from mem_req and must be refuted.
module pretrans_no_memreq #(parameter MUTANT = 0)
  (input mem_op_eligible, input uc_data_busreq, input x87_direct_mem_req,
   input gp_fault_trigger, input ucrd_route_pre, input st_route,
   input vipt_slow_submit, input ucrd_slow_submit,
   input ucrd_phys_ok_r, input vipt_slow_phys_ok_r,
   input s_idle, input mem_servicing, input mem_write, input mem_is_io,
   input idle_mem_crossing, output mismatch);
  wire mem_req = (mem_op_eligible && (uc_data_busreq || x87_direct_mem_req) &&
                  !gp_fault_trigger && !ucrd_route_pre && !st_route) ||
                 (MUTANT ? 1'b0 : vipt_slow_submit) || ucrd_slow_submit;
  wire pretrans_valid = (ucrd_slow_submit && ucrd_phys_ok_r) ||
                        (vipt_slow_submit && vipt_slow_phys_ok_r);
  wire idle_data_req = s_idle && mem_req && !mem_servicing;
  wire old_p = idle_data_req && pretrans_valid && !mem_write && !mem_is_io && !idle_mem_crossing;
  wire new_p = s_idle && !mem_servicing && pretrans_valid && !mem_write && !mem_is_io &&
               !idle_mem_crossing;
  assign mismatch = old_p != new_p;
endmodule
