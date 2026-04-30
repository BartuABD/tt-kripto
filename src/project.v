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

   
    reg [63:0] data_reg;
    reg [31:0] key_reg;
    reg [63:0] ks_reg;

    reg [4:0] round;
    reg       busy;
    reg       done;
    reg       mode;

    wire [2:0] addr = uio_in[2:0];

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

    function [63:0] rotl64_7;
        input [63:0] x;
        begin
            rotl64_7 = {x[56:0], x[63:57]};
        end
    endfunction

    function [63:0] rotl64_13;
        input [63:0] x;
        begin
            rotl64_13 = {x[50:0], x[63:51]};
        end
    endfunction

    function [63:0] next_keystream;
        input [63:0] ks;
        input [31:0] key;
        input [4:0]  r;
        reg   [63:0] round_const;
        begin
            round_const = {24'hA53C5A, r[3:0], 4'hF, 24'h3C5AA5, r[3:0], 4'hC};

            next_keystream =
                rotl64_7(ks) ^
                rotl64_13(ks + {key, ~key}) ^
                round_const ^
                {key ^ 32'hC3A5_9669, ~key ^ 32'h5A3C_F00D};
        end
    endfunction

    wire [63:0] ks_next;
    assign ks_next = next_keystream(ks_reg, key_reg, round);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_reg <= 64'b0;
            key_reg  <= 32'b0;
            ks_reg   <= 64'b0;
            round    <= 5'b0;
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
                    ks_reg <= {key_reg ^ 32'h9E37_79B9, ~key_reg ^ 32'h7F4A_7C15};
                    round  <= 5'd0;
                    busy   <= 1'b1;
                    done   <= 1'b0;
                    mode   <= uio_in[6];
                end
            end else begin
                ks_reg <= ks_next;

                if (round == 5'd15) begin
                    data_reg <= data_reg ^ ks_next;
                    busy     <= 1'b0;
                    done     <= 1'b1;
                    round    <= 5'd0;
                end else begin
                    round <= round + 5'd1;
                end
            end
        end
    end

endmodule

`default_nettype wire
