`timescale 1ns / 1ps

module tb_receiver;

  // ==================== PARAMETERS ====================
  parameter N = 128;
  parameter Nr = 14;
  parameter nk = 8;
  parameter CLK_PERIOD = 10;

  // ==================== TEST DATA ====================
  parameter [31:0] TEST_ID = 32'habcd1234;
  parameter [255:0] TEST_KEY = 256'h603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4;

  // ==================== SIGNALS ====================
  reg clk;
  reg rstn;
  reg start;
  reg [31:0] id;
  reg [255:0] key;
  reg [7:0] ciphertext;
  reg valid;
  reg last;
  
  wire done;
  wire [63:0] dec_sample;
  wire [63:0] hash_sample;

  // ==================== DATA STORAGE ====================
  reg [127:0] test_ciphertext;
  reg [127:0] captured_plaintext;
  reg [255:0] captured_hash;
  reg [159:0] captured_sha_input;
  reg [255:0] loaded_expected_hash;  // Lưu expected hash từ file
  
  // ✅ FIXED: Thay đổi từ wire sang reg để có thể gán giá trị
  reg hash_match_internal;
  reg verification_done_internal;
  
  // ASCII conversion results
  reg [8*16:1] ascii_plaintext;      // 16 characters max
  reg [8*32:1] hex_plaintext;        // Hex representation
  
  // File handles
  integer input_file, hash_file, output_file;
  integer scan_result;

  // ==================== CLOCK GENERATION ====================
  initial begin
      clk = 0;
      forever #(CLK_PERIOD/2) clk = ~clk;
  end

  // ==================== DUT INSTANTIATION - SIMPLIFIED ====================
  receiver #(
      .N(N),
      .Nr(Nr),
      .nk(nk)
  ) dut (
      .clk(clk),
      .rstn(rstn),
      .start(start),
      .id(id),
      .key(key),
      .ciphertext(ciphertext),
      .valid(valid),
      .last(last),
      .done(done),
      .dec_sample(dec_sample),
      .hash_sample(hash_sample)
  );

  // ==================== TASK: READ CIPHERTEXT ====================
  task read_ciphertext;
      begin
          $display("=== READING CIPHERTEXT ===");
          
          input_file = $fopen("D:/HK242/DATN/Hardware/receiver/ciphertext.txt", "r");
          if (input_file == 0) input_file = $fopen("ciphertext.txt", "r");
          
          if (input_file != 0) begin
              scan_result = $fscanf(input_file, "%h", test_ciphertext);
              if (scan_result == 1 && test_ciphertext != 0) begin
                  $display("✅ Ciphertext from file: %h", test_ciphertext);
              end else begin
                  test_ciphertext = 128'hfedcba9876543210fedcba9876543210;
                  $display("⚠️ Using fallback: %h", test_ciphertext);
              end
              $fclose(input_file);
          end else begin
              test_ciphertext = 128'hfedcba9876543210fedcba9876543210;
              $display("⚠️ File not found, using fallback: %h", test_ciphertext);
          end
          
          $display("==========================");
      end
  endtask

  // ==================== TASK: READ EXPECTED HASH ====================
  task read_expected_hash;
      begin
          $display("=== READING EXPECTED HASH ===");
          
          hash_file = $fopen("D:/HK242/DATN/Hardware/receiver/expected_hash.txt", "r");
          if (hash_file == 0) hash_file = $fopen("expected_hash.txt", "r");
          
          if (hash_file != 0) begin
              scan_result = $fscanf(hash_file, "%h", loaded_expected_hash);
              if (scan_result == 1) begin
                  $display("✅ Expected hash from file: %064h", loaded_expected_hash);
              end else begin
                  loaded_expected_hash = 256'h0;
                  $display("⚠️ Cannot read hash, using zero: %064h", loaded_expected_hash);
              end
              $fclose(hash_file);
          end else begin
              loaded_expected_hash = 256'h0;
              $display("⚠️ Hash file not found, using zero: %064h", loaded_expected_hash);
          end
          
          $display("=============================");
      end
  endtask

  // ==================== TASK: SEND CIPHERTEXT ====================
  task send_ciphertext;
      input [127:0] cipher_data;
      integer i;
      begin
          $display("=== SENDING CIPHERTEXT ===");
          
          for (i = 15; i >= 0; i = i - 1) begin
              @(posedge clk);
              ciphertext = cipher_data[(i*8) +: 8];
              valid = 1'b1;
              last = (i == 0) ? 1'b1 : 1'b0;
              
              $display("  Sending byte %02d: 0x%02h", 15-i, ciphertext);
              
              @(posedge clk);
              valid = 1'b0;
              if (i == 0) last = 1'b0;
          end
          
          $display("✅ Ciphertext sent successfully");
          $display("=========================");
      end
  endtask

  // ==================== TASK: WAIT FOR COMPLETION ====================
  task wait_for_completion;
      integer timeout;
      begin
          $display("=== WAITING FOR COMPLETION ===");
          
          timeout = 0;
          while (!done && timeout < 10000) begin
              @(posedge clk);
              timeout = timeout + 1;
              
              if (timeout % 500 == 0) begin
                  $display("  Processing... cycle %0d", timeout);
                  $display("    Current state: %0d", dut.state);
              end
          end
          
          if (done) begin
              $display("✅ Processing completed in %0d cycles", timeout);
              
              // Capture từ receiver internal signals
              captured_plaintext = dut.full_decrypted;
              captured_hash = dut.computed_hash;
              captured_sha_input = dut.sha_input_data;
              
              // ✅ FIXED: Cập nhật giá trị hash verification sau khi có dữ liệu
              hash_match_internal = (captured_hash == loaded_expected_hash);
              verification_done_internal = 1'b1;
              
              // Debug information
              $display("=== CAPTURE DEBUG ===");
              $display("dec_sample:        0x%016h", dec_sample);
              $display("hash_sample:       0x%016h", hash_sample);  
              $display("full_decrypted:    0x%032h", dut.full_decrypted);
              $display("computed_hash:     0x%064h", dut.computed_hash);
              $display("sha_input_data:    0x%040h", dut.sha_input_data);
              $display("expected_hash:     0x%064h", loaded_expected_hash);
              $display("hash_match:        %0b", hash_match_internal);
              $display("verification_done: %0b", verification_done_internal);
              $display("====================");
              
          end else begin
              $display("❌ Timeout after %0d cycles", timeout);
              // Still capture what we can for debugging
              captured_plaintext = dut.full_decrypted;
              captured_hash = dut.computed_hash;
              captured_sha_input = dut.sha_input_data;
              
              // ✅ FIXED: Set verification status for timeout case
              hash_match_internal = 1'b0;
              verification_done_internal = 1'b0;
          end
          
          $display("==============================");
      end
  endtask

  // ==================== TASK: VERIFY HASH CALCULATION ====================
  task verify_hash_calculation;
      reg [159:0] expected_sha_input;
      begin
          $display("=== HASH VERIFICATION ===");
          
          // Expected SHA input: {id, plaintext}
          expected_sha_input = {TEST_ID, captured_plaintext};
          
          $display("Expected SHA input: 0x%040h", expected_sha_input);
          $display("Actual SHA input:   0x%040h", captured_sha_input);
          
          if (captured_sha_input == expected_sha_input) begin
              $display("✅ SHA INPUT CORRECT");
          end else begin
              $display("❌ SHA INPUT MISMATCH!");
              $display("  Expected ID:      0x%08h", TEST_ID);
              $display("  Expected Plain:   0x%032h", captured_plaintext);
              $display("  Actual combined:  0x%040h", captured_sha_input);
          end
          
          $display("Computed hash:      0x%064h", captured_hash);
          $display("Expected hash:      0x%064h", loaded_expected_hash);
          $display("Hash sample (top):  0x%016h", hash_sample);
          
          // Internal hash verification
          $display("Internal Hash Match: %0b", hash_match_internal);
          $display("Internal Verification: %0b", verification_done_internal);
          
          // Manual verification
          if (captured_hash == loaded_expected_hash) begin
              $display("✅ MANUAL HASH VERIFICATION: MATCH");
          end else begin
              $display("❌ MANUAL HASH VERIFICATION: MISMATCH");
          end
          
          // Verify hash sample matches top bits
          if (hash_sample == captured_hash[255:192]) begin
              $display("✅ HASH SAMPLE MATCHES TOP BITS");
          end else begin
              $display("❌ HASH SAMPLE MISMATCH!");
              $display("  Expected: 0x%016h", captured_hash[255:192]);
              $display("  Actual:   0x%016h", hash_sample);
          end
          
          // Verify dec sample matches top bits of plaintext
          if (dec_sample == captured_plaintext[127:64]) begin
              $display("✅ DEC SAMPLE MATCHES TOP BITS");
          end else begin
              $display("❌ DEC SAMPLE MISMATCH!");
              $display("  Expected: 0x%016h", captured_plaintext[127:64]);
              $display("  Actual:   0x%016h", dec_sample);
          end
          
          $display("=========================");
      end
  endtask

  // ==================== TASK: CONVERT TO ASCII ====================
  task convert_plaintext_to_ascii;
      input [127:0] plaintext_data;
      integer i;
      reg [7:0] current_byte;
      reg [8*3:1] hex_byte;
      begin
          $display("=== ASCII CONVERSION ===");
          
          // Initialize strings
          ascii_plaintext = "";
          hex_plaintext = "";
          
          $display("Plaintext hex: %h", plaintext_data);
          $display("Byte-by-byte conversion:");
          
          // Process each byte (MSB first)
          for (i = 15; i >= 0; i = i - 1) begin
              current_byte = plaintext_data[(i*8) +: 8];
              
              // Create hex representation
              $sformat(hex_byte, "%02h", current_byte);
              hex_plaintext = {hex_plaintext[8*29:1], hex_byte};
              
              // ASCII conversion
              if (current_byte >= 8'h20 && current_byte <= 8'h7E) begin
                  // Printable ASCII character
                  ascii_plaintext = {ascii_plaintext[8*15:1], current_byte};
                  $display("  Byte %02d: 0x%02h = '%c' (printable)", 15-i, current_byte, current_byte);
              end else if (current_byte == 8'h00) begin
                  // NULL character
                  ascii_plaintext = {ascii_plaintext[8*15:1], 8'h20}; // Space
                  $display("  Byte %02d: 0x%02h = NULL (replaced with space)", 15-i, current_byte);
              end else if (current_byte == 8'h0A) begin
                  // Line feed
                  ascii_plaintext = {ascii_plaintext[8*15:1], 8'h5C}; // '\'
                  $display("  Byte %02d: 0x%02h = LF (replaced with \\)", 15-i, current_byte);
              end else if (current_byte == 8'h0D) begin
                  // Carriage return
                  ascii_plaintext = {ascii_plaintext[8*15:1], 8'h5C}; // '\'
                  $display("  Byte %02d: 0x%02h = CR (replaced with \\)", 15-i, current_byte);
              end else begin
                  // Non-printable character
                  ascii_plaintext = {ascii_plaintext[8*15:1], 8'h2E}; // '.'
                  $display("  Byte %02d: 0x%02h = non-printable (replaced with .)", 15-i, current_byte);
              end
          end
          
          $display("");
          $display("ASCII Result: '%s'", ascii_plaintext);
          $display("Hex String:   %s", hex_plaintext);
          $display("========================");
      end
  endtask

  // ==================== TASK: ANALYZE PLAINTEXT CONTENT ====================
  task analyze_plaintext_content;
      integer i;
      reg [7:0] current_byte;
      integer printable_count, null_count, control_count;
      begin
          $display("=== PLAINTEXT CONTENT ANALYSIS ===");
          
          printable_count = 0;
          null_count = 0;
          control_count = 0;
          
          for (i = 15; i >= 0; i = i - 1) begin
              current_byte = captured_plaintext[(i*8) +: 8];
              
              if (current_byte >= 8'h20 && current_byte <= 8'h7E) begin
                  printable_count = printable_count + 1;
              end else if (current_byte == 8'h00) begin
                  null_count = null_count + 1;
              end else begin
                  control_count = control_count + 1;
              end
          end
          
          $display("Content Statistics:");
          $display("  Printable characters: %0d/16", printable_count);
          $display("  NULL bytes:          %0d/16", null_count);
          $display("  Control characters:  %0d/16", control_count);
          
          if (printable_count >= 8) begin
              $display("✅ Likely contains readable text");
          end else if (null_count >= 8) begin
              $display("⚠️ Many NULL bytes - possible padding");
          end else begin
              $display("❓ Mixed content - may be binary data");
          end
          
          $display("==================================");
      end
  endtask

  // ==================== TASK: WRITE DATA_OUTPUT FILE ====================
  task write_data_output;
      integer i;
      reg [7:0] current_byte;
      begin
          $display("=== WRITING DATA_OUTPUT FILE ===");
          
          output_file = $fopen("D:/HK242/DATN/Hardware/receiver/data_output.txt", "w");
          if (output_file == 0) output_file = $fopen("data_output.txt", "w");
          
          if (output_file != 0) begin
              // Header
              $fwrite(output_file, "========================================\n");
              $fwrite(output_file, "  RECEIVER HASH VERIFICATION RESULTS\n");
              $fwrite(output_file, "========================================\n");
              $fwrite(output_file, "Test Time: %0t ns\n", $time);
              $fwrite(output_file, "Status: %s\n\n", done ? "SUCCESS" : "FAILED");
              
              // Input Section
              $fwrite(output_file, "--- INPUT DATA ---\n");
              $fwrite(output_file, "ID:             0x%08h\n", TEST_ID);
              $fwrite(output_file, "Key:            0x%064h\n", TEST_KEY);
              $fwrite(output_file, "Ciphertext:     0x%032h\n", test_ciphertext);
              $fwrite(output_file, "Expected Hash:  0x%064h\n\n", loaded_expected_hash);
              
              // Processing Results
              $fwrite(output_file, "--- PROCESSING RESULTS ---\n");
              $fwrite(output_file, "Processing Status: %s\n", done ? "COMPLETED" : "FAILED");
              $fwrite(output_file, "Dec Sample:       0x%016h\n", dec_sample);
              $fwrite(output_file, "Hash Sample:      0x%016h\n", hash_sample);
              $fwrite(output_file, "Full Plaintext:   0x%032h\n", captured_plaintext);
              $fwrite(output_file, "Computed Hash:    0x%064h\n\n", captured_hash);
              
              // ✅ FIXED: HASH VERIFICATION SECTION - DETAILED
              $fwrite(output_file, "--- HASH VERIFICATION ---\n");
              $fwrite(output_file, "Expected SHA Input: 0x%040h\n", {TEST_ID, captured_plaintext});
              $fwrite(output_file, "Actual SHA Input:   0x%040h\n", captured_sha_input);
              $fwrite(output_file, "SHA Input Match:    %s\n", 
                  (captured_sha_input == {TEST_ID, captured_plaintext}) ? "YES" : "NO");
              $fwrite(output_file, "Expected Hash:      0x%064h\n", loaded_expected_hash);
              $fwrite(output_file, "Computed Hash:      0x%064h\n", captured_hash);
              $fwrite(output_file, "Hash Match (Internal): %s\n", hash_match_internal ? "YES" : "NO");
              $fwrite(output_file, "Hash Match (Manual):   %s\n", 
                  (captured_hash == loaded_expected_hash) ? "YES" : "NO");
              $fwrite(output_file, "Verification Done:     %s\n", verification_done_internal ? "YES" : "NO");
              
              // ✅ HASH COMPARISON DETAILS
              if (captured_hash != loaded_expected_hash) begin
                  $fwrite(output_file, "\n--- HASH MISMATCH ANALYSIS ---\n");
                  $fwrite(output_file, "Computed: 0x%064h\n", captured_hash);
                  $fwrite(output_file, "Expected: 0x%064h\n", loaded_expected_hash);
                  $fwrite(output_file, "XOR Diff: 0x%064h\n", captured_hash ^ loaded_expected_hash);
                  
                  // Bit-by-bit analysis
                  for (i = 255; i >= 0; i = i - 1) begin
                      if (captured_hash[i] != loaded_expected_hash[i]) begin
                          $fwrite(output_file, "Bit %03d differs: computed=%b, expected=%b\n", 
                              i, captured_hash[i], loaded_expected_hash[i]);
                      end
                  end
              end else begin
                  $fwrite(output_file, "\n✅ HASH MATCH: All 256 bits identical\n");
              end
              $fwrite(output_file, "\n");
              
              // ASCII Conversion Section
              $fwrite(output_file, "--- ASCII CONVERSION ---\n");
              $fwrite(output_file, "ASCII Text:       '%s'\n", ascii_plaintext);
              $fwrite(output_file, "Hex String:       %s\n\n", hex_plaintext);
              
              // Detailed Byte Analysis
              $fwrite(output_file, "--- BYTE-BY-BYTE ANALYSIS ---\n");
              for (i = 15; i >= 0; i = i - 1) begin
                  current_byte = captured_plaintext[(i*8) +: 8];
                  $fwrite(output_file, "Byte %02d: 0x%02h", 15-i, current_byte);
                  
                  if (current_byte >= 8'h20 && current_byte <= 8'h7E) begin
                      $fwrite(output_file, " = '%c' (printable)\n", current_byte);
                  end else if (current_byte == 8'h00) begin
                      $fwrite(output_file, " = NULL\n");
                  end else if (current_byte == 8'h0A) begin
                      $fwrite(output_file, " = LF (Line Feed)\n");
                  end else if (current_byte == 8'h0D) begin
                      $fwrite(output_file, " = CR (Carriage Return)\n");
                  end else begin
                      $fwrite(output_file, " = non-printable (control: %0d)\n", current_byte);
                  end
              end
              
              // ✅ FIXED: COMPREHENSIVE VERIFICATION SUMMARY
              $fwrite(output_file, "\n--- VERIFICATION SUMMARY ---\n");
              $fwrite(output_file, "Decryption:       %s\n", done ? "SUCCESS" : "FAILED");
              $fwrite(output_file, "SHA Input:        %s\n", 
                  (captured_sha_input == {TEST_ID, captured_plaintext}) ? "CORRECT" : "INCORRECT");
              $fwrite(output_file, "Dec Sample:       %s\n", 
                  (dec_sample == captured_plaintext[127:64]) ? "CORRECT" : "INCORRECT");
              $fwrite(output_file, "Hash Sample:      %s\n", 
                  (hash_sample == captured_hash[255:192]) ? "CORRECT" : "INCORRECT");
              $fwrite(output_file, "Hash Verification: %s\n", 
                  hash_match_internal ? "PASSED" : "FAILED");
              $fwrite(output_file, "ASCII Readable:   %s\n", ascii_plaintext != "" ? "YES" : "NO");
              $fwrite(output_file, "Overall Result:   %s\n", 
                  (done && hash_match_internal && verification_done_internal) ? "✅ PASS" : "❌ FAIL");
              
              // ✅ FIXED: FINAL STATUS
              $fwrite(output_file, "\n--- FINAL STATUS ---\n");
              if (done && hash_match_internal && verification_done_internal) begin
                  $fwrite(output_file, "🎉 TEST PASSED: All verifications successful\n");
                  $fwrite(output_file, "   - Decryption completed successfully\n");
                  $fwrite(output_file, "   - Hash computation correct\n");
                  $fwrite(output_file, "   - Hash verification passed\n");
                  $fwrite(output_file, "   - All samples match expected values\n");
              end else begin
                  $fwrite(output_file, "❌ TEST FAILED: One or more verifications failed\n");
                  if (!done) $fwrite(output_file, "   - Decryption did not complete\n");
                  if (!hash_match_internal) $fwrite(output_file, "   - Hash verification failed\n");
                  if (!verification_done_internal) $fwrite(output_file, "   - Verification process incomplete\n");
              end
              
              $fwrite(output_file, "\n========================================\n");
              $fclose(output_file);
              $display("✅ Complete results written to data_output.txt");
          end else begin
              $display("❌ Cannot create data_output.txt file");
          end
          
          $display("====================================");
      end
  endtask

  // ==================== MAIN TEST SEQUENCE ====================
  initial begin
      $display("========================================");
      $display("  OPTIMIZED RECEIVER TESTBENCH START");
      $display("========================================");
      
      // ✅ FIXED: Initialize verification signals
      hash_match_internal = 1'b0;
      verification_done_internal = 1'b0;
      
      // Initialize all signals
      rstn = 1'b0;
      start = 1'b0;
      id = 32'b0;
      key = 256'b0;
      ciphertext = 8'b0;
      valid = 1'b0;
      last = 1'b0;
      
      // Reset sequence
      #(CLK_PERIOD * 5);
      rstn = 1'b1;
      #(CLK_PERIOD * 3);
      
      // Read test data
      read_ciphertext();
      read_expected_hash();
      
      // Configure DUT
      id = TEST_ID;
      key = TEST_KEY;
      
      $display("=== TEST CONFIGURATION ===");
      $display("ID:            0x%08h", TEST_ID);
      $display("Key:           0x%064h", TEST_KEY);
      $display("Ciphertext:    0x%032h", test_ciphertext);
      $display("Expected Hash: 0x%064h", loaded_expected_hash);
      $display("==============================");
      
      // Start processing
      @(posedge clk);
      start = 1'b1;
      @(posedge clk);
      start = 1'b0;
      
      // Wait before sending data
      repeat(5) @(posedge clk);
      
      // Send ciphertext to DUT
      send_ciphertext(test_ciphertext);
      
      // Wait for processing completion
      wait_for_completion();
      
      // Verify hash calculation
      verify_hash_calculation();
      
      // Convert plaintext to ASCII
      convert_plaintext_to_ascii(captured_plaintext);
      
      // Analyze plaintext content
      analyze_plaintext_content();
      
      // ✅ Write data_output file with hash comparison results
      write_data_output();
      
      // Final summary
      $display("========================================");
      $display("         FINAL TEST SUMMARY");
      $display("========================================");
      $display("Processing Status:    %s", done ? "✅ SUCCESS" : "❌ FAILED");
      $display("Plaintext (hex):      %032h", captured_plaintext);
      $display("Plaintext (ASCII):    '%s'", ascii_plaintext);
      $display("Computed Hash:        %064h", captured_hash);
      $display("Expected Hash:        %064h", loaded_expected_hash);
      $display("SHA Input Correct:    %s", 
          (captured_sha_input == {TEST_ID, captured_plaintext}) ? "✅ YES" : "❌ NO");
      $display("Hash Verification:    %s", hash_match_internal ? "✅ PASS" : "❌ FAIL");
      $display("Overall Result:       %s", 
          (done && hash_match_internal && verification_done_internal) ? "🎉 SUCCESS" : "❌ FAILED");
      $display("Output Files:         data_output.txt created");
      $display("========================================");
      
      #(CLK_PERIOD * 10);
      $display("🎉 OPTIMIZED TEST COMPLETED!");
      $finish;
  end

  // Safety timeout
  initial begin
      #(CLK_PERIOD * 50000);
      $display("❌ SAFETY TIMEOUT - Test took too long");
      $finish;
  end

endmodule




