// Copyright (C) 2017 ETH Zurich, University of Bologna
//
// Licensed under the Solderpad Hardware Licence, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.0
// You may obtain a copy of the License at https://solderpad.org/licenses/
//
// Author: Florian Zaruba, ETH Zurich
// Date: 03.10.2017
// Description: Re-name registers

module re_name import ariane_pkg::*; (
    input  logic                                   clk_i,    // Clock
    input  logic                                   rst_ni,   // Asynchronous reset active low
    input  logic                                   flush_i,  // Flush renaming state
    input  logic                                   flush_unissied_instr_i,
    // from/to scoreboard
    input  scoreboard_entry_t [ISSUE_WIDTH-1:0]    issue_instr_i,
    input  logic [ISSUE_WIDTH-1:0]                 issue_instr_valid_i,
    output logic [ISSUE_WIDTH-1:0]                 issue_ack_o,
    // from/to issue and read operands
    output scoreboard_entry_t [ISSUE_WIDTH-1:0]    issue_instr_o,
    output logic [ISSUE_WIDTH-1:0]                 issue_instr_valid_o,
    input  logic [ISSUE_WIDTH-1:0]                 issue_ack_i
);

    // pass through handshaking signals
    assign issue_instr_valid_o = issue_instr_valid_i;
    assign issue_ack_o         = issue_ack_i;

    // keep track of re-naming data structures
    logic [31:0] re_name_table_gpr_n, re_name_table_gpr_q;
    logic [31:0] re_name_table_fpr_n, re_name_table_fpr_q;

    // -------------------
    // Re-naming
    // -------------------
    always_comb begin
        // MSB of the renamed source register addresses
        logic name_bit_rs1, name_bit_rs2, name_bit_rs3, name_bit_rd;

        // default assignments
        re_name_table_gpr_n = re_name_table_gpr_q;
        re_name_table_fpr_n = re_name_table_fpr_q;
        issue_instr_o       = issue_instr_i;
        for (int unsigned i = 0; i < ISSUE_WIDTH; i++) begin
            if (issue_ack_i[i] && !flush_unissied_instr_i) begin
                // if we acknowledge the instruction tic the corresponding destination register
                if (is_rd_fpr(issue_instr_i[i].op))
                    re_name_table_fpr_n[issue_instr_i[i].rd] = re_name_table_fpr_q[issue_instr_i[i].rd] ^ 1'b1;
                else
                    re_name_table_gpr_n[issue_instr_i[i].rd] = re_name_table_gpr_q[issue_instr_i[i].rd] ^ 1'b1;
            end

            // select name bit according to the register file used for source operands
            name_bit_rs1 = is_rs1_fpr(issue_instr_i[i].op) ? re_name_table_fpr_q[issue_instr_i[i].rs1]
                                                           : re_name_table_gpr_q[issue_instr_i[i].rs1];
            name_bit_rs2 = is_rs2_fpr(issue_instr_i[i].op) ? re_name_table_fpr_q[issue_instr_i[i].rs2]
                                                           : re_name_table_gpr_q[issue_instr_i[i].rs2];
            // rs3 is only used in certain FP operations and held like an immediate
            name_bit_rs3 = re_name_table_fpr_q[issue_instr_i[i].result[4:0]]; // make sure only the addr bits are read

            // select name bit according to the state it will have after renaming
            name_bit_rd = is_rd_fpr(issue_instr_i[i].op) ? re_name_table_fpr_q[issue_instr_i[i].rd] ^ 1'b1
                                                         : re_name_table_gpr_q[issue_instr_i[i].rd] ^ (issue_instr_i[i].rd != '0); // don't rename x0

            // re-name the source registers
            issue_instr_o[i].rs1 = { ENABLE_RENAME & name_bit_rs1, issue_instr_i[i].rs1[4:0] };
            issue_instr_o[i].rs2 = { ENABLE_RENAME & name_bit_rs2, issue_instr_i[i].rs2[4:0] };

            // re-name the third operand in imm if it's actually an operand
            if (is_imm_fpr(issue_instr_i[i].op))
                issue_instr_o[i].result = { ENABLE_RENAME & name_bit_rs3, issue_instr_i[i].result[4:0]};

            // re-name the destination register
            issue_instr_o[i].rd = { ENABLE_RENAME & name_bit_rd, issue_instr_i[i].rd[4:0] };
        end

        // we don't want to re-name gp register zero, it is non-writeable anyway
        re_name_table_gpr_n[0] = 1'b0;

        // Handle flushes
        if (flush_i) begin
            re_name_table_gpr_n = '0;
            re_name_table_fpr_n = '0;
        end

    end

    // -------------------
    // Registers
    // -------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            re_name_table_gpr_q <= '0;
            re_name_table_fpr_q <= '0;
        end else begin
            re_name_table_gpr_q <= re_name_table_gpr_n;
            re_name_table_fpr_q <= re_name_table_fpr_n;
        end
    end
    // pragma translate_off
    `ifndef VERILATOR
      initial begin
        assert (ENABLE_RENAME && ISSUW_WIDTH != 1) else $fatal("[re-name] re-name in multi-issue is not supported");
      end
    `endif
    // pragma translate_on
endmodule
