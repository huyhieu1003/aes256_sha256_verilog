module invshiftrows (
    //input clk,                  // Tín hiệu clock
    input [0:127] in,           // Dữ liệu đầu vào
    output reg [0:127] shifted  // Dữ liệu đầu ra (đồng bộ theo clock)
);

    always @(*) begin
        // First row (r = 0) is not shifted
        shifted[0+:8] <= in[0+:8];
        shifted[32+:8] <= in[32+:8];
        shifted[64+:8] <= in[64+:8];
        shifted[96+:8] <= in[96+:8];

        // Second row (r = 1) is cyclically right shifted by 1 offset
        shifted[8+:8] <= in[104+:8];
        shifted[40+:8] <= in[8+:8];
        shifted[72+:8] <= in[40+:8];
        shifted[104+:8] <= in[72+:8];

        // Third row (r = 2) is cyclically right shifted by 2 offsets
        shifted[16+:8] <= in[80+:8];
        shifted[48+:8] <= in[112+:8];
        shifted[80+:8] <= in[16+:8];
        shifted[112+:8] <= in[48+:8];

        // Fourth row (r = 3) is cyclically right shifted by 3 offsets
        shifted[24+:8] <= in[56+:8];
        shifted[56+:8] <= in[88+:8];
        shifted[88+:8] <= in[120+:8];
        shifted[120+:8] <= in[24+:8];
    end

endmodule
