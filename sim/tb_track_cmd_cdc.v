`timescale 1ns/1ps
module tb_track_cmd_cdc;
    reg vclk,sclk,rst;
    reg req_v;
    reg [1:0] data_v;
    reg req_s1,req_s2,seen_s;
    reg [1:0] data_s1,data_s2;
    reg ack_s;
    reg prev_s,next_s;
    integer prev_count,next_count,errors;
    always #20 vclk=~vclk;
    always #5 sclk=~sclk;
    always @(posedge sclk or posedge rst) begin
        if(rst) begin req_s1<=0;req_s2<=0;seen_s<=0;data_s1<=0;data_s2<=0;ack_s<=0;prev_s<=0;next_s<=0; end
        else begin
            req_s1<=req_v;req_s2<=req_s1;data_s1<=data_v;data_s2<=data_s1;prev_s<=0;next_s<=0;
            if(req_s2!=seen_s) begin seen_s<=req_s2;ack_s<=req_s2; if(data_s2==1)prev_s<=1; else if(data_s2==2)next_s<=1; end
        end
    end
    always @(posedge sclk) begin if(prev_s)prev_count=prev_count+1; if(next_s)next_count=next_count+1; end
    task send; input [1:0] cmd; begin @(negedge vclk);data_v=cmd;req_v=~req_v;wait(ack_s==req_v);repeat(4)@(posedge sclk);end endtask
    initial begin vclk=0;sclk=0;rst=1;req_v=0;data_v=0;prev_count=0;next_count=0;errors=0;repeat(4)@(posedge sclk);rst=0;
        send(1);send(2);send(2);send(1);
        if(prev_count!=2||next_count!=2)begin $display("FAIL CDC prev=%0d next=%0d",prev_count,next_count);errors=errors+1;end
        if(errors==0)$display("TRACK_CMD_CDC PASS");else $display("TRACK_CMD_CDC FAIL");$finish;end
    initial begin #100000;$display("TRACK_CMD_CDC TIMEOUT");$finish;end
endmodule
