module receiver #(
  parameter N = 128,
  parameter Nr = 14, 
  parameter nk = 8
)(
  input clk,
  input rstn,
  input start,
  input [31:0] id,
  input [255:0] key,
  input [7:0] ciphertext,
  input valid,
  input last,

  output reg done,
  output reg [63:0] dec_sample,
  output reg [63:0] hash_sample
);

  // ==================== STATE MACHINE ====================
  localparam IDLE = 3'b000;
  localparam RECEIVING = 3'b001;
  localparam DECRYPTING = 3'b010;
  localparam PREPARE_HASH = 3'b011;
  localparam HASHING = 3'b100;
  localparam COMPLETE = 3'b101;

  reg [2:0] state, next_state;

  // ==================== DATA STORAGE ====================
  reg [127:0] aes_buffer;
  reg [3:0] byte_count;
  reg [127:0] full_decrypted;
  reg [255:0] computed_hash;
  reg [159:0] sha_input_data;  // ✅ THÊM: Để testbench có thể access

  // ==================== AES DECRYPTION ====================
  wire [127:0] aes_plaintext;

  AES_decrypt #(
      .N(N),
      .Nr(Nr), 
      .nk(nk)
  ) aes_inst (
      .in(aes_buffer),
      .key(key),
      .out(aes_plaintext)
  );

  // ==================== SHA-256 HASHING ====================
  reg sha_data_valid;
  reg sha_last;
  reg [7:0] sha_data;
  reg [31:0] sha_id;
  reg sha_reset;

  wire sha_ready;
  wire sha_out_valid;
  wire [31:0] sha_out_id;
  wire [60:0] sha_out_len;
  wire [255:0] sha_out_hash;

  sha256 sha_inst (
      .rstn(rstn & ~sha_reset),
      .clk(clk),
      .ready(sha_ready),
      .valid(sha_data_valid),
      .last(sha_last),
      .id(sha_id),
      .data(sha_data),
      .out_valid(sha_out_valid),
      .out_id(sha_out_id),
      .out_len(sha_out_len),
      .out_hash(sha_out_hash)
  );

  // ==================== SHA FEEDING CONTROL ====================
  reg [4:0] sha_byte_count;
  reg sha_feeding;
  reg sha_start_feeding;

  // ==================== STATE MACHINE ====================
  always @(posedge clk or negedge rstn) begin
      if (!rstn) begin
          state <= IDLE;
      end else begin
          state <= next_state;
      end
  end

  always @(*) begin
      next_state = state;
      case (state)
          IDLE: begin
              if (start) next_state = RECEIVING;
          end
          
          RECEIVING: begin
              if (last && valid) next_state = DECRYPTING;
          end
          
          DECRYPTING: begin
              next_state = PREPARE_HASH;
          end
          
          PREPARE_HASH: begin
              next_state = HASHING;
          end
          
          HASHING: begin
              if (sha_out_valid && sha_out_id == sha_id) begin
                  next_state = COMPLETE;
              end
          end
          
          COMPLETE: begin
              next_state = IDLE;
          end
          
          default: next_state = IDLE;
      endcase
  end

  // ==================== DATA RECEIVING ====================
  always @(posedge clk or negedge rstn) begin
      if (!rstn) begin
          aes_buffer <= 128'b0;
          byte_count <= 4'b0;
      end else if (state == IDLE && start) begin
          aes_buffer <= 128'b0;
          byte_count <= 4'b0;
      end else if (state == RECEIVING && valid) begin
          aes_buffer <= {aes_buffer[119:0], ciphertext};
          byte_count <= byte_count + 1;
      end
  end

  // ==================== AES DECRYPTION CAPTURE ====================
  always @(posedge clk or negedge rstn) begin
      if (!rstn) begin
          full_decrypted <= 128'b0;
      end else if (state == DECRYPTING) begin
          full_decrypted <= aes_plaintext;
      end
  end

  // ==================== SHA RESET & INPUT PREPARATION ====================
  always @(posedge clk or negedge rstn) begin
      if (!rstn) begin
          sha_input_data <= 160'b0;
          sha_id <= 32'b0;
          sha_reset <= 1'b0;
          sha_start_feeding <= 1'b0;
      end else begin
          case (state)
              IDLE: begin
                  sha_reset <= 1'b1;
                  sha_start_feeding <= 1'b0;
              end
              
              PREPARE_HASH: begin
                  sha_reset <= 1'b0;
                  sha_input_data <= {id, full_decrypted};
                  sha_id <= id;
                  sha_start_feeding <= 1'b1;
              end
              
              HASHING: begin
                  sha_start_feeding <= 1'b0;
              end
              
              default: begin
                  sha_reset <= 1'b0;
                  sha_start_feeding <= 1'b0;
              end
          endcase
      end
  end

  // ==================== SHA FEEDING PROCESS ====================
  always @(posedge clk or negedge rstn) begin
      if (!rstn) begin
          sha_data <= 8'b0;
          sha_data_valid <= 1'b0;
          sha_last <= 1'b0;
          sha_byte_count <= 5'b0;
          sha_feeding <= 1'b0;
      end else begin
          case (state)
              HASHING: begin
                  if (!sha_feeding && sha_ready && sha_start_feeding) begin
                      sha_feeding <= 1'b1;
                      sha_byte_count <= 5'b0;
                      
                      sha_data <= sha_input_data[159:152];
                      sha_data_valid <= 1'b1;
                      sha_last <= 1'b0;
                      sha_byte_count <= 5'b1;
                      
                  end else if (sha_feeding && sha_ready) begin
                      if (sha_byte_count < 20) begin
                          sha_data <= sha_input_data[(159 - sha_byte_count*8) -: 8];
                          sha_data_valid <= 1'b1;
                          
                          if (sha_byte_count == 19) begin
                              sha_last <= 1'b1;
                              sha_feeding <= 1'b0;
                          end else begin
                              sha_last <= 1'b0;
                          end
                          
                          sha_byte_count <= sha_byte_count + 1;
                      end else begin
                          sha_data_valid <= 1'b0;
                          sha_last <= 1'b0;
                      end
                  end
              end
              
              default: begin
                  sha_data_valid <= 1'b0;
                  sha_last <= 1'b0;
                  sha_feeding <= 1'b0;
                  sha_byte_count <= 5'b0;
              end
          endcase
      end
  end

  // ==================== HASH CAPTURE ====================
  always @(posedge clk or negedge rstn) begin
      if (!rstn) begin
          computed_hash <= 256'b0;
      end else if (sha_out_valid && sha_out_id == sha_id) begin
          computed_hash <= sha_out_hash;
      end
  end

  // ==================== OUTPUT GENERATION ====================
  always @(posedge clk or negedge rstn) begin
      if (!rstn) begin
          done <= 1'b0;
          dec_sample <= 64'b0;
          hash_sample <= 64'b0;
      end else if (state == COMPLETE) begin
          done <= 1'b1;
          dec_sample <= full_decrypted[127:64];
          hash_sample <= computed_hash[255:192];
      end else if (state == IDLE) begin
          done <= 1'b0;
      end
  end

