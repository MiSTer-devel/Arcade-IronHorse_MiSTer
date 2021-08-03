//============================================================================
// 
//  SystemVerilog implementation of the Konami 005885 custom tilemap
//  generator
//  Graphics logic based on the video section of the Green Beret core for
//  MiSTer by MiSTer-X
//  Copyright (C) 2020, 2021 Ace
//
//  Permission is hereby granted, free of charge, to any person obtaining a
//  copy of this software and associated documentation files (the "Software"),
//  to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense,
//  and/or sell copies of the Software, and to permit persons to whom the 
//  Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
//  DEALINGS IN THE SOFTWARE.
//
//============================================================================

//Note: This model of the 005885 cannot be used as-is to replace an original 005885.

module k005885
(
	input         CK49,     //49.152MHz clock input
	output        NCK2,     //6.144MHz clock output
	output        H1O,      //3.072MHz clock output
	output        NCPE,     //E clock for MC6809E
	output        NCPQ,     //Q clock for MC6809E
	output        NEQ,      //AND of E and Q clocks for MC6809E
	input         NRD,      //Read enable (active low)
	output        NRES,     //Reset passthrough
	input  [13:0] A,        //Address bus from CPU
	input   [7:0] DBi,      //Data bus input from CPU
	output  [7:0] DBo,      //Data output to CPU
	output  [3:0] VCF,      //Color address to tilemap LUT PROM
	output  [3:0] VCB,      //Tile index to tilemap LUT PROM
	input   [3:0] VCD,      //Data input from tilemap LUT PROM
	output  [3:0] OCF,      //Color address to sprite LUT PROM
	output  [3:0] OCB,      //Sprite index to sprite LUT PROM
	input   [3:0] OCD,      //Data input from sprite LUT PROM
	output  [4:0] COL,      //Color data output from color mixer
	input         NEXR,     //Reset input (active low)
	input         NXCS,     //Chip select (active low)
	output        NCSY,     //Composite sync (active low)
	output        NHSY,     //HSync (active low) - Not exposed on the original chip
	output        NVSY,     //VSync (active low)
	output        HBLK,     //HBlank (active high) - Not exposed on the original chip
	output        VBLK,     //VBlank (active high) - Not exposed on the original chip
	input         NBUE,     //Unknown
	output        NFIR,     //Fast IRQ (FIRQ) output for MC6809E
	output        NIRQ,     //IRQ output for MC6809E (VBlank IRQ)
	output        NNMI,     //Non-maskable IRQ (NMI) for MC6809E
	output        NIOC,     //Inverse of address line A11 for external address decoding logic
	output        NRMW,
	
	//Split I/O for tile and sprite data
	output [15:0] R,        //Address output to graphics ROMs (tiles)
	input   [7:0] RDU,      //Upper 8 bits of graphics ROM data (tiles)
	input   [7:0] RDL,      //Lower 8 bits of graphics ROM data (tiles)
	output [15:0] S,        //Address output to graphics ROMs (sprites)
	input   [7:0] SDU,      //Upper 8 bits of graphics ROM data (sprites)
	input   [7:0] SDL,      //Lower 8 bits of graphics ROM data (sprites)
	
	//Extra inputs for screen centering (alters HSync and VSync timing to reposition the video output)
	input   [3:0] HCTR, VCTR,
	
	//Special flag for reconfiguring the chip to mimic the anomalies found on bootlegs of games that use the 005885
	//Valid values:
	//-00: Original behavior
	//-01: Jackal bootleg (faster video timings, missing 4 lines from the video signal, misplaced HBlank, altered screen
	//     centering, sprite layer is missing one line per sprite, sprite layer is misplaced by one line when the screen is
	//     flipped)
	//-10: Iron Horse bootleg (10 extra vertical lines resulting in slower VSync, altered screen centering, sprite layer is
	//     offset vertically by 1 line, sprite limit significantly lower than normal)
	input   [1:0] BTLG, 
	
	//Extra data outputs for graphics ROMs
	output        ATR4,     //Tilemap attribute bit 4
	output        ATR5     //Tilemap attribute bit 5
	
	`ifdef MISTER_IRONHORSE
	//MiSTer high score system I/O (to be used only with Iron Horse)
		,
		input  [11:0] hs_address,
		input   [7:0] hs_data_in,
		output  [7:0] hs_data_out,
		input         hs_write_enable,
		input         hs_access_read,
		input         hs_access_write
	`endif
);

//------------------------------------------------------- Signal outputs -------------------------------------------------------//

//Reset line passthrough
assign NRES = NEXR;

