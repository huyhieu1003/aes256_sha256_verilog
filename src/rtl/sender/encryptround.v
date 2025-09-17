module encryptround(in,key,out);
input [127:0] in;
input [127:0] key;
output [127:0] out;

wire [127:0] asb;    // after sub bytes
wire [127:0] asr;    // after shift rows
wire [127:0] amc;    // after mix columns
wire [127:0] aar;		// after addroundkey

sub_bytes sb(in, asb);
shiftrows sr(asb,asr);
mixcolumns mc(asr,amc);
adroundkey ar(amc,out,key);
		
endmodule