`timescale 1ns/1ps
// 仿真用 SDRAM 命令监视器：替换 eagle_macro 中空的 EG_PHY_SDRAM_2M_32
// 只解析命令、计数 AUTO REFRESH（不返回读数据，用于研究刷新产出/仲裁）
module EG_PHY_SDRAM_2M_32(clk,ras_n,cas_n,we_n,addr,ba,dq,cs_n,dm0,dm1,dm2,dm3,cke);
    input clk;
    input ras_n, cas_n, we_n;
    input [10:0] addr;
    input [1:0] ba;
    inout [31:0] dq;
    input cs_n, dm0, dm1, dm2, dm3, cke;

    assign dq = 32'hzzzzzzzz;

    integer refcnt, actcnt, rdcnt, wrcnt, precnt;
    initial begin refcnt=0; actcnt=0; rdcnt=0; wrcnt=0; precnt=0; end

    always @(posedge clk) begin
        if (cs_n==1'b0 && cke==1'b1) begin
            casez ({ras_n,cas_n,we_n})
                3'b001: begin refcnt=refcnt+1; $display("    AUTOREF #%0d @%0t", refcnt, $time); end
                3'b011: actcnt=actcnt+1;
                3'b101: rdcnt=rdcnt+1;
                3'b100: wrcnt=wrcnt+1;
                3'b010: precnt=precnt+1;
                default: ;
            endcase
        end
    end
endmodule
