`timescale 1ns/1ps
module tb_track_controller;
    reg clk,rst,enable,cmd_prev,cmd_next,lookup_valid,player_busy,player_finish,player_error,sector_idle;
    reg [15:0] valid_mask;
    reg [4:0] track_count;
    wire lookup_req;
    wire [3:0] lookup_index;
    reg [87:0] lookup_name;
    reg [31:0] lookup_cluster,lookup_size;
    wire player_start,player_stop,chain_load_start,playlist_active;
    wire [31:0] player_size,chain_start_cluster;
    wire [3:0] current_index;
    wire [87:0] current_name;
    integer errors;
    reg [3:0] pending_lookup;

    track_controller dut(
        .clk(clk),.rst(rst),.enable(enable),.valid_mask(valid_mask),.track_count(track_count),
        .cmd_prev(cmd_prev),.cmd_next(cmd_next),.lookup_req(lookup_req),.lookup_index(lookup_index),
        .lookup_valid(lookup_valid),.lookup_name(lookup_name),.lookup_cluster(lookup_cluster),.lookup_size(lookup_size),
        .player_busy(player_busy),.player_finish(player_finish),.player_error(player_error),
        .player_start(player_start),.player_stop(player_stop),.player_size(player_size),.sector_idle(sector_idle),
        .chain_load_start(chain_load_start),.chain_start_cluster(chain_start_cluster),
        .playlist_active(playlist_active),.current_index(current_index),.current_name(current_name));
    always #5 clk=~clk;

    always @(posedge clk) begin
        lookup_valid<=0;
        if(lookup_req) begin
            pending_lookup<=lookup_index;
            lookup_name<={"TRACK0",8'h31+lookup_index," RAW"};
            lookup_cluster<=32'd100+lookup_index;
            lookup_size<=32'd1000+lookup_index*2;
            lookup_valid<=1;
        end
        if(player_start) player_busy<=1;
        if(player_stop) player_busy<=0;
    end

    task pulse_finish;
        begin @(negedge clk); player_finish=1; @(posedge clk); @(negedge clk); player_finish=0; end
    endtask
    task pulse_error;
        begin @(negedge clk); player_error=1; @(posedge clk); @(negedge clk); player_error=0; end
    endtask
    task wait_index;
        input [3:0] idx;
        integer wd;
        begin wd=0; while((current_index!=idx || !playlist_active)&&wd<200) begin @(posedge clk); wd=wd+1; end
            if(wd>=200) begin $display("FAIL index expected=%0d got=%0d state=%0d",idx,current_index,dut.state); errors=errors+1; end end
    endtask

    initial begin
        clk=0;rst=1;enable=0;valid_mask=0;track_count=0;cmd_prev=0;cmd_next=0;
        lookup_valid=0;lookup_name=0;lookup_cluster=0;lookup_size=0;player_busy=0;player_finish=0;player_error=0;sector_idle=1;errors=0;
        repeat(3)@(posedge clk);@(negedge clk);rst=0;
        repeat(5)@(posedge clk);
        if(playlist_active) begin $display("FAIL empty active"); errors=errors+1; end
        valid_mask=16'h8005; track_count=3; enable=1;
        wait_index(0);
        pulse_finish; wait_index(2);
        pulse_finish; wait_index(15);
        pulse_finish; wait_index(0);
        @(negedge clk); cmd_prev=1; @(posedge clk); @(negedge clk); cmd_prev=0; wait_index(15);
        pulse_error; wait_index(0);
        if(errors==0)$display("TRACK_CONTROLLER PASS"); else $display("TRACK_CONTROLLER FAIL errors=%0d",errors);
        $finish;
    end
    initial begin #1000000;$display("TRACK_CONTROLLER TIMEOUT");$finish;end
endmodule
