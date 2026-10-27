module track_list (
    input  wire        clk,
    input  wire        rst,
    input  wire        clear,
    input  wire        push,
    input  wire [3:0]  push_index,
    input  wire [87:0] push_name,
    input  wire [31:0] push_cluster,
    input  wire [31:0] push_size,
    output reg  [15:0] valid_mask,
    output reg  [4:0]  track_count,
    input  wire        lookup_req,
    input  wire [3:0]  lookup_index,
    output reg         lookup_valid,
    output reg  [87:0] lookup_name,
    output reg  [31:0] lookup_cluster,
    output reg  [31:0] lookup_size
);

    localparam L_IDLE = 2'd0;
    localparam L_WRITE = 2'd1;
    localparam L_READ = 2'd2;

    reg [1:0] state;
    reg [4:0] byte_index;
    reg [8:0] base_addr;
    reg [151:0] write_data;
    reg [151:0] read_data;
    reg [7:0] mem_dout;
    wire [8:0] mem_addr = base_addr + byte_index;
    wire mem_we = (state == L_WRITE);
    wire [7:0] mem_din = write_data[151 - byte_index*8 -: 8];
    wire [151:0] read_complete = {read_data[151:8],mem_dout};

`ifdef TRACK_LIST_SIM
    reg [7:0] memory [0:511];
    always @(posedge clk) begin
        if (mem_we)
            memory[mem_addr] <= mem_din;
        mem_dout <= memory[mem_addr];
    end
`else
    wire [7:0] mem_do;
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(8), .ADDR_WIDTH_A(9), .DATA_DEPTH_A(512),
        .DATA_WIDTH_B(8), .ADDR_WIDTH_B(9), .DATA_DEPTH_B(512),
        .MODE("SP"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("ON"), .INIT_FILE("NONE"), .FILL_ALL("NONE"),
        .IMPLEMENT("9K")
    ) memory_inst (
        .dia(mem_din), .addra(mem_addr), .cea(1'b1), .ocea(1'b0),
        .clka(clk), .wea(mem_we), .rsta(1'b0), .bea(1'b0),
        .dib(8'd0), .addrb(9'd0), .ceb(1'b0), .oceb(1'b0),
        .clkb(clk), .web(1'b0), .rstb(1'b0), .beb(1'b0),
        .doa(mem_do), .dob()
    );
    always @(*) mem_dout = mem_do;
`endif

    function [8:0] slot_base;
        input [3:0] index;
        begin
            slot_base = ({5'd0,index} << 4) + ({5'd0,index} << 1) + {5'd0,index};
        end
    endfunction

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= L_IDLE;
            byte_index <= 5'd0;
            base_addr <= 9'd0;
            write_data <= 152'd0;
            read_data <= 152'd0;
            valid_mask <= 16'd0;
            track_count <= 5'd0;
            lookup_valid <= 1'b0;
            lookup_name <= 88'd0;
            lookup_cluster <= 32'd0;
            lookup_size <= 32'd0;
        end else begin
            lookup_valid <= 1'b0;
            if (clear) begin
                state <= L_IDLE;
                valid_mask <= 16'd0;
                track_count <= 5'd0;
            end else begin
                case (state)
                    L_IDLE: begin
                        if (push) begin
                            base_addr <= slot_base(push_index);
                            byte_index <= 5'd0;
                            write_data <= {push_name,push_cluster,push_size};
                            if (!valid_mask[push_index]) begin
                                valid_mask[push_index] <= 1'b1;
                                track_count <= track_count + 5'd1;
                            end
                            state <= L_WRITE;
                        end else if (lookup_req && valid_mask[lookup_index]) begin
                            base_addr <= slot_base(lookup_index);
                            byte_index <= 5'd0;
                            read_data <= 152'd0;
                            state <= L_READ;
                        end
                    end
                    L_WRITE: begin
                        if (byte_index == 5'd18) begin
                            byte_index <= 5'd0;
                            state <= L_IDLE;
                        end else begin
                            byte_index <= byte_index + 5'd1;
                        end
                    end
                    default: begin
                        if (byte_index != 5'd0)
                            read_data[159 - byte_index*8 -: 8] <= mem_dout;
                        if (byte_index == 5'd19) begin
                            lookup_name <= read_complete[151:64];
                            lookup_cluster <= read_complete[63:32];
                            lookup_size <= read_complete[31:0];
                            lookup_valid <= 1'b1;
                            byte_index <= 5'd0;
                            state <= L_IDLE;
                        end else begin
                            byte_index <= byte_index + 5'd1;
                        end
                    end
                endcase
            end
        end
    end

endmodule
