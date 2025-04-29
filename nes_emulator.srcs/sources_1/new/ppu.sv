`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/18/2025 05:46:15 PM
// Design Name: 
// Module Name: ppu
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module ppu(
    input  logic        clk,
    input  logic        reset,

    // CPU bus interface
    input  logic        cpu_we,
    input  logic [2:0]  cpu_addr,        // $2000-$2007
    input  logic [7:0]  cpu_data_in,
    output logic [7:0]  cpu_data_out,
    output logic [12:0] cpu_vram_addr,
    output logic [7:0] cpu_vram_datain,
    output logic cpu_vram_we,
    output logic nmi_out,

    output logic [23:0]  pixel_color,
    output logic        pixel_valid,

    // Connections to external memory
    input  logic [7:0]  chr_rom_data,
    output logic [12:0] chr_rom_addr,

    input  logic [7:0]  vram_data,
    output logic [10:0] vram_addr,
    //output logic        vram_read
    
    
    output logic hdmi_tmds_clk_n,
    output logic hdmi_tmds_clk_p,
    output logic [2:0]hdmi_tmds_data_n,
    output logic [2:0]hdmi_tmds_data_p,

    input logic clk_25MHz,
    input logic clk_125MHz,
    input logic locked
    
    );
    // get rid of this
logic vram_read;
// VGA logic
logic [9:0] drawX, drawY;
logic vsync, hsync;
logic vde;

logic hdmi_reset;
assign hdmi_reset = reset;

vga_controller vga (
        .pixel_clk(clk_25MHz),
        .reset(hdmi_reset),
        .hs(hsync),
        .vs(vsync),
        .active_nblank(vde),
        .drawX(drawX),
        .drawY(drawY)
); 

hdmi_tx_0 vga_to_hdmi (
        //Clocking and Reset
        .pix_clk(clk_25MHz),
        .pix_clkx5(clk_125MHz),
        .pix_clk_locked(locked),
        //Reset is active LOW
        .rst(hdmi_reset),
        //Color and Sync Signals
        .red(pixel_color[23:16]),
        .green(pixel_color[15:8]),
        .blue(pixel_color[7:0]),
        .hsync(hsync),
        .vsync(vsync),
        .vde(vde),
        
        //aux Data (unused)
        .aux0_din(4'b0),
        .aux1_din(4'b0),
        .aux2_din(4'b0),
        .ade(1'b0),
        
        //Differential outputs
        .TMDS_CLK_P(hdmi_tmds_clk_p),          
        .TMDS_CLK_N(hdmi_tmds_clk_n),          
        .TMDS_DATA_P(hdmi_tmds_data_p),         
        .TMDS_DATA_N(hdmi_tmds_data_n)          
    );

// CPU visible registers
logic [7:0] regs [8];

// PPU Control
logic nmi, sprite_size, pattern_addr, increment, sprite_pattern_addr;
logic [1:0] name_addr;
assign nmi = regs[0][7];
assign sprite_size = regs[0][5];
assign pattern_addr = regs[0][4];
assign sprite_pattern_addr = regs[0][3];
assign increment = regs[0][2];
assign name_addr = regs[0][1:0];

// VRAM/CHR-ROM access
localparam TOTAL_SCANLINES = 262;
localparam CYCLES_PER_SCANLINE = 341;
logic [15:0] scanline;
logic [15:0] cycle;
logic [7:0] name_table_byte, attribute_table_byte, tile_lsb, tile_msb;
logic [1:0] palette_index;
logic [3:0] final_color_index;
logic [5:0] pixel_x;

// PPU address and scrolling registers
logic [14:0] v; // Current VRAM address (15 bits)
logic [14:0] t; // Temporary VRAM address (15 bits)
logic [2:0]  x; // Fine X scroll
logic        w; // Write toggle
logic [7:0]  tile_shift_low, tile_shift_high;

// Palette RAM (32 bytes)
logic [7:0] palette_ram [0:31];

// NES palette: 6-bit RGB values from palette index (converted to 24-bit RGB)
function automatic [23:0] get_rgb(input [7:0] palette_val);
    case (palette_val)
        8'h00: get_rgb = 24'h000000;
        8'h01: get_rgb = 24'h555555;
        8'h02: get_rgb = 24'hAAAAAA;
        8'h03: get_rgb = 24'hFFFFFF;
        8'h04: get_rgb = 24'h5C007E;
        8'h05: get_rgb = 24'h6E0040;
        8'h06: get_rgb = 24'h6C0700;
        8'h07: get_rgb = 24'h561D00;
        8'h08: get_rgb = 24'h333500;
        8'h09: get_rgb = 24'h0B4800;
        8'h0A: get_rgb = 24'h005200;
        8'h0B: get_rgb = 24'h004F08;
        8'h0C: get_rgb = 24'h00404D;
        8'h0D: get_rgb = 24'h000000;
        default: get_rgb = 24'h000000;
    endcase
endfunction

always_comb begin
    cpu_data_out = regs[cpu_addr];
end

// CPU bus
always_ff @(posedge clk) begin
    if(reset) begin
        for (int i = 0; i < 8; i++) begin
            regs[i] <= 8'd0;
        end
        regs[2] <= 8'b10000000;
        v <= 11'b0;
        w <= 1'b0;
        nmi_out <= 1'b1;
        scanline <= 0;
            cycle <= 0;
    end else begin
            if (cycle == CYCLES_PER_SCANLINE - 1) begin
                cycle <= 0;
                if (scanline == TOTAL_SCANLINES - 1)
                    scanline <= 0;
                else
                    scanline <= scanline + 1;
            end else begin
                cycle <= cycle + 1;
            end
            if(nmi) begin
                // Enter VBlank at scanline 241
                if (scanline == 241 && cycle == 1)
                    nmi_out <= 1'b0;
    
                // Leave VBlank at scanline 261
                if (scanline == 261 && cycle == 1)
                    nmi_out <= 1'b1;
            end
                
            case(cpu_addr)
                3'h2: begin // PPP Status
                    regs[2] <= regs[2] & (8'b01111111); 
                end
                3'h5: begin // PPU Scrolling
                    // Y-scroll
                    if(w) begin
                        t[9:5] <= cpu_data_in[7:3];
                        // Tile is 8 tall
                        t[14:12] <= cpu_data_in[2:0];
                        w <= 0;
                    end else begin
                        //scroll_x <= cpu_data_in[2:0];
                        t[4:0] <= cpu_data_in[7:3];
                        w <= 1;
                    end
                end
                3'h6: begin // PPUADDR
                    if(cpu_we) begin
                        if(!w) begin
                            // High byte-ish
                            t[14:8] <= cpu_data_in[6:0];
                            w <= 1;
                        end else begin
                            // Low byte
                            t[7:0] <= cpu_data_in[7:0];
                            //v <= t;
                            w <= 0;
                        end
                    end
                end
                3'h7: begin // PPU Data
                    if(cpu_we)  begin
                        if (t >= 15'h2000 && t < 15'h3000) begin
                            cpu_vram_addr <= t[10:0];
                            cpu_vram_we <= 1'b1;
                            cpu_vram_datain <= cpu_data_in;
                        end 
                        //else if (v >= 16'h3F00 && v <= 16'h3F1F) begin
                        //    palette_ram[v[4:0]] <= cpu_data_in;
                        //end
                        t <= t + (increment ? 32 : 1);
                    end                    
                end
                default: begin
                    cpu_vram_we <= 1'b0;
                    if(cpu_we && cpu_addr != 2)
                        regs[cpu_addr] <= cpu_data_in;
                end
            endcase;
       
        
    end
end

// 
logic [2:0] cycle_offset;
assign cycle_offset = drawX % 8;

logic [2:0] bit_index;
assign bit_index = 7 - cycle_offset;
logic pixel_low;
assign pixel_low = tile_shift_low[bit_index];
logic pixel_high;
assign pixel_high = tile_shift_high[bit_index];
logic [1:0] pixel_bits;
assign pixel_bits = {pixel_high, pixel_low};
logic [1:0] palette_latch;
assign palette_latch = 2'b0;
logic [4:0] palette_addr;
assign palette_addr = {1'b0, palette_latch, pixel_bits};

// Pixel rendering USES 25 MHZ
always_ff @(posedge clk_25MHz) begin
    if(reset) begin
        pixel_color <= 24'h00FFFF;
        pixel_valid <= 0; // Might not be needed
        name_table_byte <= 0;
    end else begin
        
        // Rendering
        // Resolution of 256x240, not all cycles are visible
        pixel_valid <= 0;
            case(cycle_offset)
                3'b0: begin // Load shift register 
                      vram_addr <= drawX[9:3] + 32 * drawY[9:3];
                end
                3'b1: begin // Read from Nametable/VRAM
                end
                3'd2: begin
                    
                    name_table_byte <= vram_data;
                    chr_rom_addr <= {regs[0][4], vram_data, 1'b0, drawY[2:0]};
                    //$display(vram_data);
                    vram_addr <= vram_addr + 10'h3C0;
                end
                3'd3: begin
                    attribute_table_byte <= vram_data;
                end
                3'd5: begin
                     tile_lsb <= chr_rom_data;
                     chr_rom_addr <= {regs[0][4], name_table_byte, 1'b1, drawY[2:0]};
                    
                end
                3'd7: begin
                    tile_msb <= chr_rom_data;
                    tile_shift_low <= tile_lsb;
                    tile_shift_high <= chr_rom_data;
                    
                end
                default;
            endcase
            if(drawX == 120 && drawY == 5)
                $display("%h", tile_msb);
            //pixel_color <= get_rgb(palette_ram[palette_addr]);
            if(drawX <= 255 && drawY < 240)
                pixel_color <= get_rgb(palette_addr);
            else
                pixel_color <= 24'h0000FF;
            pixel_valid <= 1;
    end
end


endmodule
