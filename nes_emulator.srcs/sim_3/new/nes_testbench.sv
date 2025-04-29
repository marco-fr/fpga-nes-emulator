`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/24/2025 11:07:16 AM
// Design Name: 
// Module Name: nes_testbench
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
//`define SIM_VIDEO

module nes_testbench(

    );
    logic clk = 0;
    logic reset = 1;
    logic hdmi_tmds_clk_n;
    logic hdmi_tmds_clk_p;
    logic [2:0]hdmi_tmds_data_n;
    logic [2:0]hdmi_tmds_data_p;
       logic uart_rtl_0_rxd;
    logic uart_rtl_0_txd;
    
    nes_top nes(
        .Clk(clk),
        .reset_rtl_0(reset),
        .*
       );
    
    // Clock
    always #5 clk = ~clk;

    // Reset pulse
    initial begin
        #700 reset = 0;
    end
    
    initial begin
        nes.clk_reset = 1;
        #5 nes.clk_reset = 0;
    end
    
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
//    always@(posedge clk) begin
//        if (reset) begin
//            for (j = 0; j < BMP_HEIGHT; j++) begin    //assign bitmap default to some light gray so we 
//                for (i = 0; i < BMP_WIDTH; i++) //can tell the difference between drawn black
//                    bitmap[i][j] <= 24'h0F0FFF; //and default color
//                    end
//        end
//        else
//            if (nes.p.vde) //Only draw when not in the blanking interval
//                bitmap[nes.p.drawX][nes.p.drawY] <= {nes.pixel_color[23:16], nes.pixel_color[15:8],nes.pixel_color[7:0]};
//     end
    
    initial begin
        //#10000000;
        #100000
        `ifdef SIM_VIDEO
		//wait (~pixel_vs);
		save_bmp ("lab7_1_sim_test.bmp");
		`endif
		$finish();
    end
endmodule
