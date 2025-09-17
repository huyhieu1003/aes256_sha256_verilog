module sender #(
    parameter N = 128,
    parameter Nr = 14,
    parameter nk = 8
)(
    input  wire         clk,
    input  wire         rstn,
    input  wire         start,
    input  wire [31:0]  id,
    input  wire [255:0] key,
    input  wire [7:0]   data,
    input  wire         valid,
    input  wire         last,
    output wire         done,
    output wire [63:0]  hash_sample,
    output wire [63:0]  enc_sample
);

// Internal signals
wire [255:0] full_hash;
wire [N-1:0] full_encrypted;

// ✅ SHA-256: Manual ID+Data combination
reg [7:0]  sha_data;
reg        sha_valid;
reg        sha_last;
reg [2:0]  id_byte_count;
reg        id_phase;
reg        processing;

// AES data collection (unchanged)
reg [N-1:0] aes_buffer;
reg [3:0]   byte_count;
reg         aes_data_ready;

// State tracking
reg         data_last_received;

// ==================== SHA-256 CONTROL LOGIC ====================
always @(posedge clk or negedge rstn) begin
    if (~rstn) begin
        sha_data <= 8'h00;
        sha_valid <= 1'b0;
        sha_last <= 1'b0;
        id_byte_count <= 3'b0;
        id_phase <= 1'b1;          // Start with ID phase
        processing <= 1'b0;
        data_last_received <= 1'b0;
    end else if (start) begin
        // Reset for new transaction
        id_byte_count <= 3'b0;
        id_phase <= 1'b1;
        processing <= 1'b1;
        sha_valid <= 1'b0;
        sha_last <= 1'b0;
        data_last_received <= 1'b0;
    end else if (processing) begin
        
        if (id_phase) begin
            // ✅ PHASE 1: Send ID bytes (big-endian)
            case (id_byte_count)
                3'b000: sha_data <= id[31:24];  // MSB first
                3'b001: sha_data <= id[23:16];
                3'b010: sha_data <= id[15:8];
                3'b011: sha_data <= id[7:0];    // LSB last
            endcase
            
            sha_valid <= 1'b1;
            sha_last <= 1'b0;
            
            if (id_byte_count == 3'b011) begin
                id_phase <= 1'b0;        // Switch to data phase
                id_byte_count <= 3'b0;
            end else begin
                id_byte_count <= id_byte_count + 1;
            end
            
        end else begin
            // ✅ PHASE 2: Send data bytes
            if (valid) begin
                sha_data <= data;
                sha_valid <= 1'b1;
                sha_last <= last;
                
                if (last) begin
                    data_last_received <= 1'b1;
                    processing <= 1'b0;
                end
            end else begin
                sha_valid <= 1'b0;
                sha_last <= 1'b0;
            end
        end
        
    end else begin
        sha_valid <= 1'b0;
        sha_last <= 1'b0;
    end
end

// ==================== AES DATA COLLECTION ====================
always @(posedge clk or negedge rstn) begin
    if (~rstn) begin
        aes_buffer <= {N{1'b0}};
        byte_count <= 4'b0;
        aes_data_ready <= 1'b0;
    end else if (start) begin
        byte_count <= 4'b0;
        aes_data_ready <= 1'b0;
        aes_buffer <= {N{1'b0}};
    end else if (valid && byte_count < 16) begin
        // ✅ Collect first 16 bytes for AES (little-endian)
        aes_buffer[(15-byte_count)*8 +: 8] <= data;
        byte_count <= byte_count + 1;
        
        if (byte_count == 15) begin
            aes_data_ready <= 1'b1;
        end
    end
end

// ==================== SHA-256 MODULE ====================
wire sha_ready, sha_out_valid;
wire [31:0] sha_out_id;
wire [60:0] sha_out_len;

sha256 sha_inst (
    .rstn(rstn),
    .clk(clk),
    .ready(sha_ready),
    .valid(sha_valid),        // ✅ Use manual combined stream
    .last(sha_last),          // ✅ Use manual last signal
    .id(32'h00000000),        // ✅ Not used - we handle manually
    .data(sha_data),          // ✅ Use manual combined data
    .out_valid(sha_out_valid),
    .out_id(sha_out_id),
    .out_len(sha_out_len),
    .out_hash(full_hash)
);

// ==================== AES MODULE ====================
AES_encrypt #(
    .N(N),
    .Nr(Nr),
    .nk(nk)
) aes_inst (
    .in(aes_buffer),
    .key(key),
    .out(full_encrypted)
);

// ==================== OUTPUT ASSIGNMENTS ====================
assign done = sha_out_valid && aes_data_ready;
assign hash_sample = full_hash[255:192];  // Top 64 bits
assign enc_sample = full_encrypted[N-1:N-64];  // Top 64 bits

endmodule

/*

module sender #(
parameter N = 128,        // AES block size
parameter Nr = 14,        // Number of rounds (14 for AES-256)
parameter nk = 8          // Key words (8 for AES-256)
)(
input  wire         clk,
input  wire         rstn,
input  wire         start,
input  wire [31:0]  id,           
input  wire [255:0] key,          
input  wire [7:0]   data,         
input  wire         valid,        
input  wire         last,         
output wire         done,         
output wire [63:0]  hash_sample,  
output wire [63:0]  enc_sample    
);

// Internal signals
wire [255:0] full_hash;      
wire [N-1:0] full_encrypted;     
reg  [N-1:0] aes_buffer;         
reg  [3:0]   byte_count;     
reg          aes_data_ready;
reg          processing;

// ==================== ✅ FIXED: AES DATA COLLECTION ====================
always @(posedge clk or negedge rstn) begin
if (~rstn) begin
    aes_buffer <= {N{1'b0}};     
    byte_count <= 4'b0;
    aes_data_ready <= 1'b0;
    processing <= 1'b0;
end else if (start) begin
    // ✅ FIX: Reset tất cả khi start
    byte_count <= 4'b0;
    aes_data_ready <= 1'b0;
    processing <= 1'b1;
    aes_buffer <= {N{1'b0}};     
end else if (processing && valid) begin
    // ✅ FIX: Chỉ lấy 16 bytes đầu tiên
    if (byte_count < 16) begin      
        // ✅ CRITICAL FIX: Sửa công thức index
        // Thay vì: aes_buffer[(15-byte_count)*8 +: 8] <= data;
        // Dùng:    aes_buffer[byte_count*8 +: 8] <= data;
        aes_buffer[byte_count*8 +: 8] <= data;
        byte_count <= byte_count + 1;
        
        // ✅ Đánh dấu ready khi đã có đủ 16 bytes
        if (byte_count == 15) begin  
            aes_data_ready <= 1'b1;
        end
    end
    // ✅ Bỏ qua tất cả bytes sau byte thứ 16
    
    // ✅ FIX: Kết thúc processing khi gặp last signal
    if (last) begin
        processing <= 1'b0;
    end
end
end

// SHA-256 module
wire sha_ready, sha_out_valid;
wire [31:0] sha_out_id;
wire [60:0] sha_out_len;

sha256 sha_inst (
.rstn(rstn), 
.clk(clk), 
.ready(sha_ready),
.valid(processing && valid), 
.last(last), 
.id(id), 
.data(data),
.out_valid(sha_out_valid), 
.out_id(sha_out_id), 
.out_len(sha_out_len), 
.out_hash(full_hash)
);

// AES module
AES_encrypt #(
.N(N),                
.Nr(Nr),              
.nk(nk)               
) aes_inst (
.in(aes_buffer),      
.key(key),            
.out(full_encrypted)  
);

// Output assignments
assign done = sha_out_valid && aes_data_ready;
assign hash_sample = full_hash[255:192];        
assign enc_sample = full_encrypted[N-1:N-64];   

endmodule
*/