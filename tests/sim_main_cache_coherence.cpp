#include "Vtb_cache_coherence.h"
#include "verilated.h"

int main(int argc, char **argv) {
    auto contextp = new VerilatedContext;
    contextp->commandArgs(argc, argv);
    Vtb_cache_coherence *top = new Vtb_cache_coherence{contextp};

    while (!contextp->gotFinish() && contextp->time() < 2000000) {
        top->eval();
        contextp->timeInc(1);
    }

    int failed = contextp->gotFinish() ? 0 : 1;
    delete top;
    delete contextp;
    return failed;
}
