`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/24/2025 01:10:49 AM
// Design Name: 
// Module Name: nes_top
// Project Name:9
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


module nes_top(
    input logic Clk,
    input logic reset_rtl_0,

    //USB signals
    input logic [0:0] gpio_usb_int_tri_i,
    output logic gpio_usb_rst_tri_o,
    input logic usb_spi_miso,
    output logic usb_spi_mosi,
    output logic usb_spi_sclk,
    output logic usb_spi_ss,

    //UART
    input logic uart_rtl_0_rxd,
    output logic uart_rtl_0_txd,
    
    //HDMI
    output logic hdmi_tmds_clk_n,
    output logic hdmi_tmds_clk_p,
    output logic [2:0]hdmi_tmds_data_n,
    output logic [2:0]hdmi_tmds_data_p,
    
    //HEX displays
    output logic [7:0] hex_segA,
    output logic [3:0] hex_gridA,
    output logic [7:0] hex_segB,
    output logic [3:0] hex_gridB
    );
    //assign uart_rtl_0_txd = 1'b1;
    logic clk_reset = 0;
    
    // Microblaze Block Design Ports
    logic [31:0] keycode0_gpio, keycode1_gpio;
    
    // USB Input
    logic [7:0] controller_byte;
    logic [7:0] cur_keycode[4];
    logic [7:0] cpu_controller_byte;
    logic [7:0] latched_controller;
    assign cur_keycode[0] = keycode0_gpio[7:0];
    assign cur_keycode[1] = keycode0_gpio[15:8];
    assign cur_keycode[2] = keycode0_gpio[23:16];
    assign cur_keycode[3] = keycode0_gpio[31:24];

    
    
    //Keycode HEX drivers
    hex_driver HexA (
        .clk(Clk),
        .reset(reset_ah),
        .in({controller_byte[7:4], controller_byte[3:0], keycode0_gpio[23:20], keycode0_gpio[19:16]}),
        .hex_seg(hex_segA),
        .hex_grid(hex_gridA)
    );
    
    hex_driver HexB (
        .clk(Clk),
        .reset(reset_ah),
        .in({keycode0_gpio[15:12], keycode0_gpio[11:8], keycode0_gpio[7:4], keycode0_gpio[3:0]}),
        .hex_seg(hex_segB),
        .hex_grid(hex_gridB)
    );

    // Microblaze for USB
    mb_usb mb (
        .clk_100MHz(Clk),
        .gpio_usb_int_tri_i(gpio_usb_int_tri_i),
        .gpio_usb_keycode_0_tri_o(keycode0_gpio),
        .gpio_usb_keycode_1_tri_o(keycode1_gpio),
        .gpio_usb_rst_tri_o(gpio_usb_rst_tri_o),
        .reset_rtl_0(~reset_rtl_0), //Block designs expect active low reset, all other modules are active high
        .uart_rtl_0_rxd(uart_rtl_0_rxd),
        .uart_rtl_0_txd(uart_rtl_0_txd),
        .usb_spi_miso(usb_spi_miso),
        .usb_spi_mosi(usb_spi_mosi),
        .usb_spi_sclk(usb_spi_sclk),
        .usb_spi_ss(usb_spi_ss)
    );
    
    
    
    // VRAM BRAM Configuration
    logic [12:0] vram_addr;
    logic [7:0] vram_data;
    logic [7:0] vram_dina;
    assign vram_dina = 0;
    
    
    // PPU CPU IO
    logic cpu_we;
    logic cpu_vram_we;
    logic [7:0]  cpu_data_in;
    logic [7:0]  cpu_data_out;
    logic [7:0]  cpu_doutb;
    logic [12:0]  cpu_vram_addr;
    logic [7:0] cpu_vram_datain;

    // OAM
    logic [7:0] oam_cpu_start_addr;
    logic [7:0] oam_cpu_ram_data;
    logic [12:0] oam_cpu_ram_addr;
    logic [8:0] oamdma_begin;
    
    // CPU Configuration
    logic [15:0] AB;
    logic [7:0] DI;      
    logic [7:0] DO;
    logic WE_inv;     
    logic WE;           
    logic IRQ;           
    logic NMI;           
    logic RDY;        

    assign IRQ = 1'b1;   
    assign WE = ~WE_inv;
    
    T65 c(
        .mode   (2'b0),		// 6502 mode
        .BCD_en (1'b0),
        
        .clk    (clk_1_66mhz),		// clock
    
        .res_n  (~reset),		// cpu reset 
        .enable (1'b1),	// enable (cpu doesnt continue unless this is high)
        .rdy    (RDY),		// ready (cpu doesnt continue with some extra steps)
    
        .IRQ_n  (IRQ),
        .NMI_n  (NMI),
        
        .R_W_n  (WE_inv),	// read = 1, write = 0
        .A      (AB),	// address in DRAM
        .DI     (DI),	// data in
        .DO     (DO)	// data out
    );
    
    // PRG-ROM BRAM Configuration
    logic [14:0] prg_rom_addr;
    logic [7:0] prg_rom_data;
    logic [7:0] prg_rom_dina;
    logic [7:0] prg_rom_doutb;


    // Clocks and Reset
    logic clk_25MHz, clk_125MHz, clk_1_66mhz;
    logic locked;
    logic reset;

    assign reset = reset_rtl_0;
    
    //logic tmp;
    
    clk_wiz_0 clk_wiz (
        .clk_out1(clk_25MHz),
        .clk_out2(clk_125MHz),
        //.clk_out3(tmp),
        .clk_out3(clk_1_66mhz),
        .reset(reset),
        .locked(locked),
        .clk_in1(Clk)
    );
    //assign clk_1_66mhz = clk_25MHz;
    
//    nes_clock_gen nes_clock(
//        .clk_100mhz(Clk),
//        .reset(reset),
//        .clk_1_66mhz(clk_1_66mhz)
//    );
    
    // PPU Configuration
    logic        clk;
    
    // PPU uses same CPU clock for IO
    // Rendering is done at 25MHz for VGA
    assign clk = clk_1_66mhz;
    
    logic [23:0]  pixel_color;
    logic        pixel_valid;
    logic [2:0]  cpu_addr;

    ppu p(
        .nmi_out(NMI),
        .cpu_ready(RDY),
        .*
    );
    
    
    
    always_ff @(posedge clk_1_66mhz) begin
        controller_byte <= 8'b0;
        for(int i = 0; i < 4; i++) begin
            case (cur_keycode[i])
                8'h1C: controller_byte[0] <= 1'b1; // A: 'Y' key
                8'h0B: controller_byte[1] <= 1'b1; // B: 'H' key
                8'h06: controller_byte[2] <= 1'b1; // Select: 'C'
                8'h19: controller_byte[3] <= 1'b1; // Start: 'V'
                8'h1A: controller_byte[4] <= 1'b1; // Up: W
                8'h16: controller_byte[5] <= 1'b1; // Down: S
                8'h04: controller_byte[6] <= 1'b1; // Left: A
                8'h07: controller_byte[7] <= 1'b1; // Right: D
                default;
            endcase
        end
        
        // Controller 1 Address
        if(AB == 16'h4016) begin
            if(WE) begin
                if(DO == 8'b1) begin
                    cpu_controller_byte <= controller_byte;
                end
                //else begin
                //    cpu_controller_byte <= latched_controller;
                //end
            end else begin        
                    cpu_controller_byte <= {1'b1, cpu_controller_byte[7:1]};
                    
            end
        end
    end
    
    // CPU Memory Map
    always_comb begin
        cpu_we = 1'b0;
        cpu_addr = 3'b0;
        cpu_data_in = 8'b0;
        cpu_ram_we = 1'b0;;
        DI = 8'b0;
        cpu_ram_we = 1'b0;
        cpu_ram_addr = 13'b0;
        cpu_ram_dina = 8'b0;
        prg_rom_addr = 15'b0;
        oamdma_begin = 9'b0;
        oam_cpu_start_addr = 8'b0;
        // CPU RAM
        if (AB < 16'h2000)  begin
            cpu_ram_we = WE;
            cpu_ram_addr = (AB[10:0]);
            DI = cpu_ram_data;
            cpu_ram_dina = DO;
        end
        // PPU IO
        else if(AB < 16'h4000) begin
            cpu_we = WE;
            cpu_addr = AB[2:0];
            cpu_data_in = DO;
            DI = cpu_data_out;
        end
        // OAMDMA
        else if(AB == 16'h4014) begin
            if(WE) begin
                oam_cpu_start_addr = DO;
                oamdma_begin = 9'b1;
            end
        end
        else if(AB == 16'h4016) begin
            if(~WE) begin
                DI = {7'b0, cpu_controller_byte[0]};
            end
        end
        // PRG-ROM
        else if (AB >= 16'h8000) begin
            // Change to 13 if 16 KB PRG
            prg_rom_addr = AB[14:0];
            DI = prg_rom_data;
        end
    end

    // CPU RAM BRAM Configuration
    logic [12:0] cpu_ram_addr;
    logic [7:0] cpu_ram_data;
    logic [7:0] cpu_ram_dina;
    //logic [7:0] cpu_ram_doutb;
    logic cpu_ram_we;
    
    CPU_RAM cpu_ram(
        .addra(cpu_ram_addr),
        .clka(clk_25MHz),
        .dina(cpu_ram_dina),
        .douta(cpu_ram_data),
        .ena(1'b1),
        .wea(cpu_ram_we),
        
        .addrb(oam_cpu_ram_addr),
        .clkb(clk_25MHz),
        .dinb(8'b0),
        .doutb(oam_cpu_ram_data),
        .enb(1'b1),
        .web(1'b0)
    );

    
    PRG_ROM prg_rom(
        .addra(prg_rom_addr),
        .clka(clk_25MHz),
        .dina(prg_rom_dina),
        .douta(prg_rom_data),
        .ena(1'b1),
        .wea(1'b0),
        
        .addrb(15'b0),
        .clkb(clk_25MHz),
        .dinb(8'b0),
        .doutb(prg_rom_doutb),
        .enb(1'b0),
        .web(1'b0)
    );

    // CHR_ROM BRAM Configuration
    logic [12:0] chr_rom_addr;
    logic [7:0] chr_rom_data;

    logic [12:0] sprite_chr_rom_addr;
    logic [7:0] sprite_chr_rom_data;
    
    CHR_ROM chr_rom(
        .addra(chr_rom_addr),
        .clka(clk_25MHz),
        .douta(chr_rom_data),
        .dina(8'b0),
        .ena(1'b1),
        .wea(1'b0),

        .addrb(sprite_chr_rom_addr),
        .clkb(clk_25MHz),
        .doutb(sprite_chr_rom_data),
        .dinb(8'b0),
        .enb(1'b1),
        .web(1'b0)
    );
    
    VRAM vram(
        .addra(vram_addr),
        .clka(clk_25MHz),
        .dina(vram_dina),
        .douta(vram_data),
        .ena(1'b1),
        .wea(1'b0),
        
        .addrb(cpu_vram_addr),
        .clkb(clk_25MHz),
        .dinb(cpu_vram_datain),
        .doutb(cpu_doutb),
        .enb(1'b1),
        .web(cpu_vram_we)
    );
    
    
endmodule
