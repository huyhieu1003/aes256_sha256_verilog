/*
module AES_encrypt#(
    parameter N=128,          // Kích thước khối dữ liệu (128-bit)
    parameter Nr=14,          // Số vòng (10 vòng cho AES-128)
    parameter nk=8            // Số phần tử trong khóa (4 phần tử cho AES-128)
)(
    input [N-1:0] in,        // Dữ liệu đầu vào (128-bit plaintext)
    input [255:0] key,       // Khóa 256-bit
    output [N-1:0] out       // Dữ liệu đầu ra (128-bit ciphertext)
);

    // Các tín hiệu cần thiết
    wire [N-1:0] state [Nr:0];     // Trạng thái sau mỗi vòng
    wire [N-1:0] round_key[Nr:0];
	 wire [N-1:0] asb;  // after sub bytes
    wire [N-1:0] asr;  // after shift rows
	 // Khóa của mỗi vòng

    // Sử dụng keyexpansion để tạo khóa cho các vòng
    keyexpansion #(Nr, nk) ke (
        .key(key), 
        .round(0),          // Vòng 0 cho AddRoundKey ban đầu
        .w_out(round_key[0])   // Khóa con cho vòng 0
    );

    // Thực hiện AddRoundKey cho vòng 0
    adroundkey addrk1 (
        .data(in), 
        .out(state[0]), 
        .key(round_key[0])
    );

    // Các vòng mã hóa
    genvar i;
    generate
        for (i = 1; i < Nr; i = i + 1) begin : round_loop
            // Truyền khóa tương ứng từ module keyexpansion cho từng vòng
            keyexpansion ke_round (
                .key(key), 
                .round(i),         // Truyền vòng hiện tại
                .w_out(round_key[i])  // Khóa của vòng i
            );
            encryptround er (
                .in(state[i-1]), 
                .key(round_key[i]), 
                .out(state[i])
            );
        end
		 // SubBytes, ShiftRows và AddRoundKey cho vòng cuối cùng
    sub_bytes sb (
        .data_in(state[Nr-1]), 
        .data_out(asb)
    );
    shiftrows sr (
        .in(asb), 
        .shifted(asr)
    );
    keyexpansion ke_last (
        .key(key), 
        .round(Nr),       // Vòng cuối cùng
        .w_out(round_key[Nr]) // Khóa của vòng cuối
    );
    adroundkey addrk2 (
        .data(asr), 
        .out(state[Nr]), 
        .key(round_key[Nr])
    );

    // Gán kết quả cuối cùng
    assign out = state[Nr]; 
    endgenerate

endmodule
*/
module AES_encrypt#(
    parameter N=128,          // Kích thước khối dữ liệu (128-bit)
    parameter Nr=14,          // Số vòng (14 vòng cho AES-256)
    parameter nk=8            // Số phần tử trong khóa (8 phần tử cho AES-256)
)(
    input [N-1:0] in,        // Dữ liệu đầu vào (128-bit plaintext)
    input [255:0] key,       // Khóa 256-bit
    output [N-1:0] out       // Dữ liệu đầu ra (128-bit ciphertext)
);

    // Các tín hiệu cần thiết
    wire [N-1:0] state [Nr:0];     // Trạng thái sau mỗi vòng
    wire [N-1:0] round_key[Nr:0];  // Khóa của mỗi vòng
    wire [N-1:0] asb;              // after sub bytes
    wire [N-1:0] asr;              // after shift rows

    //===========================================================================================================
    // KEY EXPANSION - TẠO TẤT CẢ ROUND KEYS
    //===========================================================================================================
    
    genvar j;
    generate
        for (j = 0; j <= Nr; j = j + 1) begin : key_gen
            keyexpansion #(.Nr(Nr), .nk(nk)) ke (
                .key(key), 
                .round(j[3:0]),              // ✅ 4-bit round number
                .w_out(round_key[j])         // Khóa con cho vòng j
            );
        end
    endgenerate

    //===========================================================================================================
    // VÒNG 0: ADD ROUND KEY BAN ĐẦU
    //===========================================================================================================
    
    adroundkey addrk1 (
        .data(in), 
        .out(state[0]), 
        .key(round_key[0])
    );

    //===========================================================================================================
    // CÁC VÒNG 1 ĐẾN Nr-1: FULL ROUNDS (SubBytes + ShiftRows + MixColumns + AddRoundKey)
    //===========================================================================================================
    
    genvar i;
    generate
        for (i = 1; i < Nr; i = i + 1) begin : round_loop
            encryptround er (
                .in(state[i-1]), 
                .key(round_key[i]), 
                .out(state[i])
            );
        end
    endgenerate

    //===========================================================================================================
    // VÒNG CUỐI CÙNG (Nr): FINAL ROUND - SubBytes + ShiftRows + AddRoundKey (KHÔNG CÓ MixColumns)
    //===========================================================================================================
    
    // SubBytes
    sub_bytes sb (
        .data_in(state[Nr-1]), 
        .data_out(asb)
    );
    
    // ShiftRows
    shiftrows sr (
        .in(asb), 
        .shifted(asr)
    );
    
    // AddRoundKey cuối cùng
    adroundkey addrk2 (
        .data(asr), 
        .out(state[Nr]), 
        .key(round_key[Nr])
    );

    // Gán kết quả cuối cùng
    assign out = state[Nr]; 

endmodule
