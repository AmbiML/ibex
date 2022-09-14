#include "Vibex_top_sram.h"
#include <iostream>
#include "verilated_fst_c.h"
#include "socket_packet_utils.c"

struct RVFI_DII_Execution_Packet {
    std::uint64_t rvfi_order : 64;      // [00 - 07] Instruction number:      INSTRET value after completion.
    std::uint64_t rvfi_pc_rdata : 64;   // [08 - 15] PC before instr:         PC for current instruction
    std::uint64_t rvfi_pc_wdata : 64;   // [16 - 23] PC after instr:          Following PC - either PC + 4 or jump/trap target.
    std::uint64_t rvfi_insn : 64;       // [24 - 31] Instruction word:        32-bit command value.
    std::uint64_t rvfi_rs1_data : 64;   // [32 - 39] Read register values:    Values as read from registers named
    std::uint64_t rvfi_rs2_data : 64;   // [40 - 47]                          above. Must be 0 if register ID is 0.
    std::uint64_t rvfi_rd_wdata : 64;   // [48 - 55] Write register value:    MUST be 0 if rd_ is 0.
    std::uint64_t rvfi_mem_addr : 64;   // [56 - 63] Memory access addr:      Points to byte address (aligned if define
                                        //                                      is set). *Should* be straightforward.
                                        //                                      0 if unused.
    std::uint64_t rvfi_mem_rdata : 64;  // [64 - 71] Read data:               Data read from mem_addr (i.e. before write)
    std::uint64_t rvfi_mem_wdata : 64;  // [72 - 79] Write data:              Data written to memory by this command.
    std::uint8_t rvfi_mem_rmask : 8;    // [80]      Read mask:               Indicates valid bytes read. 0 if unused.
    std::uint8_t rvfi_mem_wmask : 8;    // [81]      Write mask:              Indicates valid bytes written. 0 if unused.
    std::uint8_t rvfi_rs1_addr : 8;     // [82]      Read register addresses: Can be arbitrary when not used,
    std::uint8_t rvfi_rs2_addr : 8;     // [83]                               otherwise set as decoded.
    std::uint8_t rvfi_rd_addr : 8;      // [84]      Write register address:  MUST be 0 if not used.
    std::uint8_t rvfi_trap : 8;         // [85] Trap indicator:               Invalid decode, misaligned access or
                                        //                                      jump command to misaligned address.
    std::uint8_t rvfi_halt : 8;         // [86] Halt indicator:               Marks the last instruction retired
                                        //                                      before halting execution.
    std::uint8_t rvfi_intr : 8;         // [87] Trap handler:                 Set for first instruction in trap handler.
};

struct RVFI_DII_Instruction_Packet {
    std::uint32_t dii_insn : 32;      // [0 - 3] Instruction word: 32-bit instruction or command. The lower 16-bits
                                      // may decode to a 16-bit compressed instruction.
    std::uint16_t dii_time : 16;      // [5 - 4] Time to inject token.  The difference between this and the previous
                                      // instruction time gives a delay before injecting this instruction.
                                      // This can be ignored for models but gives repeatability for implementations
                                      // while shortening counterexamples.
    std::uint8_t dii_cmd : 8;         // [6] This token is a trace command.  For example, reset device under test.
    std::uint8_t padding : 8;         // [7]
};

RVFI_DII_Execution_Packet readRVFI(Vibex_top_sram *top, bool signExtend);
void sendReturnTrace(std::vector<RVFI_DII_Execution_Packet> &returnTrace, unsigned long long socket);

double main_time = 0;

double sc_time_stamp() {
    return main_time;
}

const int memory_base = 0x80000000;
const int memory_size =   0x800000;

