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
`define SIM_VIDEO

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
    
    localparam BMP_WIDTH  = 640;
    localparam BMP_HEIGHT = 480;
    logic [23:0] bitmap [BMP_WIDTH][BMP_HEIGHT];
    
    task save_bmp(string bmp_file_name);
        begin
        
            integer unsigned        fout_bmp_pointer, BMP_file_size,BMP_row_size,r;
            logic   unsigned [31:0] BMP_header[0:12];
        
                                      BMP_row_size  = 32'(BMP_WIDTH) & 32'hFFFC;  // When saving a bitmap, the row size/width must be
        if ((BMP_WIDTH & 32'd3) !=0)  BMP_row_size  = BMP_row_size + 4;           // padded to chunks of 4 bytes.
    
        fout_bmp_pointer= $fopen(bmp_file_name,"wb");
        if (fout_bmp_pointer==0) begin
            $display("Could not open file '%s' for writing",bmp_file_name);
            $stop;     
        end
        $display("Saving bitmap '%s'.",bmp_file_name);
       
        BMP_header[0:12] = '{BMP_file_size,0,0054,40,BMP_WIDTH,BMP_HEIGHT,{16'd24,16'd8},0,(BMP_row_size*BMP_HEIGHT*3),2835,2835,0,0};
        
        //Write header out      
        $fwrite(fout_bmp_pointer,"BM");
        for (int i =0 ; i <13 ; i++ ) $fwrite(fout_bmp_pointer,"%c%c%c%c",BMP_header[i][7 -:8],BMP_header[i][15 -:8],BMP_header[i][23 -:8],BMP_header[i][31 -:8]); // Better compatibility with Lattice Active_HDL.
        
        //Write image out (note that image is flipped in Y)
        for (int y=BMP_HEIGHT-1;y>=0;y--) begin
          for (int x=0;x<BMP_WIDTH;x++)
            $fwrite(fout_bmp_pointer,"%c%c%c",bitmap[x][y][23:16],bitmap[x][y][15:8],bitmap[x][y][7:0]) ;
        end
    
        $fclose(fout_bmp_pointer);
        end
    endtask
    int i, j;
    always@(posedge clk) begin
        if (reset) begin
            for (j = 0; j < BMP_HEIGHT; j++) begin    //assign bitmap default to some light gray so we 
                for (i = 0; i < BMP_WIDTH; i++) //can tell the difference between drawn black
                    bitmap[i][j] <= 24'h0F0FFF; //and default color
                    end
        end
        else
            if (p.vde) //Only draw when not in the blanking interval
                bitmap[p.drawX][p.drawY] <= {pixel_color[23:16], pixel_color[15:8],pixel_color[7:0]};
     end

    // Clock
    always #5 clk = ~clk;

    // Reset pulse
    initial begin
        #20 reset = 0;
    end
    
    logic [7:0] vram [0:2048];
    logic [7:0] chr_rom [0:8192];

    ppu p(.*);
    
//    logic [10:0] addra;
//logic [31:0] dina;
//logic [31:0] douta;
//logic [3:0] wea;

//logic [10:0] addrb;
//logic [31:0] dinb;
//logic [31:0] doutb;
//logic [3:0] web;
//logic [1:0] delay;

////assign wea = S_AXI_WSTRB;

//VRAM vram(
//    .addra(vram_addr),
//    .clka(clk),
//    .dina(8'b0),
//    .douta(vram_data),
//    .ena(1'b1),
//    .wea(1'b0),
    
//    .addrb(addrb),
//    .clkb(clk),
//    .dinb(dinb),
//    .doutb(doutb),
//    .enb(1'b1),
//    .web(web)
//);

    
    initial begin
    //web = 0;
        $readmemh("chr_rom.hex", chr_rom, 16'h0000);
        $display("%h",chr_rom[0:16]);
        for(i = 0; i < 2048; i++)
            vram[i] = 0;
        for(i = 0; i < 512; i++)
            vram[i] = i;
        //reset = 1;
//        for(i = 0; i < 10; i++)
//            web <= 1;
//            addrb <= i;
//            dinb <= i;
//            #10;
//            web <= 0 ;
//        reset = 0;
        //vram[1] = 8'd3;
    end
    
    always_ff @(posedge clk) begin
        vram_data <= vram[vram_addr];
        chr_rom_data <= chr_rom[chr_rom_addr];
    end
    
    initial begin
        #700000;
        `ifdef SIM_VIDEO
		//wait (~pixel_vs);
		save_bmp ("lab7_1_sim_test.bmp");
		`endif
		$finish();
        $finish;
    end
endmodule