endmodule


/*
module receiver #(
  parameter N = 128,
  parameter Nr = 14, 
  parameter nk = 8
)(
  input clk,
  input rstn,
  input start,
  input [31:0] id,
  input [255:0] key,
  input [7:0] ciphertext,
  input valid,
  input last,
  output reg done,
  output reg [63:0] dec_sample,
  output reg [63:0] hash_sample
);

  // ==================== STATE MACHINE ====================
  localparam IDLE = 3'b000;
  localparam RECEIVING = 3'b001;
  localparam DECRYPTING = 3'b010;
  localparam PREPARE_HASH = 3'b011;
  localparam HASHING = 3'b100;
  localparam COMPLETE = 3'b101;
  
  reg [2:0] state, next_state;
  
  // ==================== DATA STORAGE ====================
  reg [127:0] aes_buffer;
  reg [3:0] byte_count;
  reg [127:0] full_decrypted;
  reg [255:0] computed_hash;
  
  // ==================== AES DECRYPTION ====================
  wire [127:0] aes_plaintext;
  
  AES_decrypt #(
      .N(N),
      .Nr(Nr), 
      .nk(nk)
  ) aes_inst (
      .in(aes_buffer),
      .key(key),
      .out(aes_plaintext)
  );
  
  // ==================== SHA-256 HASHING - ENHANCED ====================
  reg sha_data_valid;
  reg sha_last;
  reg [7:0] sha_data;
  reg [31:0] sha_id;
  reg sha_reset;  // ✅ Add SHA reset control
  
  wire sha_ready;
  wire sha_out_valid;
  wire [31:0] sha_out_id;
  wire [60:0] sha_out_len;
  wire [255:0] sha_out_hash;
  
  // ✅ SHA256 with reset control
  sha256 sha_inst (
      .rstn(rstn & ~sha_reset),   // ✅ Controlled reset
      .clk(clk),
      .ready(sha_ready),
      .valid(sha_data_valid),
      .last(sha_last),
      .id(sha_id),
      .data(sha_data),
      .out_valid(sha_out_valid),
      .out_id(sha_out_id),
      .out_len(sha_out_len),
      .out_hash(sha_out_hash)
  );
  
  // ==================== SHA FEEDING CONTROL ====================
  reg [4:0] sha_byte_count;
  reg sha_feeding;
  reg [159:0] sha_input_data;
  reg sha_start_feeding;  // ✅ Add feeding control
  
  // ==================== STATE MACHINE ====================
  always @(posedge clk or negedge rstn) begin
      if (!rstn) begin
          state <= IDLE;
      end else begin
          state <= next_state;
      end
  end
  
  always @(*) begin
      next_state = state;
      case (state)
          IDLE: begin
              if (start) next_state = RECEIVING;
          end
          
          RECEIVING: begin
              if (last && valid) next_state = DECRYPTING;
          end
          
          DECRYPTING: begin
              next_state = PREPARE_HASH;
          end
          
          PREPARE_HASH: begin
              next_state = HASHING;
          end
          
          HASHING: begin
              if (sha_out_valid && sha_out_id == sha_id) begin  // ✅ Check ID match
                  next_state = COMPLETE;
              end
          end
          
          COMPLETE: begin
              next_state = IDLE;
          end
          
          default: next_state = IDLE;
      endcase
  end
  
  // ==================== DATA RECEIVING ====================
  always @(posedge clk or negedge rstn) begin
      if (!rstn) begin
          aes_buffer <= 128'b0;
          byte_count <= 4'b0;
      end else if (state == IDLE && start) begin
          aes_buffer <= 128'b0;
          byte_count <= 4'b0;
      end else if (state == RECEIVING && valid) begin
          aes_buffer <= {aes_buffer[119:0], ciphertext};
          byte_count <= byte_count + 1;
      end
  end
  
  // ==================== AES DECRYPTION CAPTURE ====================
  always @(posedge clk or negedge rstn) begin
      if (!rstn) begin
          full_decrypted <= 128'b0;
      end else if (state == DECRYPTING) begin
          full_decrypted <= aes_plaintext;
      end
  end
  
  // ==================== SHA RESET & INPUT PREPARATION - ENHANCED ====================
  always @(posedge clk or negedge rstn) begin
      if (!rstn) begin
          sha_input_data <= 160'b0;
          sha_id <= 32'b0;
          sha_reset <= 1'b0;
          sha_start_feeding <= 1'b0;
      end else begin
          case (state)
              IDLE: begin
                  sha_reset <= 1'b1;  // ✅ Reset SHA when idle
                  sha_start_feeding <= 1'b0;
              end
              
              PREPARE_HASH: begin
                  sha_reset <= 1'b0;  // ✅ Release SHA reset
                  sha_input_data <= {id, full_decrypted};
                  sha_id <= id;
                  sha_start_feeding <= 1'b1;  // ✅ Signal to start feeding
              end
              
              HASHING: begin
                  sha_start_feeding <= 1'b0;  // ✅ Clear start signal
              end
              
              default: begin
                  sha_reset <= 1'b0;
                  sha_start_feeding <= 1'b0;
              end
          endcase
      end
  end
  
  // ==================== SHA FEEDING PROCESS - ENHANCED ====================
  always @(posedge clk or negedge rstn) begin
      if (!rstn) begin
          sha_data <= 8'b0;
          sha_data_valid <= 1'b0;
          sha_last <= 1'b0;
          sha_byte_count <= 5'b0;
          sha_feeding <= 1'b0;
      end else begin
          case (state)
              HASHING: begin
                  // ✅ Start feeding when SHA is ready and we have start signal
                  if (!sha_feeding && sha_ready && sha_start_feeding) begin
                      sha_feeding <= 1'b1;
                      sha_byte_count <= 5'b0;
                      
                      // Feed first byte
                      sha_data <= sha_input_data[159:152];
                      sha_data_valid <= 1'b1;
                      sha_last <= 1'b0;
                      sha_byte_count <= 5'b1;
                      
                  end else if (sha_feeding && sha_ready) begin
                      if (sha_byte_count < 20) begin
                          // Feed next byte
                          sha_data <= sha_input_data[(159 - sha_byte_count*8) -: 8];
                          sha_data_valid <= 1'b1;
                          
                          if (sha_byte_count == 19) begin
                              sha_last <= 1'b1;
                              sha_feeding <= 1'b0;
                          end else begin
                              sha_last <= 1'b0;
                          end
                          
                          sha_byte_count <= sha_byte_count + 1;
                      end else begin
                          sha_data_valid <= 1'b0;
                          sha_last <= 1'b0;
                      end
                  end else if (!sha_ready) begin
                      // ✅ Hold signals when SHA not ready
                      // Keep current values
                  end else begin
                      // Not feeding and no start signal
                      if (!sha_feeding) begin
                          sha_data_valid <= 1'b0;
                          sha_last <= 1'b0;
                      end
                  end
              end
              
              default: begin
                  sha_data_valid <= 1'b0;
                  sha_last <= 1'b0;
                  sha_feeding <= 1'b0;
                  sha_byte_count <= 5'b0;
              end
          endcase
      end
  end
  
  // ==================== HASH CAPTURE - ENHANCED ====================
  always @(posedge clk or negedge rstn) begin
      if (!rstn) begin
          computed_hash <= 256'b0;
      end else if (sha_out_valid && sha_out_id == sha_id) begin  // ✅ Check ID match
          computed_hash <= sha_out_hash;
      end
  end
  
  // ==================== OUTPUT GENERATION ====================
  always @(posedge clk or negedge rstn) begin
      if (!rstn) begin
          done <= 1'b0;
          dec_sample <= 64'b0;
          hash_sample <= 64'b0;
      end else if (state == COMPLETE) begin
          done <= 1'b1;
          dec_sample <= full_decrypted[127:64];
          hash_sample <= computed_hash[255:192];
      end else if (state == IDLE) begin
          done <= 1'b0;
      end
  end

endmodule
*/