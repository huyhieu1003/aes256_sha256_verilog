module decryptround(in,key,out);
input [127:0] in;
output [127:0] out;
input [127:0] key;
wire [127:0] aisb;
wire [127:0] aisr;
wire [127:0] aimx;
wire [127:0] aar;

invshiftrows r(in,aisr);
inversesubbytes s(aisr,aisb);
adroundkey b(aisb,aar,key);
invmixcolumns m(aar,out);
		
endmodule