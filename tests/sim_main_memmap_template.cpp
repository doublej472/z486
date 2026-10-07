#include "Vtb_memmap_template.h"
#include "verilated.h"

int main(int argc, char **argv) {
    auto contextp = new VerilatedContext;
    contextp->commandArgs(argc, argv);
    Vtb_memmap_template *top = new Vtb_memmap_template{contextp};

    while (!contextp->gotFinish() && contextp->time() < 200000) {
        top->eval();
        contextp->timeInc(1);
    }

    int failed = contextp->gotFinish() ? 0 : 1;
    delete top;
    delete contextp;
    return failed;
}
