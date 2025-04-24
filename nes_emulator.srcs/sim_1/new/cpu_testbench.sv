`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/18/2025 04:51:43 PM
// Design Name: 
// Module Name: cpu_testbench
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


module cpu_testbench(

    );
    logic clk = 0;
    logic reset = 1;
    logic [15:0] AB;
    logic [7:0] DI, DO;
    logic WE;
    logic IRQ = 0;
    logic NMI = 0;
    logic RDY = 1;

    // Clock
    always #5 clk = ~clk;

    // Reset pulse
    initial begin
        #20 reset = 0;
    end

    // Memory (64KB)
    logic [7:0] memory [0:65535];

    // Load test program into memory
    initial begin
        $readmemh("test.hex", memory, 16'h0000);
        $display("%h",memory[0:16]);
        // Set reset vector to 0x0000
        memory[16'hFFFC] = 8'h00;
        memory[16'hFFFD] = 8'h00;
    end

    // Hook up memory
    always_ff @(posedge clk) begin
        if (WE) begin
            memory[AB] <= DO;
        end
        DI <= memory[AB];
    end

    // Instantiate Arlet's 6502 CPU
    cpu cpu_inst (
        .clk(clk),
        .reset(reset),
        .AB(AB),
        .DI(DI),
        .DO(DO),
        .WE(WE),
        .IRQ(IRQ),
        .NMI(NMI),
        .RDY(RDY)
    );

    // Monitor key activity
    always_ff @(posedge clk) begin
        if (!reset) begin
            $display("CLK=%0t PC=%h AB=%h DI=%h DO=%h WE=%b", $time, AB, AB, DI, DO, WE);
        end
    end
    
    logic [7:0] m10, m20;

    initial begin
        #600;  // wait ~30 clock cycles after reset

        m10 = memory[16'h0010];
        m20 = memory[16'h0020];

        assert(m10 == 8'h01)
            else $fatal("Assertion failed: Expected memory[$10] = 0x01, got %02h", m10);

        assert(m20 == 8'h06)
            else $fatal("Assertion failed: Expected memory[$20] = 0x06, got %02h", m20);

        $display("✅ All assertions passed. CPU test successful.");
        $finish;
    end
    
endmodule
