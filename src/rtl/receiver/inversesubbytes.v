module inversesubbytes (
    //input clk,                // Tín hiệu clock
    input [127:0] data_in,    // Dữ liệu đầu vào
    output reg [127:0] data_out // Dữ liệu đầu ra (sử dụng reg để cập nhật theo clock)
);

    // Định nghĩa mảng Inv S-Box để lưu trữ các giá trị từ file
    reg [7:0] invsbox [0:255];
	 integer i;

    // Đọc bảng S-Box từ file khi mô-đun được khởi tạo
    initial begin
      $readmemh("D:/HK241/DA2/AES/decrypt/inversesbox/invsbox.txt", invsbox);  // Đọc dữ liệu từ file sbox.mem
    end

    // Update  `data_out`
    always @(*) begin
        for (i = 0; i < 16; i = i + 1) begin
            data_out[8*i +: 8] <= invsbox[data_in[8*i +: 8]];
        end
    end

endmodule