// SPDX-FileCopyrightText: 2020 Efabless Corporation
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// SPDX-License-Identifier: Apache-2.0

`default_nettype none
/*
 *-------------------------------------------------------------
 *
 * user_proj_example
 *
 * This is an example of a (trivially simple) user project,
 * showing how the user project can connect to the logic
 * analyzer, the wishbone bus, and the I/O pads.
 *
 * This project generates an integer count, which is output
 * on the user area GPIO pads (digital output only).  The
 * wishbone connection allows the project to be controlled
 * (start and stop) from the management SoC program.
 *
 * See the testbenches in directory "mprj_counter" for the
 * example programs that drive this user project.  The three
 * testbenches are "io_ports", "la_test1", and "la_test2".
 *
 *-------------------------------------------------------------
 */

module user_proj_example #(
    parameter BITS = 16
)(
`ifdef USE_POWER_PINS
    inout vccd1,	// User area 1 1.8V supply
    inout vssd1,	// User area 1 digital ground
`endif

    // Wishbone Slave ports (WB MI A)
    input wb_clk_i,
    input wb_rst_i,
 /*   input wbs_stb_i,
    input wbs_cyc_i,
    input wbs_we_i,
    input [3:0] wbs_sel_i,
    input [31:0] wbs_dat_i,
    input [31:0] wbs_adr_i,
    output wbs_ack_o,
    output [31:0] wbs_dat_o,

    // Logic Analyzer Signals
    input  [127:0] la_data_in,
    output [127:0] la_data_out,
    input  [127:0] la_oenb,
	*/
    // IOs
    input  [37:7] io_in,
    output [6:3] io_out,
    output [37:3] io_oeb

    // IRQ
   // output [2:0] irq
);

wire rst_sum;
	wire ld_in, ld_weight, shift_in, change, ld_multiplication;
	wire ld_bias_LSB, ld_bias_MSB, bias_addition;
	wire ReLU_computation;
	wire ld_max_func;
	wire [3:0]ld_neuron; // control signal from tb to decide the number of neuron
	wire [15:0]in;
	
	wire [3:0]number; // output

	assign rst_sum = io_in[7];
	assign ld_in = io_in[37];
	assign ld_weight = io_in[36];
	assign shift_in = io_in[35];
	assign change = io_in[34];
   assign ld_multiplication = io_in[33];
	assign ld_bias_LSB = io_in[32];
	assign ld_bias_MSB = io_in[31];
	assign bias_addition = io_in[30];
	assign ReLU_computation = io_in[29];
	assign ld_max_func = io_in[28];
	assign ld_neuron = io_in[27:24];

	assign in = io_in[23:8];

	assign io_oeb[37:7] = 31'b1111111111111111111111111111111; // for inputs
	assign io_oeb[6:3] = 4'b0000; // for outputs

	ANN ann(
	.clk(wb_clk_i), .rst(wb_rst_i),
	.rst_sum(rst_sum),
	.ld_in(ld_in), .ld_weight(ld_weight), .shift_in(shift_in), .change(change), .ld_multiplication(ld_multiplication), 
	.ld_bias_LSB(ld_bias_LSB), .ld_bias_MSB(ld_bias_MSB), .bias_addition(bias_addition),
	.ReLU_computation(ReLU_computation),
	.ld_max_func(ld_max_func),
	.ld_neuron(ld_neuron),
	.in(in),
	.number(number) // final predicted digit
);

	assign io_out[6:3] = number;
   
endmodule

module ANN(
	input clk, rst,
	input rst_sum,
	input ld_in, ld_weight, shift_in, change, ld_multiplication, 
	input ld_bias_LSB, ld_bias_MSB, bias_addition,
	input ReLU_computation,
	input ld_max_func,
	input [3:0]ld_neuron, // control signal from tb to decide the number of neuron
	input [15:0]in,
	output reg [3:0]number // final predicted digit
	
);

	integer i, j, k;
	reg [15:0]in_ff[31:0];
	reg [15:0]weight;
	reg [31:0]multiply_out, multiply_FF, bias, Y, X, sum;
	reg [31:0]ReLU_out[9:0]; // 10 ReLU result for 10 neurons, each of 32-bits

	reg [31:0]temp;

	// --------------------------------- Storing 32*16-bit inputs into the registers -----------------------------
	// Shift Register : Method-2
	//reg [15:0]in_ff1, in_ff2, in_ff3;
	
	always @ (posedge clk) begin
		if(rst) begin
			for (i = 0; i < 32; i = i + 1) begin
				in_ff[i] <= 16'b00000000000000000;
			end 
		end
		else if(ld_in) begin
			in_ff[0] <= in;
			for (j = 1; j < 32; j = j + 1) begin
				in_ff[j] <= in_ff[j-1];
			end
		end
		else if(shift_in) begin
			in_ff[0] <= in_ff[2];
			for (k = 1; k < 32; k = k + 1) begin
				in_ff[k] <= in_ff[k-1];
			end
		end
	end	
	
	// --------------------------------- Weight load -----------------------------
	// Storing weight memory into registers
	always @ (posedge clk) begin
		if(rst) weight <= 16'bxxxxxxxxxxxxxxxx;
		else if(ld_weight) weight <= in; // at every clock cycle it will take different value from 'memory'
		else weight <= 16'bxxxxxxxxxxxxxxxx;		// as per the address values that we are incrementing.
	end	

	// --------------------------------- Bias load -----------------------------
	// Bias load for LSB 
	// Storing bias into registers
	always @ (posedge clk) begin
		if(rst) bias[15:0] <= 16'b0000000000000000;
		else if(ld_bias_LSB) bias[15:0] <= in; // at every clock cycle it will take different value from 'memory'
		else bias[15:0] <= bias[15:0];		// as per the address values that we are incrementing.
	end

	// Bias load for MSB
	// Storing bias into registers
	always @ (posedge clk) begin
		if(rst) bias[31:16] <= 16'b0000000000000000;
		else if(ld_bias_MSB) bias[31:16] <= in; // at every clock cycle it will take different value from 'memory'
		else bias[31:16] <= bias[31:16];		// as per the address values that we are incrementing.
	end

	/*wire [31:0]temp;
	assign temp = { {16{in_ff[0][15]}}, in_ff[0][15:0] };*/
	
	// ------------------- Shifting the value of inputs in the register at every clock cycle -----------------------------
	/*always @ (in or change) begin
		if(shift_in) begin
			in_ff[0] <= in_ff[2];
			for (i = 1; i < 32; i = i + 1) begin
				in_ff[i] <= in_ff[i-1];
			end
		end
	end*/
	// ---------------------------------------------------------------------------------------------------------------------

	// Block for Multiplication
	always @ (weight or rst or rst_sum) begin
		if(rst) multiply_out = 32'b00000000000000000000000000000000;  
	   else if(rst_sum == 1) multiply_out = 0;
		// at every clock cycle if input and weights are loaded then do the multiplication
		else if(ld_weight == 1) begin	
			multiply_out = { {16{in_ff[2][15]}}, in_ff[2][15:0] } * { {16{weight[15]}}, weight[15:0] };
		end
		//else multiply_out = multiply_out;
	end

	always @ (posedge clk) begin
		if(rst) begin
			multiply_FF <= 0;
		end
		else if(rst_sum == 1) multiply_FF <= 0;
		else multiply_FF <= multiply_out;
	end

	reg mux_sel, ldX, add_enable;

	// Multiplexer and Adder
	always @ (multiply_FF or bias) begin
		if(rst) Y = 0;
		else if(rst_sum == 1) Y = 0;
		else /*if(mux_sel == 0) begin*/ 
				Y = multiply_FF;
		//end
		/*else if (mux_sel)begin
			Y = bias;
		end
     	 else 
         Y = 0; */
	end 

	// Loading the value of 'X'
	always @ (posedge clk) begin
		if(rst) X <= 0;
		else if(rst_sum == 1) X <= 0;
		else if(ldX) X <= sum;
		else X <= X;
	end

	// Cummulative Adder
	always @ (*) begin
		if(rst) sum = 0;
		else if(rst_sum == 1) sum = 0;
		else if (add_enable) sum = Y + X;
		else if(bias_addition) begin
			sum = sum + bias;
		end
		else sum = sum;
	end

	// bias addtion
	/*always @ (posedge clk) begin
		if(rst) sum = 0;
		else if(rst_sum == 1) sum = 0;
		if(bias_addition) begin
			sum = sum + bias;
		end
	end*/

	integer m;

	// --------------------------------------- ReLU_computation ----------------------------
	always @ (posedge clk) begin
		if(rst) begin
			for (m = 0; m < 32; m = m + 1) begin
				ReLU_out[m] <= 32'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
			end 
		end
		// N0: 
		else if((ReLU_computation == 1) && (ld_neuron == 4'b0000)) begin
			if(sum[31] == 1) ReLU_out[0] = 32'b00000000000000000000000000000000;
			else ReLU_out[0] = sum;
		end
		// N1: 
		else if((ReLU_computation == 1) && (ld_neuron == 4'b0001)) begin
			if(sum[31] == 1) ReLU_out[1] = 32'b00000000000000000000000000000000;
			else ReLU_out[1] = sum;
		end		
		// N2: 
		else if((ReLU_computation == 1) && (ld_neuron == 4'b0010)) begin
			if(sum[31] == 1) ReLU_out[2] = 32'b00000000000000000000000000000000;
			else ReLU_out[2] = sum;
		end	
		// N3: 
		else if((ReLU_computation == 1) && (ld_neuron == 4'b0011)) begin
			if(sum[31] == 1) ReLU_out[3] = 32'b00000000000000000000000000000000;
			else ReLU_out[3] = sum;
		end
		// N4: 
		else if((ReLU_computation == 1) && (ld_neuron == 4'b0100)) begin
			if(sum[31] == 1) ReLU_out[4] = 32'b00000000000000000000000000000000;
			else ReLU_out[4] = sum;
		end
		// N5: 
		else if((ReLU_computation == 1) && (ld_neuron == 4'b0101)) begin
			if(sum[31] == 1) ReLU_out[5] = 32'b00000000000000000000000000000000;
			else ReLU_out[5] = sum;
		end
		// N6: 
		else if((ReLU_computation == 1) && (ld_neuron == 4'b0110)) begin
			if(sum[31] == 1) ReLU_out[6] = 32'b00000000000000000000000000000000;
			else ReLU_out[6] = sum;
		end
		// N7: 
		else if((ReLU_computation == 1) && (ld_neuron == 4'b0111)) begin
			if(sum[31] == 1) ReLU_out[7] = 32'b00000000000000000000000000000000;
			else ReLU_out[7] = sum;
		end
		// N8: 
		else if((ReLU_computation == 1) && (ld_neuron == 4'b1000)) begin
			if(sum[31] == 1) ReLU_out[8] = 32'b00000000000000000000000000000000;
			else ReLU_out[8] = sum;
		end
		// N9: 
		else if((ReLU_computation == 1) && (ld_neuron == 4'b1001)) begin
			if(sum[31] == 1) ReLU_out[9] = 32'b00000000000000000000000000000000;
			else ReLU_out[9] = sum;
		end

	end
		
	// ------------------------------- Max function computation ---------------------------------
	always @ (posedge clk) begin
		if(rst) number <= 4'bx;
		else if(ld_max_func) begin
			  
				// 0th
				 temp <= ReLU_out[0];
				 number <= 4'b0000;
		
			// 1st
			 if (ReLU_out[1][30:20] > temp[30:20]) begin
				temp <= ReLU_out[1];
				number <= 4'b0001;
			 end
			else if (ReLU_out[1][30:20] == temp[30:20]) begin
				if (ReLU_out[1][19:0] > temp[19:0]) begin
					temp <= ReLU_out[1];
					number <= 4'b0001;
				end
			end

			// 2nd
			 if (ReLU_out[2][30:20] > temp[30:20]) begin
				temp <= ReLU_out[2];
				number <= 4'b0010;
			 end
			else if (ReLU_out[2][30:20] == temp[30:20]) begin
				if (ReLU_out[2][19:0] > temp[19:0]) begin
					temp <= ReLU_out[2];
					number <= 4'b0010;
				end
			end

			// 3rd
			 if (ReLU_out[3][30:20] > temp[30:20]) begin
				temp <= ReLU_out[3];
				number <= 4'b0011;
			 end
			else if (ReLU_out[3][30:20] == temp[30:20]) begin
				if (ReLU_out[3][19:0] > temp[19:0]) begin
					temp <= ReLU_out[3];
					number <= 4'b0011;
				end
			end

			// 4th
			 if (ReLU_out[4][30:20] > temp[30:20]) begin
				temp <= ReLU_out[4];
				number <= 4'b0100;
			 end
			else if (ReLU_out[4][30:20] == temp[30:20]) begin
				if (ReLU_out[4][19:0] > temp[19:0]) begin
					temp <= ReLU_out[4];
					number <= 4'b0100;
				end
			end

			// 5th
			 if (ReLU_out[5][30:20] > temp[30:20]) begin
				temp <= ReLU_out[5];
				number <= 4'b0101;
			 end
			else if (ReLU_out[5][30:20] == temp[30:20]) begin
				if (ReLU_out[5][19:0] > temp[19:0]) begin
					temp <= ReLU_out[5];
					number <= 4'b0101;
				end
			end

			// 6th
			 if (ReLU_out[6][30:20] > temp[30:20]) begin
				temp <= ReLU_out[6];
				number <= 4'b0110;
			 end
			else if (ReLU_out[6][30:20] == temp[30:20]) begin
				if (ReLU_out[6][19:0] > temp[19:0]) begin
					temp <= ReLU_out[6];
					number <= 4'b0110;
				end
			end

			// 7th
			 if (ReLU_out[7][30:20] > temp[30:20]) begin
				temp <= ReLU_out[7];
				number <= 4'b0111;
			 end
			else if (ReLU_out[7][30:20] == temp[30:20]) begin
				if (ReLU_out[7][19:0] > temp[19:0]) begin
					temp <= ReLU_out[7];
					number <= 4'b0111;
				end
			end

			// 8th
			 if (ReLU_out[8][30:20] > temp[30:20]) begin
				temp <= ReLU_out[8];
				number <= 4'b1000;
			 end
			else if (ReLU_out[8][30:20] == temp[30:20]) begin
				if (ReLU_out[8][19:0] > temp[19:0]) begin
					temp <= ReLU_out[8];
					number <= 4'b1000;
				end
			end

			// 9th
			 if (ReLU_out[9][30:20] > temp[30:20]) begin
				temp <= ReLU_out[9];
				number <= 4'b1001;
			 end
			else if (ReLU_out[9][30:20] == temp[30:20]) begin
				if (ReLU_out[9][19:0] > temp[19:0]) begin
					temp <= ReLU_out[9];
					number <= 4'b1001;
				end
			end
			 

		end
		else number <= 4'bxxxx;
	end
		


	// -------------------------------- FSM for cummulative addition ------------------------------------
	reg [2:0] state, next_state;
	parameter S0 = 3'b000, S1 = 3'b001, S2 = 3'b010, S3 = 3'b011;

	always @ (posedge clk) state <= next_state;

	always @ (*) begin
		next_state = 4'bxxxx;

		case(state) 
		S0: begin
			// initializing every control signal with '0'
			add_enable = 0; /*mux_sel = 0;*/ ldX = 0;
			if(ld_multiplication) next_state = S1;
			else next_state = S0;
		    end
		S1: begin
			// Adder
			add_enable = 1; /*mux_sel = 0;*/ ldX = 0;
			next_state = S2;
		     end
		S2: begin
			 // Storing sum values in X
			 add_enable = 0; /*mux_sel = 0;*/ ldX = 1;
			 if (!shift_in) next_state = S3;
			 else next_state = S1;
			 end		
		S3: begin
			// stop doing the addition
			ldX = 0;
			next_state = S0; 
	 	    end
		default: next_state = S0;

		endcase
	end
	// ---------------------------------------------------------------------------------------------------------------------


endmodule



`default_nettype wire
