// Copyright lowRISC contributors.
// Copyright 2018 ETH Zurich and University of Bologna, see also CREDITS.md.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

/**
 * Prefetcher Buffer for 32 bit memory interface
 *
 * Prefetch Buffer that caches instructions. This cuts overly long critical
 * paths to the instruction cache.
 */
module ibex_prefetch_buffer #(
  parameter bit ResetAll        = 1'b0,
  parameter int TestRIG         = 0
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic        req_i,

  input  logic        branch_i,
  input  logic [31:0] addr_i,

  input  logic                       ready_i,
  output logic                       valid_o,
  output logic                       imm_o,
  output logic [31:0]                rdata_o,
  output logic [31:0]                addr_o,
  output logic                       err_o,
  output ibex_pkg::cheri_instr_exc_t cheri_err_o,
  output logic                       cheri_len_err_o,
  output logic                       err_plus2_o,

  // goes to instruction memory / instruction cache
  output logic                       instr_req_o,
  input  logic                       instr_gnt_i,
  output logic [31:0]                instr_addr_o,
  input  logic [31:0]                instr_rdata_i,
  input  logic                       instr_err_i,
  input  logic                       instr_rvalid_i,
  // CHERI errors are received in the same cycle that a request goes out
  // This signals exceptions that are guaranteed to have happened
  // The only exceptions that are not guaranteed are length exceptions in the
  // case that either halfword within the fetch would have been allowed,
  // because we do not know when the request is made whether that access is
  // for the upper or lower half of the word
  input  ibex_pkg::cheri_instr_exc_t instr_cheri_err_i,
  // these two signals respectively indicate whether the lower or upper half of
  // the fetch would cause an exception
  // We don't know whether an exception is actually thrown until we know which
  // half was actually fetched, which we only know when the instruction is
  // being returned by the fetch fifo
  input  logic                       instr_cheri_lower_err_i,
  input  logic                       instr_cheri_upper_err_i,
  input  logic                       instr_cheri_upper_err_2_i,

`ifdef RVFI
  output logic        perf_if_cheri_err_o,
`endif

  // Prefetch Buffer Status
  output logic        busy_o
);
  import ibex_pkg::*;

  localparam int unsigned NUM_REQS  = 2;

  logic                valid_new_req, valid_req, valid_req_out;
  logic                valid_req_d, valid_req_q;
  logic                discard_req_d, discard_req_q;
  logic [NUM_REQS-1:0] rdata_outstanding_n, rdata_outstanding_s, rdata_outstanding_q;
  logic [NUM_REQS-1:0] branch_discard_n, branch_discard_s, branch_discard_q;
  logic [NUM_REQS-1:0] rdata_outstanding_rev;
  logic                rdata_outstanding_any;

  // Keep track of the errors when requests are made to sync these with the
  // response when we receive it
  cheri_instr_exc_t    errs_outstanding_n [NUM_REQS];
  cheri_instr_exc_t    errs_outstanding_s [NUM_REQS];
  cheri_instr_exc_t    errs_outstanding_q [NUM_REQS];
  logic [NUM_REQS-1:0] errl_outstanding_n,  errl_outstanding_s,  errl_outstanding_q;
  logic [NUM_REQS-1:0] erru_outstanding_n,  erru_outstanding_s,  erru_outstanding_q;
  logic [NUM_REQS-1:0] erru2_outstanding_n, erru2_outstanding_s, erru2_outstanding_q;

  logic [31:0]         stored_addr_d, stored_addr_q;
  logic                stored_addr_en;
  logic [31:0]         fetch_addr_d, fetch_addr_q;
  logic                fetch_addr_en;
  logic [31:0]         instr_addr, instr_addr_w_aligned;

  logic                fifo_valid;
  logic [31:0]         fifo_addr;
  logic                fifo_ready;
  logic                fifo_clear;
  logic [NUM_REQS-1:0] fifo_busy;
  logic                fifo_lower_err, fifo_upper_err, fifo_upper_err_2;
  cheri_instr_exc_t    fifo_cheri_err;

  ////////////////////////////
  // Prefetch buffer status //
  ////////////////////////////

  // Whether there is any rdata outstanding
  assign rdata_outstanding_any = |rdata_outstanding_q;
  assign busy_o = rdata_outstanding_any | instr_req_o;
