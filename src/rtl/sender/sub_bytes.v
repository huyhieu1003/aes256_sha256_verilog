
module sub_bytes (
    //input clk,                // Tín hiệu clock
    input [127:0] data_in,    // Dữ liệu đầu vào
    output reg [127:0] data_out // Dữ liệu đầu ra (sử dụng reg để cập nhật theo clock)
);

    // Định nghĩa mảng S-Box để lưu trữ các giá trị từ file
    reg [7:0] sbox [0:255];
	 integer i;

    // Đọc bảng S-Box từ file khi mô-đun được khởi tạo
    initial begin
      $readmemh("D:/HK241/DA2/AES/encrypt/sbox/sbox.mem.txt", sbox);  // Đọc dữ liệu từ file sbox.mem
    end

    // Đồng bộ hóa với tín hiệu clock để cập nhật `data_out`
    always @(*) begin
        for (i = 0; i < 16; i = i + 1) begin
            data_out[8*i +: 8] <= sbox[data_in[8*i +: 8]];
        end
    end

endmodule
        /*$readmemh("D:/HK241/DA2/AES/encrypt/sbox/sbox.mem.txt", sbox);  // Đọc dữ liệu từ file sbox.mem
    end

    // Dữ liệu đầu vào được chia thành 16 byte, mỗi byte có chỉ số từ 0 đến 15
    generate
        genvar i;
        for (i = 0; i < 16; i = i + 1) begin : subbyte_loop
            assign data_out[8*i +: 8] = sbox[data_in[8*i +: 8]];
        end
    endgenerate

endmodule*/