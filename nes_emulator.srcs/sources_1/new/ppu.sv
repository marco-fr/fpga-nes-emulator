`timescale 1ns / 1ps

module ppu(
    input  logic        clk,
    input  logic        reset,

    // CPU bus interface
    input  logic        cpu_we,
    input  logic [2:0]  cpu_addr,        // $2000-$2007
    input  logic [7:0]  cpu_data_in,
    output logic [7:0]  cpu_data_out,
    output logic [10:0] cpu_mirror_vram_addr,
    output logic [7:0] cpu_vram_datain,
    input logic [7:0]  cpu_vram_doutb,
    output logic cpu_vram_we,
    output logic nmi_out,

    // OAM
    input logic [7:0] oam_cpu_start_addr,
    input logic [8:0]oamdma_begin,
    input logic [7:0] oam_cpu_ram_data,
    output logic [12:0] oam_cpu_ram_addr,
    output logic [12:0] cpu_chr_rom_addr,
    input logic [7:0] cpu_chr_rom_data,
    
    output logic cpu_ready,

    output logic [23:0]  pixel_color,

    // Connections to external memory
    input  logic [7:0]  chr_rom_data,
    output logic [12:0] chr_rom_addr,

    input  logic [7:0]  vram_data,
    output logic [10:0] vram_mirror_addr,
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
logic vblank;

logic hdmi_reset;
assign hdmi_reset = reset;

vga_controller vga (
        .pixel_clk(clk_25MHz),
        .reset(hdmi_reset),
        .hs(hsync),
        .vs(vsync),
        .active_nblank(vde),
        .vblank(vblank),
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
//assign name_addr = 2'd0;
logic [11:0] cpu_vram_addr, vram_addr;

// VRAM/CHR-ROM access
logic [7:0] name_table_byte, attribute_table_byte, tile_lsb, tile_msb;
logic [1:0] palette_index;
logic [3:0] final_color_index;
logic [5:0] pixel_x;

// PPU address and scrolling registers
logic [14:0] v; 
logic [14:0] t; 
logic [7:0] tmp_t;
logic [2:0]  fine_x; // Fine X scroll
logic [2:0]  fine_y; // Fine Y scroll
logic [4:0]  scroll_x; // X scroll
logic [4:0]  scroll_y; // Y scroll
logic [7:0]  total_scroll_x; // X scroll
logic [7:0]  total_scroll_y; // Y scroll
logic        w; // Write toggle
logic [7:0]  tile_shift_low, tile_shift_high;

// Background Palette RAM (16 bytes)
logic [7:0] palette_ram [0:31];

logic sprite_collision;
logic [8:0] col_x, col_y;

logic [9:0] scaled_drawX;
logic [9:0] scaled_drawY;

//logic [9:0] drawX_shift;
logic [9:0] drawY_shift;

always_comb begin
    scaled_drawX = {1'b0, drawX[9:1]};
    drawY_shift = drawY + 1;
        //scaled_drawX = {1'b0, drawX_shift[9:1]};
    scaled_drawY = {1'b0, drawY[9:1]};
    if(scaled_drawX + fine_x + 8 >= 400)
        scaled_drawY = {1'b0, drawY_shift[9:1]};
end

always_comb begin
    cpu_data_out = regs[cpu_addr];
    if(cpu_addr == 3'd7) begin
        if(v < 15'h2000)
            cpu_data_out = cpu_chr_rom_data;
        else if (v < 15'h3000)
            cpu_data_out = cpu_vram_doutb;
    end
        
    scroll_x = t[4:0];
    scroll_y = t[9:5];
    fine_y = t[14:12];
    name_addr = t[11:10];
end

logic vblank_prev;
logic sprite_col_prev;

// Mirroring
always_comb begin
    vram_mirror_addr = vram_addr[10:0];
    cpu_mirror_vram_addr = cpu_vram_addr[10:0];
end

//logic [26:0] test_counter;
logic ppu_data_started_read;
logic [7:0] ppu_data_out_buffer;
logic [7:0] ppu_data_final_out;
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
        regs[2] <= 8'b11000000;
        v <= 11'b0;
        w <= 1'b0;
        oam_counter <= 9'b0;
        oam_cpu_ram_addr <= 13'b0;
        oam_finished <= 1'b0;
        oam_start_addr <= 8'b0;
        ppu_data_final_out <= 8'b0;
        tmp_t <= 8'b0;
    end else begin
            cpu_ready <= 1'b1;
            cpu_vram_we <= 1'b0;
            ppu_data_started_read <= 1'b0;
            vblank_prev <= vblank;
            sprite_col_prev <= sprite_collision;

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
            //scroll_x <= 5'd10;
            // CPU Register IO 
            case(cpu_addr)
                3'h0: begin // PPU Control
                    if(cpu_we) begin
                        regs[cpu_addr] <= cpu_data_in;
                        t[11:10] <= cpu_data_in[1:0];
                    end
                end
                3'h2: begin // PPU Status
                    // Set VBlank when read
                    regs[2][7] <= 1'b0;
                    w <= 0;
                end
                3'h4: begin // OAM Data
                    if(cpu_we) begin
                        OAM_regs[regs[3]] <= cpu_data_in;
                    end
                end
                3'h5: begin // PPU Scrolling
                    if(cpu_we) begin
                        // Y-scroll
                        if(w) begin
                            //total_scroll_y <= cpu_data_in;
                            t[14:12] <= cpu_data_in[2:0];
                            t[9:5] <= cpu_data_in[7:3];
                            w <= 0;
                        // X-scroll
                        end else begin
                            //total_scroll_x <= cpu_data_in;
                            t[4:0] <= cpu_data_in[7:3];
                            fine_x <= cpu_data_in[2:0];
                            w <= 1;
                        end
                    end
                end
                3'h6: begin // PPU Address
                    if(cpu_we) begin
                        if(!w) begin
                            // High byte-ish
                            t[13:8] <= cpu_data_in[5:0];
                            t[14] <= 1'b0;
                            w <= 1;
                        end else begin
                            // Low byte
                            t[7:0] <= cpu_data_in[7:0];
                            v <= {t[14:8], cpu_data_in[7:0]};
                            w <= 0;
                        end
                    end
                end
                3'h7: begin // PPU Data
                    if (v >= 15'h2000 && v < 15'h3000) begin
                        cpu_vram_addr <= v[11:0];
                        if(cpu_we)  begin
                            cpu_vram_we <= 1'b1;
                            cpu_vram_datain <= cpu_data_in;
                        end
                        else
                            ppu_data_started_read = 1'b1;
                    end
                    else if (v >= 15'h3F00 && v < 15'h4000) begin
                        if(cpu_we)  begin
                            if (v[4:0] == 5'h10 || v[4:0] == 5'h14 || 
                                v[4:0] == 5'h18 || v[4:0] == 5'h1C)
                                palette_ram[v[4:0] - 16] <= cpu_data_in;
                            else
                                palette_ram[v[4:0]] <= cpu_data_in;
                        end else begin
                            if (v[4:0] == 5'h10 || v[4:0] == 5'h14 || 
                                v[4:0] == 5'h18 || v[4:0] == 5'h1C)
                                regs[7] <= palette_ram[v[4:0] - 16];
                            else
                                regs[7] <= palette_ram[v[4:0]];
                        end
                    end
                    if(~cpu_we && v < 15'h2000) begin
                        cpu_chr_rom_addr <= v[12:0];
                    end
                    v <= v + (increment ? 32 : 1);
                end
                default: begin
                    if(cpu_we && cpu_addr != 2)
                        regs[cpu_addr] <= cpu_data_in;
                end
            endcase;
       
            if (vblank && ~vblank_prev) begin
                regs[2][7] <= 1'b1;
            end
            else if(~vblank || cpu_addr == 3'd2)begin
                regs[2][7] <= 1'b0;
            end
            
            // Sprite 0 Collision Status Flip
            if(sprite_collision && ~sprite_col_prev)
                regs[2][6] <= 1'b1;
            else if(~sprite_collision)
                regs[2][6] <= 1'b0;

    end
    
end

// Rendering
logic [2:0] cycle_offset;
assign cycle_offset = (delayedX) % 8;

logic [2:0] total_cycle_offset;
assign total_cycle_offset = (delayedX) % 8;

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

always_comb begin
    palette_addr = palette_ram[{1'b0, tile_attribute_bits, pixel_bits}];
    if(pixel_bits == 2'b0) begin
        palette_addr = palette_ram[{1'b0, 2'b0, pixel_bits}];
    end
end

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

assign sprite_y = OAM_regs[(drawX - 512) * 4 + 0];

// Load Sprite CHR-ROM bytes during blanking period
logic [8:0] sprite_load_counter;
logic [7:0] sprite_name_table_byte;
logic [2:0] cur_sprite_load;
logic [2:0] cur_sprite_y_offset;

assign cur_sprite_load = sprite_load_counter[5:3];

// Compensate for rendering delay
logic [9:0] delayedX, delayedY;
logic [9:0] tmpX, tmpY;
always_comb begin
    //tmpX = ((drawX + 16) + fine_x * 2) % 800;
    //delayedX = {1'b0, tmpX[9:1]};
    delayedX = (scaled_drawX + fine_x + 8) % 400;

    // May not work

    delayedY = scaled_drawY + fine_y;
    //if(scaled_drawX + fine_x + 8 > 255) begin
        //delayedY = (scaled_drawY + fine_y + 1) % 262;
    //end
end

// Compensate for scrolling in attribute table
logic [9:0] attr_x = scroll_x + delayedX[9:3];
logic [9:0] attr_y = scroll_y + delayedY[9:3];

// Sprite 0 Detection
logic sprite_0_in_scanline;
logic sprite_0_overlap;
logic sprite_0_done;

// Sprite Vertical Flip
always_comb begin
    cur_sprite_y_offset = scaled_drawY - visible_sprites[cur_sprite_load].y;
    if(visible_sprites[cur_sprite_load].attr[7])
        cur_sprite_y_offset = 7 - (scaled_drawY - visible_sprites[cur_sprite_load].y);
end

// Background tiles
always_ff @(posedge clk_25MHz) begin
    if(reset) begin
        name_table_byte <= 0;
        sprite_collision <= 0;
        //sprite_chr_rom_addr <= 13'b0;
        sprite_name_table_byte <= 8'b0;
        
    end else begin
        // Sprite 0 Collision
        //if(sprite_0_in_scanline) begin
            //// Currently drawing on screen + collision + first time this frame
            //if(scaled_drawX >= 0 && scaled_drawX < 256 && sprite_0_overlap && ~sprite_0_done && drawY[0]) begin
                //sprite_collision <= 1'b1;
                //sprite_0_done <= 1;
            //end
        //end

        // Hardcoded Sprite 0 for SMB
        // Collision breaks with scaled video for some reason
        if(scaled_drawX == 200 && scaled_drawY == 30 && drawY[0]) begin
            sprite_collision <= 1'b1;
        end

        // Turn off Sprite 0 Hit during VBlank
        // Exact number doesn't seem to matter
        if(drawY == 520) begin
            sprite_collision <= 1'b0;
            sprite_0_done <= 0;
        end

        // Sprite Logic
        nmi_out <= 1'b1;
        if(nmi) begin
            // Enter VBlank at scanline 241
            if (vblank) begin
                nmi_out <= 1'b0;
            end
        end

        // Reset sprite count
        if(drawX == 511) begin
            sprite_count <= 0;
            sprite_0_in_scanline <= 0;
        end

        // Get first 8 visible sprites on scanline
        if(drawX >= 512 && drawX < 576) begin
            if (scaled_drawY >= sprite_y && scaled_drawY < sprite_y + 8 && sprite_count < 8) begin
                visible_sprites[sprite_count].y    <= sprite_y;
                visible_sprites[sprite_count].tile <= OAM_regs[(drawX - 512) * 4 + 1];
                visible_sprites[sprite_count].attr <= OAM_regs[(drawX - 512) * 4 + 2];
                visible_sprites[sprite_count].x    <= OAM_regs[(drawX - 512) * 4 + 3];
                sprite_count <= sprite_count + 1;

                // Implies Sprite 0 is on the current line
                if(drawX == 512) begin
                    sprite_0_in_scanline <= 1;
                end
            end
        end
        
        // Load CHR-ROM for each sprite
        if(drawX >= 600 && drawX < 664) begin
            case(sprite_load_counter[2:0])
                3'd2: begin                
                    sprite_name_table_byte <= visible_sprites[cur_sprite_load].tile;
                    chr_rom_addr <= {regs[0][3], visible_sprites[cur_sprite_load].tile, 1'b0, cur_sprite_y_offset};
                end
                3'd5: begin
                    visible_sprites[cur_sprite_load].lsb <= chr_rom_data;
                    chr_rom_addr <= {regs[0][3], sprite_name_table_byte, 1'b1, cur_sprite_y_offset};
                end
                3'd7: begin
                    visible_sprites[cur_sprite_load].msb <= chr_rom_data;
                end
                default;
            endcase
            sprite_load_counter <= sprite_load_counter + 9'b1;
        end else begin
            sprite_load_counter <= 9'b0;

            // Background rendering
            if(drawX[0]) begin
                case(total_cycle_offset)
                    3'b0: begin // Load shift register 
                            vram_addr <= (delayedX[9:3] + 32 * delayedY[9:3] + name_addr * 11'h400 + scroll_x + 32 * scroll_y) % 2048;
                            if(delayedX[9:3] + scroll_x >= 32)
                                vram_addr <= ((delayedX[9:3] + scroll_x) % 32 + 32 * delayedY[9:3] + (name_addr + 1) * 11'h400 + 32 * scroll_y) % 2048;
                    end
                    3'd2: begin                
                        name_table_byte <= vram_data;
                        chr_rom_addr <= {regs[0][4], vram_data, 1'b0, delayedY[2:0]};
                        vram_addr <= 11'h3C0 + vram_addr[11:10] * 11'h400 + {vram_addr[9:7], vram_addr[4:2]};
                    end
                    3'd4: begin
                        attribute_table_byte <= vram_data;
                    end
                    3'd5: begin
                        tile_lsb <= chr_rom_data;
                        chr_rom_addr <= {regs[0][4], name_table_byte, 1'b1, delayedY[2:0]};
                    end 
                    3'd7: begin
                        case ({attr_y[1], attr_x[1]})
                            2'b00: tile_attribute_bits <= attribute_table_byte[1:0]; // top-left
                            2'b01: tile_attribute_bits <= attribute_table_byte[3:2]; // top-right
                            2'b10: tile_attribute_bits <= attribute_table_byte[5:4]; // bottom-left
                            2'b11: tile_attribute_bits <= attribute_table_byte[7:6]; // bottom-right
                        endcase
                        tile_msb <= chr_rom_data;
                        tile_shift_low <= tile_lsb;
                        tile_shift_high <= chr_rom_data;
                    end
                    default;
                endcase
            end
        end

    end
end

// Pixel Rendering
logic found_sprite;
logic [23:0] sprite_pixel;
logic [2:0] sprite_offset;
logic [5:0] sprite_palette_addr;
always_comb begin
    found_sprite = 1'b0;
    sprite_palette_addr = 6'b0;
    sprite_0_overlap = 0;
    // Check the 8 sprites if they need to be rendered.
    for(int i = 0; i < sprite_count; i++) begin
        if(found_sprite == 1'b0) begin
            if(visible_sprites[i].x <= scaled_drawX && visible_sprites[i].x + 8 > scaled_drawX) begin
                found_sprite = 1'b1;

                sprite_offset = 7 - (scaled_drawX - visible_sprites[i].x);
                // Horizontal flip
                if(visible_sprites[i].attr[6])
                    sprite_offset = scaled_drawX - visible_sprites[i].x;
                
                // Fetch palette ram
                sprite_palette_addr = palette_ram[{1'b1, visible_sprites[i].attr[1:0], 
                    visible_sprites[i].msb[sprite_offset], 
                    visible_sprites[i].lsb[sprite_offset]}];

                // Background has priority or sprite is transparent
                if({visible_sprites[i].msb[sprite_offset], visible_sprites[i].lsb[sprite_offset]} == 2'd0 ||
                    (pixel_bits != 2'b0 && visible_sprites[i].attr[5]))
                    found_sprite = 1'b0;

                // Detect Sprite 0 Hit
                if(i == 0 && sprite_0_in_scanline &&
                    {visible_sprites[i].msb[sprite_offset], visible_sprites[i].lsb[sprite_offset]} != 2'd0 &&
                    pixel_bits != 2'd0
                ) begin
                    sprite_0_overlap = 1;
                end
            end
        end
    end

    // 256 x 240 Resolution
    if(scaled_drawX <= 255 && scaled_drawY < 240) begin
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