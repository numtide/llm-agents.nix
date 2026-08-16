#ifndef _MES_CONFIG_H
#undef SYSTEM_LIBC
#define MES_VERSION "0.27.1"
#ifndef __M2__
typedef unsigned long uintptr_t;
typedef unsigned long size_t;
typedef long ssize_t;
typedef long intptr_t;
typedef long ptrdiff_t;
#define __MES_SIZE_T
#define __MES_SSIZE_T
#define __MES_INTPTR_T
#define __MES_UINTPTR_T
#define __MES_PTRDIFF_T
#endif
#endif
