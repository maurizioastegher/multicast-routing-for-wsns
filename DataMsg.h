#ifndef DATAMSG_H
#define DATAMSG_H

enum {
  N_NODES = 13,
  N_COLORS = 4,
  ANYCAST = 0
};

enum {
  AM_DATAMSG = 20,
  COLOR_PERIOD = 1000*60*3,
  DATA_PERIOD = 1000*13,
  DATA_DELAY = 1000*60*3,
  RESET_PERIOD = 1000*60*20,
  WAKE_UP_PERIOD = 1000*60*3
};

enum {
  BLUE = 0,
  GREEN = 1,
  RED = 2,
  YELLOW = 3
};

typedef nx_struct ColorMsg {
  nx_uint8_t color;
  nx_uint8_t source;
} ColorMsg;

typedef nx_struct DataMsg {
  nx_uint8_t msgNo;
  nx_uint8_t source;
  nx_uint8_t destination;
  nx_uint8_t data;
  nx_uint8_t onlyToParent;
  nx_uint8_t isFirstHop;
} DataMsg;

typedef nx_struct ResetMsg {
  nx_uint8_t resetNo;
} ResetMsg;

#endif