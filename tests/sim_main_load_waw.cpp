#include "Vtb_load_waw.h"
#include "verilated.h"

// The testbench reports "LOAD WAW TEST PASS" on success and "LOAD WAW TEST
// FAIL" otherwise.  `make test-load-waw` treats a run without the PASS marker
// as a failure; this driver only guards against a hang.
int main(int argc, char **argv) {
    auto contextp = new VerilatedContext;
    contextp->commandArgs(argc, argv);
    Vtb_load_waw *top = new Vtb_load_waw{contextp};

    while (!contextp->gotFinish() && contextp->time() < 100000) {
        top->eval();
        contextp->timeInc(1);
    }

    int failed = contextp->gotFinish() ? 0 : 1;
    if (!contextp->gotFinish())
        VL_PRINTF("LOAD WAW TEST FAIL: no completion before time limit\n");
    delete top;
    delete contextp;
    return failed;
}