int main(int argc, char** argv, char** env) {
    if (argc != 3) {
        std::cerr << "Please provide 2 argument (port number and verbosity)" << std::endl;
        exit(-1);
    }

    Verilated::commandArgs(argc, argv);
    Vibex_top_sram * top = new Vibex_top_sram;

    int verbosity = std::atoi(argv[2]);

    // initialize the socket with the input parameters
    unsigned long long socket = serv_socket_create_nameless(std::atoi(argv[1]));
    serv_socket_init(socket);

    // TODO set up initial boot address
    top->clk_i = 1;
    top->rst_ni = 1;
    top->test_en_i = 1;
    top->fetch_enable_i = 1;
    top-> eval();

    // TestRIG expects cores to start fetching from address 0x80000000
    top->boot_addr_i = 0x80000000;

    // set up tracing
    #if VM_TRACE
    Verilated::traceEverOn(true);
    VerilatedFstC* trace_obj = new VerilatedFstC;
    top->trace(trace_obj, 99);
    trace_obj->open("vlt_d.vcd");
    #endif

    int received = 0; // number of instructions received on the socket
    int in_count = 0; // number of instructions that have been read by the core
    int out_count = 0;// number of traces that have been produced by the core

    // socket receive buffer. When we try to receive a packet, we will actually
    // receive 1 more byte which will tell us whether we actually received
    // a packet or not
    char recbuf[sizeof(RVFI_DII_Instruction_Packet) + 1] = {0};

    // the instructions to execute
    std::vector<RVFI_DII_Instruction_Packet> instructions;

    // the traces to be sent to TestRIG, which are generated from the RVFI
    // signals that the core provides
    std::vector<RVFI_DII_Execution_Packet> returntrace;

    int instr_addr_prev = 0;
    int data_addr_prev = 0;
    int data_be_prev = 0;
    int data_we_prev = 0;
    int data_wdata_prev = 0;

    uint8_t *memory = (uint8_t *) malloc(memory_size);
    if (!memory) {
        std::cout << "malloc didn't work" << std::endl;
    }

    // TODO loop condition
    while (1) {
        // If we have not received any packets, or the last packet is not a reset command, try to receive
        // packets until we get a reset command
        if (received == 0 || instructions[received-1].dii_cmd) {
            // attempt to receive packets until we receive an EndOfTrace packet
            RVFI_DII_Instruction_Packet *packet;
            do {
                serv_socket_getN((unsigned int *) recbuf, socket, sizeof(RVFI_DII_Instruction_Packet));

                // the last byte received will be 0 if our attempt to receive a packet was successful
                if (recbuf[sizeof(RVFI_DII_Instruction_Packet)] == 0) {
                    packet = (RVFI_DII_Instruction_Packet *) recbuf;
                    instructions.push_back(*packet);
                    received++;
                    if (verbosity > 0) {
                        std::cout << "received new instruction; new count: " << received << std::endl;
                        if (packet->dii_cmd) {
                            std::cout << "    cmd: " << std::hex << (int) packet->dii_cmd << " instruction: " << packet->dii_insn << std::endl;
                        } else {
                            std::cout << "    reset command" << std::endl;
                        }
                    }
                }

                // sleep for 0.1ms before trying to receive another instruction
                usleep(100);
            } while (packet->dii_cmd != 0);
        }

        // only want to clock the core if we can push instructions in
        // or we're waiting for some output
        if (received > 0                // we have instructions to feed into the core
            && (in_count == 0           // we have not yet inserted an instruction
                || in_count > out_count // there is an instruction in the pipeline
                || received > in_count) // there are instructions that we can put in the pipeline
           ) {
            // When there is a valid RVFI signal, read the RVFI data, add it to
            // the end of the trace and increment out_count
            if (top->rvfi_valid) {
                RVFI_DII_Execution_Packet execpacket = readRVFI(top, false);
                returntrace.push_back(execpacket);
                // temporarily send the return trace every time there is a
                // valid RVFI trace to aid debugging
                // TODO remove this
                sendReturnTrace(returntrace, socket);

                out_count++;
                if (verbosity > 0) {
                    std::cout << "rvfi trace received;"
                              << " instruction: " << std::hex << execpacket.rvfi_insn
                              << " out_count: " << std::dec << out_count
                              << std::endl;
                }
            }


            // Reset when necessary
            // We reset when the pipeline is empty, and the last executed
            // instruction was the last in the trace, and the next command is
            // a reset command
            if (out_count == in_count // there are no instructions in the pipeline
                && in_count == received - 1 // this is the last instruction in the trace
                && !instructions[in_count].dii_cmd // this is a reset command
               ) {
                if (verbosity > 0) {
                    std::cout << "Executing reset" << std::endl;
                }

                // Set the reset signal and clock the core a few times
                // Also record traces
                top->rst_ni = 0;
                for (int i = 0; i < 10; i++) {
                    top->clk_i = !top->clk_i;
                    top->eval();
                    main_time++;
                    #if VM_TRACE
                    trace_obj->dump(main_time);
                    trace_obj->flush();
                    #endif
                }
                top->rst_ni = 1;

                // The returned trace needs a packet at the end with
                // rvfi_halt set to 1
                RVFI_DII_Execution_Packet rstpacket = {
                    .rvfi_halt = 1
                };
                returntrace.push_back(rstpacket);
                sendReturnTrace(returntrace, socket);

                // Reset program state
                instructions.clear();
                in_count = 0;
                out_count = 0;
                received = 0;

                // Reset core inputs
                top->instr_rdata_i = 0;
                top->instr_rvalid_i = 0;
                top->instr_gnt_i = 0;
                top->instr_err_i = 0;
                top->boot_addr_i = 0x80000000;

                // Reset memory
                for (int i = 0; i < memory_size; i++) {
                    memory[i] = 0;
                }

                continue;
            }

            // TODO need to track whether an instruction that was input was
            // actually executed or whether it was skipped (branch pred miss,
            // exception, etc)
            // For now, experiment and see if these static instruction offsets
            // work
            if (top->rvfi_valid && top->rvfi_trap) {
                // there was an exception; roll back instruction counter
                // not sure what to roll back to yet
                // for now, just roll back to the latest instruction that
                // was committed in RVFI
                in_count = out_count;
                if (verbosity > 0) {
                    std::cout << "Encountered exception"
                              << " in_count: " << in_count
                              << " out_count: " << out_count
                              << std::endl;
                }
            } else if (top->perf_jump_o || top->perf_tbranch_o) {
                // there was a branch or jump; roll back as above
                in_count = out_count + 1;
                if (verbosity > 0) {
                    std::cout << "Encountered branch/jump"
                              << " in_count: " << in_count
                              << " out_count: " << out_count
                              << std::endl;
                }
            }

            // A response is always issued on the cycle after it is granted
            // Since we haven't updated instr_gnt_i yet, it has its value from
            // the previous cycle
            top->instr_rvalid_i = top->instr_gnt_i;

            // If there was a gnt_i signal last cycle, then provide an
            // instruction
            if (top->instr_gnt_i) {
                // TODO handle requests out of bounds
                if (1) {
                //if (instr_addr_prev >= 0x80000000 && instr_addr_prev < 0x80010000) {
                    // address is in range
                    top->instr_rdata_i = instructions[in_count].dii_insn;
                    top->instr_err_i = 0;
                    top->boot_addr_i = 0x00000000;
                    in_count++;
                    if (verbosity > 0) {
                        std::cout << "inserting instruction; in_count: " << in_count << std::endl;
                        std::cout << "    instruction: " << std::hex << top->instr_rdata_i << std::endl;
                    }
                } else {
                    // address is not in range
                    top->instr_err_i = 1;
                    if (verbosity > 0) {
                        std::cout << "instruction request out of range; in_count: " << in_count << std::endl;
                        std::cout << "    address: " << std::hex << instr_addr_prev << std::endl;
                    }
                }
            }

            // handle memory requests
            // if there was a data_gnt_i signal last cycle, then execute the
            // memory access
            top->data_rvalid_i = top->data_gnt_i;
            if (top->data_gnt_i) {
                bool addr_out_of_range = data_addr_prev < memory_base
                                         || data_addr_prev >= memory_base + memory_size;
                int int_mem_addr = data_addr_prev - memory_base;
                if (addr_out_of_range) {
                    top->data_err_i = 1;
                    if (verbosity > 0) {
                        std::cout << "memory read out of range" << std::endl;
                        std::cout << "addr: " << std::hex << data_addr_prev << std::endl;
                    }
                } else {
                    top->data_err_i = 0;
                    if (data_we_prev) {
                        // write
                        for (int i = 0; i < 4; i++) {
                            if ((data_be_prev >> i) & 1) {
                                memory[int_mem_addr + i] = (uint8_t) (data_wdata_prev >> (i*8));
                            }
                        }
                        if (verbosity > 0) {
                            std::cout << "store addr: " << std::hex << data_addr_prev
                                      << " memory values:"
                                      << " " << std::hex << (int) memory[int_mem_addr]
                                      << " " << std::hex << (int) memory[int_mem_addr + 1]
                                      << " " << std::hex << (int) memory[int_mem_addr + 2]
                                      << " " << std::hex << (int) memory[int_mem_addr + 3]
                                      << std::endl;
                        }
                    } else {
                        // read
                        // ignore byte-enable for now
                        uint32_t val = 0;
                        for (int i = 0; i < 4; i++) {
                            val |= ((uint32_t) memory[int_mem_addr + i]) << (8*i);
                        }
                        //uint32_t val = memory[int_mem_addr]
                        //             | memory[int_mem_addr+1] << 8
                        //             | memory[int_mem_addr+2] << 16
                        //             | memory[int_mem_addr+3] << 24;
                        if (verbosity > 0) {
                            std::cout << "read addr: " << std::hex << data_addr_prev
                                      << " read value: " << std::hex << val << std::endl;
                        }
                        top->data_rdata_i = val;
                    }
                }
            }


            top->eval();
            main_time++;
            // tracing
            #if VM_TRACE
            if (verbosity > 2) {
                trace_obj->dump(main_time);
                trace_obj->flush();
            }
            #endif

            // instr_gnt_i can be high in the same cycle that instr_req_o goes
            // high, so set it to follow instr_req_o here and evaluate again
            // so that combinational logic that depends on it gets updated
            top->instr_gnt_i = top->instr_req_o;
                               //&& received > in_count;
                               //&& instructions[in_count].dii_cmd;
            // we can always service memory requests
            top->data_gnt_i = top->data_req_o;
            if (verbosity > 0 && top->data_gnt_i) {
                std::cout << "setting data_gnt_i" << std::endl;
                std::cout << "addr: " << std::hex << top->data_addr_o << std::endl;
            }

            if (top->data_req_o) {
                data_addr_prev = top->data_addr_o;
                data_wdata_prev = top->data_wdata_o;
                data_be_prev = top->data_be_o;
                data_we_prev = top->data_we_o;
                if (verbosity > 0) {
                    std::cout << "data_addr_prev: " << std::hex << data_addr_prev << std::endl;
                }
            }
            if (top->instr_req_o) {
                instr_addr_prev = top->instr_addr_o;
            }

            top->eval();
            main_time++;

            // tracing
            #if VM_TRACE
            if (verbosity > 2) {
                trace_obj->dump(main_time);
                trace_obj->flush();
            }
            #endif

            // Clock the core and trace signals
            top->clk_i = 0;
            top->eval();
            main_time++;

            // tracing
            #if VM_TRACE
            if (verbosity > 2) {
                trace_obj->dump(main_time);
                trace_obj->flush();
            }
            #endif


            top->clk_i = 1;
            top->eval();
            main_time++;

            // tracing
            #if VM_TRACE
            if (verbosity > 2) {
                trace_obj->dump(main_time);
                trace_obj->flush();
            }
            #endif
        }
    }

    std::cout << "finished" << std::endl << std::flush;
    delete top;
    exit(0);
}

