// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

module ibex_cheri_memchecker #(
    parameter bit DataMem = 1'b1,
    parameter int unsigned CheriCapWidth = 91
) (
    // this provides the authority for memory access
    input logic [CheriCapWidth-1:0] auth_cap_i,

    // data access information
    input logic [31:0] data_addr_i,
    input logic        data_we_i,
    input logic [1:0]  data_type_i,
    input logic [3:0]  data_be_i,
    input logic        data_cap_i,

    // exceptions that have been caused
    output ibex_pkg::cheri_exc_t cheri_mem_exc_o,
    // whether there was a length exception caused by fetching the second half
    // of an instruction
    output logic instr_upper_exc_o,
    // (for DII) when using DII, there is no backing instruction memory so fetching misaligned
    // instructions would normally lead to multiple requests but only leads to 1 with DII,
    // which means that there is no check on whether the _next_ fetch (for the
    // top bits of the current instruction being fetched) are in bounds
    output logic instr_upper_exc_2_o
);
  import ibex_pkg::*;

  // CHERI module inputs & outputs
  logic [31:0]                auth_cap_getAddr_o;
  logic                       auth_cap_isValidCap_o;
  logic                       auth_cap_isSealed_o;
  logic [31:0]                auth_cap_getBase_o;
  logic [32:0]                auth_cap_getTop_o;
  logic [CheriPermsWidth-1:0] auth_cap_getPerms_o;

  cheri_exc_t cheri_mem_exc;
  logic       instr_upper_exc;
  logic       instr_upper_exc_2;

  // get data size from type to use in bounds checking, and then zero-extend
  // it to the correct size (33 bits since capability "top" is 33 bits)
  logic [3:0]  data_size;
  logic [31:0] data_size_ext;
  if (DataMem) begin
    assign data_size = data_type_i == 2'b00 ? 4'h4 : // Word
                       data_type_i == 2'b01 ? 4'h2 : // Halfword
                       data_type_i == 2'b10 ? 4'h1 : // Byte
                                              4'h8;  // Double
  end else begin
    assign data_size = 4'h2; // instruction accesses are 2 bytes
  end
  assign data_size_ext = {28'h0, data_size};

  // calculate actual data start address using byte enable
  // upper bits are identical since Ibex only produces accesses aligned to 4 bytes
  logic [31:0] data_addr_actual, data_addr_actual_upper;;
  assign data_addr_actual[31:2]       = data_addr_i[31:2];
  assign data_addr_actual_upper[31:2] = data_addr_i[31:2];
  if (DataMem) begin
    // for data memory, check byte enables to get the real address
    assign data_addr_actual[1:0]  = data_be_i[0] == 1'b1 ? 2'b00
                                  : data_be_i[1] == 1'b1 ? 2'b01
                                  : data_be_i[2] == 1'b1 ? 2'b10
                                  : 2'b11;
    assign data_addr_actual_upper[1:0] = 2'bX;
  end else begin
    // for instructions, bottom bit is always 0 and need to check 2 accesses
    // (in case we read a compressed instruction)
    assign data_addr_actual[1:0]       = 2'b00;
    assign data_addr_actual_upper[1:0] = 2'b11;
  end

  // perform the memory checks
  always_comb begin
    cheri_mem_exc                          = cheri_exc_t'(0);
    cheri_mem_exc.tag_violation            = ~auth_cap_isValidCap_o;
    cheri_mem_exc.seal_violation           =  auth_cap_isSealed_o;
    cheri_mem_exc.permit_load_violation    = ~data_we_i & DataMem & ~auth_cap_getPerms_o[2];
    cheri_mem_exc.permit_store_violation   =  data_we_i & ~auth_cap_getPerms_o[3];
    cheri_mem_exc.permit_execute_violation = ~DataMem & ~auth_cap_getPerms_o[PermitExecuteIndex];
    cheri_mem_exc.length_violation         = (data_addr_actual < auth_cap_getBase_o)
                                             // if this is an instruction checker, allow accesses that
                                             // overflow the address calculation
                                           | (DataMem ? ({1'b0, data_addr_actual} + {1'b0, data_size_ext} > auth_cap_getTop_o)
                                                      : ({1'b0, data_addr_actual + data_size_ext} > auth_cap_getTop_o));
    // don't bother checking if it is below base (if it is, then there will be
    // a length violation in the lower word anyway
    instr_upper_exc                        = DataMem ? 0 : {1'b0, data_addr_actual_upper} >= auth_cap_getTop_o;
    instr_upper_exc_2                      = DataMem ? 0 : {1'b0, data_addr_actual + 'h6} > auth_cap_getTop_o;
  end

  assign cheri_mem_exc_o     = cheri_mem_exc;
  assign instr_upper_exc_o   = instr_upper_exc;
  assign instr_upper_exc_2_o = instr_upper_exc_2;

  // CHERI module instantiation
  module_wrap64_isValidCap auth_cap_isValidCap (
    .wrap64_isValidCap_cap(auth_cap_i),
    .wrap64_isValidCap    (auth_cap_isValidCap_o)
  );

  logic [CheriKindWidth-1:0] auth_cap_getKind_o;
  module_wrap64_getKind auth_cap_getKind(
    .wrap64_getKind_cap(auth_cap_i),
    .wrap64_getKind    (auth_cap_getKind_o)
  );
  assign auth_cap_isSealed_o = auth_cap_getKind_o[CheriKindWidth-1:CheriOTypeWidth] != '0;

  module_wrap64_getBase auth_cap_getBase(
    .wrap64_getBase_cap(auth_cap_i),
    .wrap64_getBase    (auth_cap_getBase_o)
  );

  module_wrap64_getTop auth_cap_getTop(
    .wrap64_getTop_cap(auth_cap_i),
    .wrap64_getTop    (auth_cap_getTop_o)
  );

  module_wrap64_getPerms auth_cap_getPerms(
    .wrap64_getPerms_cap(auth_cap_i),
    .wrap64_getPerms    (auth_cap_getPerms_o)
  );

endmodule
