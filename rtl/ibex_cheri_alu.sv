// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

module ibex_cheri_alu #(
  parameter int unsigned CheriCapWidth = 91,
  parameter int unsigned IntWidth = 32
) (
  input ibex_pkg::cheri_base_opcode_e             base_opcode_i,
  input ibex_pkg::cheri_threeop_funct7_e          threeop_opcode_i,
  input ibex_pkg::cheri_s_a_d_funct5_e  s_a_d_opcode_i,
  input logic                                     exc_only_i,
  input logic                                     instr_first_cycle_i,

  input logic [CheriCapWidth-1:0] operand_a_i,
  input logic [CheriCapWidth-1:0] operand_b_i,

  output logic [IntWidth-1:0] alu_operand_a_o,
  output logic [IntWidth-1:0] alu_operand_b_o,
  output ibex_pkg::alu_op_e alu_operator_o,

  input logic [32:0] alu_result_i,
  input logic [31:0] btalu_result_i,

  output logic [CheriCapWidth-1:0] result_o,
  output logic wrote_capability,

  output ibex_pkg::cheri_exc_t exceptions_a_o,
  output ibex_pkg::cheri_exc_t exceptions_b_o

);
  import ibex_pkg::*;

  // Verbosity: 0 = no printing; 1 = print each instruction.
  localparam bit Verbosity = 1'b0;

  // Constant parameters
  // TODO perhaps these should be moved to ibex_pkg?
  //    (or perhaps ibex_cheri_pkg?)
  localparam int unsigned KindWidth       = CheriKindWidth;
  localparam int unsigned OTypeWidth      = CheriOTypeWidth;
  localparam int unsigned RegsPerQuarter  = 4;
  localparam int unsigned FlagWidth       = 1;
  localparam int unsigned PermsWidth      = CheriPermsWidth;
  localparam int unsigned LengthWidth     = 33;
  localparam int unsigned OffsetWidth     = 32;
  localparam int unsigned BaseWidth       = 32;
  localparam int unsigned ImmWidth        = 12;

  // there are 22 exceptions currently defined in the CHERI-RISCV spec
  // TODO see if there are any unused exceptions (there are some that are MIPS-only)
  cheri_exc_t exceptions_a;
  cheri_exc_t exceptions_b;

  // Operands a and b as integers (ie bottom IntWidth bits)
  logic [IntWidth-1:0] operand_a_int = operand_a_i[IntWidth-1:0];
  logic [IntWidth-1:0] operand_b_int = operand_b_i[IntWidth-1:0];


  // function input and output declarations
  // these are inputs and outputs for modules that are generated from bluespec code
  // see https://github.com/CTSRD-CHERI/cheri-cap-lib for the bluespec code
  // This is being used because the spec for cheri capability compression is still being worked on
  // so it is possible the internals of the functions might change
  // naming: O_FFF...FFF_D
  // where O is the operand being worked on (operand a or b)
  //       F is the function being used
  //       D is the direction of the connection - _i means it is an input to the function
  //                                              _o means it is an output from the function
  logic [IntWidth-1:0]    a_setBounds_i;
  logic [CheriCapWidth:0] a_setBounds_o;

  logic [IntWidth-1:0] a_getAddr_o;

  logic [IntWidth-1:0] b_getAddr_o;

  logic [IntWidth:0] a_getTop_o;

  logic [IntWidth:0] b_getTop_o;

  logic [CheriCapWidth-1:0] a_setKind_cap_i;
  logic [    KindWidth-1:0] a_setKind_i;
  logic [    KindWidth-1:0] a_setKind_int;
  logic [CheriCapWidth-1:0] a_setKind_o;

  logic [    KindWidth-1:0] b_setKind_i;
  logic [CheriCapWidth-1:0] b_setKind_o;

  logic [PermsWidth-1:0] a_getPerms_o;

  logic [PermsWidth-1:0] b_getPerms_o;

  logic [   PermsWidth-1:0] a_setPerms_i;
  logic [CheriCapWidth-1:0] a_setPerms_o;

  logic [   PermsWidth-1:0] b_setPerms_i;
  logic [CheriCapWidth-1:0] b_setPerms_o;

  logic                     a_setFlags_i;
  logic [CheriCapWidth-1:0] a_setFlags_o;

  logic [   IntWidth-1:0] a_setOffset_i;
  logic [CheriCapWidth:0] a_setOffset_o;

  logic [   IntWidth-1:0] a_incOffset_i;
  logic [CheriCapWidth:0] a_incOffset_o;

  logic [IntWidth-1:0] a_getBase_o;

  logic [IntWidth-1:0] b_getBase_o;

  logic [IntWidth-1:0] a_getOffset_o;

  logic [IntWidth-1:0] b_getOffset_o;

  logic a_isValidCap_o;

  logic b_isValidCap_o;

  logic [KindWidth-1:0] a_getKind_o;
  logic [KindWidth-1:0] b_getKind_o;

  // the lower bits of the Kind hold the object type
  // TODO interacting with the "Kind" and "Type" of a capability needs nasty
  // code atm. Should discuss with cheri-cap-lib what would be a cleaner way
  // to do this
  logic [OTypeWidth-1:0] a_getOType_o = a_getKind_o[OTypeWidth-1:0];
  logic [OTypeWidth-1:0] b_getOType_o = b_getKind_o[OTypeWidth-1:0];

  logic a_isSealed_o = a_getKind_o[KindWidth-1:OTypeWidth] != 0;
  logic b_isSealed_o = b_getKind_o[KindWidth-1:OTypeWidth] != 0;

  logic a_isSentry_o = a_getKind_o[KindWidth-1:OTypeWidth] == 1;
  logic b_isSentry_o = b_getKind_o[KindWidth-1:OTypeWidth] == 1;

  logic a_isReserved_o = a_getKind_o[KindWidth-1:OTypeWidth] == 2
                       | a_getKind_o[KindWidth-1:OTypeWidth] == 3;
  logic b_isReserved_o = b_getKind_o[KindWidth-1:OTypeWidth] == 2
                       | b_getKind_o[KindWidth-1:OTypeWidth] == 3;

  logic a_isSealedWithType_o = a_getKind_o[KindWidth-1:OTypeWidth] == 4;
  logic b_isSealedWithType_o = b_getKind_o[KindWidth-1:OTypeWidth] == 4;

  logic [IntWidth:0] a_getLength_o;

  logic a_getFlags_o;

  logic                     a_setValidCap_i;
  logic [CheriCapWidth-1:0] a_setValidCap_o;

  logic                     b_setValidCap_i;
  logic [CheriCapWidth-1:0] b_setValidCap_o;

  logic [   IntWidth-1:0] a_setAddr_i;
  // This signal is used as the input for another module inside the
  // always_comb block, which leads Verilator to output UNOPTFLAT and
  // IMPERFECTSCH warnings; silence these here
  // verilator lint_off UNOPTFLAT
  // verilator lint_off IMPERFECTSCH
  logic [CheriCapWidth:0] a_setAddr_o;
  // verilator lint_on IMPERFECTSCH
  // verilator lint_on UNOPTFLAT

  logic [   IntWidth-1:0] b_setAddr_i;
  logic [CheriCapWidth:0] b_setAddr_o;

  logic a_isInBounds_isTopIncluded_i;
  logic a_isInBounds_o;

  logic b_isInBounds_isTopIncluded_i;
  logic b_isInBounds_o;

  logic [IntWidth-1:0] a_getRepAlignMask_i;
  logic [IntWidth-1:0] a_getRepAlignMask_o;

  logic [IntWidth-1:0] a_getRepLen_i;
  logic [IntWidth-1:0] a_getRepLen_o;

  logic [IntWidth:0] cmp_gt_a_i, cmp_gt_b_i;
  logic cmp_gt_res_o;
  assign cmp_gt_res_o = $unsigned(cmp_gt_a_i) > $unsigned(cmp_gt_b_i);

  logic [IntWidth:0] cmp_lt_a_i, cmp_lt_b_i;
  logic cmp_lt_res_o;
  assign cmp_lt_res_o = $unsigned(cmp_lt_a_i) < $unsigned(cmp_lt_b_i);

  //////////////////////////
  // CHERI ALU operations //
  //////////////////////////

  always_comb begin
    exceptions_a_o = cheri_exc_t'(0);
    exceptions_b_o = cheri_exc_t'(0);

    alu_operand_a_o  = '0;
    alu_operand_b_o  = '0;
    alu_operator_o   = ALU_ADD;
    result_o         = '0;
    wrote_capability = '0;

    cmp_lt_a_i = '0;
    cmp_lt_b_i = '0;
    cmp_gt_a_i = '0;
    cmp_gt_b_i = '0;

    a_setBounds_i   = '0;
    a_setKind_cap_i = '0;
    a_setKind_i     = '0;
    b_setKind_i     = '0;
    a_setPerms_i    = '0;
    b_setPerms_i    = '0;
    a_setFlags_i    = '0;
    a_setOffset_i   = '0;
    a_setValidCap_i = '0;
    b_setValidCap_i = '0;
    a_setAddr_i     = '0;
    b_setAddr_i     = '0;
    a_isInBounds_isTopIncluded_i = '0;
    b_isInBounds_isTopIncluded_i = '0;

    // used for checking branch targets
    if (exc_only_i) begin
      // TODO this assumes that the value of getLength is unsigned, and that
      // if the base is above the top then the length is 0
      // The API does not explicitly state whether the base can be above the
      // top, or what the behaviour is in that case.
      cmp_gt_a_i = {1'b0, btalu_result_i[31:1], 1'b0} + 2;
      cmp_gt_b_i = a_getLength_o;
      exceptions_a_o.length_violation = cmp_gt_res_o;

    end else begin
      case (base_opcode_i)
        THREE_OP: begin
          case (threeop_opcode_i)
            C_SPECIAL_RW: begin
              // operand b is the register id
              // operand a is the data that is (maybe) going to be written to the register
              // this operation is implemented in other places since there's nothing the ALU can do
              // for it
              result_o         = operand_a_i;
              wrote_capability = 1'b1;

              if (Verbosity) begin
                $display("cspecialrw output: %h", result_o);
              end
            end

            C_SET_BOUNDS: begin
              a_setBounds_i = b_getAddr_o;

              result_o         = a_setBounds_o[CheriCapWidth-1:0];
              wrote_capability = 1'b1;

              alu_operand_a_o = a_getAddr_o;
              alu_operand_b_o = b_getAddr_o;
              alu_operator_o  = ALU_ADD;

              cmp_gt_a_i = alu_result_i;
              cmp_gt_b_i = a_getTop_o;

              exceptions_a_o.tag_violation    = exceptions_a.tag_violation;
              exceptions_a_o.seal_violation   = exceptions_a.seal_violation;
              exceptions_a_o.length_violation = exceptions_a.length_violation
                                               | cmp_gt_res_o;

              if (Verbosity) begin
                $display("csetbounds output: %h   exceptions: %h", result_o, exceptions_a_o);
              end
            end

            C_SET_BOUNDS_EXACT: begin
              a_setBounds_i = b_getAddr_o;

              result_o         = a_setBounds_o[CheriCapWidth-1:0];
              wrote_capability = 1'b1;

              alu_operand_a_o = a_getAddr_o;
              alu_operand_b_o = b_getAddr_o;
              alu_operator_o  = ALU_ADD;

              cmp_gt_a_i = alu_result_i;
              cmp_gt_b_i = a_getTop_o;

              exceptions_a_o.tag_violation            = exceptions_a.tag_violation;
              exceptions_a_o.seal_violation           = exceptions_a.seal_violation;
              exceptions_a_o.length_violation         = exceptions_a.length_violation
                                                      | cmp_gt_res_o;
              exceptions_a_o.inexact_bounds_violation = ~a_setBounds_o[CheriCapWidth];

              if (Verbosity) begin
                $display("csetboundse output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
              end
            end

            C_SEAL: begin
              a_setKind_cap_i = operand_a_i;
              a_setKind_i     = b_getAddr_o[KindWidth-1:0];

              result_o         = a_setKind_o;
              wrote_capability = 1'b1;

              cmp_gt_a_i = {1'b0, b_getAddr_o};
              cmp_gt_b_i = {1'b0, CheriMaxOType};

              cmp_lt_a_i = {1'b0, b_getAddr_o};
              cmp_lt_b_i = b_getTop_o;

              exceptions_a_o.tag_violation  = exceptions_a.tag_violation;
              exceptions_a_o.seal_violation = exceptions_a.seal_violation;

              exceptions_b_o.tag_violation         = exceptions_b.tag_violation;
              exceptions_b_o.seal_violation        = exceptions_b.seal_violation;
              exceptions_b_o.length_violation      = exceptions_b.length_violation
                                                   | (~cmp_lt_res_o)
                                                   | (cmp_gt_res_o);
              exceptions_b_o.permit_seal_violation = exceptions_b.permit_seal_violation;

              if (Verbosity) begin
                $display("cseal output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
              end
            end

            C_UNSEAL: begin
              a_setPerms_i                    = a_getPerms_o;
              a_setPerms_i[PermitGlobalIndex] = a_getPerms_o[PermitGlobalIndex] & b_getPerms_o[PermitGlobalIndex];
              a_setKind_cap_i                 = a_setPerms_o;
              a_setKind_i                     = {KindWidth{1'b1}};

              cmp_lt_a_i = b_getTop_o;
              cmp_lt_b_i = {1'b0, b_getAddr_o};

              result_o         = a_setKind_o;
              wrote_capability = 1'b1;

              exceptions_a_o.tag_violation  = exceptions_a.tag_violation;
              exceptions_a_o.seal_violation = !a_isSealed_o;

              exceptions_b_o.tag_violation           = exceptions_b.tag_violation;
              exceptions_b_o.seal_violation          = b_isSealed_o;
              exceptions_b_o.type_violation          = b_getAddr_o != {{(IntWidth-OTypeWidth){1'b0}}, a_getOType_o};
              exceptions_b_o.permit_unseal_violation = exceptions_b.permit_unseal_violation;
              exceptions_b_o.length_violation        = exceptions_b.length_violation
                                                     | cmp_lt_res_o;

              if (Verbosity) begin
                $display("cunseal output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
              end
            end

            C_AND_PERM: begin
              a_setPerms_i = a_getPerms_o & b_getAddr_o[PermsWidth-1:0];

              result_o         = a_setPerms_o;
              wrote_capability = 1'b1;

              exceptions_a_o.tag_violation  = exceptions_a.tag_violation;
              exceptions_a_o.seal_violation = exceptions_a.seal_violation;

              if (Verbosity) begin
                $display("candperm output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
              end
            end

            C_SET_FLAGS: begin
              a_setFlags_i = b_getAddr_o[FlagWidth-1:0];

              result_o         = a_setFlags_o;
              wrote_capability = 1'b1;

              exceptions_a_o.seal_violation = exceptions_a.seal_violation;

              if (Verbosity) begin
                $display("csetflags output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
              end
            end

            C_SET_OFFSET: begin
              a_setOffset_i = b_getAddr_o;

              result_o         = a_setOffset_o[CheriCapWidth-1:0];
              wrote_capability = 1'b1;

              exceptions_a_o.seal_violation = exceptions_a.seal_violation;

              if (Verbosity) begin
                $display("csetoffset output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
              end
            end

            C_SET_ADDR: begin
              a_setAddr_i = b_getAddr_o;

              result_o         = a_setAddr_o[CheriCapWidth-1:0];
              wrote_capability = 1'b1;

              exceptions_a_o.seal_violation = exceptions_a.seal_violation;

              if (Verbosity) begin
                $display("csetaddr output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
              end
            end

            C_INC_OFFSET: begin
              a_incOffset_i = b_getAddr_o;

              result_o                  = a_incOffset_o[CheriCapWidth-1:0];
              // only preserve the tag if the result was "exact"
              result_o[CheriCapWidth-1] = result_o[CheriCapWidth-1] & a_incOffset_o[CheriCapWidth];
              wrote_capability          = 1'b1;

              exceptions_a_o.seal_violation = exceptions_a.seal_violation;

              if (Verbosity) begin
                $display("cincoffset output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
              end
            end

            C_TO_PTR: begin
              result_o[IntWidth-1:0] = a_isValidCap_o ? a_getAddr_o - b_getBase_o : IntWidth'(1'b0);
              wrote_capability       = 1'b0;

              exceptions_a_o.seal_violation = exceptions_a.seal_violation;

              exceptions_b_o.tag_violation  = exceptions_b.tag_violation;

              if (Verbosity) begin
                $display("ctoptr output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
              end
            end

            C_FROM_PTR: begin
              a_setOffset_i = b_getAddr_o;

              // the comparison performed is unsigned, so this tells us
              // whether the value is not equal to 0
              cmp_gt_a_i = {1'b0, b_getAddr_o};
              cmp_gt_b_i = 0;

              wrote_capability = cmp_gt_res_o;
              result_o         = ~cmp_gt_res_o ? '0
                                               : a_setOffset_o[CheriCapWidth-1:0];

              exceptions_a_o.tag_violation  = cmp_gt_res_o && exceptions_a.tag_violation;
              exceptions_a_o.seal_violation = cmp_gt_res_o && exceptions_a.seal_violation;

              if (Verbosity) begin
                $display("cfromptr output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
              end
            end

            C_SUB: begin
              alu_operand_a_o = a_getAddr_o;
              alu_operand_b_o = b_getAddr_o;
              alu_operator_o  = ALU_SUB;

              result_o[IntWidth-1:0] = alu_result_i[IntWidth-1:0];
              wrote_capability       = 1'b0;

              if (Verbosity) begin
                $display("csub output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
              end
            end

            C_BUILD_CAP: begin
              // preserve sentries
              // upper bits of kind tell us it's unsealed
              b_setKind_i = b_getKind_o[KindWidth-1:OTypeWidth] == 'h1 ? b_getKind_o
                                                                       : {3'h0, 4'hX};

              result_o                  = b_setKind_o;
              // always tag the resulting capability
              result_o[CheriCapWidth-1] = 1'b1;
              wrote_capability = 1'b1;

              cmp_gt_a_i = b_getTop_o;
              cmp_gt_b_i = a_getTop_o;

              cmp_lt_a_i = {1'b0, b_getBase_o};
              cmp_lt_b_i = {1'b0, a_getBase_o};

              exceptions_a_o.tag_violation              = exceptions_a.tag_violation;
              exceptions_a_o.seal_violation             = exceptions_a.seal_violation;
              exceptions_a_o.length_violation           = (cmp_lt_res_o)
                                                        | (cmp_gt_res_o);
              exceptions_a_o.software_defined_violation = (a_getPerms_o & b_getPerms_o) != b_getPerms_o;

              // Top is 1 bit longer than base (ie 33 bit when XLEN is 32)
              exceptions_b_o.length_violation = {1'b0, b_getBase_o} > b_getTop_o;

              if (Verbosity) begin
                $display("cbuildcap output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
              end
            end

            C_COPY_TYPE: begin
              // unsealed, sentry and reserved otypes are not "software" types
              logic b_has_software_type = b_isSealedWithType_o;
              a_setAddr_i = {{(IntWidth-OTypeWidth){1'b0}}, b_getOType_o};

              wrote_capability = b_has_software_type;
              result_o         = b_has_software_type ? a_setAddr_o[CheriCapWidth-1:0]
                                                     // sign-extend the otype
                                                     : {{(CheriCapWidth-OTypeWidth){b_getOType_o[OTypeWidth-1]}}, b_getOType_o};

              cmp_lt_a_i = {{(IntWidth+1-OTypeWidth){1'b0}}, b_getOType_o};
              cmp_lt_b_i = {1'b0, a_getBase_o};

              exceptions_a_o.tag_violation    = exceptions_a.tag_violation;
              exceptions_a_o.seal_violation   = exceptions_a.seal_violation;
              // Not the same as a "common" length violation so we can't use the common case
              exceptions_a_o.length_violation = b_has_software_type
                                              & (cmp_lt_res_o
                                                |{{(IntWidth-OTypeWidth+1){1'b0}}, b_getOType_o} >= a_getTop_o);

              if (Verbosity) begin
                $display("ccopytype output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
              end
            end

            C_C_SEAL: begin
              // whether B passes the conditions to seal
              logic b_is_ok   = b_isValidCap_o & b_isInBounds_o & b_getAddr_o != {IntWidth{1'b1}};
              logic a_is_ok   = a_isValidCap_o & ~a_isSealed_o;
              a_setKind_cap_i = operand_a_i;
              a_setKind_i     = b_getAddr_o[KindWidth-1:0];

              // if both are OK then save the new value, otherwise save the old value
              result_o         = b_is_ok & a_is_ok ? a_setKind_o : operand_a_i;
              wrote_capability = 1'b1;

              exceptions_a_o.tag_violation = exceptions_a.tag_violation;

              cmp_gt_a_i = {1'b0, b_getAddr_o};
              cmp_gt_b_i = {1'b0, CheriMaxOType};

              exceptions_b_o.seal_violation        = a_is_ok && b_is_ok && exceptions_b.seal_violation;
              exceptions_b_o.permit_seal_violation = a_is_ok && b_is_ok && exceptions_b.permit_seal_violation;
              exceptions_b_o.length_violation      = a_is_ok && b_is_ok && (exceptions_b.length_violation
                                                                           |cmp_gt_res_o);

              if (Verbosity) begin
                $display("ccseal output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
              end
            end

            C_TEST_SUBSET: begin
              cmp_lt_a_i = {1'b0, b_getBase_o};
              cmp_lt_b_i = {1'b0, a_getBase_o};
              cmp_gt_a_i = b_getTop_o;
              cmp_gt_b_i = a_getTop_o;
              wrote_capability = 1'b0;
              result_o[0]      = a_isValidCap_o != b_isValidCap_o              ? 1'b0
                               : cmp_lt_res_o                                  ? 1'b0
                               : cmp_gt_res_o                                  ? 1'b0
                               : (b_getPerms_o & a_getPerms_o) != b_getPerms_o ? 1'b0
                               : 1'b1;

              if (Verbosity) begin
                $display("ctestsubset output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
              end
            end

            C_INVOKE: begin
              logic [IntWidth-1:0] new_offset = {a_getOffset_o[IntWidth-1:1], 1'b0};
              // second cycle operations (unseal capability b)
              // capability b is the data capability to be placed in register 31
              b_setKind_i = { {(KindWidth-OTypeWidth){1'b0}}, {OTypeWidth{1'b1}} }; // unseal capability b

              wrote_capability = 1'b1;
              result_o         = b_setKind_o;

              // check if we can fetch a full instruction with the bounds on this capability
              alu_operand_a_o = new_offset;
              alu_operand_b_o = instr_first_cycle_i ? 0 : 2;
              alu_operator_o  = ALU_ADD;

              cmp_gt_a_i = alu_result_i;
              cmp_gt_b_i = a_getLength_o;

              exceptions_a_o.tag_violation            =  exceptions_a.tag_violation;
              // capability a SHOULD be sealed
              exceptions_a_o.seal_violation           = ~exceptions_a.seal_violation;
              exceptions_a_o.type_violation           =  a_getKind_o != b_getKind_o;
              exceptions_a_o.permit_cinvoke_violation =  exceptions_a.permit_cinvoke_violation;
              exceptions_a_o.permit_execute_violation =  exceptions_a.permit_execute_violation;
              exceptions_a_o.length_violation         =  cmp_gt_res_o;
              exceptions_a_o.unaligned_base_violation =  a_getBase_o[0];

              exceptions_b_o.tag_violation            =  exceptions_b.tag_violation;
              // capability b SHOULD be sealed
              exceptions_b_o.seal_violation           = ~exceptions_b.seal_violation;
              // capability b SHOULD NOT be executable (it should be a data capability)
              exceptions_b_o.permit_execute_violation = ~exceptions_b.permit_execute_violation;
              exceptions_b_o.permit_cinvoke_violation =  exceptions_b.permit_cinvoke_violation;
            end

            SOURCE_AND_DEST: begin
              case(s_a_d_opcode_i)
                C_GET_PERM: begin
                  result_o[PermsWidth-1:0] = a_getPerms_o;
                  wrote_capability         = 1'b0;

                  if (Verbosity) begin
                    $display("cgetperm output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
                  end
                end

                C_GET_TYPE: begin
                  // if the type is a reserved one (ie it is not a software
                  // one), zero-extend else sign-extend
                  wrote_capability       = 1'b0;
                  result_o[IntWidth-1:0] = ~a_isSealedWithType_o ? {{(IntWidth-OTypeWidth){a_getOType_o[OTypeWidth-1]}}, a_getOType_o}
                                                                 : {{(IntWidth-OTypeWidth){1'b0}},                       a_getOType_o};

                  if (Verbosity) begin
                    $display("cgettype output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
                  end
                end

                C_GET_BASE: begin
                  wrote_capability       = 1'b0;
                  result_o[IntWidth-1:0] = a_getBase_o;

                  if (Verbosity) begin
                    $display("cgetbase output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
                  end
                end

                C_GET_LEN: begin
                  wrote_capability       = 1'b0;
                  result_o[IntWidth-1:0] = a_getLength_o[LengthWidth-1] ? {IntWidth{1'b1}}
                                                                        : a_getLength_o[IntWidth-1:0];

                  if (Verbosity) begin
                    $display("cgetlen output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
                  end
                end

                C_GET_TAG: begin
                  result_o[0]      = a_isValidCap_o;
                  wrote_capability = 1'b0;

                  if (Verbosity) begin
                    $display("cgettag output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
                  end
                end

                C_GET_SEALED: begin
                  result_o[0]      = a_isSealed_o;
                  wrote_capability = 1'b0;

                  if (Verbosity) begin
                    $display("cgetsealed output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
                  end
                end

                C_GET_OFFSET: begin
                  result_o[IntWidth-1:0] = a_getOffset_o;
                  wrote_capability       = 1'b0;

                  if (Verbosity) begin
                    $display("cgetoffset output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
                  end
                end

                C_GET_FLAGS: begin
                  result_o[FlagWidth-1:0] = a_getFlags_o;
                  wrote_capability        = 1'b0;

                  if (Verbosity) begin
                    $display("cgetflags output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
                  end
                end

                C_MOVE: begin
                  result_o         = operand_a_i;
                  wrote_capability = 1'b1;

                  if (Verbosity) begin
                    $display("cmove output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
                  end
                end

                C_CLEAR_TAG: begin
                  a_setValidCap_i  = 1'b0;
                  result_o         = a_setValidCap_o;
                  wrote_capability = 1'b1;

                  if (Verbosity) begin
                    $display("ccleartag output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
                  end
                end

                C_JALR: begin
                  // current implementation of JAL and JALR:
                  // ibex takes 2 cycles to do a normal JAL and JALR, so this one can also take 2 cycles
                  // in the first cycle, ibex calculates the jump target and sends it to the IF stage
                  // in the second cycle, ibex calculates the old PC + 4 and stores that in the destination
                  // register

                  // potential implementation of CJALR:
                  // we call this instruction here for the first cycle. we do all the exception checking
                  // here, and calculate the next PCC from the input register
                  // in the second cycle, we just do an incoffsetimm with a = old pcc and b = 4
                  // issue is this isn't a very clean way of doing this - we need to fake incoffsetimm instruction
                  // in the decoder. However, ibex already does it this way.

                  if (instr_first_cycle_i) begin
                    // calculate the target offset in the ALU for the IF stage
                    alu_operand_a_o = a_getOffset_o;
                    alu_operand_b_o = operand_b_int;
                    alu_operator_o  = ALU_ADD;
                  end else begin
                    alu_operand_a_o = a_getOffset_o;
                    alu_operand_b_o = 4;
                    alu_operator_o  = ALU_ADD;
                    a_setOffset_i   = alu_result_i[IntWidth-1:0];
                    a_setKind_cap_i = a_setOffset_o[CheriCapWidth-1:0];
                    a_setKind_i     = 7'h1E;
                    result_o        = a_setKind_o;
                  end

                  wrote_capability = 1'b1;

                  if (instr_first_cycle_i) begin
                    // check that at least a compressed instruction can be fetched
                    // TODO: adding to the PC can overflow the 32bit PC and lead to low integer results
                    // CHERI allows this and does not cause a trap, but this behaviour might change
                    // this next line is here to allow easy updating of that logic
                    logic [32:0] alu_result_int = 33'h2 + (operand_b_int[31] ? {1'b0, alu_result_i[31:1], 1'b0}
                                                                             : {1'b0, alu_result_i[31:1], 1'b0});

                    cmp_gt_a_i = alu_result_int;
                    cmp_gt_b_i = a_getLength_o;

                    exceptions_a_o.tag_violation            = exceptions_a.tag_violation;
                    // capabilities sealed as Sentries are allowed
                    // if the capability _is_ a sentry, the immediate must be 0 (for cap-mode JALR)
                    exceptions_a_o.seal_violation           = (exceptions_a.seal_violation
                                                              & a_getKind_o != 7'h1E)
                                                            | (a_getKind_o == 7'h1E & operand_b_int != 0);
                    exceptions_a_o.permit_execute_violation = exceptions_a.permit_execute_violation;
                    exceptions_a_o.length_violation         = cmp_gt_res_o;
                    exceptions_a_o.unaligned_base_violation = a_getBase_o[0];
                    // we don't care about trying to throw the last exception since we do support
                    // compressed instructions
                  end

                  if (Verbosity) begin
                    $display("cjalr output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
                  end
                end

                // TODO implement elsewhere
                CLEAR: begin
                end

                C_GET_ADDR: begin
                  result_o[IntWidth-1:0] = a_getAddr_o;
                  wrote_capability       = 1'b0;

                  if (Verbosity) begin
                    $display("cgetaddr output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
                  end
                end

                C_SEAL_ENTRY: begin
                  a_setKind_cap_i = operand_a_i;
                  a_setKind_i     = 7'h1E;

                  result_o         = a_setKind_o;
                  wrote_capability = 1'b1;

                  exceptions_a_o.tag_violation            = exceptions_a.tag_violation;
                  exceptions_a_o.seal_violation           = exceptions_a.seal_violation;
                  exceptions_a_o.permit_execute_violation = exceptions_a.permit_execute_violation;
                end

                C_ROUND_REP_LEN: begin
                  a_getRepLen_i = a_getAddr_o;

                  result_o[IntWidth-1:0] = a_getRepLen_o;
                  wrote_capability       = 1'b0;
                end

                C_REP_ALIGN_MASK: begin
                  a_getRepAlignMask_i    = a_getAddr_o;

                  result_o[IntWidth-1:0] = a_getRepAlignMask_o;
                  wrote_capability       = 1'b0;
                end

                default: begin
                  //$display("something went wrong in the ibex_alu");
                end
              endcase
            end

            default: begin
              //$display("something went wrong in the ibex_alu");
            end
          endcase
        end

        C_INC_OFFSET_IMM: begin
          a_incOffset_i = operand_b_int;

          result_o                  = a_incOffset_o[CheriCapWidth-1:0];
          // only preserve the tag if the result was "exact"
          result_o[CheriCapWidth-1] = result_o[CheriCapWidth-1] & a_incOffset_o[CheriCapWidth];
          wrote_capability          = 1'b1;

          exceptions_a_o.seal_violation = exceptions_a.seal_violation;

          if (Verbosity) begin
            $display  ("cincoffsetimm output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
          end
        end

        C_SET_BOUNDS_IMM: begin
          // need to truncate input since we want it to be unsigned
          a_setBounds_i = {{(IntWidth-ImmWidth){1'b0}}, operand_b_int[ImmWidth-1:0]};

          result_o         = a_setBounds_o[CheriCapWidth-1:0];
          wrote_capability = 1'b1;

          alu_operand_a_o = a_getAddr_o;
          alu_operand_b_o = {{(IntWidth-ImmWidth){1'b0}}, operand_b_int[ImmWidth-1:0]};
          alu_operator_o  = ALU_ADD;

          cmp_gt_a_i = alu_result_i;
          cmp_gt_b_i = a_getTop_o;

          exceptions_a_o.tag_violation    = exceptions_a.tag_violation;
          exceptions_a_o.seal_violation   = exceptions_a.seal_violation;
          exceptions_a_o.length_violation = exceptions_a.length_violation
                                          | cmp_gt_res_o;

          if (Verbosity) begin
            $display("csetboundsimm output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
          end
        end

        default: begin
          //$display("something went wrong in the ibex_alu");
        end
      endcase
    end
  end


// TODO rename/rearrange/refactor these

module_wrap64_setBounds module_wrap64_setBounds_a (
      .wrap64_setBounds_cap     (operand_a_i),
      .wrap64_setBounds_length  (a_setBounds_i),
      .wrap64_setBounds         (a_setBounds_o));

module_wrap64_getAddr module_getAddr_a (
      .wrap64_getAddr_cap (operand_a_i),
      .wrap64_getAddr     (a_getAddr_o));

module_wrap64_getAddr module_getAddr_b (
      .wrap64_getAddr_cap (operand_b_i),
      .wrap64_getAddr     (b_getAddr_o));

module_wrap64_getTop module_wrap64_getTop_a (
      .wrap64_getTop_cap  (operand_a_i),
      .wrap64_getTop      (a_getTop_o));

module_wrap64_getTop module_wrap64_getTop_b (
      .wrap64_getTop_cap  (operand_b_i),
      .wrap64_getTop      (b_getTop_o));

// TODO implementing setKind with these modules isn't great since they expect
// a "Kind" as an input, which is not easy to input from Verilog
// since it's a BSV tagged union

// TODO this is hardwired for now - update to not be hardwired later
assign a_setKind_int = a_setKind_i[3:0] == 4'hF ? {3'b000, a_setKind_i[3:0]}
                     : a_setKind_i[3:0] == 4'hE ? {3'b001, a_setKind_i[3:0]}
                     : a_setKind_i[3:0] == 4'hD ? {3'b010, a_setKind_i[3:0]}
                     : a_setKind_i[3:0] == 4'hC ? {3'b011, a_setKind_i[3:0]}
                     : {3'b100, a_setKind_i[3:0]};
module_wrap64_setKind module_wrap64_setKind_a (
      .wrap64_setKind_cap   (a_setKind_cap_i),
      .wrap64_setKind_kind  (a_setKind_int),
      .wrap64_setKind       (a_setKind_o));

module_wrap64_setKind module_wrap64_setKind_b (
      .wrap64_setKind_cap   (operand_b_i),
      .wrap64_setKind_kind  (b_setKind_i),
      .wrap64_setKind       (b_setKind_o));

module_wrap64_getPerms module_wrap64_getPerms_a (
      .wrap64_getPerms_cap  (operand_a_i),
      .wrap64_getPerms      (a_getPerms_o));

module_wrap64_getPerms module_wrap64_getPerms_b (
      .wrap64_getPerms_cap  (operand_b_i),
      .wrap64_getPerms      (b_getPerms_o));


module_wrap64_setPerms module_wrap64_setPerms_a (
      .wrap64_setPerms_cap    (operand_a_i),
      .wrap64_setPerms_perms  (a_setPerms_i),
      .wrap64_setPerms        (a_setPerms_o));

module_wrap64_setPerms module_wrap64_setPerms_b (
      .wrap64_setPerms_cap    (operand_b_i),
      .wrap64_setPerms_perms  (b_setPerms_i),
      .wrap64_setPerms        (b_setPerms_o));

module_wrap64_setFlags module_wrap64_setFlags_a (
      .wrap64_setFlags_cap    (operand_a_i),
      .wrap64_setFlags_flags  (a_setFlags_i),
      .wrap64_setFlags        (a_setFlags_o));

module_wrap64_setOffset module_wrap64_setOffset_a (
      .wrap64_setOffset_cap   (operand_a_i),
      .wrap64_setOffset_offset(a_setOffset_i),
      .wrap64_setOffset       (a_setOffset_o));

module_wrap64_incOffset module_wrap64_incOffset_a (
      .wrap64_incOffset_cap   (operand_a_i),
      .wrap64_incOffset_inc   (a_incOffset_i),
      .wrap64_incOffset       (a_incOffset_o)
    );

module_wrap64_getBase module_getBase_a (
      .wrap64_getBase_cap     (operand_a_i),
      .wrap64_getBase         (a_getBase_o));

module_wrap64_getBase module_getBase_b (
      .wrap64_getBase_cap     (operand_b_i),
      .wrap64_getBase         (b_getBase_o));

module_wrap64_getOffset module_getOffset_a (
      .wrap64_getOffset_cap   (operand_a_i),
      .wrap64_getOffset       (a_getOffset_o));

module_wrap64_getOffset module_getOffset_b (
      .wrap64_getOffset_cap   (operand_b_i),
      .wrap64_getOffset       (b_getOffset_o));

module_wrap64_isValidCap module_wrap64_isValidCap_a (
      .wrap64_isValidCap_cap  (operand_a_i),
      .wrap64_isValidCap      (a_isValidCap_o));

module_wrap64_isValidCap module_wrap64_isValidCap_b (
      .wrap64_isValidCap_cap  (operand_b_i),
      .wrap64_isValidCap      (b_isValidCap_o));

module_wrap64_getKind module_wrap64_getKind_a (
      .wrap64_getKind_cap     (operand_a_i),
      .wrap64_getKind         (a_getKind_o));

module_wrap64_getKind module_wrap64_getKind_b (
      .wrap64_getKind_cap     (operand_b_i),
      .wrap64_getKind         (b_getKind_o));

module_wrap64_getLength module_getLength_a (
      .wrap64_getLength_cap   (operand_a_i),
      .wrap64_getLength       (a_getLength_o));

module_wrap64_getFlags module_getFlags_a (
      .wrap64_getFlags_cap    (operand_a_i),
      .wrap64_getFlags        (a_getFlags_o));

module_wrap64_setValidCap module_wrap64_setValidCap_a (
      .wrap64_setValidCap_cap   (operand_a_i),
      .wrap64_setValidCap_valid (a_setValidCap_i),
      .wrap64_setValidCap       (a_setValidCap_o));

module_wrap64_setValidCap module_wrap64_setValidCap_b (
      .wrap64_setValidCap_cap   (operand_b_i),
      .wrap64_setValidCap_valid (b_setValidCap_i),
      .wrap64_setValidCap       (b_setValidCap_o));

module_wrap64_setAddr module_wrap64_setAddr_a (
      .wrap64_setAddr_cap       (operand_a_i),
      .wrap64_setAddr_addr      (a_setAddr_i),
      .wrap64_setAddr           (a_setAddr_o));

module_wrap64_setAddr module_wrap64_setAddr_b (
      .wrap64_setAddr_cap   (operand_b_i),
      .wrap64_setAddr_addr  (b_setAddr_i),
      .wrap64_setAddr       (b_setAddr_o));

module_wrap64_isInBounds module_isInBounds_a (
      .wrap64_isInBounds_cap (operand_a_i),
      .wrap64_isInBounds_isTopIncluded(a_isInBounds_isTopIncluded_i),
      .wrap64_isInBounds (a_isInBounds_o));

module_wrap64_isInBounds module_isInBounds_b (
      .wrap64_isInBounds_cap (operand_b_i),
      .wrap64_isInBounds_isTopIncluded(b_isInBounds_isTopIncluded_i),
      .wrap64_isInBounds (b_isInBounds_o));

module_wrap64_getRepresentableAlignmentMask module_getRepresentableAlignmentMask_a (
      .wrap64_getRepresentableAlignmentMask_dummy  (operand_a_i),
      .wrap64_getRepresentableAlignmentMask_length (a_getRepAlignMask_i),
      .wrap64_getRepresentableAlignmentMask        (a_getRepAlignMask_o));

module_wrap64_getRepresentableLength module_getRepresentableLength_a (
      .wrap64_getRepresentableLength_dummy  (operand_a_i),
      .wrap64_getRepresentableLength_length (a_getRepLen_i),
      .wrap64_getRepresentableLength        (a_getRepLen_o));



  // TODO
  // strictly speaking, some of the exceptions that are being set after isSealed and
  // isValidCap would need to be &&'d with the negative of the ones above them
  // (ie a_isValidCap_o && !a_isSealed_o && a_CURSOR_o < a_isSealed_o)
  // this may not actually be needed because exceptions have priorities

  // check for common violations
  always_comb begin
    exceptions_a = cheri_exc_t'(0);
    exceptions_b = cheri_exc_t'(0);

    if (!a_isValidCap_o)
      exceptions_a.tag_violation = 1'b1;

    if (!b_isValidCap_o)
      exceptions_b.tag_violation = 1'b1;

    if (a_isValidCap_o && a_isSealed_o)
      exceptions_a.seal_violation = 1'b1;

    if (b_isValidCap_o && b_isSealed_o)
      exceptions_b.seal_violation = 1'b1;

    if (a_getAddr_o < a_getBase_o)
      exceptions_a.length_violation = 1'b1;

    if (b_getAddr_o < b_getBase_o)
      exceptions_b.length_violation = 1'b1;

    if (a_getKind_o != b_getKind_o)
      exceptions_a.type_violation = 1'b1;

    if (!b_getPerms_o[PermitUnsealIndex])
      exceptions_b.permit_unseal_violation = 1'b1;

    if (!b_getPerms_o[PermitSealIndex])
      exceptions_b.permit_seal_violation = 1'b1;

    if (!a_getPerms_o[PermitExecuteIndex])
      exceptions_a.permit_execute_violation = 1'b1;

    if (!b_getPerms_o[PermitExecuteIndex])
      exceptions_b.permit_execute_violation = 1'b1;

    if (!a_getPerms_o[PermitCInvokeIndex])
      exceptions_a.permit_cinvoke_violation = 1'b1;

    if (!b_getPerms_o[PermitCInvokeIndex])
      exceptions_b.permit_cinvoke_violation = 1'b1;

  end
endmodule
