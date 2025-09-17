`timescale 1ns/1ps

module tb_sender;

//===========================================================================================================
// TESTBENCH PARAMETERS
//===========================================================================================================

parameter MAX_DATA_SIZE = 1024;
parameter TIMEOUT_CYCLES = 50000;
parameter INPUT_FILE = "D:/HK242/DATN/Hardware/sender/data.txt";
parameter OUTPUT_FILE = "D:/HK242/DATN/Hardware/sender/output.txt";

//===========================================================================================================
// TESTBENCH SIGNALS
//===========================================================================================================

reg         clk, rstn, start;
reg  [31:0] id;
reg  [255:0] key;
reg  [7:0]  data;
reg         valid, last;

wire        done;
wire [63:0] hash_sample;   
wire [63:0] enc_sample;    

// ✅ INTERNAL ACCESS: Access full results via hierarchical reference
wire [255:0] full_hash;
wire [127:0] full_encrypted;

// Data handling
reg  [7:0]  original_data [0:MAX_DATA_SIZE-1];
reg  [31:0] original_length;
reg  [31:0] cycle_count;
reg         timeout_flag;
reg         file_read_done;

integer file_handle;
integer char_code;
integer i, j, k;

//===========================================================================================================
// DUT INSTANTIATION 
//===========================================================================================================

sender #(
  .N(128),
  .Nr(14),
  .nk(8)
) dut (
  .clk(clk),
  .rstn(rstn),
  .start(start),
  .id(id),
  .key(key),
  .data(data),
  .valid(valid),
  .last(last),
  .done(done),
  .hash_sample(hash_sample),    
  .enc_sample(enc_sample)       
);

// ✅ INTERNAL ACCESS: Get full results via hierarchical reference
assign full_hash = dut.full_hash;           
assign full_encrypted = dut.full_encrypted; 

//===========================================================================================================
// ✅ NEW: SHA-256 INPUT MONITORING
//===========================================================================================================

// Monitor SHA-256 input stream for debugging
always @(posedge clk) begin
  if (dut.sha_valid) begin
      if (dut.id_phase) begin
          $display("🔍 SHA-256 ID Byte[%0d]: 0x%02h", dut.id_byte_count, dut.sha_data);
      end else begin
          if (dut.sha_data >= 32 && dut.sha_data <= 126) begin
              $display("🔍 SHA-256 Data Byte: 0x%02h ('%c') %s", 
                       dut.sha_data, dut.sha_data, dut.sha_last ? "(LAST)" : "");
          end else begin
              $display("🔍 SHA-256 Data Byte: 0x%02h %s", 
                       dut.sha_data, dut.sha_last ? "(LAST)" : "");
          end
      end
  end
end

// Monitor processing phases
always @(posedge clk) begin
  if (dut.processing) begin
      if (dut.id_phase && dut.id_byte_count == 0 && dut.sha_valid) begin
          $display("🔄 SHA-256: Starting ID phase");
      end else if (!dut.id_phase && dut.sha_valid && dut.id_byte_count == 0) begin
          $display("🔄 SHA-256: Starting Data phase");
      end
  end
end

//===========================================================================================================
// CLOCK GENERATION
//===========================================================================================================

initial begin
  clk = 0;
  forever #5 clk = ~clk;
end

//===========================================================================================================
// TIMEOUT COUNTER
//===========================================================================================================

always @(posedge clk or negedge rstn) begin
  if (~rstn) begin
      cycle_count <= 32'b0;
      timeout_flag <= 1'b0;
  end else begin
      cycle_count <= cycle_count + 1;
      if (cycle_count > TIMEOUT_CYCLES && !done) begin
          timeout_flag <= 1'b1;
          $display("⚠️  TIMEOUT at cycle %0d", cycle_count);
      end
  end
end

//===========================================================================================================
// FILE READING TASK
//===========================================================================================================

task read_text_file;
  input [1023:0] filename;
  reg [7:0] current_char;
  begin
      $display("🔍 Reading TEXT file: %s", filename);
      
      file_handle = $fopen(filename, "r");
      if (file_handle == 0) begin
          file_handle = $fopen({"./", filename}, "r");
          if (file_handle == 0) begin
              $display("❌ ERROR: Cannot open file %s", filename);
              $finish;
          end
      end
      
      original_length = 0;
      
      while (!$feof(file_handle) && original_length < MAX_DATA_SIZE) begin
          char_code = $fgetc(file_handle);
          
          if (char_code != -1) begin
              current_char = char_code[7:0];
              
              if (current_char != 8'h0D) begin  // Skip carriage return
                  original_data[original_length] = current_char;
                  original_length = original_length + 1;
              end
          end
      end
      
      $fclose(file_handle);
      $display("✅ Read %0d bytes from file", original_length);
      
      // Display original data
      $write("📝 Original data: \"");
      for (i = 0; i < original_length && i < 50; i = i + 1) begin
          if (original_data[i] >= 8'h20 && original_data[i] <= 8'h7E) begin
              $write("%c", original_data[i]);
          end else begin
              $write("\\x%02h", original_data[i]);
          end
      end
      if (original_length > 50) $write("...");
      $display("\"");
      
      file_read_done = 1;
  end
endtask

//===========================================================================================================
// ✅ UPDATED: DATA TRANSMISSION - COMPATIBLE WITH NEW SENDER LOGIC
//===========================================================================================================

task send_data_stream;
  begin
      $display("🚀 Sending data stream to DUT...");
      $display("   📊 Expected SHA-256 Input Sequence:");
      $display("      1. ID bytes: %02h %02h %02h %02h", 
               id[31:24], id[23:16], id[15:8], id[7:0]);
      $display("      2. Data bytes: %0d bytes", original_length);
      $display("   📊 AES-256 will process: First 16 bytes of data");
      
      // ✅ Wait for sender to be ready for data
      wait (dut.processing && !dut.id_phase);
      $display("✅ Sender ready for data input");
      
      // Send data stream
      for (i = 0; i < original_length; i = i + 1) begin
          @(posedge clk);
          data = original_data[i];
          valid = 1;
          last = (i == original_length - 1) ? 1 : 0;
          
          // Show progress for first/last few bytes
          if (i < 5 || i >= original_length - 5) begin
              if (original_data[i] >= 8'h20 && original_data[i] <= 8'h7E) begin
                  $display("   📤 Data[%0d] = 0x%02h ('%c') %s", 
                           i, data, data, last ? "(LAST)" : "");
              end else begin
                  $display("   📤 Data[%0d] = 0x%02h %s", 
                           i, data, last ? "(LAST)" : "");
              end
          end else if (i == 5 && original_length > 10) begin
              $display("   📤 ... (sending %0d more bytes) ...", original_length - 10);
          end
      end
      
      @(posedge clk);
      valid = 0;
      last = 0;
      
      $display("✅ Data transmission completed (%0d bytes)", original_length);
  end
endtask

//===========================================================================================================
// ✅ ENHANCED: RESULT VERIFICATION WITH EXPECTED VALUES
//===========================================================================================================

task verify_results;
  begin
      $display("🔍 VERIFYING RESULTS...");
      
      // ✅ Display expected SHA-256 input for manual verification
      $display("📊 Expected SHA-256 Processing:");
      $display("   Combined Input: ID + Data = %0d bytes total", 4 + original_length);
      
      $write("   Expected hex sequence: ");
      // ID bytes (big-endian)
      $write("%02h%02h%02h%02h", id[31:24], id[23:16], id[15:8], id[7:0]);
      // Data bytes (first 20 for display)
      for (i = 0; i < original_length && i < 20; i = i + 1) begin
          $write("%02h", original_data[i]);
      end
      if (original_length > 20) $write("...");
      $display("");
      
      // ✅ Display expected AES input
      $display("📊 Expected AES-256 Processing:");
      $write("   First 16 bytes (hex): ");
      for (i = 0; i < 16 && i < original_length; i = i + 1) begin
          $write("%02h", original_data[i]);
      end
      $display("");
      
      // ✅ Basic sanity checks
      if (full_hash == 256'h0) begin
          $display("❌ ERROR: SHA-256 hash is zero!");
      end else begin
          $display("✅ SHA-256 hash is non-zero");
      end
      
      if (full_encrypted == 128'h0) begin
          $display("❌ ERROR: AES-256 encryption is zero!");
      end else begin
          $display("✅ AES-256 encryption is non-zero");
      end
      
      // ✅ Check if samples match full results
      if (hash_sample == full_hash[255:192]) begin
          $display("✅ Hash sample matches top 64 bits of full hash");
      end else begin
          $display("❌ Hash sample mismatch!");
      end
      
      if (enc_sample == full_encrypted[127:64]) begin
          $display("✅ Encryption sample matches top 64 bits of full encryption");
      end else begin
          $display("❌ Encryption sample mismatch!");
      end
  end
endtask

//===========================================================================================================
// ✅ ENHANCED: RESULT WRITING WITH EXPECTED VALUES
//===========================================================================================================

task write_results_file;
  input [1023:0] filename;
  begin
      $display("📝 Writing results to: %s", filename);
      
      file_handle = $fopen(filename, "w");
      if (file_handle == 0) begin
          file_handle = $fopen({"./", filename}, "w");
      end
      
      if (file_handle != 0) begin
          $fwrite(file_handle, "=====================================\n");
          $fwrite(file_handle, "   SENDER MODULE TEST RESULTS        \n");
          $fwrite(file_handle, "   ✅ FIXED VERSION - MANUAL ID+DATA \n");
          $fwrite(file_handle, "=====================================\n\n");
          
          // Configuration
          $fwrite(file_handle, "=== CONFIGURATION ===\n");
          $fwrite(file_handle, "ID:  0x%08h\n", id);
          $fwrite(file_handle, "Key: 0x%064h\n", key);
          $fwrite(file_handle, "Data length: %0d bytes\n", original_length);
          $fwrite(file_handle, "\n");
          
          // Processing info
          $fwrite(file_handle, "=== PROCESSING INFO ===\n");
          $fwrite(file_handle, "Status: %s\n", done ? "COMPLETED" : "FAILED/TIMEOUT");
          $fwrite(file_handle, "Processing cycles: %0d\n", cycle_count);
          $fwrite(file_handle, "Processing time: %.2f us (@ 100MHz)\n", cycle_count * 0.01);
          $fwrite(file_handle, "SHA-256 processes: ID + Data = %0d bytes\n", 4 + original_length);
          $fwrite(file_handle, "AES-256 processes: First 16 bytes of data\n");
          $fwrite(file_handle, "\n");
          
          // ✅ Expected inputs for verification
          $fwrite(file_handle, "=== EXPECTED INPUTS (for manual verification) ===\n");
          $fwrite(file_handle, "SHA-256 Expected Input Sequence:\n");
          $fwrite(file_handle, "  ID bytes (big-endian): %02h %02h %02h %02h\n", 
                  id[31:24], id[23:16], id[15:8], id[7:0]);
          
          $fwrite(file_handle, "  Data bytes: ");
          for (i = 0; i < original_length && i < 32; i = i + 1) begin
              $fwrite(file_handle, "%02h ", original_data[i]);
          end
          if (original_length > 32) $fwrite(file_handle, "...");
          $fwrite(file_handle, "\n");
          
          $fwrite(file_handle, "  Combined hex for manual SHA-256: ");
          $fwrite(file_handle, "%02h%02h%02h%02h", id[31:24], id[23:16], id[15:8], id[7:0]);
          for (i = 0; i < original_length && i < 28; i = i + 1) begin
              $fwrite(file_handle, "%02h", original_data[i]);
          end
          if (original_length > 28) $fwrite(file_handle, "...");
          $fwrite(file_handle, "\n\n");
          
          $fwrite(file_handle, "AES-256 Expected Input (first 16 bytes):\n");
          $fwrite(file_handle, "  ");
          for (i = 0; i < 16 && i < original_length; i = i + 1) begin
              $fwrite(file_handle, "%02h ", original_data[i]);
          end
          $fwrite(file_handle, "\n\n");
          
          // Results - I/O outputs
          $fwrite(file_handle, "=== I/O OUTPUTS (64-bit samples) ===\n");
          $fwrite(file_handle, "SHA-256 Hash Sample:  0x%016h\n", hash_sample);
          $fwrite(file_handle, "AES-256 Enc Sample:   0x%016h\n", enc_sample);
          $fwrite(file_handle, "\n");
          
          // Results - Internal full outputs  
          $fwrite(file_handle, "=== INTERNAL FULL OUTPUTS ===\n");
          $fwrite(file_handle, "Full SHA-256 Hash (256-bit):\n");
          $fwrite(file_handle, "0x%064h\n", full_hash);
          $fwrite(file_handle, "\n");
          
          $fwrite(file_handle, "Full AES-256 Encrypted (128-bit):\n");
          $fwrite(file_handle, "0x%032h\n", full_encrypted);
          $fwrite(file_handle, "\n");
          
          $fwrite(file_handle, "=====================================\n");
          
          $fclose(file_handle);
          $display("✅ Results written successfully");
      end else begin
          $display("❌ Failed to write results file");
      end
  end
endtask

//===========================================================================================================
// ✅ UPDATED: MAIN TEST SEQUENCE
//===========================================================================================================

initial begin
  $display("🚀 FIXED SENDER TESTBENCH - MANUAL ID+DATA COMBINATION");
  $display("=====================================================");

  // Initialize
  rstn = 0;
  start = 0;
  valid = 0;
  last = 0;
  data = 8'h00;
  file_read_done = 0;
  timeout_flag = 0;

  // Test configuration
  id = 32'hABCD1234;
  key = 256'h603DEB1015CA71BE2B73AEF0857D77811F352C073B6108D72D9810A30914DFF4;

  $display("🔧 Configuration:");
  $display("   ID: 0x%08h", id);
  $display("   Key: 0x%064h", key);

  // Reset
  #20;
  rstn = 1;
  $display("✅ Reset completed");

  // Read input file
  read_text_file(INPUT_FILE);

  if (!file_read_done || original_length == 0) begin
      $display("❌ ERROR: File reading failed");
      $finish;
  end

  // Wait for modules to stabilize
  #50;

  // Start processing
  $display("🚀 Starting processing...");
  start = 1;
  #10;
  start = 0;

  // Send data stream (will wait for ID phase to complete)
  fork
      send_data_stream();
  join

  // Wait for completion
  $display("⏳ Waiting for processing completion...");
  while (~done && ~timeout_flag) begin
      @(posedge clk);
      if (cycle_count % 1000 == 0) begin
          $display("   Waiting... cycle %0d", cycle_count);
      end
  end

  // Results
  if (done) begin
      $display("🎉 PROCESSING COMPLETED SUCCESSFULLY!");
      
      // ✅ Verify results
      verify_results();
      
      $display("📊 Results Summary:");
      $display("   I/O Outputs (64-bit samples):");
      $display("     SHA-256 Hash Sample:  0x%016h", hash_sample);
      $display("     AES-256 Enc Sample:   0x%016h", enc_sample);
      $display("   Internal Full Results:");
      $display("     Full SHA-256 Hash:    0x%064h", full_hash);
      $display("     Full AES-256 Encrypt: 0x%032h", full_encrypted);
      $display("   Processing cycles:      %0d", cycle_count);
      
      write_results_file(OUTPUT_FILE);
      
  end else if (timeout_flag) begin
      $display("❌ ERROR: Timeout after %0d cycles", cycle_count);
  end

  #100;
  $display("✅ TESTBENCH COMPLETED");
  $finish;
end

//===========================================================================================================
// WAVEFORM DUMP
//===========================================================================================================

initial begin
  $dumpfile("sender_fixed_simulation.vcd");
  $dumpvars(0, tb_sender);
end

endmodule



