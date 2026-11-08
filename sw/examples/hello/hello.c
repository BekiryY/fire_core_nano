/* hello.c -- printf through picolibc on the BSP console. Returns 0: LEDs 0x01 on the FPGA. */
#include <stdio.h>

int main(void)
{
    printf("Hello from fc32e1s_nano: %d + %d = %d, 0x%x\n", 2, 3, 2 + 3, 0xC0FFEEu);
    return 0;
}
