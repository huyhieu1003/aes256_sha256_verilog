module AES_decrypt #(
  parameter N = 128,        // Kích thước khối dữ liệu (128-bit)
  parameter Nr = 14,        // Số vòng (14 vòng cho AES-256)
  parameter nk = 8          // Số phần tử trong khóa (8 phần tử cho AES-256)
)(
  input [N-1:0] in,         // Dữ liệu đầu vào (128-bit ciphertext)
  input [255:0] key,        // Khóa 256-bit
  output [N-1:0] out        // Dữ liệu đầu ra (128-bit plaintext)
);

  // Các tín hiệu cần thiết
  wire [N-1:0] state [Nr:0];     // Trạng thái sau mỗi vòng
  wire [N-1:0] round_key[Nr:0];  // Khóa của mỗi vòng
  wire [N-1:0] aisb;             // after inverse sub bytes
  wire [N-1:0] aisr;             // after inverse shift rows

  // ✅ Sử dụng keyexpansion cho AES-256 để tạo khóa vòng đầu tiên
  keyexpansion #(.Nr(Nr), .nk(nk)) ke_initial (
      .key(key), 
      .round(4'd14),           // ✅ 4-bit literal
      .w_out(round_key[Nr])    // Khóa con cho vòng Nr
  );

  // ✅ Thực hiện AddRoundKey ban đầu (với khóa vòng 14)
  adroundkey addrk_initial (
      .data(in), 
      .out(state[0]), 
      .key(round_key[Nr])
  );

  // ✅ Các vòng decrypt (từ vòng 1 đến vòng 13)
  genvar i;
  generate
      for (i = 1; i < Nr; i = i + 1) begin : round_loop
          // ✅ Tạo intermediate wire cho round number
          wire [3:0] current_round;
          assign current_round = Nr - i;  // Tính toán round number
          
          // Tạo khóa cho vòng hiện tại
          keyexpansion #(.Nr(Nr), .nk(nk)) ke_round (
              .key(key), 
              .round(current_round),       // ✅ Sử dụng wire thay vì expression
              .w_out(round_key[Nr - i])    // Khóa của vòng tương ứng
          );
          
          // Thực hiện decrypt round
          decryptround dr (
              .in(state[i-1]), 
              .key(round_key[Nr - i]), 
              .out(state[i])
          );
      end
  endgenerate

  // ✅ Vòng cuối cùng: InvShiftRows + InvSubBytes + AddRoundKey
  
  // Inverse ShiftRows
  invshiftrows isr (
      .in(state[Nr-1]), 
      .shifted(aisr)
  );
  
  // Inverse SubBytes
  inversesubbytes isb (
      .data_in(aisr), 
      .data_out(aisb)
  );
  
  // Tạo khóa cho vòng cuối (vòng 0)
  keyexpansion #(.Nr(Nr), .nk(nk)) ke_final (
      .key(key), 
      .round(4'd0),            // ✅ 4-bit literal
      .w_out(round_key[0])     // Khóa của vòng cuối
  );
  
  // AddRoundKey cuối cùng
  adroundkey addrk_final (
      .data(aisb), 
      .out(state[Nr]), 
      .key(round_key[0])
  );

  // ✅ Gán kết quả cuối cùng
  assign out = state[Nr];

endmodule