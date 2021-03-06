#include <stdio.h>
#include <stdlib.h>
#include "gc.h"
#include <time.h>
#include "tests.demo1.h"

extern void body(struct thread_info *);

extern value args[];

/*
  OS: Checks if an int represents a pointer, implemented as an extern in Clight
*/
_Bool is_ptr(unsigned int s) {
  return (_Bool) Is_block(s);
} 



/* OS: not generated */
void bool_elim(value bool){
    value ordinal;
 

    elim_bool(bool, &ordinal, NULL);
    if(ordinal == 0){
      printf(" %s ", names_of_bool[ordinal]);
    } else {
      printf(" %s ", names_of_bool[ordinal]);     
    }
}

/* OS: not generated */
void alpha_list_elim(value list, void* f_ptr){
  value prod_arr[2]; 
  value ordinal;
  void *v;
 
  value curr = list;
  printf("(");
  while(1){
    
    elim_list(curr, &ordinal, prod_arr);
    if(ordinal == 0){
      v = prod_arr[0];
      curr = prod_arr[1];
      ((void (*)(value)) f_ptr)(v);
      printf("::");     
    }else {
      printf(" %s", names_of_list[ordinal]);
      break;
    }

  }
  printf(")\n");
} 

/* OS: not generated */
void list_bool_print(value list){
  value prod_arr[2]; 
  value ordinal;
  void *v_bool;
 
  value curr = list;
  printf("(");
  while(1){
    
    elim_list(curr, &ordinal, prod_arr);
    if(ordinal == 0){
      v_bool = prod_arr[0];
      curr = prod_arr[1];
      elim_bool(v_bool, &ordinal, NULL);
      printf(" %s ", names_of_bool[ordinal]);
      printf("::");           
    }else {
      printf(" %s", names_of_list[ordinal]);
      break;
    }
  }
    printf(")\n");
} 



int main(int argc, char *argv[]) {
  value val; 

  struct thread_info* tinfo;
  tinfo = make_tinfo();
  body(tinfo);
  printf("After execution \n");
  val = tinfo -> args[1];
  alpha_list_elim(val, bool_elim);

  return 0;
    
}
