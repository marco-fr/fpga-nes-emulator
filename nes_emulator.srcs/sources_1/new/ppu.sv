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

    // OAM
    input logic [7:0] oam_cpu_start_addr,
    input logic [8:0]oamdma_begin,
    input logic [7:0] oam_cpu_ram_data,
    output logic [12:0] oam_cpu_ram_addr,
    output logic [12:0] sprite_chr_rom_addr,
    input logic [7:0] sprite_chr_rom_data,
    
    output logic cpu_ready,

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
    
// OAM
logic [7:0] OAM_regs[256];
logic [7:0] oam_start_addr;
logic [8:0] oam_counter;
logic oam_bram_wait;
logic [8:0] oam_shifted_counter;
logic [7:0] dma_index;
logic oam_finished;

assign oam_shifted_counter = oam_counter - 9'b1;

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
//localparam CYCLES_PER_SCANLINE = 341;
localparam CYCLES_PER_SCANLINE = 200;
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

// Background Palette RAM (16 bytes)
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

// Always output current what register the CPU is looking at
always_comb begin
    cpu_data_out = regs[cpu_addr];
end

// CPU bus
always_ff @(posedge clk) begin
    if(reset) begin
        for (int i = 0; i < 8; i++) begin
            regs[i] <= 8'd0;
        end
        for (int j = 0; j < 256; j++) begin
            OAM_regs[j] <= 8'b1;
        end
        for (int i = 0; i < 32; i++) begin
            palette_ram[i] <= 8'd0;
        end
        regs[2] <= 8'b10000000;
        v <= 11'b0;
        w <= 1'b0;
        nmi_out <= 1'b1;
        scanline <= 0;
        cycle <= 0;
        oam_counter <= 9'b0;
        oam_cpu_ram_addr <= 13'b0;
        oam_finished <= 1'b0;
        oam_start_addr <= 8'b0;
    end else begin
            cpu_ready <= 1'b1;

            // NMI for VBlank
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
            
            // OAM
            if(oam_counter > 0 && oam_finished == 1'b0) begin
                // Pause CPU
                cpu_ready <= 1'b0;
                if(oam_counter == 257) begin
                    oam_finished <= 1'b1;
                end
                if(oam_bram_wait == 1'b0) begin
                    oam_cpu_ram_addr <= {oam_start_addr[4:0], oam_shifted_counter[7:0]};
                end else begin
                    OAM_regs[oam_shifted_counter[7:0]] <= oam_cpu_ram_data;
                    oam_counter <= oam_counter + 9'b1;
                end
                oam_bram_wait <= ~oam_bram_wait;
            end else begin
                oam_start_addr <= oam_cpu_start_addr;
                oam_counter <= oamdma_begin;
                oam_finished <= 1'b0;
                oam_bram_wait <= 1'b0;
            end
            
            // CPU Register IO 
            case(cpu_addr)
                3'h2: begin // PPU Status
                    // Set VBlank when read
                    regs[2] <= regs[2] & (8'b01111111); 
                end
                3'h4: begin // OAM Data
                    if(cpu_we) begin
                        OAM_regs[regs[3]] <= cpu_data_in;
                    end
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
                3'h6: begin // PPU Address
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
                        else if (t >= 15'h3F00 && t < 15'h4000) begin
                            if (t[4:0] == 5'h10 || t[4:0] == 5'h14 || 
                                t[4:0] == 5'h18 || t[4:0] == 5'h1C)
                                palette_ram[t[4:0] - 16] <= cpu_data_in;
                            else
                                palette_ram[t[4:0]] <= cpu_data_in;
                        end
                        t <= t + (increment ? 32 : 1);
                    end                    
                end
                default: begin
                    // Move out after testing
                    cpu_vram_we <= 1'b0;
                    if(cpu_we && cpu_addr != 2)
                        regs[cpu_addr] <= cpu_data_in;
                end
            endcase;
       
        
    end
end

// Rendering
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
logic [1:0] tile_attribute_bits;
logic [5:0] palette_addr;
assign palette_addr = palette_ram[{1'b0, tile_attribute_bits, pixel_bits}];

// Sprite 4-Byte Definition
typedef struct packed {
    logic [7:0] y;
    logic [7:0] tile;
    logic [7:0] attr;
    logic [7:0] x;
    logic [7:0] lsb;
    logic [7:0] msb;
} sprite_t;

sprite_t visible_sprites [8];
logic [7:0] sprite_y;
// Get first 8 visible sprites for current scanline
logic [3:0] sprite_count;

assign sprite_y = OAM_regs[(drawX - 256) * 4 + 0];

// Load Sprite CHR-ROM bytes during blanking period
logic [8:0] sprite_load_counter;
logic [7:0] sprite_name_table_byte;
logic [2:0] cur_sprite_load;
logic [2:0] cur_sprite_y_offset;

assign cur_sprite_load = sprite_load_counter[5:3];
assign cur_sprite_y_offset = drawY - visible_sprites[cur_sprite_load].y;

always_ff @(posedge clk_25MHz) begin
    if(reset) begin
        sprite_chr_rom_addr <= 13'b0;
        //cur_sprite_load <= 3'b0;
        sprite_name_table_byte <= 8'b0;
    end else begin
        if(drawX == 255)
            sprite_count <= 0;
        if(drawX >= 256 && drawX < 320) begin
            if (drawY >= sprite_y && drawY < sprite_y + 8 && sprite_count < 8) begin
                visible_sprites[sprite_count].y    <= sprite_y;
                visible_sprites[sprite_count].tile <= OAM_regs[(drawX - 256) * 4 + 1];
                visible_sprites[sprite_count].attr <= OAM_regs[(drawX - 256) * 4 + 2];
                visible_sprites[sprite_count].x    <= OAM_regs[(drawX - 256) * 4 + 3];
                sprite_count <= sprite_count + 1;
            end
        end
        if(drawX >= 320 && drawX < 384) begin
            case(sprite_load_counter[2:0])
                3'd2: begin                
                    sprite_name_table_byte <= visible_sprites[cur_sprite_load].tile;
                    sprite_chr_rom_addr <= {regs[0][3], visible_sprites[cur_sprite_load].tile, 1'b0, cur_sprite_y_offset};
                end
                3'd5: begin
                    visible_sprites[cur_sprite_load].lsb <= sprite_chr_rom_data;
                    sprite_chr_rom_addr <= {regs[0][3], sprite_name_table_byte, 1'b1, cur_sprite_y_offset};
                end
                3'd7: begin
                    visible_sprites[cur_sprite_load].msb <= sprite_chr_rom_data;
                end
                default;
            endcase
            sprite_load_counter <= sprite_load_counter + 9'b1;
        end else begin
            sprite_load_counter <= 9'b0;
        end
    end
end

// Compensate for rendering delay
logic [9:0] delayedX, delayedY;
always_comb begin
    delayedX = (drawX + 8);
    if(drawX >= 632)
        delayedX = drawX[2:0];
    delayedY = drawY;
    if(drawX + 8 >= 640) begin
        delayedY = (drawY + 1) % 480;
    end
end

// Background tiles
always_ff @(posedge clk_25MHz) begin
    if(reset) begin
        pixel_valid <= 0; // Might not be needed
        name_table_byte <= 0;
        
    end else begin
        // Resolution of 256x240, not all cycles are visible
        pixel_valid <= 0;

        case(cycle_offset)
            3'b0: begin // Load shift register 
                    vram_addr <= delayedX[9:3] + 32 * delayedY[9:3];
            end
            3'd2: begin                
                name_table_byte <= vram_data;
                chr_rom_addr <= {regs[0][4], vram_data, 1'b0, delayedY[2:0]};
                vram_addr <= 11'h3C0 + delayedY[9:5] * 8 + delayedX[9:5];
            end
            3'd4: begin
                attribute_table_byte <= vram_data;
            end
            3'd5: begin
                    tile_lsb <= chr_rom_data;
                    chr_rom_addr <= {regs[0][4], name_table_byte, 1'b1, delayedY[2:0]};
            end 
            3'd6: begin
                case ({delayedY[4], delayedX[4]})
                    2'b00: tile_attribute_bits <= attribute_table_byte[1:0]; // top-left
                    2'b01: tile_attribute_bits <= attribute_table_byte[3:2]; // top-right
                    2'b10: tile_attribute_bits <= attribute_table_byte[5:4]; // bottom-left
                    2'b11: tile_attribute_bits <= attribute_table_byte[7:6]; // bottom-right
                endcase
            end
            3'd7: begin
                tile_msb <= chr_rom_data;
                tile_shift_low <= tile_lsb;
                tile_shift_high <= chr_rom_data;
            end
            default;
        endcase
    end
end

// Pixel Rendering
logic found_sprite;
logic [23:0] sprite_pixel;
logic [2:0] sprite_offset;
logic [5:0] sprite_palette_addr;
always_comb begin
    found_sprite = 1'b0;
    for(int i = 0; i < sprite_count; i++) begin
        if(found_sprite == 1'b0) begin
            if(visible_sprites[i].x <= drawX && visible_sprites[i].x + 8 > drawX) begin
                found_sprite = 1'b1;
                sprite_offset = 7 - (drawX - visible_sprites[i].x);
                if(visible_sprites[i].attr[6])
                    sprite_offset = drawX - visible_sprites[i].x;
                sprite_palette_addr = palette_ram[{1'b1, visible_sprites[i].attr[1:0], 
                    visible_sprites[i].msb[sprite_offset], 
                    visible_sprites[i].lsb[sprite_offset]}];
                if({visible_sprites[i].msb[sprite_offset], visible_sprites[i].lsb[sprite_offset]} == 2'd0)
                    found_sprite = 1'b0;
            end
        end
    end

    if(drawX <= 255 && drawY < 240) begin
        pixel_color = get_palette_color(palette_addr);
        if(found_sprite == 1'b1)
            pixel_color = get_palette_color(sprite_palette_addr);
    end
    else
        pixel_color = 24'h0000FF;
end

// Fixed 64-color palette
function automatic logic [23:0] get_palette_color(input logic [5:0] color_index);
    case (color_index)
        6'h00: get_palette_color = 24'h7C7C7C;
        6'h01: get_palette_color = 24'h0000FC;
        6'h02: get_palette_color = 24'h0000BC;
        6'h03: get_palette_color = 24'h4428BC;
        6'h04: get_palette_color = 24'h940084;
        6'h05: get_palette_color = 24'hA80020;
        6'h06: get_palette_color = 24'hA81000;
        6'h07: get_palette_color = 24'h881400;
        6'h08: get_palette_color = 24'h503000;
        6'h09: get_palette_color = 24'h007800;
        6'h0A: get_palette_color = 24'h006800;
        6'h0B: get_palette_color = 24'h005800;
        6'h0C: get_palette_color = 24'h004058;
        6'h0D: get_palette_color = 24'h000000;
        6'h0E: get_palette_color = 24'h000000;
        6'h0F: get_palette_color = 24'h000000;

        6'h10: get_palette_color = 24'hBCBCBC;
        6'h11: get_palette_color = 24'h0078F8;
        6'h12: get_palette_color = 24'h0058F8;
        6'h13: get_palette_color = 24'h6844FC;
        6'h14: get_palette_color = 24'hD800CC;
        6'h15: get_palette_color = 24'hE40058;
        6'h16: get_palette_color = 24'hF83800;
        6'h17: get_palette_color = 24'hE45C10;
        6'h18: get_palette_color = 24'hAC7C00;
        6'h19: get_palette_color = 24'h00B800;
        6'h1A: get_palette_color = 24'h00A800;
        6'h1B: get_palette_color = 24'h00A844;
        6'h1C: get_palette_color = 24'h008888;
        6'h1D: get_palette_color = 24'h000000;
        6'h1E: get_palette_color = 24'h000000;
        6'h1F: get_palette_color = 24'h000000;

        6'h20: get_palette_color = 24'hF8F8F8;
        6'h21: get_palette_color = 24'h3CBCFC;
        6'h22: get_palette_color = 24'h6888FC;
        6'h23: get_palette_color = 24'h9878F8;
        6'h24: get_palette_color = 24'hF878F8;
        6'h25: get_palette_color = 24'hF85898;
        6'h26: get_palette_color = 24'hF87858;
        6'h27: get_palette_color = 24'hFCA044;
        6'h28: get_palette_color = 24'hF8B800;
        6'h29: get_palette_color = 24'hB8F818;
        6'h2A: get_palette_color = 24'h58D854;
        6'h2B: get_palette_color = 24'h58F898;
        6'h2C: get_palette_color = 24'h00E8D8;
        6'h2D: get_palette_color = 24'h787878;
        6'h2E: get_palette_color = 24'h000000;
        6'h2F: get_palette_color = 24'h000000;

        6'h30: get_palette_color = 24'hFCFCFC;
        6'h31: get_palette_color = 24'hA4E4FC;
        6'h32: get_palette_color = 24'hB8B8F8;
        6'h33: get_palette_color = 24'hD8B8F8;
        6'h34: get_palette_color = 24'hF8B8F8;
        6'h35: get_palette_color = 24'hF8A4C0;
        6'h36: get_palette_color = 24'hF0D0B0;
        6'h37: get_palette_color = 24'hFCE0A8;
        6'h38: get_palette_color = 24'hF8D878;
        6'h39: get_palette_color = 24'hD8F878;
        6'h3A: get_palette_color = 24'hB8F8B8;
        6'h3B: get_palette_color = 24'hB8F8D8;
        6'h3C: get_palette_color = 24'h00FCFC;
        6'h3D: get_palette_color = 24'hF8D8F8;
        6'h3E: get_palette_color = 24'h000000;
        6'h3F: get_palette_color = 24'h000000;

        default: get_palette_color = 24'h000000;
    endcase
endfunction



endmodule