`ifdef RVFI
  assign perf_if_cheri_err_o = 1'b0;
`endif

  //////////////////////////////////////////////
  // Fetch fifo - consumes addresses and data //
  //////////////////////////////////////////////

  // A branch will invalidate any previously fetched instructions.
  // Note that the FENCE.I instruction relies on this flushing behaviour on branch. If it is
  // altered the FENCE.I implementation may require changes.
  assign fifo_clear = branch_i;

  // Reversed version of rdata_outstanding_q which can be overlaid with fifo fill state
  for (genvar i = 0; i < NUM_REQS; i++) begin : gen_rd_rev
    assign rdata_outstanding_rev[i] = rdata_outstanding_q[NUM_REQS-1-i];
  end

  // The fifo is ready to accept a new request if it is not full - including space reserved for
  // requests already outstanding.
  // Overlay the fifo fill state with the outstanding requests to see if there is space.
  assign fifo_ready = ~&(fifo_busy | rdata_outstanding_rev);

  ibex_fetch_fifo #(
    .NUM_REQS (NUM_REQS),
    .ResetAll (ResetAll),
    .TestRIG  (TestRIG)
  ) fifo_i (
      .clk_i                 ( clk_i             ),
      .rst_ni                ( rst_ni            ),

      .clear_i               ( fifo_clear        ),
      .busy_o                ( fifo_busy         ),

      .in_valid_i            ( fifo_valid        ),
      .in_addr_i             ( fifo_addr         ),
      .in_rdata_i            ( instr_rdata_i     ),
      .in_err_i              ( instr_err_i       ),
      .in_cheri_err_i        ( fifo_cheri_err    ),
      .in_cheri_lower_err_i  ( fifo_lower_err    ),
      .in_cheri_upper_err_i  ( fifo_upper_err    ),
      .in_cheri_upper_err_2_i( fifo_upper_err_2  ),

      .out_valid_o           ( valid_o           ),
      .out_imm_o             ( imm_o             ),
      .out_ready_i           ( ready_i           ),
      .out_rdata_o           ( rdata_o           ),
      .out_addr_o            ( addr_o            ),
      .out_err_o             ( err_o             ),
      .out_err_plus2_o       ( err_plus2_o       ),
      .out_cheri_err_o       ( cheri_err_o       ),
      .out_cheri_len_err_o   ( cheri_len_err_o   )
  );

  //////////////
  // Requests //
  //////////////

  // Make a new request any time there is space in the FIFO, and space in the request queue
  assign valid_new_req = req_i & (fifo_ready | branch_i) &
                         ~rdata_outstanding_q[NUM_REQS-1];

  assign valid_req = valid_req_q | valid_new_req;

  // Hold the request stable for requests that didn't get granted and did not
  // cause a CHERI error
  // Requests that cause a CHERI error will not actually issue a request on
  // the bus, so this is the same as checking that the request actually made
  // it to the bus but was not granted
  // Since requests that cause a CHERI error do not make it to the bus, we do
  // not want to track whether we receive a response for them on the bus
  assign valid_req_d = valid_req & ~instr_gnt_i;

  // If there is a CHERI error, don't issue the request
  // The request is still valid within this module, the same way that
  // a request which causes a bus error is still valid
  assign valid_req_out = valid_req;

  // Record whether an outstanding bus request is cancelled by a branch
  assign discard_req_d = valid_req_q & (branch_i | discard_req_q);

  ////////////////
  // Fetch addr //
  ////////////////

  // Two addresses are tracked in the prefetch buffer:
  // 1. stored_addr_q - This is the address issued on the bus. It stays stable until
  //                    the request is granted.
  // 2. fetch_addr_q  - This is our next address to fetch from. It is updated on branches to
  //                    capture the new address, and then for each new request issued.
  // A third address is tracked in the fetch FIFO itself:
  // 3. instr_addr_q  - This is the address at the head of the FIFO, efectively our oldest fetched
  //                    address. This address is updated on branches, and does its own increment
  //                    each time the FIFO is popped.

  // 1. stored_addr_q

  // Only update stored_addr_q for new ungranted requests
  // Requests that are guaranteed to cause a CHERI exception do not make it
  // to the bus and hence will never be granted, and should be held stable
  // until the instructions in the FIFO have been executed.
  assign stored_addr_en = valid_new_req & ~valid_req_q & ~instr_gnt_i;

  // Store whatever address was issued on the bus
  assign stored_addr_d = instr_addr;

  // CPU resets with a branch, so no need to reset these addresses
  if (ResetAll) begin : g_stored_addr_ra
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        stored_addr_q <= '0;
      end else if (stored_addr_en) begin
        stored_addr_q <= stored_addr_d;
      end
    end
  end else begin : g_stored_addr_nr
    always_ff @(posedge clk_i) begin
      if (stored_addr_en) begin
        stored_addr_q <= stored_addr_d;
      end
    end
  end
  // 2. fetch_addr_q

  // Update on a branch or as soon as a request is issued
  assign fetch_addr_en = branch_i | (valid_new_req & ~valid_req_q);

  assign fetch_addr_d = (branch_i ? addr_i : {fetch_addr_q[31:2], 2'b00}) +
                        // Current address + 4
                        {{29{1'b0}},(valid_new_req & ~valid_req_q),2'b00};

  if (ResetAll) begin : g_fetch_addr_ra
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        fetch_addr_q <= '0;
      end else if (fetch_addr_en) begin
        fetch_addr_q <= fetch_addr_d;
      end
    end
  end else begin : g_fetch_addr_nr
    always_ff @(posedge clk_i) begin
      if (fetch_addr_en) begin
        fetch_addr_q <= fetch_addr_d;
      end
    end
  end

  // Address mux
  // If there is no branch and there is a CHERI exception, hold the address
  // stable to maintain the exception
  assign instr_addr = valid_req_q       ? stored_addr_q :
                      branch_i          ? addr_i :
                                          fetch_addr_q;

  assign instr_addr_w_aligned = {instr_addr[31:2], 2'b00};

  ///////////////////////////////
  // Request outstanding queue //
  ///////////////////////////////

  for (genvar i = 0; i < NUM_REQS; i++) begin : g_outstanding_reqs
    // Request 0 (always the oldest outstanding request)
    if (i == 0) begin : g_req0
      // A request becomes outstanding once granted, and is cleared once the rvalid is received.
      // Outstanding requests shift down the queue towards entry 0.
      assign rdata_outstanding_n[i] = (valid_req_out & instr_gnt_i) |
                                      rdata_outstanding_q[i];
      // If a branch is received at any point while a request is outstanding, it must be tracked
      // to ensure we discard the data once received
      assign branch_discard_n[i]    = (valid_req_out & instr_gnt_i & discard_req_d) |
                                      (branch_i & rdata_outstanding_q[i]) |
                                      branch_discard_q[i];
      // If there is a request that is granted and returning an error, and
      // this entry is not already full, then set it
      // otherwise maintain this entry if it is full
      assign errs_outstanding_n[i] = (valid_req_out & instr_gnt_i & ~rdata_outstanding_q[i]) ? instr_cheri_err_i
                                   : (rdata_outstanding_q[i]) ? errs_outstanding_q[i]
                                   : cheri_instr_exc_t'(0);
      assign errl_outstanding_n[i] = (valid_req_out & instr_gnt_i & instr_cheri_lower_err_i &
                                      ~rdata_outstanding_q[i])
                                   | (errl_outstanding_q[i] & rdata_outstanding_q[i]);
      assign erru_outstanding_n[i] = (valid_req_out & instr_gnt_i & instr_cheri_upper_err_i &
                                      ~rdata_outstanding_q[i])
                                   | (erru_outstanding_q[i] & rdata_outstanding_q[i]);
      assign erru2_outstanding_n[i] = (valid_req_out & instr_gnt_i & instr_cheri_upper_err_2_i &
                                       ~rdata_outstanding_q[i])
                                    | (erru2_outstanding_q[i] & rdata_outstanding_q[i]);

    end else begin : g_reqtop
    // Entries > 0 consider the FIFO fill state to calculate their next state (by checking
    // whether the previous entry is valid)

      assign rdata_outstanding_n[i] = (valid_req_out & instr_gnt_i &
                                       rdata_outstanding_q[i-1]) |
                                      rdata_outstanding_q[i];
      assign branch_discard_n[i]    = (valid_req_out & instr_gnt_i & discard_req_d &
                                       rdata_outstanding_q[i-1]) |
                                      (branch_i & rdata_outstanding_q[i]) |
                                      branch_discard_q[i];
      // if we are issuing a request and it's coming back with an error,
      // and the entry below this one is already populated and this entry is
      // not populated, then set this entry
      // otherwise if this is already populated, maintain the value
      assign errs_outstanding_n[i] = (valid_req_out & instr_gnt_i & rdata_outstanding_q[i-1]
                                      & ~rdata_outstanding_q[i]) ? instr_cheri_err_i
                                   : rdata_outstanding_q[i] ? errs_outstanding_q[i]
                                   : cheri_instr_exc_t'(0);
      assign errl_outstanding_n[i] = (valid_req_out & instr_gnt_i & instr_cheri_lower_err_i &
                                      rdata_outstanding_q[i-1] & ~rdata_outstanding_q[i])
                                   | (errl_outstanding_q[i] & rdata_outstanding_q[i]);
      assign erru_outstanding_n[i] = (valid_req_out & instr_gnt_i & instr_cheri_upper_err_i &
                                      rdata_outstanding_q[i-1] & ~rdata_outstanding_q[i])
                                   | (erru_outstanding_q[i] & rdata_outstanding_q[i]);
      assign erru2_outstanding_n[i] = (valid_req_out & instr_gnt_i & instr_cheri_upper_err_2_i &
                                       rdata_outstanding_q[i-1] & ~rdata_outstanding_q[i])
                                    | (erru2_outstanding_q[i] & rdata_outstanding_q[i]);
    end
  end

  // Shift the entries down on each instr_rvalid_i
  assign rdata_outstanding_s = instr_rvalid_i ? {1'b0,rdata_outstanding_n[NUM_REQS-1:1]} :
                                                rdata_outstanding_n;
  assign branch_discard_s    = instr_rvalid_i ? {1'b0,branch_discard_n[NUM_REQS-1:1]} :
                                                branch_discard_n;
  assign errl_outstanding_s  = instr_rvalid_i ? {1'b0,errl_outstanding_n[NUM_REQS-1:1]} :
                                                errl_outstanding_n;
  assign erru_outstanding_s  = instr_rvalid_i ? {1'b0,erru_outstanding_n[NUM_REQS-1:1]} :
                                                erru_outstanding_n;
  assign erru2_outstanding_s = instr_rvalid_i ? {1'b0,erru2_outstanding_n[NUM_REQS-1:1]} :
                                                erru2_outstanding_n;
  for (genvar i = 0; i < NUM_REQS; i++) begin : g_shifted_errs_outstanding
    if (i == NUM_REQS-1) begin : g_shifted_errs_top
      assign errs_outstanding_s[i] = instr_rvalid_i ?   cheri_instr_exc_t'(0) : errs_outstanding_n[i];
    end else begin : g_shifter_errs_rest
      assign errs_outstanding_s[i] = instr_rvalid_i ? errs_outstanding_n[i+1] : errs_outstanding_n[i];
    end
  end

  // Push a new entry to the FIFO once complete (and not cancelled by a branch).
  // Also push when there is no outstanding rdata and we are making a new
  // request that raises a CHERI error
  assign fifo_valid = (instr_rvalid_i & ~branch_discard_q[0]);

  assign fifo_addr = addr_i;

  // These types of errors do not halt the generation of requests, and the
  // queue for them is synchronised with the queue of outstanding requests
  assign fifo_cheri_err   = errs_outstanding_q[0];
  assign fifo_lower_err   = errl_outstanding_q[0];
  assign fifo_upper_err   = erru_outstanding_q[0];
  assign fifo_upper_err_2 = erru2_outstanding_q[0];

  ///////////////
  // Registers //
  ///////////////

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      valid_req_q          <= 1'b0;
      discard_req_q        <= 1'b0;
      rdata_outstanding_q  <= 'b0;
      branch_discard_q     <= 'b0;
      for (int i = 0; i < NUM_REQS; i++) begin
        errs_outstanding_q[i] <= cheri_instr_exc_t'(0);
      end
      errl_outstanding_q   <= 'b0;
      erru_outstanding_q   <= 'b0;
      erru2_outstanding_q  <= 'b0;
    end else begin
      valid_req_q          <= valid_req_d;
      discard_req_q        <= discard_req_d;
      rdata_outstanding_q  <= rdata_outstanding_s;
      branch_discard_q     <= branch_discard_s;
      errs_outstanding_q   <= errs_outstanding_s;
      errl_outstanding_q   <= errl_outstanding_s;
      erru_outstanding_q   <= erru_outstanding_s;
      erru2_outstanding_q  <= erru2_outstanding_s;
    end
  end

  /////////////
  // Outputs //
  /////////////

  assign instr_req_o  = valid_req_out;
  assign instr_addr_o = instr_addr_w_aligned;

endmodule
