#include <stddef.h>
#include <string.h>
#include "generated_plan.h"
int mp_replay(void) {
  unsigned char ram[48] = {0};
  const size_t offset[] = {MP_BUFFER_0_OFFSET, MP_BUFFER_1_OFFSET, MP_BUFFER_2_OFFSET};
  const size_t bytes[] = {MP_BUFFER_0_BYTES, MP_BUFFER_1_BYTES, MP_BUFFER_2_BYTES};
  const int first[] = {0,1,2}, last[] = {1,2,3};
  for (int time=0; time<=3; time++) {
    for (int i=0;i<3;i++) {
      if (offset[i]+bytes[i]>sizeof(ram)) return 1;
      if (first[i]==time) memset(ram+offset[i],0x40+i,bytes[i]);
    }
    for (int i=0;i<3;i++) if (first[i]<=time && time<=last[i]) {
      for (size_t j=0;j<bytes[i];j++) if (ram[offset[i]+j]!=(unsigned char)(0x40+i)) return 2;
    }
  }
  return 0;
}
