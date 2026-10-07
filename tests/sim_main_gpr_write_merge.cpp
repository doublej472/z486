#include "Vtb_gpr_write_merge.h"
#include "verilated.h"

// Pure combinational unit bench: it prints per-case PASS/FAIL and a summary.
int main(int argc, char **argv) {
    auto contextp = new VerilatedContext;
    contextp->commandArgs(argc, argv);
    Vtb_gpr_write_merge *top = new Vtb_gpr_write_merge{contextp};

    while (!contextp->gotFinish() && contextp->time() < 100000) {
        top->eval();
        contextp->timeInc(1);
    }

    int failed = contextp->gotFinish() ? 0 : 1;
    if (!contextp->gotFinish())
        VL_PRINTF("GPR WRITE MERGE TEST FAIL: no completion before time limit\n");
    delete top;
    delete contextp;
    return failed;
}