//Generate NIOC output (active low)
assign NIOC = ~(~NXCS & (A[13:11] == 3'b001));

//TODO: The timing of the NRMW output is currently unknown - set to 1 for now
assign NRMW = 1;

//Output bits 4 and 5 of tilemap attributes for graphics ROM addressing
assign ATR4 = tileram_attrib_D[4];
assign ATR5 = tileram_attrib_D[5];

//Data output to CPU
assign DBo = (ram_cs & ~NRD)          ? ram_Dout:
             (zram0_cs & ~NRD)        ? zram0_Dout:
             (zram1_cs & ~NRD)        ? zram1_Dout:
             (zram2_cs & ~NRD)        ? zram2_Dout:
             (tile_attrib_cs & ~NRD)  ? tileram_attrib_Dout:
             (tile_cs & ~NRD)         ? tileram_Dout:
             (tile1_attrib_cs & ~NRD) ? tileram1_attrib_Dout:
             (tile1_cs & ~NRD)        ? tileram1_Dout:
             (spriteram_cs & ~NRD)    ? spriteram_Dout:
             8'hFF;

//------------------------------------------------------- Clock division -------------------------------------------------------//

//Divide the incoming 49.152MHz clock to 6.144MHz and 3.072MHz
reg [3:0] div = 4'd0;
always_ff @(posedge CK49) begin
	div <= div + 4'd1;
end
reg [2:0] n_div = 3'd0;
always_ff @(negedge CK49) begin
	n_div <= n_div + 3'd1;
end
wire cen_6m = !div[2:0];
wire n_cen_6m = !n_div;
wire cen_3m = !div;
assign NCK2 = div[2];
assign H1O = div[3];

//The MC6809E requires two identical clocks with a 90-degree offset - assign these here
reg mc6809e_E = 0;
reg mc6809e_Q = 0;
always_ff @(posedge CK49) begin
	reg [1:0] clk_phase = 0;
	if(cen_6m) begin
		clk_phase <= clk_phase + 1'd1;
		case(clk_phase)
			2'b00: mc6809e_E <= 0;
			2'b01: mc6809e_Q <= 1;
			2'b10: mc6809e_E <= 1;
			2'b11: mc6809e_Q <= 0;
		endcase
	end
end
assign NCPQ = mc6809e_Q;
assign NCPE = mc6809e_E;

//Output NEQ combines NCPE and NCPQ together via an AND gate - assign this here
assign NEQ = NCPE & NCPQ;

//-------------------------------------------------------- Video timings -------------------------------------------------------//

//The 005885's video output has 384 horziontal lines and 262 vertical lines with an active resolution of 240x224.  Declare both
//counters as 9-bit registers.
reg [8:0] h_cnt = 9'd0;
reg [8:0] v_cnt = 9'd0;

//Increment horizontal counter on every falling edge of the pixel clock and increment vertical counter when horizontal counter
//rolls over
reg hblank = 0;
reg vblank = 0;
reg vblank_irq_en = 0;
reg frame_odd_even = 0;
//Add an extra 10 lines to the vertical counter if a bootleg Iron Horse ROM set is loaded or remove 9 lines from the vertical
//counter if a bootleg Jackal ROM set is loaded
reg [8:0] vcnt_end = 0;
always_ff @(posedge CK49) begin
	if(cen_6m) begin
		if(BTLG == 2'b01)
			vcnt_end <= 9'd252;
		else if(BTLG == 2'b10)
			vcnt_end <= 9'd271;
		else
			vcnt_end <= 9'd261;
	end
end
//Reposition HSync and VSync if a bootleg Iron Horse or Jackal ROM set is loaded
reg [8:0] hsync_start = 9'd0;
reg [8:0] hsync_end = 9'd0;
reg [8:0] vsync_start = 9'd0;
reg [8:0] vsync_end = 9'd0;
always_ff @(posedge CK49) begin
	if(BTLG == 2'b01) begin
		hsync_start <= HCTR[3] ? 9'd287 : 9'd295;
		hsync_end <= HCTR[3] ? 9'd318 : 9'd326;
		vsync_start <= 9'd244;
		vsync_end <= 9'd251;
	end
	else if(BTLG == 2'b10) begin
		hsync_start <= HCTR[3] ? 9'd290 : 9'd310;
		hsync_end <= HCTR[3] ? 9'd321 : 9'd341;
		vsync_start <= 9'd255;
		vsync_end <= 9'd262;
	end
	else begin
		hsync_start <= HCTR[3] ? 9'd288 : 9'd296;
		hsync_end <= HCTR[3] ? 9'd319 : 9'd327;
		vsync_start <= 9'd254;
		vsync_end <= 9'd261;
	end
end
always_ff @(posedge CK49) begin
	if(cen_6m) begin
		case(h_cnt)
			0: begin
				vblank_irq_en <= 0;
				h_cnt <= h_cnt + 9'd1;
			end
			//HBlank ends two lines earlier than normal on bootleg Jackal PCBs
			11: begin
				if(BTLG == 2'b01)
					hblank <= 0;
				h_cnt <= h_cnt + 9'd1;
			end
			13: begin
				if(BTLG != 2'b01)
					hblank <= 0;
				h_cnt <= h_cnt + 9'd1;
			end
			//Shift the start of HBlank two lines earlier when bootleg Jackal ROMs are loaded
			251: begin
				if(BTLG == 2'b01)
					hblank <= 1;
				h_cnt <= h_cnt + 9'd1;
			end
			253: begin
				if(BTLG != 2'b01)
					hblank <= 1;
				h_cnt <= h_cnt + 9'd1;
			end
			383: begin
				h_cnt <= 0;
				case(v_cnt)
					15: begin
						vblank <= 0;
						v_cnt <= v_cnt + 9'd1;
					end
					239: begin
						vblank <= 1;
						vblank_irq_en <= 1;
						frame_odd_even <= ~frame_odd_even;
						v_cnt <= v_cnt + 9'd1;
					end
					vcnt_end: begin
						v_cnt <= 9'd0;
					end
					default: v_cnt <= v_cnt + 9'd1;
				endcase
			end
			default: h_cnt <= h_cnt + 9'd1;
		endcase
	end
end

//Output HBlank and VBlank (both active high)
assign HBLK = hblank;
assign VBLK = vblank;

//Generate horizontal sync and vertical sync (both active low)
assign NHSY = HCTR[3] ? ~(h_cnt >= hsync_start - ~HCTR[2:0] && h_cnt <= hsync_end - ~HCTR[2:0]):
                        ~(h_cnt >= hsync_start + HCTR[2:0] && h_cnt <= hsync_end + HCTR[2:0]);
assign NVSY = ~(v_cnt >= vsync_start - VCTR && v_cnt <= vsync_end - VCTR);
assign NCSY = NHSY ^ NVSY;

//------------------------------------------------------------- IRQs -----------------------------------------------------------//

//IRQ (triggers every VBlank)
reg vblank_irq = 1;
always_ff @(posedge CK49 or negedge NEXR) begin
	if(!NEXR)
		vblank_irq <= 1;
	else if(cen_6m) begin
		if(!irq_mask)
			vblank_irq <= 1;
		else if(vblank_irq_en)
			vblank_irq <= 0;
	end
end
assign NIRQ = vblank_irq;

//NMI (triggers every 64 scanlines starting from scanline 48)
reg nmi = 1;
always_ff @(posedge CK49 or negedge NEXR) begin
	if(!NEXR)
		nmi <= 1;
	else if(cen_3m) begin
		if(!nmi_mask)
			nmi <= 1;
		else if((v_cnt[7:0] + 9'd16) % 9'd64 == 0)
			nmi <= 0;
	end
end
assign NNMI = nmi;

//FIRQ (triggers every second VBlank)
reg firq = 1;
always_ff @(posedge CK49 or negedge NEXR) begin
	if(!NEXR)
		firq <= 1;
	else if(cen_3m) begin
		if(!firq_mask)
			firq <= 1;
		else if(!frame_odd_even && v_cnt == 9'd239)
			firq <= 0;
	end
end
assign NFIR = firq;

//----------------------------------------------------- Internal registers -----------------------------------------------------//

//The 005885 has five 8-bit registers set up as follows according to information in konamiic.txt found in MAME's source code:
/*
control registers
000:          scroll y
001:          scroll x (low 8 bits)
002: -------x scroll x (high bit)
     ----xxx- row/colscroll control
              000 = solid scroll (finalizr, ddribble bg)
              100 = solid scroll (jackal)
              001 = ? (ddribble fg)
              011 = colscroll (jackal high scores)
              101 = rowscroll (ironhors, jackal map)
003: ------xx high bits of the tile code
     -----x-- unknown (finalizr)
     ----x--- selects sprite buffer (and makes a copy to a private buffer?)
     --x----- unknown (ironhors)
     -x------ unknown (ironhors)
     x------- unknown (ironhors, jackal)
004: -------x nmi enable
     ------x- irq enable
     -----x-- firq enable
     ----x--- flip screen
*/

wire regs_cs = ~NXCS & (A[13:11] == 2'b00) & (A[6:3] == 4'd0);

reg [7:0] scroll_y, scroll_x, scroll_ctrl, tile_ctrl;
reg nmi_mask = 0;
reg irq_mask = 0;
reg firq_mask = 0;
reg flipscreen = 0;

//Write to the appropriate register
always_ff @(posedge CK49) begin
	if(cen_3m) begin
		if(regs_cs && NRD)
			case(A[2:0])
				3'b000: scroll_y <= DBi;
				3'b001: scroll_x <= DBi;
				3'b010: scroll_ctrl <= DBi;
				3'b011: tile_ctrl <= DBi;
				3'b100: begin
					nmi_mask <= DBi[0];
					irq_mask <= DBi[1];
					firq_mask <= DBi[2];
					flipscreen <= DBi[3];
				end
				default;
			endcase
	end
end

//--------------------------------------------------------- Unknown RAM --------------------------------------------------------//

wire ram_cs = ~NXCS & (A >= 14'h0005 && A <= 14'h001F);

wire [7:0] ram_Dout;
spram #(8, 5) RAM
(
	.clk(CK49),
	.we(ram_cs & NRD),
	.addr(A[4:0]),
	.data(DBi),
	.q(ram_Dout)
);

//-------------------------------------------------------- Internal ZRAM -------------------------------------------------------//

wire zram0_cs = ~NXCS & (A >= 16'h0020 && A <= 16'h003F);
wire zram1_cs = ~NXCS & (A >= 16'h0040 && A <= 16'h005F);
wire zram2_cs = ~NXCS & (A >= 16'h0060 && A <= 16'h00DF);

//The 005885 addresses ZRAM with either horizontal or vertical position bits depending on whether its scroll mode is set to
//line scroll or column scroll - use vertical position bits for line scroll and horizontal position bits for column scroll,
//otherwise don't address it
wire [4:0] zram_A = (scroll_ctrl[3:1] == 3'b101) ? tilemap_vpos[7:3]:
                    (scroll_ctrl[3:1] == 3'b011) ? tilemap_hpos[7:3]:
                    5'h00;
wire [7:0] zram0_D, zram1_D, zram2_D, zram0_Dout, zram1_Dout, zram2_Dout;
dpram_dc #(.widthad_a(5)) ZRAM0
(
	.clock_a(CK49),
	.address_a(A[4:0]),
	.data_a(DBi),
	.q_a(zram0_Dout),
	.wren_a(zram0_cs & NRD),
	
	.clock_b(CK49),
	.address_b(zram_A),
	.q_b(zram0_D)
);
spram #(8, 5) ZRAM1
(
	.clk(CK49),
	.we(zram1_cs & NRD),
	.addr(A[4:0]),
	.data(DBi),
	.q(zram1_Dout)
);
spram #(8, 5) ZRAM2
(
	.clk(CK49),
	.we(zram2_cs & NRD),
	.addr(A[4:0]),
	.data(DBi),
	.q(zram2_Dout)
);

//------------------------------------------------------------ VRAM ------------------------------------------------------------//

//VRAM is external to the 005885 and combines multiple banks into a single 8KB RAM chip for tile attributes and data (two layers),
//and two sprite banks.  For simplicity, this RAM has been made internal to the 005885 implementation and split into its
//constituent components.
wire tile_attrib_cs = ~NXCS & (A[13:10] == 4'b1000);
wire tile_cs = ~NXCS & (A[13:10] == 4'b1001);
wire tile1_attrib_cs = ~NXCS & (A[13:10] == 4'b1010);
wire tile1_cs = ~NXCS & (A[13:10] == 4'b1011);
wire spriteram_cs = ~NXCS & (A[13:12] == 2'b11);

wire [7:0] tileram_attrib_Dout, tileram_Dout, tileram1_attrib_Dout, tileram1_Dout, spriteram_Dout;
wire [7:0] tileram_attrib_D, tileram_D, tileram1_attrib_D, tileram1_D, spriteram_D;
//Tilemap layer 0
dpram_dc #(.widthad_a(10)) VRAM_TILEATTRIB0
(
	.clock_a(CK49),
	.address_a(A[9:0]),
	.data_a(DBi),
	.q_a(tileram_attrib_Dout),
	.wren_a(tile_attrib_cs & NRD),
	
	.clock_b(CK49),
	.address_b(vram_A),
	.q_b(tileram_attrib_D)
);
dpram_dc #(.widthad_a(10)) VRAM_TILECODE0
(
	.clock_a(CK49),
	.address_a(A[9:0]),
	.data_a(DBi),
	.q_a(tileram_Dout),
	.wren_a(tile_cs & NRD),
	
	.clock_b(CK49),
	.address_b(vram_A),
	.q_b(tileram_D)
);
//Tilemap layer 1
dpram_dc #(.widthad_a(10)) VRAM_TILEATTRIB1
(
	.clock_a(CK49),
	.address_a(A[9:0]),
	.data_a(DBi),
	.q_a(tileram1_attrib_Dout),
	.wren_a(tile1_attrib_cs & NRD),
	
	.clock_b(CK49),
	.address_b(vram_A),
	.q_b(tileram1_attrib_D)
);
dpram_dc #(.widthad_a(10)) VRAM_TILECODE1
(
	.clock_a(CK49),
	.address_a(A[9:0]),
	.data_a(DBi),
	.q_a(tileram1_Dout),
	.wren_a(tile1_cs & NRD),
	
	.clock_b(CK49),
	.address_b(vram_A),
	.q_b(tileram1_D)
);



`ifndef MISTER_IRONHORSE
//Sprites
dpram_dc #(.widthad_a(12)) VRAM_SPR
(
	.clock_a(CK49),
	.address_a(A[11:0]),
	.data_a(DBi),
	.q_a(spriteram_Dout),
	.wren_a(spriteram_cs & NRD),
	
	.clock_b(~CK49),
	.address_b(spriteram_A),
	.q_b(spriteram_D)
);
`else
// Hiscore mux (this is only to be used with Iron Horse as its high scores are stored in sprite RAM)
// - Mirrored sprite RAM used to protect against corruption while retrieving highscore data
wire [11:0] VRAM_SPR_AD = hs_access_write ? hs_address : A[11:0];
wire [7:0] VRAM_SPR_DIN = hs_access_write ? hs_data_in : DBi;
wire VRAM_SPR_WE = hs_access_write ? hs_write_enable : (spriteram_cs & NRD);
//Sprites
dpram_dc #(.widthad_a(12)) VRAM_SPR
(
	.clock_a(CK49),
	.address_a(VRAM_SPR_AD),
	.data_a(VRAM_SPR_DIN),
	.q_a(spriteram_Dout),
	.wren_a(VRAM_SPR_WE),
	
	.clock_b(~CK49),
	.address_b(spriteram_A),
	.q_b(spriteram_D)
);
//Sprite RAM shadow for highscore read access
dpram_dc #(.widthad_a(12)) VRAM_SPR_SHADOW
(
	.clock_a(CK49),
	.address_a(VRAM_SPR_AD),
	.data_a(VRAM_SPR_DIN),
	.wren_a(VRAM_SPR_WE),
	
	.clock_b(CK49),
	.address_b(hs_address),
	.q_b(hs_data_out)
);
`endif

//-------------------------------------------------------- Tilemap layer -------------------------------------------------------//

//TODO: The current implementation only handles one of the 005885's two tilemap layers - add logic to handle both layers

//XOR horizontal and vertical counter bits with flipscreen bit
wire [8:0] hcnt_x = h_cnt ^ {9{flipscreen}};
wire [8:0] vcnt_x = v_cnt ^ {9{flipscreen}};

//Generate tilemap position by summing the XORed counter bits with their respective scroll registers or ZRAM bank 0 based on
//whether row scroll or column scroll is enabled
wire [8:0] row_scroll = (scroll_ctrl[3:1] == 3'b101) ? zram0_D : {scroll_ctrl[0], scroll_x};
wire [8:0] col_scroll = (scroll_ctrl[3:1] == 3'b011) ? zram0_D : scroll_y;
wire [8:0] tilemap_hpos = hcnt_x + row_scroll;
wire [8:0] tilemap_vpos = vcnt_x + col_scroll;

//Address output to tilemap section of VRAM
wire [9:0] vram_A = {tilemap_vpos[7:3], tilemap_hpos[7:3]};

//Assign tile index as bits 5 and 6 of tilemap attributes and the tile code
wire [9:0] tile_index = {tileram_attrib_D[7:6], tileram_D};

//XOR tile H/V flip bits with the flipscreen bit
wire tile_hflip = tileram_attrib_D[4];
wire tile_vflip = tileram_attrib_D[5];

//Address output to graphics ROMs
assign R = {tile_ctrl[1:0], tile_index, (tilemap_vpos[2:0] ^ {3{tile_vflip}}), (tilemap_hpos[2] ^ tile_hflip)};

//Latch tile data from graphics ROMs, tile colors and tile H flip bit from VRAM on the falling edge of tilemap horizontal position
//bit 1
reg [15:0] RD_lat = 16'd0;
reg [3:0] tile_color = 4'd0;
reg tile_hflip_lat = 0;
reg old_tilehpos1;
always_ff @(posedge CK49) begin
	old_tilehpos1 <= tilemap_hpos[1];
	if(old_tilehpos1 && !tilemap_hpos[1]) begin
		tile_color <= tileram_attrib_D[3:0];
		RD_lat <= flipscreen ? {RDL, RDU} : {RDU, RDL};
		tile_hflip_lat <= tileram_attrib_D[4];
	end
end

//Multiplex graphics ROM data down from 16 bits to 8 using bit 1 of the horizontal position
wire [7:0] RD = (tilemap_hpos[1] ^ tile_hflip_lat) ? RD_lat[7:0] : RD_lat[15:8];

//Further multiplex graphics ROM data down from 8 bits to 4 using bit 0 of the horizontal position
wire [3:0] tile_pixel = (tilemap_hpos[0] ^ tile_hflip_lat) ? RD[3:0] : RD[7:4];

//Retrieve tilemap select bit from bit 1 of the tile control register XORed with bit 5 of the same register
wire tile_sel = tile_ctrl[1] ^ tile_ctrl[5];
reg tilemap_en = 0;
always_ff @(posedge CK49) begin
	if(n_cen_6m) begin
		tilemap_en <= tile_sel;
	end
end

//Address output to tilemap LUT PROM
assign VCF = tile_color;
assign VCB = tile_pixel;

//Shift the tilemap layer left by two lines when the screen is flipped
reg [7:0] tilemap_shift;
always_ff @(posedge CK49) begin
	if(cen_6m)
		tilemap_shift <= {VCD, tilemap_shift[7:4]};
end
wire [3:0] tilemap_D = flipscreen ? tilemap_shift[3:0] : VCD; 

//-------------------------------------------------------- Sprite layer --------------------------------------------------------//

//The following code is an adaptation of the sprite renderer from MiSTer-X's Green Beret core tweaked for the 005885's sprite format
reg [8:0] sprite_hpos = 9'd0;
reg [8:0] sprite_vpos = 9'd0;
always_ff @(posedge CK49) begin
	if(cen_6m) begin
		sprite_hpos <= h_cnt;
		//If a bootleg Iron Horse ROM set is loaded, apply a vertical offset of 65 lines (66 when flipped) to recreate the
		//bootleg hardware's 1-line downward vertical offset between the sprite and tilemap layers, otherwise apply a
		//vertical offset of 66 lines (65 lines when flipped)
		if(BTLG == 2'b10)
			if(flipscreen)
				sprite_vpos <= v_cnt + 9'd66;
			else
				sprite_vpos <= v_cnt + 9'd65;
		else
			if(flipscreen)
				sprite_vpos <= v_cnt + 9'd65;
			else
				sprite_vpos <= v_cnt + 9'd66;
	end
end

//Sprite state machine
reg [8:0] sprite_index;
reg [2:0] sprite_offset;
reg [7:0] sprite_attrib0, sprite_attrib1, sprite_attrib2, sprite_attrib3, sprite_attrib4;
reg [2:0] sprite_fsm_state;
reg [5:0] sprite_width;
//Bootleg Iron Horse PCBs have a lower-than-normal sprite limit causing noticeable sprite flickering - reduce the sprite limit
//to 32 sprites (0 - 155 in increments of 5) if one such ROM set is loaded (render 96 sprites at once, 0 - 485 in increments of
//5, otherwise)
wire [8:0] sprite_limit = (BTLG == 2'b10) ? 9'd155 : 9'd485;
always_ff @(posedge CK49) begin
	//Reset the sprite state machine whenever the sprite horizontal postion, and in turn the horziontal counter, returns to 0
	//Also hold the sprite state machine in this initial state for the first line while drawing sprites for bootleg Iron Horse
	//ROM sets to prevent graphical garbage from occurring on the top-most line
	if(sprite_hpos == 9'd0 || (BTLG == 2'b10 && (!flipscreen && sprite_vpos <= 9'd80) || (flipscreen && sprite_vpos >= 9'd304))) begin
		sprite_width <= 0;
		sprite_index <= 0;
		sprite_offset <= 3'd4;
		sprite_fsm_state <= 1;
	end
	else
		case(sprite_fsm_state)
			0: /* empty */ ;
			1: begin
				if(sprite_index > sprite_limit)
					sprite_fsm_state <= 0;
				else begin
					sprite_attrib4 <= spriteram_D;
					sprite_offset <= 3'd3;
					sprite_fsm_state <= sprite_fsm_state + 3'd1;
				end
			end
			2: begin
				sprite_attrib3 <= spriteram_D;
				sprite_offset <= 3'd2;
				sprite_fsm_state <= sprite_fsm_state + 3'd1;
			end
			3: begin
				//Skip the current sprite if it's inactive, otherwise obtain the sprite Y attribute and continue
				//scanning out the rest of the sprite attributes
				if(sprite_active) begin
					sprite_attrib2 <= spriteram_D;
					sprite_offset <= 3'd1;
					sprite_fsm_state <= sprite_fsm_state + 3'd1;
				end
				else begin
					sprite_index <= sprite_index + 9'd5;
					sprite_offset <= 3'd4;
					sprite_fsm_state <= 3'd1;
				end
			end
			4: begin
				sprite_attrib1 <= spriteram_D;
				sprite_offset <= 3'd0;
				sprite_fsm_state <= sprite_fsm_state + 3'd1;
			end
			5: begin
				sprite_attrib0 <= spriteram_D;
				sprite_offset <= 3'd4;
				sprite_index <= sprite_index + 9'd5;
				case(sprite_size)
					3'b000: sprite_width <= 6'b110000 + (BTLG == 2'b01 && flipscreen);
					3'b001: sprite_width <= 6'b110000 + (BTLG == 2'b01 && flipscreen);
					3'b010: sprite_width <= 6'b111000 + (BTLG == 2'b01 && flipscreen);
					3'b011: sprite_width <= 6'b111000 + (BTLG == 2'b01 && flipscreen);
					3'b100: sprite_width <= 6'b100000 + (BTLG == 2'b01 && flipscreen);
					default: sprite_width <= 6'b100000 + (BTLG == 2'b01 && flipscreen);
				endcase
				sprite_fsm_state <= sprite_fsm_state + 3'd1;
			end
			6: begin
				//Skip the last line of a sprite if a bootleg Jackal ROM set is loaded (the hardware on such bootlegs fails
				//to render the last line of sprites), otherwise write sprites as normal
				if(BTLG == 2'b01 && !flipscreen)
					if(sprite_width == 6'b111110)
						sprite_width <= sprite_width + 6'd2;
					else
						sprite_width <= sprite_width + 6'd1;
				else
					sprite_width <= sprite_width + 6'd1;
				sprite_fsm_state <= wre ? sprite_fsm_state : 3'd1;
			end
			default:;
		endcase
end

//Obtain sprite X position from sprite attribute byte 3 - append a 9th bit based on the state of bit 1 sprite attribute byte 4,
//bit 0 of sprite attribute byte 4 if high or the AND of the upper 5 bits of the horizontal position if low
reg sprite_x8;
always_ff @(posedge CK49) begin
	if(sprite_attrib4[1])
		sprite_x8 <= sprite_attrib4[0];
	else
		sprite_x8 <= &sprite_attrib3[7:3];
end
wire [8:0] sprite_x = {sprite_x8 ^ flipscreen, sprite_attrib3 ^ {8{flipscreen}}};

//If the sprite state machine is in state 3, obtain sprite Y position directly from sprite RAM, otherwise obtain it from
//sprite attribute byte 2
wire [7:0] sprite_y = (sprite_fsm_state == 3'd3) ? spriteram_D : sprite_attrib2;

//Sprite flip attributes are stored in bits 5 (horizontal) and 6 (vertical) of sprite attribute byte 4
//Also XOR these attributes with the flipscreen bit (XOR with the inverse for vertical flip)
wire sprite_hflip = sprite_attrib4[5] ^ flipscreen;
wire sprite_vflip = sprite_attrib4[6] ^ ~flipscreen;

//Sprite code is sprite attribute byte 0 sandwiched between bits 1 and 0 and bits 3 and 2 of sprite attribute byte 1
wire [11:0] sprite_code = {sprite_attrib1[1:0], sprite_attrib0, sprite_attrib1[3:2]};

//Sprite color is the upper 4 bits of sprite attribute byte 1
wire [3:0] sprite_color = sprite_attrib1[7:4];

//The 005885 supports 5 different sprite sizes: 8x8, 8x16, 16x8, 16x16 and 32x32.  Retrieve this attribute from bits [4:2] of
//sprite attribute byte 4
wire [2:0] sprite_size = sprite_attrib4[4:2];

//Adjust sprite code based on sprite size
wire [11:0] sprite_code_sized = sprite_size == 3'b000 ? {sprite_code[11:2], ly[3], lx[3]}:          //16x16
                                sprite_size == 3'b001 ? {sprite_code[11:1], lx[3]}:                 //16x8
                                sprite_size == 3'b010 ? {sprite_code[11:2], ly[3], sprite_code[0]}: //8x16
                                sprite_size == 3'b011 ? sprite_code:                                //8x8
                                {sprite_code[11:2] + {ly[4], lx[4]}, ly[3], lx[3]};                 //32x32

//Subtract vertical sprite position from sprite Y parameter to obtain sprite height
wire [8:0] sprite_height = {(sprite_y[7:4] == 4'hF), sprite_y ^ {8{flipscreen}}} - sprite_vpos;

//Set when a sprite is active depending on whether it is 8, 16 or 32 pixels tall
reg sprite_active;
always @(*) begin
	case(sprite_size)
		3'b000: sprite_active <= (sprite_height[8:7] == 2'b11) & (sprite_height[6] ^ ~flipscreen) & (sprite_height[5] ^ flipscreen)
		                         & (sprite_height[4] ^ flipscreen);
		3'b001: sprite_active <= (sprite_height[8:7] == 2'b11) & (sprite_height[6] ^ ~flipscreen) & (sprite_height[5] ^ flipscreen)
		                         & (sprite_height[4] ^ flipscreen) & (sprite_height[3] ^ flipscreen);
		3'b010: sprite_active <= (sprite_height[8:7] == 2'b11) & (sprite_height[6] ^ ~flipscreen) & (sprite_height[5] ^ flipscreen)
		                         & (sprite_height[4] ^ flipscreen);
		3'b011: sprite_active <= (sprite_height[8:7] == 2'b11) & (sprite_height[6] ^ ~flipscreen) & (sprite_height[5] ^ flipscreen)
		                         & (sprite_height[4] ^ flipscreen) & (sprite_height[3] ^ flipscreen);
		3'b100: sprite_active <= (sprite_height[8:7] == 2'b11) & (sprite_height[6] ^ ~flipscreen) & (sprite_height[5] ^ flipscreen);
		default: sprite_active <= (sprite_height[8:7] == 2'b11) & (sprite_height[6] ^ ~flipscreen) & (sprite_height[5] ^ flipscreen);
	endcase
end

wire [4:0] lx = sprite_width[4:0] ^ {5{sprite_hflip}};
wire [4:0] ly = sprite_height[4:0] ^ {5{sprite_vflip}};

//Assign address outputs to sprite ROMs
assign S = {sprite_code_sized, ly[2:0], lx[2]};

//Multiplex sprite ROM data down from 16 bits to 8 using bit 1 of the horizontal position
wire [7:0] SD = lx[1] ? SDL : SDU;

//Further multiplex sprite ROM data down from 8 bits to 4 using bit 0 of the horizontal position
wire [3:0] sprite_pixel = lx[0] ? SD[3:0] : SD[7:4];

//Sum the sprite index with the sprite offset and address sprite RAM with it along with tile control register bit 3
wire [8:0] sprite_address = (sprite_index + sprite_offset);
reg sprite_bank = 0;
reg old_vsync;
//Normally, the 005885 latches the sprite bank from bit 3 of the tile control register on the rising edge of VSync, though this causes
//jerky scrolling with sprites for bootleg Jackal ROM sets - bypass this latch if such ROM sets are loaded
always_ff @(posedge CK49) begin
	old_vsync <= NVSY;
	if(!NEXR)
		sprite_bank <= 0;
	else if(!old_vsync && NVSY)
		sprite_bank <= tile_ctrl[3];
end
wire [11:0] spriteram_A = {(BTLG == 2'b01) ? tile_ctrl[3] : sprite_bank, 2'b00, sprite_address};

//Address output to sprite LUT PROM
assign OCF = sprite_color;
assign OCB = sprite_pixel;

//----------------------------------------------------- Sprite line buffer -----------------------------------------------------//

//The sprite line buffer is external to the 005885 and consists of two 4464 DRAM chips.  For simplicity, both the logic for the
//sprite line buffer and the sprite line buffer itself are internal to the 005885 implementation.

//Enable writing to sprite line buffer when bit 5 of the sprite width is 1
wire wre = sprite_width[5];

//Set sprite line buffer bank as bit 0 of the sprite vertical position
wire sprite_lbuff_bank = sprite_vpos[0];

//Sum sprite X position with the following bits of the sprite width to address the sprite line buffer based on sprite size:
//32 pixels wide: bits [4:0]
//16 pixels wide: bits [3:0]
//8 pixels wide: bits [2:0]
//XOR the upper bits for screen flipping on 16 pixel and 8 pixel wide sprites
reg [4:0] final_sprite_width;
always @(*) begin
	case(sprite_size)
		3'b000: final_sprite_width <= {sprite_width[4] ^ ~flipscreen, sprite_width[3:0]};
		3'b001: final_sprite_width <= {sprite_width[4] ^ ~flipscreen, sprite_width[3:0]};
		3'b010: final_sprite_width <= {sprite_width[4:3] ^ {2{~flipscreen}}, sprite_width[2:0]};
		3'b011: final_sprite_width <= {sprite_width[4:3] ^ {2{~flipscreen}}, sprite_width[2:0]};
		3'b100: final_sprite_width <= sprite_width[4:0];
		default: final_sprite_width <= sprite_width[4:0];
	endcase
end
wire [8:0] wpx = sprite_x + final_sprite_width;

//Generate sprite line buffer write addresses
reg [9:0] lbuff_A;
reg lbuff_we;
always_ff @(posedge CK49) begin
	lbuff_A <= {~sprite_lbuff_bank, wpx};
	lbuff_we <= wre;
end

//Latch sprite LUT PROM data on the falling edge of the main clock
reg [3:0] lbuff_Din;
always_ff @(negedge CK49) begin
	lbuff_Din <= OCD;
end

//Generate read address for sprite line buffer on the rising edge of the pixel clock (apply a -225 offset when the screen
//is flipped)
reg [9:0] radr0 = 10'd0;
reg [9:0] radr1 = 10'd1;
always_ff @(posedge CK49) begin
	if(cen_6m)
		radr0 <= {sprite_lbuff_bank, flipscreen ? sprite_hpos - 9'd225 : sprite_hpos};
end

//Sprite line buffer
wire [3:0] lbuff_Dout;
dpram_dc #(.widthad_a(10)) LBUFF
(
	.clock_a(CK49),
	.address_a(lbuff_A),
	.data_a({4'd0, lbuff_Din}),
	.wren_a(lbuff_we & (lbuff_Din != 0)),
	
	.clock_b(CK49),
	.address_b(radr0),
	.data_b(8'h0),
	.wren_b(radr0 == radr1),
	.q_b({4'bZZZZ, lbuff_Dout})
);

//Latch sprite data from the sprite line buffer
wire lbuff_read_en = (div[2:0] == 3'b100);
reg [3:0] lbuff_read = 4'd0;
always_ff @(posedge CK49) begin
	if(lbuff_read_en) begin
		if(radr0 != radr1)
			lbuff_read <= lbuff_Dout;
		radr1 <= radr0;
	end
end

//Delay sprite layer by 2 horizontal lines (1 line if a bootleg Jackal ROM set is loaded and the screen is flipped)
reg [7:0] sprite_dly = 8'd0;
always_ff @(posedge CK49) begin
	if(cen_6m) begin
		if(BTLG == 2'b01 && flipscreen)
			sprite_dly <= {4'd0, lbuff_read};
		else
			sprite_dly <= {lbuff_read, sprite_dly[7:4]};
	end
end
//Jackal bootlegs fail to render the last two vertical lines of the sprite layer - model this behavior here
wire [3:0] sprite_D = (BTLG == 2'b01 && ((h_cnt >= 244 && ~flipscreen) || (h_cnt >= 248 && flipscreen))) ? 4'd0 : sprite_dly[3:0];

//--------------------------------------------------------- Color mixer --------------------------------------------------------//

//Multiplex tile and sprite data, then output the final result
wire tile_sprite_sel = (tilemap_en | ~(|sprite_D));
wire [3:0] tile_sprite_D = tile_sprite_sel ? tilemap_D : sprite_D;

//Latch and output pixel data
reg [4:0] pixel_D;
always_ff @(posedge CK49) begin
	if(cen_6m)
		pixel_D <= {tile_sprite_sel, tile_sprite_D};
end
assign COL = (BTLG == 2'b01 && ((h_cnt >= 247 && ~flipscreen) || (h_cnt <= 14 && flipscreen))) ||
             (BTLG == 2'b10 && ((h_cnt <= 20 && ~flipscreen) || ((h_cnt <= 18 || h_cnt >= 251) && flipscreen))) ? 5'd0 : pixel_D;
//The above condition blacks out the last 4 lines on the right side of the screen (left when flipped) when a bootleg Jackal ROM set
//is loaded and blacks out the left-most 8 lines (7 when flipped plus an extra 2 lines on the right side) when a bootleg Iron Horse
//ROM set is loaded - this simulates the earlier-than-normal start of HBlank for Jackal bootlegs and later-than-normal end of
//HBlank for Iron Horse bootlegs while maintaining the usual 240x224 display area

endmodule
