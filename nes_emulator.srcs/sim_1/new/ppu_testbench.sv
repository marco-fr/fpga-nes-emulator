`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/21/2025 12:55:22 AM
// Design Name: 
// Module Name: ppu_testbench
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


module ppu_testbench(

    );
    logic clk = 0;
    logic reset = 1;
    logic        cpu_we;
    logic [2:0]  cpu_addr;       // $2000-$2007
    logic [7:0]  cpu_data_in;
    logic [7:0]  cpu_data_out;
                      
    logic [23:0]  pixel_color;
    logic        pixel_valid;
    logic        hsync;
    logic        vsync;
                      
    logic [7:0]  chr_rom_data;
    logic [12:0] chr_rom_addr;
                      
    logic [7:0]  vram_data;
    logic [10:0] vram_addr;
    logic        vram_read;

    // Clock
    always #1 clk = ~clk;

    // Reset pulse
    initial begin
        #20 reset = 0;
    end
    
    logic [7:0] vram [0:2048];
    logic [7:0] chr_rom [0:8192];

    ppu p(.*);
    
    initial begin
        $readmemh("chr_rom.hex", chr_rom, 16'h0000);
        $display("%h",chr_rom[0:16]);
        
        vram[0] = 8'd2;
        vram[1] = 8'd3;
    end
    
    always_ff @(posedge clk) begin
        vram_data <= vram[vram_addr];
        chr_rom_data <= chr_rom[chr_rom_addr];
    end
    
    initial begin
        #10000;
        $finish;
    end
endmodule
