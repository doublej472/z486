// Verilator wrapper for tb_pc98_map (full-core PC-98 memory-map test).
#include "Vtb_pc98_map.h"
#include "verilated.h"

int main(int argc, char **argv) {
    auto contextp = new VerilatedContext;
    contextp->commandArgs(argc, argv);
    Vtb_pc98_map *top = new Vtb_pc98_map{contextp};

    // The bench finishes itself; the time cap only bounds a mis-seeded run.
    while (!contextp->gotFinish() && contextp->time() < 1000000) {
        top->eval();
        contextp->timeInc(1);
    }

    int failed = contextp->gotFinish() ? 0 : 1;
    delete top;
    delete contextp;
    return failed;
}
