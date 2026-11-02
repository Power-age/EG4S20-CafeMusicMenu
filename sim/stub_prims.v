module EG_LOGIC_BRAM #(
  parameter DATA_WIDTH_A=24, ADDR_WIDTH_A=10, DATA_DEPTH_A=1024,
  parameter DATA_WIDTH_B=24, ADDR_WIDTH_B=10, DATA_DEPTH_B=1024,
  parameter MODE="SP", REGMODE_A="NOREG", REGMODE_B="NOREG",
  parameter WRITEMODE_A="NORMAL", WRITEMODE_B="NORMAL",
  parameter RESETMODE="SYNC", DEBUGGABLE="NO", PACKABLE="NO",
  parameter FORCE_KEEP="OFF", INIT_FILE="NONE", FILL_ALL="NONE", IMPLEMENT="9K"
)(
  input [DATA_WIDTH_A-1:0] dia, input [ADDR_WIDTH_A-1:0] addra, input cea, ocea, clka, wea, rsta, bea,
  input [DATA_WIDTH_B-1:0] dib, input [ADDR_WIDTH_B-1:0] addrb, input ceb, oceb, clkb, web, rstb, beb,
  output [DATA_WIDTH_A-1:0] doa, output [DATA_WIDTH_B-1:0] dob
);
  assign doa = 0; assign dob = 0;
endmodule
