#include "Vtb_gpr_hazard.h"
#include "verilated.h"

// The bench prints one line per probe and a summary.  Any "HAZARD" line is a
// survey finding, so the exit status only guards against a hang; make
// test-gpr-hazard decides from the summary line.
int main(int argc, char **argv) {
    auto contextp = new VerilatedContext;
    contextp->commandArgs(argc, argv);
    Vtb_gpr_hazard *top = new Vtb_gpr_hazard{contextp};

    while (!contextp->gotFinish() && contextp->time() < 200000) {
        top->eval();
        contextp->timeInc(1);
    }

    int failed = contextp->gotFinish() ? 0 : 1;
    if (!contextp->gotFinish())
        VL_PRINTF("GPR HAZARD SURVEY FAIL: no completion before time limit\n");
    delete top;
    delete contextp;
    return failed;
}
