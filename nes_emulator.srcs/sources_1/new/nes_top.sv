`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/24/2025 01:10:49 AM
// Design Name: 
// Module Name: nes_top
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


module nes_top(
    input logic Clk,
    input logic reset_rtl_0,
    //UART
    input logic uart_rtl_0_rxd,
    output logic uart_rtl_0_txd,
    
    //HDMI
    output logic hdmi_tmds_clk_n,
    output logic hdmi_tmds_clk_p,
    output logic [2:0]hdmi_tmds_data_n,
    output logic [2:0]hdmi_tmds_data_p
    );
    assign uart_rtl_0_txd = 1'b1;


    logic clk_25MHz, clk_125MHz;
    logic locked;

    clk_wiz_0 clk_wiz (
        .clk_out1(clk_25MHz),
        .clk_out2(clk_125MHz),
        .reset(reset),
        .locked(locked),
        .clk_in1(Clk)
    );

    // CHR_ROM BRAM Configuration
    logic [12:0] chr_rom_addr;
    logic [7:0] chr_rom_data;
    logic [7:0] chr_rom_dina;
    logic [7:0] chr_rom_doutb;
    
    CHR_ROM chr_rom(
        .addra(chr_rom_addr),
        .clka(clk),
        .dina(chr_rom_dina),
        .douta(chr_rom_data),
        .ena(1'b1),
        .wea(1'b0),
        
        .addrb(0),
        .clkb(clk),
        .dinb(0),
        .doutb(chr_rom_doutb),
        .enb(1'b0),
        .web(1'b0)
    );
    
    
    // VRAM BRAM Configuration
    logic [12:0] vram_addr;
    logic [7:0] vram_data;
    logic [7:0] vram_dina;
    assign vram_dina = 0;
    
    logic [7:0] vram_doutb;
    
    VRAM vram(
        .addra(vram_addr),
        .clka(clk),
        .dina(vram_dina),
        .douta(vram_data),
        .ena(1'b1),
        .wea(1'b0),
        
        .addrb(0),
        .clkb(clk),
        .dinb(0),
        .doutb(vram_doutb),
        .enb(1'b0),
        .web(1'b0)
    );
    
    // PPU Configuration
    logic        clk;
    logic        reset;
    assign clk = Clk;
    assign reset = reset_rtl_0;
    logic        cpu_we;
    logic [2:0]  cpu_addr;
    logic [7:0]  cpu_data_in;
    logic [7:0]  cpu_data_out;
    logic [23:0]  pixel_color;
    logic        pixel_valid;

    ppu p(.*);
endmodule
