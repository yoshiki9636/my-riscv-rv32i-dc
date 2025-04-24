char* heap_end = (char*)0x02000000;
//void _sbrk_r(void) {}
char* _sbrk(int incr) {
 char* heap_low = (char*)0x02000000;
 char* heap_top = (char*)0x03000000;
 char *prev_heap_end;

 if (heap_end == 0) {
  heap_end = heap_low;
 }
 prev_heap_end = heap_end;

 if (heap_end + incr > heap_top) {
  /* Heap and stack collision */
  return (char *)0;
 }

 heap_end += incr;
 return (char*) prev_heap_end;
}
