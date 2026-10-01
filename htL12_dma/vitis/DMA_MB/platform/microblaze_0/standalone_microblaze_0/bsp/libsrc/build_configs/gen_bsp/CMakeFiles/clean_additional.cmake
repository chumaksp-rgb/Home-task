# Additional clean files
cmake_minimum_required(VERSION 3.16)

if("${CONFIG}" STREQUAL "" OR "${CONFIG}" STREQUAL "")
  file(REMOVE_RECURSE
  "C:\\PROJECTS_FPGA\\Home_tasks\\HT1\\htL12_dma\\vitis\\DMA_MB\\platform\\microblaze_0\\standalone_microblaze_0\\bsp\\include\\sleep.h"
  "C:\\PROJECTS_FPGA\\Home_tasks\\HT1\\htL12_dma\\vitis\\DMA_MB\\platform\\microblaze_0\\standalone_microblaze_0\\bsp\\include\\xiltimer.h"
  "C:\\PROJECTS_FPGA\\Home_tasks\\HT1\\htL12_dma\\vitis\\DMA_MB\\platform\\microblaze_0\\standalone_microblaze_0\\bsp\\include\\xtimer_config.h"
  "C:\\PROJECTS_FPGA\\Home_tasks\\HT1\\htL12_dma\\vitis\\DMA_MB\\platform\\microblaze_0\\standalone_microblaze_0\\bsp\\lib\\libxiltimer.a"
  )
endif()
