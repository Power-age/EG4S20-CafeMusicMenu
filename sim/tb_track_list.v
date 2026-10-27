`timescale 1ns/1ps
module tb_track_list;
    reg clk, rst, clear, push, lookup_req;
    reg [3:0] push_index, lookup_index;
    reg [87:0] push_name;
    reg [31:0] push_cluster, push_size;
    wire [15:0] valid_mask;
    wire [4:0] track_count;
    wire lookup_valid;
    wire [87:0] lookup_name;
    wire [31:0] lookup_cluster, lookup_size;
    integer errors;

    track_list dut (
        .clk(clk),.rst(rst),.clear(clear),.push(push),.push_index(push_index),
        .push_name(push_name),.push_cluster(push_cluster),.push_size(push_size),
        .valid_mask(valid_mask),.track_count(track_count),.lookup_req(lookup_req),
        .lookup_index(lookup_index),.lookup_valid(lookup_valid),.lookup_name(lookup_name),
        .lookup_cluster(lookup_cluster),.lookup_size(lookup_size)
    );
    always #5 clk=~clk;

    task add;
        input [3:0] idx;
        input [87:0] name;
        input [31:0] cluster;
        input [31:0] size;
        begin
            wait(dut.state==0);
            @(negedge clk);
            push=1; push_index=idx; push_name=name; push_cluster=cluster; push_size=size;
            @(posedge clk); @(negedge clk); push=0;
            wait(dut.state==0);
        end
    endtask

    task lookup;
        input [3:0] idx;
        input [87:0] name;
        input [31:0] cluster;
        input [31:0] size;
        begin
            @(negedge clk); lookup_req=1; lookup_index=idx;
            @(posedge clk); @(negedge clk); lookup_req=0;
            wait(lookup_valid);
            #1;
            if (lookup_name!==name || lookup_cluster!==cluster || lookup_size!==size) begin
                $display("FAIL lookup idx=%0d name=%h cluster=%0d size=%0d",idx,lookup_name,lookup_cluster,lookup_size);
                errors=errors+1;
            end
            @(posedge clk);
        end
    endtask

    initial begin
        clk=0; rst=1; clear=0; push=0; lookup_req=0; push_index=0; lookup_index=0;
        push_name=0; push_cluster=0; push_size=0; errors=0;
        repeat(3) @(posedge clk); @(negedge clk); rst=0;
        add(4'd15,"TRACK16 RAW",32'd116,32'd960000);
        add(4'd1,"TRACK02 RAW",32'd102,32'd480002);
        add(4'd9,"TRACK10 RAW",32'd110,32'd720000);
        add(4'd0,"TRACK01 RAW",32'd101,32'd240000);
        if (valid_mask!==16'h8203 || track_count!==5'd4) begin
            $display("FAIL mask=%h count=%0d",valid_mask,track_count); errors=errors+1;
        end
        lookup(4'd0,"TRACK01 RAW",32'd101,32'd240000);
        lookup(4'd1,"TRACK02 RAW",32'd102,32'd480002);
        lookup(4'd9,"TRACK10 RAW",32'd110,32'd720000);
        lookup(4'd15,"TRACK16 RAW",32'd116,32'd960000);
        add(4'd1,"TRACK02 RAW",32'd202,32'd480004);
        if (track_count!==5'd4) begin $display("FAIL duplicate count=%0d",track_count); errors=errors+1; end
        lookup(4'd1,"TRACK02 RAW",32'd202,32'd480004);
        @(negedge clk); clear=1; @(posedge clk); @(negedge clk); clear=0;
        if (valid_mask!==0 || track_count!==0) begin $display("FAIL clear"); errors=errors+1; end
        if (errors==0) $display("TRACK_LIST PASS");
        else $display("TRACK_LIST FAIL errors=%0d",errors);
        $finish;
    end
    initial begin #1000000; $display("TRACK_LIST TIMEOUT"); $finish; end
endmodule
