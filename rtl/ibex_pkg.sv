// Copyright lowRISC contributors.
// Copyright 2017 ETH Zurich and University of Bologna, see also CREDITS.md.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

/**
 * Package with constants used by Ibex
 */
package ibex_pkg;

  ////////////////
  // IO Structs //
  ////////////////

  typedef struct packed {
    logic [31:0] current_pc;
    logic [31:0] next_pc;
    logic [31:0] last_data_addr;
    logic [31:0] exception_pc;
    logic [31:0] exception_addr;
  } crash_dump_t;

  typedef struct packed {
    logic        dummy_instr_id;
    logic [4:0]  raddr_a;
    logic [4:0]  waddr_a;
    logic        we_a;
    logic [4:0]  raddr_b;
  } core2rf_t;

  /////////////////////
  // Parameter Enums //
  /////////////////////

  typedef enum integer {
    RegFileFF    = 0,
    RegFileFPGA  = 1,
    RegFileLatch = 2
  } regfile_e;

  typedef enum integer {
    RV32MNone        = 0,
    RV32MSlow        = 1,
    RV32MFast        = 2,
    RV32MSingleCycle = 3
  } rv32m_e;

  typedef enum integer {
    RV32BNone       = 0,
    RV32BBalanced   = 1,
    RV32BOTEarlGrey = 2,
    RV32BFull       = 3
  } rv32b_e;

  /////////////
  // Opcodes //
  /////////////

  typedef enum logic [6:0] {
    OPCODE_LOAD     = 7'h03,
    OPCODE_MISC_MEM = 7'h0f,
    OPCODE_OP_IMM   = 7'h13,
    OPCODE_AUIPC    = 7'h17,
    OPCODE_STORE    = 7'h23,
    OPCODE_OP       = 7'h33,
    OPCODE_LUI      = 7'h37,
    OPCODE_CHERI    = 7'h5b,
    OPCODE_BRANCH   = 7'h63,
    OPCODE_JALR     = 7'h67,
    OPCODE_JAL      = 7'h6f,
    OPCODE_SYSTEM   = 7'h73
  } opcode_e;


  ////////////////////
  // ALU operations //
  ////////////////////

  typedef enum logic [6:0] {
    // Arithmetics
    ALU_ADD,
    ALU_SUB,

    // Logics
    ALU_XOR,
    ALU_OR,
    ALU_AND,
    // RV32B
    ALU_XNOR,
    ALU_ORN,
    ALU_ANDN,

    // Shifts
    ALU_SRA,
    ALU_SRL,
    ALU_SLL,
    // RV32B
    ALU_SRO,
    ALU_SLO,
    ALU_ROR,
    ALU_ROL,
    ALU_GREV,
    ALU_GORC,
    ALU_SHFL,
    ALU_UNSHFL,
    ALU_XPERM_N,
    ALU_XPERM_B,
    ALU_XPERM_H,

    // Address Calculations
    // RV32B
    ALU_SH1ADD,
    ALU_SH2ADD,
    ALU_SH3ADD,

    // Comparisons
    ALU_LT,
    ALU_LTU,
    ALU_GE,
    ALU_GEU,
    ALU_EQ,
    ALU_NE,
    // RV32B
    ALU_MIN,
    ALU_MINU,
    ALU_MAX,
    ALU_MAXU,

    // Pack
    // RV32B
    ALU_PACK,
    ALU_PACKU,
    ALU_PACKH,

    // Sign-Extend
    // RV32B
    ALU_SEXTB,
    ALU_SEXTH,

    // Bitcounting
    // RV32B
    ALU_CLZ,
    ALU_CTZ,
    ALU_CPOP,

    // Set lower than
    ALU_SLT,
    ALU_SLTU,

    // Ternary Bitmanip Operations
    // RV32B
    ALU_CMOV,
    ALU_CMIX,
    ALU_FSL,
    ALU_FSR,

    // Single-Bit Operations
    // RV32B
    ALU_BSET,
    ALU_BCLR,
    ALU_BINV,
    ALU_BEXT,

    // Bit Compress / Decompress
    // RV32B
    ALU_BCOMPRESS,
    ALU_BDECOMPRESS,

    // Bit Field Place
    // RV32B
    ALU_BFP,

    // Carry-less Multiply
    // RV32B
    ALU_CLMUL,
    ALU_CLMULR,
    ALU_CLMULH,

    // Cyclic Redundancy Check
    ALU_CRC32_B,
    ALU_CRC32C_B,
    ALU_CRC32_H,
    ALU_CRC32C_H,
    ALU_CRC32_W,
    ALU_CRC32C_W
  } alu_op_e;

  typedef enum logic [1:0] {
    // Multiplier/divider
    MD_OP_MULL,
    MD_OP_MULH,
    MD_OP_DIV,
    MD_OP_REM
  } md_op_e;

  ///////////
  // CHERI //
  ///////////

  typedef enum logic [2:0] {
    THREE_OP         = 3'h0,
    C_INC_OFFSET_IMM = 3'h1,
    C_SET_BOUNDS_IMM = 3'h2
  } cheri_base_opcode_e;

  // THREE_OP instructions, which include three-operand instructions as well
  // as two-operand instructions with an additional opcode
  typedef enum logic [6:0] {
    C_SPECIAL_RW       = 7'h01,
    C_SET_BOUNDS       = 7'h08,
    C_SET_BOUNDS_EXACT = 7'h09,
    C_SEAL             = 7'h0B,
    C_UNSEAL           = 7'h0C,
    C_AND_PERM         = 7'h0D,
    C_SET_FLAGS        = 7'h0E,
    C_SET_OFFSET       = 7'h0F,
    C_SET_ADDR         = 7'h10,
    C_INC_OFFSET       = 7'h11,
    C_TO_PTR           = 7'h12,
    C_FROM_PTR         = 7'h13,
    C_SUB              = 7'h14,
    C_BUILD_CAP        = 7'h1D,
    C_COPY_TYPE        = 7'h1E,
    C_C_SEAL           = 7'h1F,
    C_TEST_SUBSET      = 7'h20,
    C_SET_EQUAL_EXACT  = 7'h21,
    C_STORE            = 7'h7C,
    C_LOAD             = 7'h7D,
    C_INVOKE           = 7'h7E,
    SOURCE_AND_DEST    = 7'h7F      // two-operand instructions
  } cheri_threeop_funct7_e;

  // Two-operand instruction opcodes
  typedef enum logic [4:0] {
    C_GET_PERM       = 5'h00,
    C_GET_TYPE       = 5'h01,
    C_GET_BASE       = 5'h02,
    C_GET_LEN        = 5'h03,
    C_GET_TAG        = 5'h04,
    C_GET_SEALED     = 5'h05,
    C_GET_OFFSET     = 5'h06,
    C_GET_FLAGS      = 5'h07,
    C_ROUND_REP_LEN  = 5'h08,
    C_REP_ALIGN_MASK = 5'h09,
    C_MOVE           = 5'h0A,
    C_CLEAR_TAG      = 5'h0B,
    C_JALR           = 5'h0C,
    CLEAR            = 5'h0D,
    C_CLEAR          = 5'h0E,
    C_GET_ADDR       = 5'h0F,
    C_FP_CLEAR       = 5'h10,
    C_SEAL_ENTRY     = 5'h11,
    ONE_OP           = 5'h1F    //unused
  } cheri_s_a_d_funct5_e;

  // Stores
  typedef enum logic [4:0] {
    SB_DDC = 5'h00,
    SH_DDC = 5'h01,
    SW_DDC = 5'h02,
    SD_DDC = 5'h03,
    SQ_DDC = 5'h04,
    SB_CAP = 5'h08,
    SH_CAP = 5'h09,
    SW_CAP = 5'h0A,
    SD_CAP = 5'h0B,
    SQ_CAP = 5'h0C
  } cheri_store_funct5_e;

  // Loads
  typedef enum logic [4:0] {
    LB_DDC  = 5'h00,
    LH_DDC  = 5'h01,
    LW_DDC  = 5'h02,
    LD_DDC  = 5'h03,
    LBU_DDC = 5'h04,
    LHU_DDC = 5'h05,
    LWU_DDC = 5'h06,
    LB_CAP  = 5'h08,
    LH_CAP  = 5'h09,
    LW_CAP  = 5'h0A,
    LD_CAP  = 5'h0B,
    LBU_CAP = 5'h0C,
    LHU_CAP = 5'h0D,
    LWU_CAP = 5'h0E,
    LQ_DDC  = 5'h17,
    LQ_CAP  = 5'h1F
  } cheri_load_funct5_e;

  typedef struct packed {
    logic access_system_regs_violation;
    logic tag_violation;
    logic seal_violation;
    logic type_violation;
    logic permit_seal_violation;
    logic permit_cinvoke_violation;
    logic access_cinvoke_idc_violation;
    logic permit_unseal_violation;
    logic permit_set_cid_violation;
    logic permit_execute_violation;
    logic permit_load_violation;
    logic permit_store_violation;
    logic permit_load_capability_violation;
    logic permit_store_capability_violation;
    logic permit_store_local_capability_violation;
    logic global_violation;
    logic length_violation;
    logic inexact_bounds_violation;
    logic unaligned_base_violation;
    logic software_defined_violation;
  } cheri_exc_t;

  // instruction-specific exceptions, not including length violation
  typedef struct packed {
    logic tag_violation;
    logic seal_violation;
    logic permit_execute_violation;
  } cheri_instr_exc_t;

  // TODO perhaps there is a better way of representing these
  parameter int unsigned CheriKindWidth     = 7;
  parameter int unsigned CheriOTypeWidth    = 4;
  parameter int unsigned CheriPermsWidth    = 31;

  parameter int unsigned CheriMaxOType      = 'hb;

  parameter int unsigned PermitGlobalIndex  = 0;
  parameter int unsigned PermitExecuteIndex = 1;
  parameter int unsigned PermitSealIndex    = 7;
  parameter int unsigned PermitCInvokeIndex = 8;
  parameter int unsigned PermitUnsealIndex  = 9;
  parameter int unsigned PermitAccessSysReg = 10;

  //////////////////////////////////
  // Control and status registers //
  //////////////////////////////////

  // CSR operations
  typedef enum logic [1:0] {
    CSR_OP_READ,
    CSR_OP_WRITE,
    CSR_OP_SET,
    CSR_OP_CLEAR
  } csr_op_e;

  // Privileged mode
  typedef enum logic[1:0] {
    PRIV_LVL_M = 2'b11,
    PRIV_LVL_H = 2'b10,
    PRIV_LVL_S = 2'b01,
    PRIV_LVL_U = 2'b00
  } priv_lvl_e;

  // Constants for the dcsr.xdebugver fields
  typedef enum logic[3:0] {
    XDEBUGVER_NO     = 4'd0, // no external debug support
    XDEBUGVER_STD    = 4'd4, // external debug according to RISC-V debug spec
    XDEBUGVER_NONSTD = 4'd15 // debug not conforming to RISC-V debug spec
  } x_debug_ver_e;

  //////////////
  // WB stage //
  //////////////

  // Type of instruction present in writeback stage
  typedef enum logic[1:0] {
    WB_INSTR_LOAD,  // Instruction is awaiting load data
    WB_INSTR_STORE, // Instruction is awaiting store response
    WB_INSTR_OTHER  // Instruction doesn't fit into above categories
  } wb_instr_type_e;

  //////////////
  // ID stage //
  //////////////

  // Operand a selection
  typedef enum logic[1:0] {
    OP_A_REG_A,
    OP_A_FWD,
    OP_A_CURRPC,
    OP_A_IMM
  } op_a_sel_e;

  // CHERI Operand A selection
  typedef enum logic [1:0] {
    CHERI_OP_A_REG_CAP,
    CHERI_OP_A_REG_DDC,
    CHERI_OP_A_PCC,
    CHERI_OP_A_FWD
  } c_op_a_sel_e;

  // Immediate a selection
  typedef enum logic {
    IMM_A_Z,
    IMM_A_ZERO
  } imm_a_sel_e;

  // Operand b selection
  typedef enum logic {
    OP_B_REG_B,
    OP_B_IMM
  } op_b_sel_e;

  // CHERI Operand B selection
  typedef enum logic [1:0] {
    CHERI_OP_B_REG_CAP,
    CHERI_OP_B_REG_DDC,
    CHERI_OP_B_PCC,
    CHERI_OP_B_IMM
  } c_op_b_sel_e;

  // Immediate b selection
  typedef enum logic [2:0] {
    IMM_B_I,
    IMM_B_S,
    IMM_B_B,
    IMM_B_U,
    IMM_B_J,
    IMM_B_INCR_PC,
    IMM_B_INCR_ADDR,
    IMM_B_ZERO
  } imm_b_sel_e;

  // CHERI Immediate B selection
  typedef enum logic [2:0] {
    CHERI_IMM_B_I,
    CHERI_IMM_B_S,
    CHERI_IMM_B_U,
    CHERI_IMM_B_INCR_PC,
    CHERI_IMM_B_RS2,
    CHERI_IMM_B_ZERO,
    CHERI_IMM_B_TWO,
    CHERI_IMM_B_J
  } c_imm_b_sel_e;

  // Regfile write data selection
  typedef enum logic [1:0] {
    RF_WD_EX,
    RF_WD_CSR, // also covers CHERI SCRs
    RF_WD_CHERI
  } rf_wd_sel_e;

  // Controller FSM state encoding
  typedef enum logic [3:0] {
    RESET,
    BOOT_SET,
    WAIT_SLEEP,
    SLEEP,
    FIRST_FETCH,
    DECODE,
    FLUSH,
    IRQ_TAKEN,
    DBG_TAKEN_IF,
    DBG_TAKEN_ID
  } ctrl_fsm_e;

  //////////////
  // IF stage //
  //////////////

  // PC mux selection
  typedef enum logic [2:0] {
    PC_BOOT,
    PC_JUMP,
    PC_EXC,
    PC_ERET,
    PC_DRET,
    PC_BP
  } pc_sel_e;

  // Exception PC mux selection
  typedef enum logic [1:0] {
    EXC_PC_EXC,
    EXC_PC_IRQ,
    EXC_PC_DBD,
    EXC_PC_DBG_EXC // Exception while in debug mode
  } exc_pc_sel_e;

  // Interrupt requests
  typedef struct packed {
    logic        irq_software;
    logic        irq_timer;
    logic        irq_external;
    logic [14:0] irq_fast; // 15 fast interrupts,
                          // one interrupt is reserved for NMI (not visible through mip/mie)
  } irqs_t;

  typedef struct packed {
    logic       irq_int;
    logic       irq_ext;
    logic [4:0] lower_cause;
  } exc_cause_t;

  localparam exc_cause_t ExcCauseIrqSoftwareM =
    '{irq_ext: 1'b1, irq_int: 1'b0, lower_cause: 5'd03};
  localparam exc_cause_t ExcCauseIrqTimerM =
    '{irq_ext: 1'b1, irq_int: 1'b0, lower_cause: 5'd07};
  localparam exc_cause_t ExcCauseIrqExternalM =
    '{irq_ext: 1'b1, irq_int: 1'b0, lower_cause: 5'd11};
  localparam exc_cause_t ExcCauseIrqNm =
    '{irq_ext: 1'b1, irq_int: 1'b0, lower_cause: 5'd31};

  localparam exc_cause_t ExcCauseInsnAddrMisa =
    '{irq_ext: 1'b0, irq_int: 1'b0, lower_cause: 5'd00};
  localparam exc_cause_t ExcCauseInstrAccessFault =
    '{irq_ext: 1'b0, irq_int: 1'b0, lower_cause: 5'd01};
  localparam exc_cause_t ExcCauseIllegalInsn =
    '{irq_ext: 1'b0, irq_int: 1'b0, lower_cause: 5'd02};
  localparam exc_cause_t ExcCauseBreakpoint =
    '{irq_ext: 1'b0, irq_int: 1'b0, lower_cause: 5'd03};
  localparam exc_cause_t ExcCauseLoadAddrMisalign =
    '{irq_ext: 1'b0, irq_int: 1'b0, lower_cause: 5'd04};
  localparam exc_cause_t ExcCauseLoadAccessFault  =
    '{irq_ext: 1'b0, irq_int: 1'b0, lower_cause: 5'd05};
  localparam exc_cause_t ExcCauseStoreAddrMisalign =
    '{irq_ext: 1'b0, irq_int: 1'b0, lower_cause: 5'd06};
  localparam exc_cause_t ExcCauseStoreAccessFault =
    '{irq_ext: 1'b0, irq_int: 1'b0, lower_cause: 5'd07};
  localparam exc_cause_t ExcCauseEcallUMode =
    '{irq_ext: 1'b0, irq_int: 1'b0, lower_cause: 5'd08};
  localparam exc_cause_t ExcCauseEcallMMode =
    '{irq_ext: 1'b0, irq_int: 1'b0, lower_cause: 5'd11};

  localparam exc_cause_t ExcCauseCheri=
    '{irq_ext: 1'b0, irq_int: 1'b0, lower_cause: 5'h1C};

  // Internal NMI cause
  typedef enum logic [4:0] {
    NMI_INT_CAUSE_ECC = 5'b0
  } nmi_int_cause_e;

  // Debug cause
  typedef enum logic [2:0] {
    DBG_CAUSE_NONE    = 3'h0,
    DBG_CAUSE_EBREAK  = 3'h1,
    DBG_CAUSE_TRIGGER = 3'h2,
    DBG_CAUSE_HALTREQ = 3'h3,
    DBG_CAUSE_STEP    = 3'h4
  } dbg_cause_e;

  // CHERI cause
  typedef enum logic [4:0] {
    CAUSE_NONE                                     = 5'h00,
    CAUSE_LENGTH_VIOLATION                         = 5'h01,
    CAUSE_TAG_VIOLATION                            = 5'h02,
    CAUSE_SEAL_VIOLATION                           = 5'h03,
    CAUSE_TYPE_VIOLATION                           = 5'h04,
    // 'h05...'h07 reserved
    CAUSE_SOFTWARE_DEFINED_PERMISSION_VIOLATION    = 5'h08,
    // 'h09 deprecated in RISC-V
    CAUSE_REPRESENTABILITY_VIOLATION               = 5'h0A,
    CAUSE_UNALIGNED_BASE_VIOLATION                 = 5'h0B,
    // 'h0C..'h0F reserved
    CAUSE_GLOBAL_VIOLATION                         = 5'h10,
    CAUSE_PERMIT_EXECUTE_VIOLATION                 = 5'h11,
    CAUSE_PERMIT_LOAD_VIOLATION                    = 5'h12,
    CAUSE_PERMIT_STORE_VIOLATION                   = 5'h13,
    CAUSE_PERMIT_LOAD_CAPABILITY_VIOLATION         = 5'h14,
    CAUSE_PERMIT_STORE_CAPABILITY_VIOLATION        = 5'h15,
    CAUSE_PERMIT_STORE_LOCAL_CAPABILITY_VIOLATION  = 5'h16,
    CAUSE_PERMIT_SEAL_VIOLATION                    = 5'h17,
    CAUSE_PERMIT_ACCESS_SYSTEM_REGISTERS_VIOLATION = 5'h18,
    CAUSE_PERMIT_CINVOKE_VIOLATION                 = 5'h19,
    CAUSE_PERMIT_ACCESS_CINVOKE_IDC_VIOLATION      = 5'h1A,
    CAUSE_PERMIT_UNSEAL_VIOLATION                  = 5'h1B,
    CAUSE_PERMIT_SET_CID_VIOLATION                 = 5'h1C
    // 'h1C..'h1F reserved
  } c_exc_cause_e;

  // Which register caused the CHERI exception
  typedef enum logic [2:0] {
    REG_A,
    REG_B,
    REG_SCR,
    REG_PCC
  } c_exc_reg_mux_sel_e;

  // ICache constants
  parameter int unsigned ADDR_W           = 32;
  parameter int unsigned BUS_SIZE         = 32;
  parameter int unsigned BUS_BYTES        = BUS_SIZE/8;
  parameter int unsigned BUS_W            = $clog2(BUS_BYTES);
  parameter int unsigned IC_SIZE_BYTES    = 4096;
  parameter int unsigned IC_NUM_WAYS      = 2;
  parameter int unsigned IC_LINE_SIZE     = 64;
  parameter int unsigned IC_LINE_BYTES    = IC_LINE_SIZE/8;
  parameter int unsigned IC_LINE_W        = $clog2(IC_LINE_BYTES);
  parameter int unsigned IC_NUM_LINES     = IC_SIZE_BYTES / IC_NUM_WAYS / IC_LINE_BYTES;
  parameter int unsigned IC_LINE_BEATS    = IC_LINE_BYTES / BUS_BYTES;
  parameter int unsigned IC_LINE_BEATS_W  = $clog2(IC_LINE_BEATS);
  parameter int unsigned IC_INDEX_W       = $clog2(IC_NUM_LINES);
  parameter int unsigned IC_INDEX_HI      = IC_INDEX_W + IC_LINE_W - 1;
  parameter int unsigned IC_TAG_SIZE      = ADDR_W - IC_INDEX_W - IC_LINE_W + 1; // 1 valid bit
  parameter int unsigned IC_OUTPUT_BEATS  = (BUS_BYTES / 2); // number of halfwords
  // ICache Scrambling Parameters
  parameter int unsigned SCRAMBLE_KEY_W   = 128;
  parameter int unsigned SCRAMBLE_NONCE_W = 64;

  // PMP constants
  parameter int unsigned PMP_MAX_REGIONS      = 16;
  parameter int unsigned PMP_CFG_W            = 8;

  // PMP acces type
  parameter int unsigned PMP_I  = 0;
  parameter int unsigned PMP_I2 = 1;
  parameter int unsigned PMP_D  = 2;

  typedef enum logic [1:0] {
    PMP_ACC_EXEC    = 2'b00,
    PMP_ACC_WRITE   = 2'b01,
    PMP_ACC_READ    = 2'b10
  } pmp_req_e;

  // PMP cfg structures
  typedef enum logic [1:0] {
    PMP_MODE_OFF   = 2'b00,
    PMP_MODE_TOR   = 2'b01,
    PMP_MODE_NA4   = 2'b10,
    PMP_MODE_NAPOT = 2'b11
  } pmp_cfg_mode_e;

  typedef struct packed {
    logic          lock;
    pmp_cfg_mode_e mode;
    logic          exec;
    logic          write;
    logic          read;
  } pmp_cfg_t;

  // Machine Security Configuration (ePMP)
  typedef struct packed {
    logic rlb;  // Rule Locking Bypass
    logic mmwp; // Machine Mode Whitelist Policy
    logic mml;  // Machine Mode Lockdown
  } pmp_mseccfg_t;

  // CSRs
  typedef enum logic[11:0] {
    // Machine information
    CSR_MVENDORID = 12'hF11,
    CSR_MARCHID   = 12'hF12,
    CSR_MIMPID    = 12'hF13,
    CSR_MHARTID   = 12'hF14,

    // Machine trap setup
    CSR_MSTATUS   = 12'h300,
    CSR_MISA      = 12'h301,
    CSR_MIE       = 12'h304,
    CSR_MTVEC     = 12'h305,
    CSR_MCOUNTEREN= 12'h306,

    // Machine trap handling
    CSR_MSCRATCH  = 12'h340,
    CSR_MEPC      = 12'h341,
    CSR_MCAUSE    = 12'h342,
    CSR_MTVAL     = 12'h343,
    CSR_MIP       = 12'h344,

    // Physical memory protection
    CSR_PMPCFG0   = 12'h3A0,
    CSR_PMPCFG1   = 12'h3A1,
    CSR_PMPCFG2   = 12'h3A2,
    CSR_PMPCFG3   = 12'h3A3,
    CSR_PMPADDR0  = 12'h3B0,
    CSR_PMPADDR1  = 12'h3B1,
    CSR_PMPADDR2  = 12'h3B2,
    CSR_PMPADDR3  = 12'h3B3,
    CSR_PMPADDR4  = 12'h3B4,
    CSR_PMPADDR5  = 12'h3B5,
    CSR_PMPADDR6  = 12'h3B6,
    CSR_PMPADDR7  = 12'h3B7,
    CSR_PMPADDR8  = 12'h3B8,
    CSR_PMPADDR9  = 12'h3B9,
    CSR_PMPADDR10 = 12'h3BA,
    CSR_PMPADDR11 = 12'h3BB,
    CSR_PMPADDR12 = 12'h3BC,
    CSR_PMPADDR13 = 12'h3BD,
    CSR_PMPADDR14 = 12'h3BE,
    CSR_PMPADDR15 = 12'h3BF,

    // ePMP control
    CSR_MSECCFG   = 12'h747,
    CSR_MSECCFGH  = 12'h757,

    // Debug trigger
    CSR_TSELECT   = 12'h7A0,
    CSR_TDATA1    = 12'h7A1,
    CSR_TDATA2    = 12'h7A2,
    CSR_TDATA3    = 12'h7A3,
    CSR_MCONTEXT  = 12'h7A8,
    CSR_SCONTEXT  = 12'h7AA,

    // Debug/trace
    CSR_DCSR      = 12'h7b0,
    CSR_DPC       = 12'h7b1,

    // Debug
    CSR_DSCRATCH0 = 12'h7b2, // optional
    CSR_DSCRATCH1 = 12'h7b3, // optional

    // CHERI CSRs
    CSR_UCCSR = 12'h8C0,
    CSR_SCCSR = 12'h9C0,
    CSR_MCCSR = 12'hBC0,

    // Machine Counter/Timers
    CSR_MCOUNTINHIBIT  = 12'h320,
    CSR_MHPMEVENT3     = 12'h323,
    CSR_MHPMEVENT4     = 12'h324,
    CSR_MHPMEVENT5     = 12'h325,
    CSR_MHPMEVENT6     = 12'h326,
    CSR_MHPMEVENT7     = 12'h327,
    CSR_MHPMEVENT8     = 12'h328,
    CSR_MHPMEVENT9     = 12'h329,
    CSR_MHPMEVENT10    = 12'h32A,
    CSR_MHPMEVENT11    = 12'h32B,
    CSR_MHPMEVENT12    = 12'h32C,
    CSR_MHPMEVENT13    = 12'h32D,
    CSR_MHPMEVENT14    = 12'h32E,
    CSR_MHPMEVENT15    = 12'h32F,
    CSR_MHPMEVENT16    = 12'h330,
    CSR_MHPMEVENT17    = 12'h331,
    CSR_MHPMEVENT18    = 12'h332,
    CSR_MHPMEVENT19    = 12'h333,
    CSR_MHPMEVENT20    = 12'h334,
    CSR_MHPMEVENT21    = 12'h335,
    CSR_MHPMEVENT22    = 12'h336,
    CSR_MHPMEVENT23    = 12'h337,
    CSR_MHPMEVENT24    = 12'h338,
    CSR_MHPMEVENT25    = 12'h339,
    CSR_MHPMEVENT26    = 12'h33A,
    CSR_MHPMEVENT27    = 12'h33B,
    CSR_MHPMEVENT28    = 12'h33C,
    CSR_MHPMEVENT29    = 12'h33D,
    CSR_MHPMEVENT30    = 12'h33E,
    CSR_MHPMEVENT31    = 12'h33F,
    CSR_MCYCLE         = 12'hB00,
    CSR_MINSTRET       = 12'hB02,
    CSR_MHPMCOUNTER3   = 12'hB03,
    CSR_MHPMCOUNTER4   = 12'hB04,
    CSR_MHPMCOUNTER5   = 12'hB05,
    CSR_MHPMCOUNTER6   = 12'hB06,
    CSR_MHPMCOUNTER7   = 12'hB07,
    CSR_MHPMCOUNTER8   = 12'hB08,
    CSR_MHPMCOUNTER9   = 12'hB09,
    CSR_MHPMCOUNTER10  = 12'hB0A,
    CSR_MHPMCOUNTER11  = 12'hB0B,
    CSR_MHPMCOUNTER12  = 12'hB0C,
    CSR_MHPMCOUNTER13  = 12'hB0D,
    CSR_MHPMCOUNTER14  = 12'hB0E,
    CSR_MHPMCOUNTER15  = 12'hB0F,
    CSR_MHPMCOUNTER16  = 12'hB10,
    CSR_MHPMCOUNTER17  = 12'hB11,
    CSR_MHPMCOUNTER18  = 12'hB12,
    CSR_MHPMCOUNTER19  = 12'hB13,
    CSR_MHPMCOUNTER20  = 12'hB14,
    CSR_MHPMCOUNTER21  = 12'hB15,
    CSR_MHPMCOUNTER22  = 12'hB16,
    CSR_MHPMCOUNTER23  = 12'hB17,
    CSR_MHPMCOUNTER24  = 12'hB18,
    CSR_MHPMCOUNTER25  = 12'hB19,
    CSR_MHPMCOUNTER26  = 12'hB1A,
    CSR_MHPMCOUNTER27  = 12'hB1B,
    CSR_MHPMCOUNTER28  = 12'hB1C,
    CSR_MHPMCOUNTER29  = 12'hB1D,
    CSR_MHPMCOUNTER30  = 12'hB1E,
    CSR_MHPMCOUNTER31  = 12'hB1F,
    CSR_MCYCLEH        = 12'hB80,
    CSR_MINSTRETH      = 12'hB82,
    CSR_MHPMCOUNTER3H  = 12'hB83,
    CSR_MHPMCOUNTER4H  = 12'hB84,
    CSR_MHPMCOUNTER5H  = 12'hB85,
    CSR_MHPMCOUNTER6H  = 12'hB86,
    CSR_MHPMCOUNTER7H  = 12'hB87,
    CSR_MHPMCOUNTER8H  = 12'hB88,
    CSR_MHPMCOUNTER9H  = 12'hB89,
    CSR_MHPMCOUNTER10H = 12'hB8A,
    CSR_MHPMCOUNTER11H = 12'hB8B,
    CSR_MHPMCOUNTER12H = 12'hB8C,
    CSR_MHPMCOUNTER13H = 12'hB8D,
    CSR_MHPMCOUNTER14H = 12'hB8E,
    CSR_MHPMCOUNTER15H = 12'hB8F,
    CSR_MHPMCOUNTER16H = 12'hB90,
    CSR_MHPMCOUNTER17H = 12'hB91,
    CSR_MHPMCOUNTER18H = 12'hB92,
    CSR_MHPMCOUNTER19H = 12'hB93,
    CSR_MHPMCOUNTER20H = 12'hB94,
    CSR_MHPMCOUNTER21H = 12'hB95,
    CSR_MHPMCOUNTER22H = 12'hB96,
    CSR_MHPMCOUNTER23H = 12'hB97,
    CSR_MHPMCOUNTER24H = 12'hB98,
    CSR_MHPMCOUNTER25H = 12'hB99,
    CSR_MHPMCOUNTER26H = 12'hB9A,
    CSR_MHPMCOUNTER27H = 12'hB9B,
    CSR_MHPMCOUNTER28H = 12'hB9C,
    CSR_MHPMCOUNTER29H = 12'hB9D,
    CSR_MHPMCOUNTER30H = 12'hB9E,
    CSR_MHPMCOUNTER31H = 12'hB9F,
    CSR_CPUCTRL        = 12'h7C0,
    CSR_SECURESEED     = 12'h7C1
  } csr_num_e;

  // CHERI SCR
  typedef enum logic [4:0] {
    SCR_PCC       = 5'h00,
    SCR_DDC       = 5'h01,
    SCR_MTCC      = 5'h1C,
    SCR_MTDC      = 5'h1D,
    SCR_MSCRATCHC = 5'h1E,
    SCR_MEPCC     = 5'h1F
  } scr_num_e;

  // CHERI SCR operations
  // bit 0 is WRITE, bit 1 is READ
  typedef enum logic [1:0] {
    SCR_NONE      = 2'b00,
    SCR_WRITE     = 2'b01,
    SCR_READ      = 2'b10,
    SCR_READWRITE = 2'b11
  } scr_op_e;

  // CSR pmp-related offsets
  parameter logic [11:0] CSR_OFF_PMP_CFG  = 12'h3A0; // pmp_cfg  @ 12'h3a0 - 12'h3a3
  parameter logic [11:0] CSR_OFF_PMP_ADDR = 12'h3B0; // pmp_addr @ 12'h3b0 - 12'h3bf

  // CSR status bits
  parameter int unsigned CSR_MSTATUS_MIE_BIT      = 3;
  parameter int unsigned CSR_MSTATUS_MPIE_BIT     = 7;
  parameter int unsigned CSR_MSTATUS_MPP_BIT_LOW  = 11;
  parameter int unsigned CSR_MSTATUS_MPP_BIT_HIGH = 12;
  parameter int unsigned CSR_MSTATUS_MPRV_BIT     = 17;
  parameter int unsigned CSR_MSTATUS_TW_BIT       = 21;

  // CSR machine ISA
  parameter logic [1:0] CSR_MISA_MXL = 2'd1; // M-XLEN: XLEN in M-Mode for RV32

  // CSR interrupt pending/enable bits
  parameter int unsigned CSR_MSIX_BIT      = 3;
  parameter int unsigned CSR_MTIX_BIT      = 7;
  parameter int unsigned CSR_MEIX_BIT      = 11;
  parameter int unsigned CSR_MFIX_BIT_LOW  = 16;
  parameter int unsigned CSR_MFIX_BIT_HIGH = 30;

  // CSR Machine Security Configuration bits
  parameter int unsigned CSR_MSECCFG_MML_BIT  = 0;
  parameter int unsigned CSR_MSECCFG_MMWP_BIT = 1;
  parameter int unsigned CSR_MSECCFG_RLB_BIT  = 2;

  // Vendor ID
  // No JEDEC ID has been allocated to lowRISC so the value is 0 to indicate the field is not
  // implemented
  localparam logic [31:0] CSR_MVENDORID_VALUE  = 32'b0;

  // Architecture ID
  // Top bit is unset to indicate an open source project. The lower bits are an ID allocated by the
  // RISC-V Foundation. Note this is allocated specifically to Ibex, should significant changes be
  // made a different architecture ID should be supplied.
  localparam logic [31:0] CSR_MARCHID_VALUE = {1'b0, 31'd22};

  // Implementation ID
  // 0 indicates this field is not implemeted. Ibex implementors may wish to indicate an RTL/netlist
  // version here using their own unique encoding (e.g. 32 bits of the git hash of the implemented
  // commit).
  localparam logic [31:0] CSR_MIMPID_VALUE = 32'b0;

  // These LFSR parameters have been generated with
  // $ opentitan/util/design/gen-lfsr-seed.py --width 32 --seed 2480124384 --prefix ""
  parameter int LfsrWidth = 32;
  typedef logic [LfsrWidth-1:0] lfsr_seed_t;
  typedef logic [LfsrWidth-1:0][$clog2(LfsrWidth)-1:0] lfsr_perm_t;
  parameter lfsr_seed_t RndCnstLfsrSeedDefault = 32'hac533bf4;
  parameter lfsr_perm_t RndCnstLfsrPermDefault = {
    160'h1e35ecba467fd1b12e958152c04fa43878a8daed
  };
  parameter logic [SCRAMBLE_KEY_W-1:0]   RndCnstIbexKeyDefault =
      128'h14e8cecae3040d5e12286bb3cc113298;
  parameter logic [SCRAMBLE_NONCE_W-1:0] RndCnstIbexNonceDefault =
      64'hf79780bc735f3843;

  // Fetch enable. Mult-bit signal used for security hardening. For non-secure implementation all
  // bits other than the bottom bit are ignored.
  typedef logic [3:0] fetch_enable_t;

  // Note that if adjusting these parameters it is assumed the bottom bit is set for On and unset
  // for Off. This allows the use of FetchEnableOn/FetchEnableOff to work for both secure and
  // non-secure Ibex. If this assumption is broken the RTL that uses the fetch_enable signal within
  // `ibex_core` may need adjusting.
  parameter fetch_enable_t FetchEnableOn  = 4'b0101;
  parameter fetch_enable_t FetchEnableOff = 4'b1010;
endpackage
