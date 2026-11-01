#include <stdio.h>
#include <string.h>

typedef struct { int step; const char *op; const char *buffer; } Event;
typedef struct { Event events[16]; int length; } Log;

static void record(Log *log, int step, const char *op, const char *buffer) {
  Event *entry=&log->events[log->length++];
  entry->step=step; entry->op=op; entry->buffer=buffer;
}

int mp_capture_trace(void) {
  unsigned char a[24], b[16], c[24];
  Log log = {0};
  record(&log,0,"begin","a");
  memset(a,0x10,sizeof(a));
  record(&log,0,"write","a");
  record(&log,1,"begin","b");
  record(&log,1,"read","a");
  for (int i=0;i<16;i++) b[i]=(unsigned char)(a[i]+1);
  record(&log,1,"write","b");
  record(&log,1,"end","a");
  record(&log,2,"begin","c");
  record(&log,2,"read","b");
  for (int i=0;i<24;i++) c[i]=(unsigned char)(b[i%16]+1);
  record(&log,2,"write","c");
  record(&log,2,"end","b");
  record(&log,3,"read","c");
  for (int i=0;i<24;i++) if (c[i]!=0x12) return 1;
  record(&log,3,"end","c");
  printf("{\"schema\":1,\"banks\":[{\"id\":\"ram\",\"capacity\":\"48\"}],\"buffers\":[");
  const char *ids[]={"a","b","c"}; const int sizes[]={24,16,24};
  for (int i=0;i<3;i++) {
    if(i) printf(",");
    printf("{\"id\":\"%s\",\"bytes\":\"%d\",\"alignment\":\"16\",\"banks\":[\"ram\"]}",ids[i],sizes[i]);
  }
  printf("],\"events\":[");
  for(int i=0;i<log.length;i++) {
    if(i) printf(",");
    Event e=log.events[i];
    printf("{\"step\":%d,\"op\":\"%s\",\"buffer\":\"%s\"}",e.step,e.op,e.buffer);
  }
  printf("]}\n");
  return 0;
}