// send the return trace that is passed in over the socket that is passed in
void sendReturnTrace(std::vector<RVFI_DII_Execution_Packet> &returntrace, unsigned long long socket) {
    const int BULK_SEND = 50;

    if (returntrace.size() > 0) {
        int tosend = 1;
        for (int i = 0; i < returntrace.size(); i+=tosend) {
            tosend = 1;
            RVFI_DII_Execution_Packet sendarr[BULK_SEND];
            sendarr[0] = returntrace[i];

            // bulk send if possible
            if (returntrace.size() - i > BULK_SEND) {
                tosend = BULK_SEND;
                for (int j = 0; j < tosend; j++) {
                    sendarr[j] = returntrace[i+j];
                }
            }

            // loop to make sure that the packet has been properly sent
            while (
                !serv_socket_putN(socket, sizeof(RVFI_DII_Execution_Packet) * tosend, (unsigned int *) sendarr)
            ) {
                // empty
            }
        }
        returntrace.clear();
    }
}

RVFI_DII_Execution_Packet readRVFI(Vibex_top_sram *top, bool signExtend) {
    unsigned long long signExtension;
    if (signExtend) {
        signExtension = 0xFFFFFFFF00000000;
    } else {
        signExtension = 0x0000000000000000;
    }

    RVFI_DII_Execution_Packet execpacket = {
        .rvfi_order = top->rvfi_order,
        // some fields need to be sign-extended
        .rvfi_pc_rdata = top->rvfi_pc_rdata     | ((top->rvfi_pc_rdata & 0x80000000) ? signExtension : 0),
        .rvfi_pc_wdata = top->rvfi_pc_wdata     | ((top->rvfi_pc_wdata & 0x80000000) ? signExtension : 0),
        .rvfi_insn = top->rvfi_insn             | ((top->rvfi_insn & 0x80000000) ? signExtension : 0 ),
        .rvfi_rs1_data = top->rvfi_rs1_rdata    | ((top->rvfi_rs1_rdata & 0x80000000) ? signExtension : 0 ),
        .rvfi_rs2_data = top->rvfi_rs2_rdata    | ((top->rvfi_rs2_rdata & 0x80000000) ? signExtension : 0 ),
        .rvfi_rd_wdata = top->rvfi_rd_wdata     | ((top->rvfi_rd_wdata & 0x80000000) ? signExtension : 0 ),
        .rvfi_mem_addr = top->rvfi_mem_addr     | ((top->rvfi_mem_addr & 0x80000000) ? signExtension : 0 ),
        .rvfi_mem_rdata = top->rvfi_mem_rdata   | ((top->rvfi_mem_rdata & 0x80000000) ? signExtension : 0 ),
        .rvfi_mem_wdata = top->rvfi_mem_wdata   | ((top->rvfi_mem_wdata & 0x80000000) ? signExtension : 0 ),
        .rvfi_mem_rmask = top->rvfi_mem_rmask,
        .rvfi_mem_wmask = top->rvfi_mem_wmask,
        .rvfi_rs1_addr = top->rvfi_rs1_addr,
        .rvfi_rs2_addr = top->rvfi_rs2_addr,
        .rvfi_rd_addr = top->rvfi_rd_addr,
        .rvfi_trap = top->rvfi_trap,
        .rvfi_halt = !top->rst_ni,
        .rvfi_intr = top->rvfi_intr
    };

    return execpacket;
}
