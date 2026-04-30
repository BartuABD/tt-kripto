/*
 * Copyright (c) 2024 Bartu Abdioglu
 * SPDX-License-Identifier: Apache-2.0
 */


`default_nettype none

module tt_um_bartu_kripto (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    /*
        Tiny Tapeout 1x1 optimized symmetric stream cipher demo

        Data block: 64 bit
        Key:        32 bit

        Operation:
        - Data and key are loaded byte by byte.
        - On start, an 8-bit LFSR seed is generated from the 32-bit key.
        - For 8 cycles, one data byte is XORed with one generated keystream byte.
        - Encryption and decryption are identical because XOR is self-inverse.

        uio_in:
        [2:0] byte address
        [3]   load data byte
        [4]   load key byte
        [5]   start
        [6]   mode, 0 encrypt / 1 decrypt, kept for interface compatibility
        [7]   output select, 0 status / 1 data byte
    */

    reg [63:0] data_reg;
    reg [31:0] key_reg;

    reg [7:0] lfsr;
    reg [2:0] byte_cnt;

    reg busy;
    reg done;
    reg mode;

    wire [2:0] addr;
    assign addr = uio_in[2:0];

    assign uio_out = 8'b0000_0000;
    assign uio_oe  = 8'b0000_0000;

    wire [7:0] selected_output_byte;

    assign selected_output_byte =
        (addr == 3'd0) ? data_reg[7:0]   :
        (addr == 3'd1) ? data_reg[15:8]  :
        (addr == 3'd2) ? data_reg[23:16] :
        (addr == 3'd3) ? data_reg[31:24] :
        (addr == 3'd4) ? data_reg[39:32] :
        (addr == 3'd5) ? data_reg[47:40] :
        (addr == 3'd6) ? data_reg[55:48] :
                         data_reg[63:56];

    assign uo_out = uio_in[7] ? selected_output_byte : {6'b000000, done, busy};

    wire [7:0] key_byte0 = key_reg[7:0];
    wire [7:0] key_byte1 = key_reg[15:8];
    wire [7:0] key_byte2 = key_reg[23:16];
    wire [7:0] key_byte3 = key_reg[31:24];

    wire [7:0] seed;
    assign seed = key_byte0 ^ key_byte1 ^ key_byte2 ^ key_byte3 ^ 8'hA5;

    /*
        8-bit Galois/Fibonacci style LFSR next state.
        Polynomial-like taps: x^8 + x^6 + x^5 + x^4 + 1
    */
    wire feedback;
    wire [7:0] lfsr_next;

    assign feedback  = lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3];
    assign lfsr_next = {lfsr[6:0], feedback};

    /*
        Keystream byte also mixes current byte counter and key bytes.
        This prevents very simple repeated output.
    */
    wire [7:0] ks_byte;
    assign ks_byte = lfsr ^ key_reg[(byte_cnt[1:0] * 8) +: 8] ^ {5'b10101, byte_cnt};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_reg <= 64'b0;
            key_reg  <= 32'b0;
            lfsr     <= 8'b0;
            byte_cnt <= 3'b0;
            busy     <= 1'b0;
            done     <= 1'b0;
            mode     <= 1'b0;
        end else if (ena) begin
            done <= 1'b0;

            if (!busy) begin
                if (uio_in[3]) begin
                    case (addr)
                        3'd0: data_reg[7:0]   <= ui_in;
                        3'd1: data_reg[15:8]  <= ui_in;
                        3'd2: data_reg[23:16] <= ui_in;
                        3'd3: data_reg[31:24] <= ui_in;
                        3'd4: data_reg[39:32] <= ui_in;
                        3'd5: data_reg[47:40] <= ui_in;
                        3'd6: data_reg[55:48] <= ui_in;
                        3'd7: data_reg[63:56] <= ui_in;
                    endcase
                end

                if (uio_in[4]) begin
                    case (addr[1:0])
                        2'd0: key_reg[7:0]   <= ui_in;
                        2'd1: key_reg[15:8]  <= ui_in;
                        2'd2: key_reg[23:16] <= ui_in;
                        2'd3: key_reg[31:24] <= ui_in;
                    endcase
                end

                if (uio_in[5]) begin
                    lfsr     <= (seed == 8'h00) ? 8'h5A : seed;
                    byte_cnt <= 3'd0;
                    busy     <= 1'b1;
                    done     <= 1'b0;
                    mode     <= uio_in[6];
                end
            end else begin
                case (byte_cnt)
                    3'd0: data_reg[7:0]   <= data_reg[7:0]   ^ ks_byte;
                    3'd1: data_reg[15:8]  <= data_reg[15:8]  ^ ks_byte;
                    3'd2: data_reg[23:16] <= data_reg[23:16] ^ ks_byte;
                    3'd3: data_reg[31:24] <= data_reg[31:24] ^ ks_byte;
                    3'd4: data_reg[39:32] <= data_reg[39:32] ^ ks_byte;
                    3'd5: data_reg[47:40] <= data_reg[47:40] ^ ks_byte;
                    3'd6: data_reg[55:48] <= data_reg[55:48] ^ ks_byte;
                    3'd7: data_reg[63:56] <= data_reg[63:56] ^ ks_byte;
                endcase

                lfsr <= lfsr_next;

                if (byte_cnt == 3'd7) begin
                    busy     <= 1'b0;
                    done     <= 1'b1;
                    byte_cnt <= 3'd0;
                end else begin
                    byte_cnt <= byte_cnt + 3'd1;
                end
            end
        end
    end

endmodule

`default_nettype wire