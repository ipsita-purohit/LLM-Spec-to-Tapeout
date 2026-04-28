
# ── Technology files ─────────────────────────────────────────────
read_lef     /OpenROAD-flow-scripts/flow/platforms/nangate45/lef/NangateOpenCellLibrary.tech.lef
read_lef     /OpenROAD-flow-scripts/flow/platforms/nangate45/lef/NangateOpenCellLibrary.macro.mod.lef
read_liberty /OpenROAD-flow-scripts/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib

# ── Netlist ──────────────────────────────────────────────────────
read_verilog outputs/p5_mapped.v
link_design  dot_product

# ── Clock — define BEFORE read_sdc ───────────────────────────────
# Defining after read_sdc makes OpenROAD treat it as virtual →
# TritonCTS finds 0 clock nets and is skipped entirely.
create_clock -name clk -period 4.5 [get_ports clk]
set_clock_uncertainty -setup 0.05 [get_clocks clk]
set_clock_uncertainty -hold  0.02 [get_clocks clk]
set_clock_transition   0.05       [get_clocks clk]

# ── SDC (I/O delays only — clock already defined above) ──────────
read_sdc outputs/p5.sdc

# ── Wire RC model (needed for timing-driven placement) ───────────
set_wire_rc -clock  -layer metal5
set_wire_rc -signal -layer metal3

# ── Floorplan ────────────────────────────────────────────────────
# Auto-sized from Yosys chip area to keep utilisation at ~60%.
# This prevents GPL-0301 "Utilisation > 100%" errors on larger designs.
initialize_floorplan \
  -site      FreePDK45_38x28_10R_NP_162NW_34O \
  -die_area  "0 0 390 390" \
  -core_area "45 45 345 345"

source /OpenROAD-flow-scripts/flow/platforms/nangate45/make_tracks.tcl
place_pins -hor_layers metal3 -ver_layers metal2 -annealing

# ── Global placement ─────────────────────────────────────────────
global_placement -density 0.6 -timing_driven -routability_driven
estimate_parasitics -placement
repair_design

# ── Detailed placement ───────────────────────────────────────────
detailed_placement
check_placement -verbose

# ── CTS ──────────────────────────────────────────────────────────
# Full buffer list lets TritonCTS choose the right drive strength.
clock_tree_synthesis \
  -root_buf CLKBUF_X1 \
  -buf_list {BUF_X1 BUF_X2 BUF_X4 CLKBUF_X1 CLKBUF_X2 CLKBUF_X3} \
  -wire_unit 20

# Propagate clock so OpenSTA uses real (not ideal) skew
set_propagated_clock [all_clocks]
detailed_placement
check_placement -verbose

# Pre-route timing repair
estimate_parasitics -placement
repair_timing -hold -setup

# ── Routing ──────────────────────────────────────────────────────
global_route \
  -guide_file outputs/p5_route.guide
detailed_route \
  -output_drc outputs/p5_drc.rpt

# ── Post-route parasitics + timing repair ────────────────────────
estimate_parasitics -global_routing
repair_timing -hold -setup -max_buffer_percent 20

# ── Timing / power / area reports ────────────────────────────────
puts "\n=== Timing Report (Setup) ==="
report_checks -path_delay max -format full_clock_expanded \
  -fields {slew cap input_pins nets} -digits 3

puts "\n=== Timing Report (Hold) ==="
report_checks -path_delay min -format full_clock_expanded -digits 3

puts "\n=== WNS / TNS ==="
report_wns
report_tns

puts "\n=== Power ==="
report_power

puts "\n=== Area ==="
report_design_area

# ── Output files ─────────────────────────────────────────────────
write_def     outputs/p5_routed.def
write_verilog outputs/p5_final.v

puts "PD complete — DEF ready for GDS export via def2stream.py"
