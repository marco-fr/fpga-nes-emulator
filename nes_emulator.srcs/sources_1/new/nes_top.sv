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
    logic clk_reset = 0;
    
    // VRAM BRAM Configuration
    logic [12:0] vram_addr;
    logic [7:0] vram_data;
    logic [7:0] vram_dina;
    assign vram_dina = 0;
    
    
    logic cpu_we;
    logic cpu_vram_we;
    logic [7:0]  cpu_data_in;
    logic [7:0]  cpu_data_out;
    logic [7:0]  cpu_doutb;
    logic [12:0]  cpu_vram_addr;
    logic [7:0] cpu_vram_datain;
    
    //// CPU Configuration
    logic [15:0] AB;
    logic [7:0] DI;      
    logic [7:0] DO;
    logic WE_inv;     
    logic WE;           
    logic IRQ;           
    logic NMI;           
    logic RDY;        
    assign IRQ = 1'b1;   
    //assign NMI = 1'b1;
    assign RDY = 1'b1;
    assign WE = ~WE_inv;
    
//    tot6502 c(
//        .clk(clk_1_66mhz),
//        .enable(1'b1),
//        .dati(DI),
//        .dato(DO),
//        .addr(AB),
//        .rw(WE),
//        .rst_n(~reset),
//        .irq_n(IRQ),
//        .nmi_n(NMI),
//        .rdy(RDY)
//    );
    T65 c(
        	.mode   (2'b0),		// 6502 mode
        .BCD_en (1'b0),		// idk but this is right
        
        .clk    (clk_1_66mhz),		// clock
    
        .res_n  (~reset),		// cpu reset 
        .enable (1'b1),	// enable (cpu doesnt continue unless this is high)
        .rdy    (RDY),		// ready (cpu doesnt continue with some extra steps)
    
        .IRQ_n  (IRQ),		// beta interrupt (interrupt request)
        .NMI_n  (NMI),		// alpha interrupt https://en.wikipedia.org/wiki/Non-maskable_interrupt
        
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


    logic clk_25MHz, clk_125MHz, clk_1_66mhz;
    logic locked;
    logic        reset;
    assign reset = reset_rtl_0;
    clk_wiz_0 clk_wiz (
        .clk_out1(clk_25MHz),
        .clk_out2(clk_125MHz),
        .reset(reset),
        .locked(locked),
        .clk_in1(Clk)
    );
    
    
    nes_clock_gen nes_clock(
        .clk_100mhz(Clk),
        .reset(reset),
        .clk_1_66mhz(clk_1_66mhz)
    );
    
    // PPU Configuration
    logic        clk;
    
    assign clk = clk_1_66mhz;
    
    logic [23:0]  pixel_color;
    logic        pixel_valid;
    logic [2:0]  cpu_addr;

    ppu p(
        .nmi_out(NMI),
    .*);
    
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
            if (AB < 16'h2000)  begin
                cpu_ram_we = WE;
                cpu_ram_addr = (AB[10:0]);
                DI = cpu_ram_data;
                cpu_ram_dina = DO;
            end
            else if(AB < 16'h4000) begin
                cpu_we = WE;
                cpu_addr = AB[2:0];
                cpu_data_in = DO;
                DI = cpu_data_out;
            end
            else if (AB >= 16'h8000) begin
                prg_rom_addr = AB[13:0];
                DI = prg_rom_data;
            end
    end
    
//    always_comb begin
//        cpu_we = 1'b0;
//            cpu_addr = 3'b0;
//            cpu_data_in = 8'b0;
//            cpu_ram_we = 1'b0;;
            
//            cpu_ram_we = 1'b0;
//            cpu_ram_addr = 13'b0;
//            cpu_ram_dina = 8'b0;
            
//            prg_rom_addr = 13'b0;
            
//            if (AB < 16'h2000)  begin
//                cpu_ram_we = WE;
//                cpu_ram_addr = (AB[10:0]);

//                cpu_ram_dina = DO;
//            end
//            else if(AB < 16'h4000) begin
//                cpu_we = WE;
//                cpu_addr = AB[2:0];
//                cpu_data_in = DO;
//            end
//            else if (AB >= 16'h8000) begin
//                prg_rom_addr = AB[12:0];
//            end
//    end
//    always_ff @(posedge clk_1_66mhz) begin
//        //if(clk_1_66mhz) begin
//            DI <= 8'b0;
            
//            if(AB == 16'hFFFE || AB == 16'hFFFC)
//                DI <= 8'h00;
//            else if(AB == 16'hFFFF || AB == 16'hFFFD)
//                DI <= 8'h80;
//            else if (AB < 16'h2000)  begin
//                DI <= cpu_ram_data;
//            end
//            else if(AB < 16'h4000) begin
//                DI <= cpu_data_out;
//            end
//            else if (AB >= 16'h8000) begin
//                DI <= prg_rom_data;
//            end
//        //end
//    end

    // CPU RAM BRAM Configuration
    logic [12:0] cpu_ram_addr;
    logic [7:0] cpu_ram_data;
    logic [7:0] cpu_ram_dina;
    logic [7:0] cpu_ram_doutb;
    logic cpu_ram_we;
    
    CPU_RAM cpu_ram(
        .addra(cpu_ram_addr),
        .clka(Clk),
        .dina(cpu_ram_dina),
        .douta(cpu_ram_data),
        .ena(1'b1),
        .wea(cpu_ram_we),
        
        .addrb(8'b0),
        .clkb(Clk),
        .dinb(8'b0),
        .doutb(cpu_ram_doutb),
        .enb(1'b0),
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

    
//    cpu c(
//        .clk(clk_1_66mhz),
//        .*
//    );

    // CHR_ROM BRAM Configuration
    logic [12:0] chr_rom_addr;
    logic [7:0] chr_rom_data;
    
    CHR_ROM chr_rom(
        .addra(chr_rom_addr),
        .clka(Clk),
        .douta(chr_rom_data),
        .ena(1'b1)
    );
    
    

    
    VRAM vram(
        .addra(vram_addr),
        .clka(Clk),
        .dina(vram_dina),
        .douta(vram_data),
        .ena(1'b1),
        .wea(1'b0),
        
        .addrb(cpu_vram_addr),
        .clkb(Clk),
        .dinb(cpu_vram_datain),
        .doutb(cpu_doutb),
        .enb(1'b1),
        .web(cpu_vram_we)
    );
    
    
endmodule
