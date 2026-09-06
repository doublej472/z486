module reset_sync (
    input  logic clk,
    input  logic arst_n,
    output logic reset_n
);

logic [2:0] release_pipe;

always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n)
        release_pipe <= 3'b000;
    else
        release_pipe <= {release_pipe[1:0], 1'b1};
end

assign reset_n = release_pipe[2];

endmodule
