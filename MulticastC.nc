#include <Timer.h>
#include "DataMsg.h"

module MulticastC {
  uses {
    interface Boot;
    interface SplitControl as RadioControl;
    interface RootControl;    
    interface StdControl as RoutingControl;
    interface Random;
    interface LocalTime<TMilli>;
    
    interface CtpInfo;
    interface Send as CtpSend;
    interface Receive as CtpReceive;
    interface Intercept as CtpForward;
    interface Timer<TMilli> as TimerColor;
    interface Timer<TMilli> as TimerData;
    interface Timer<TMilli> as TimerReset;
    interface Timer<TMilli> as ReactiveColor;
    interface Timer<TMilli> as CtpRetransmit;
    
    interface Packet;
    interface AMSend;
    interface Receive as AMReceive;
    interface Queue<DataMsg> as DataQueue;
    interface Queue<ResetMsg> as ResetQueue;
    interface Timer<TMilli> as AMRetransmit;
  }
}

implementation {
  char colors[] = {'B', 'G', 'R', 'Y'};
  char nodesColors[] = {'R', 'G', 'Y', 'B', 'R', 'B', 'G', 'G', 'Y', 'Y', 'R', 'R', 'Y'};
  bool descendantsColors[N_COLORS]; /* List with the colors of the descendants */
  
  message_t packet;
  bool sendBusy = FALSE;
  uint8_t parentAddress = 255;
  
  /* Sequence numbers */
  uint8_t msgNo = 0;
  uint8_t flooded[N_NODES];
  uint8_t resetNo = 0;

  event void Boot.booted() {
    call RadioControl.start();
  }
  
  event void RadioControl.startDone(error_t err) {
    if (err != SUCCESS) {
      call RadioControl.start();
    } else {
      uint8_t i;
      call RoutingControl.start();
      for (i = 0; i < N_NODES; i++) {
        flooded[i] = 0;
      }
      call TimerData.startPeriodicAt(DATA_DELAY, DATA_PERIOD);
      if (TOS_NODE_ID == 0) {
	    call RootControl.setRoot();
	    call TimerReset.startPeriodic(RESET_PERIOD);
      } else {
	    call TimerColor.startPeriodic(COLOR_PERIOD);
      }
    }
  }

  event void RadioControl.stopDone(error_t err) {
  }
  
  task void sendReset() {
    if (!sendBusy) {
      ResetMsg* m = (ResetMsg*) call CtpSend.getPayload(&packet, sizeof(ResetMsg));
      if (call CtpSend.send(&packet, sizeof(ResetMsg)) == SUCCESS) {
        sendBusy = TRUE;
      }
    }
  }
  
  task void sendColor() {
    /* Reactive update mechanism: send a ResetMsg to the root if the node's parent has changed */
    am_addr_t addr; 
    if (call CtpInfo.getParent(&addr) == SUCCESS) {
      if (parentAddress == 255) {
        parentAddress = addr;
        dbg("color", ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> PARENT: %u - COLOR: %c \n", parentAddress, nodesColors[TOS_NODE_ID]);
      }
      if (addr != parentAddress) {
        dbg("color", "//////////////////////////////////////// PARENT CHANGED! OLD: %u -> NEW: %u \n", parentAddress, addr);
        parentAddress = addr;
        post sendReset();
        return;
      }
    }
    
    /* Send the node's color to the root */
    if (!sendBusy) {
      ColorMsg* m = (ColorMsg*) call CtpSend.getPayload(&packet, sizeof(ColorMsg));
      m->color = nodesColors[TOS_NODE_ID];
      m->source = TOS_NODE_ID;
      
      if (call CtpSend.send(&packet, sizeof(ColorMsg)) == SUCCESS) {
        sendBusy = TRUE;
      } 
    } 
  }
  
  task void broadcastData() {
    if (!call DataQueue.empty()) {
      if (!sendBusy) {
        DataMsg* m = (DataMsg*) call Packet.getPayload(&packet, sizeof(DataMsg));
        DataMsg queueMsg = (DataMsg) call DataQueue.dequeue();
        *m = queueMsg;  
        
        if (m->onlyToParent == 1) {
          am_addr_t addr;
          if (call CtpInfo.getParent(&addr) == SUCCESS) {
            if (call AMSend.send(addr, &packet, sizeof(DataMsg)) == SUCCESS) {
              if (m->isFirstHop == 1) { 
                dbg_clear("time", "0\n%c %u ", m->destination, call LocalTime.get());
              }
              sendBusy = TRUE;
            } else {
              call DataQueue.enqueue(*m);
              call AMRetransmit.startOneShot(call Random.rand16()%100);
            }
          }
        } else {
          if (call AMSend.send(AM_BROADCAST_ADDR, &packet, sizeof(DataMsg)) == SUCCESS) {
            if (m->isFirstHop == 1) { 
                dbg_clear("time", "0\n%c %u ", m->destination, call LocalTime.get());
            }
            sendBusy = TRUE;
          } else {
            call DataQueue.enqueue(*m);
            call AMRetransmit.startOneShot(call Random.rand16()%100);
          }
        }
   
      } else {
        call AMRetransmit.startOneShot(call Random.rand16()%100);
      }
    }
  }
  
  task void sendData() {
    if (!sendBusy) {
      DataMsg* m = (DataMsg*) call CtpSend.getPayload(&packet, sizeof(DataMsg));
      
      /* Choose a random color as a receiver */
      uint8_t destination = call Random.rand16()%100 % N_COLORS;
      /* destination = BLUE; */
      while (colors[destination] == nodesColors[TOS_NODE_ID]) {
        destination = call Random.rand16()%100 % N_COLORS;
      }
      
      atomic {
        /* Reset the sequence number */
        if (msgNo == 255) {
          msgNo = 0;
        }
        msgNo = msgNo++;
        m->msgNo = msgNo;
      }
      m->source = TOS_NODE_ID;
      m->destination = colors[destination];
      
      if (ANYCAST) {
        dbg("data", "***************************************************************** STARTING ANYCAST! \n");
        dbg("data", "**************************************** READY TO SEND - msgNo: %u, SOURCE: %u, DESTINATION: %c \n", m->msgNo, m->source, m->destination);
        flooded[m->source] = m->msgNo;
        
        /* Just for timestamping purposes */
        m->isFirstHop = 1;

        /* Broadcast if the node has at least a descendant with the chosen color; send to its parent otherwise */ 
        if (((char) m->destination == 'B' && descendantsColors[BLUE] == 1) || ((char) m->destination == 'G' && descendantsColors[GREEN] == 1) || ((char) m->destination == 'R' && descendantsColors[RED] == 1) || ((char) m->destination == 'Y' && descendantsColors[YELLOW] == 1)) {
          call DataQueue.enqueue(*m);
          post broadcastData();
        } else if (TOS_NODE_ID != 0) {
          m->onlyToParent = 1;
          call DataQueue.enqueue(*m);
          post broadcastData();
        } else {
          dbg("data", "++++++++++++++++++++++++++++++++++++++++ NO CHILDREN WITH THE CHOSEN COLOR! \n");
        }  
      } else {
        dbg("data", "***************************************************************** STARTING MULTICAST! \n");
      
        /* If the source coincide with the root start broadcasting; sends the message to the root otherwise */  
        if (TOS_NODE_ID == 0) { 
          dbg("data", "**************************************** READY TO SEND - msgNo: %u, SOURCE: %u, DESTINATION: %c \n", m->msgNo, m->source, m->destination);
          flooded[m->source] = m->msgNo;
          
          /* Just for timestamping purposes */
          m->isFirstHop = 1;
          
          /* Check if the node has at least a descendant with the chosen color and start broadcasting */ 
          if (((char) m->destination == 'B' && descendantsColors[BLUE] == 1) || ((char) m->destination == 'G' && descendantsColors[GREEN] == 1) || ((char) m->destination == 'R' && descendantsColors[RED] == 1) || ((char) m->destination == 'Y' && descendantsColors[YELLOW] == 1)) {
            call DataQueue.enqueue(*m);
            post broadcastData();
          } else {
            dbg("data", "++++++++++++++++++++++++++++++++++++++++ NO CHILDREN WITH THE CHOSEN COLOR! \n");
          }
        } else {
          if (call CtpSend.send(&packet, sizeof(DataMsg)) == SUCCESS) {
            dbg_clear("time", "0\n%c %u ", m->destination, call LocalTime.get());
            sendBusy = TRUE;
          } else {
            call CtpRetransmit.startOneShot(call Random.rand16()%100);
          }
        }
      }
    } else {
      call CtpRetransmit.startOneShot(call Random.rand16()%100);
    }
  }
  
  task void broadcastReset() {
    if (!call ResetQueue.empty()) {
      ResetMsg queueMsg = (ResetMsg) call ResetQueue.dequeue();
      if (!sendBusy) {
        ResetMsg* m = (ResetMsg*) call Packet.getPayload(&packet, sizeof(ResetMsg));
        *m = queueMsg;  

        if (call AMSend.send(AM_BROADCAST_ADDR, &packet, sizeof(ResetMsg)) == SUCCESS) {
          sendBusy = TRUE;
        } 
      }
    }
  }
  
  event void CtpSend.sendDone(message_t* m, error_t err) {
    sendBusy = FALSE;
  }
  
  event message_t* CtpReceive.receive(message_t* msg, void* payload, uint8_t len) {
    if (len == sizeof(ColorMsg)) {
      ColorMsg* m = (ColorMsg*) payload;
      
      /* ColorMsg received: update the list with the colors of the descendants */
      if (m->color == 'B') {
        descendantsColors[BLUE] = 1;
      } else if (m->color == 'G') {
        descendantsColors[GREEN] = 1;
      } else if (m->color == 'R') {
        descendantsColors[RED] = 1;
      } else if (m->color == 'Y') {
        descendantsColors[YELLOW] = 1;
      }
      
      dbg("color", "COLORS B,G,R,Y: %d,%d,%d,%d - SOURCE: %u \n", descendantsColors[BLUE], descendantsColors[GREEN], descendantsColors[RED], descendantsColors[YELLOW], m->source);
    } else if (len == sizeof(DataMsg)) {
      DataMsg* m = (DataMsg*) payload;
      flooded[m->source] = m->msgNo;
      dbg("data", "**************************************** READY TO SEND - msgNo: %u, SOURCE: %u, DESTINATION: %c \n", m->msgNo, m->source, m->destination);
     
      if ((char) m->destination == nodesColors[TOS_NODE_ID]) {
        dbg("data", "**************************************** DATA RECEIVED! msgNo: %u - SOURCE: %u \n", m->msgNo, m->source);
        dbg_clear("time", "%u ", call LocalTime.get());
      }
      
      /* Check if the node has at least a descendant with the chosen color and start broadcasting */ 
      if (((char) m->destination == 'B' && descendantsColors[BLUE] == 1) || ((char) m->destination == 'G' && descendantsColors[GREEN] == 1) || ((char) m->destination == 'R' && descendantsColors[RED] == 1) || ((char) m->destination == 'Y' && descendantsColors[YELLOW] == 1)) {
        call DataQueue.enqueue(*m);
        post broadcastData();
      } else {
        dbg("data", "++++++++++++++++++++++++++++++++++++++++ NO CHILDREN WITH THE CHOSEN COLOR! \n");
      }
    } else if (len == sizeof(ResetMsg)) {
      ResetMsg* m = (ResetMsg*) payload;
      uint8_t i;
      
      dbg("reset", "//////////////////////////////////////// NOW FORCING A RESET! \n"); 
      atomic {
        /* Reset the sequence number */
        if (resetNo == 255) {
          resetNo = 0;
        }
        resetNo++;
        m->resetNo = resetNo;
        
        /* Reset the list with the colors of the descendants */
        for (i = 0; i < N_COLORS; i++) {
          descendantsColors[i] = 0;
        }
      }
      
      /* Broadcast the ResetMsg */
      call ResetQueue.enqueue(*m);
      post broadcastReset();
    }   
    return msg;
  }
  
  event bool CtpForward.forward(message_t* msg, void* payload, uint8_t len) {
    if (len == sizeof(ColorMsg)) {
    
      /* ColorMsg intercepted: update the list with the colors of the descendants */
      ColorMsg* m = (ColorMsg*) payload;
      if (m->color == 'B') {
        descendantsColors[BLUE] = 1;
      } else if (m->color == 'G') {
        descendantsColors[GREEN] = 1;
      } else if (m->color == 'R') {
        descendantsColors[RED] = 1;
      } else if (m->color == 'Y') {
        descendantsColors[YELLOW] = 1;
      }
      dbg("color", "COLORS B,G,R,Y: %d,%d,%d,%d - SOURCE: %u \n", descendantsColors[BLUE], descendantsColors[GREEN], descendantsColors[RED], descendantsColors[YELLOW], m->source);
    } 
    return TRUE;
  }
  
  event void AMSend.sendDone(message_t* msg, error_t err) {
    sendBusy = FALSE;
  }
  
  event message_t* AMReceive.receive(message_t* msg, void* payload, uint8_t len) {
    if (len == sizeof(DataMsg)) {
      DataMsg* m = (DataMsg*) payload;
      uint8_t diff;  
         
      m->onlyToParent = 0;
      m->isFirstHop = 0;
      if (m->msgNo >= flooded[m->source]) {
        diff = m->msgNo - flooded[m->source];
      } else {
        diff = flooded[m->source] - m->msgNo;
      }
      
      if ((m->msgNo > flooded[m->source] && diff < 50) || (m->msgNo < flooded[m->source] && diff > 200)) {
        flooded[m->source] = m->msgNo;
        if ((char) m->destination == nodesColors[TOS_NODE_ID]) {
          dbg("data", "**************************************** DATA RECEIVED! msgNo: %u - SOURCE: %u \n", m->msgNo, m->source);
          dbg_clear("time", "%u ", call LocalTime.get());
          /* Do not broadcast if anycast is enabled */
          if (ANYCAST) {
            dbg("data", "++++++++++++++++++++++++++++++++++++++++ NO NEED TO SEND AGAIN! \n");
            return msg;
          }
        }
        
        if (((char) m->destination == 'B' && descendantsColors[BLUE] == 1) || ((char) m->destination == 'G' && descendantsColors[GREEN] == 1) || ((char) m->destination == 'R' && descendantsColors[RED] == 1) || ((char) m->destination == 'Y' && descendantsColors[YELLOW] == 1)) {
          call DataQueue.enqueue(*m);
          post broadcastData();
        } else if (TOS_NODE_ID != 0 && ANYCAST) {
          m->onlyToParent = 1;
          call DataQueue.enqueue(*m);
          post broadcastData();
        }
      }  
    } else if (len == sizeof(ResetMsg)) {
      ResetMsg* m = (ResetMsg*) payload;
      
      uint8_t diff;
      if (m->resetNo >= resetNo) {
        diff = m->resetNo - resetNo;
      } else {
        diff = resetNo - m->resetNo;
      }
      
      if ((m->resetNo > resetNo && diff < 50) || (m->resetNo < resetNo && diff > 200)) {
        uint8_t i;  
        dbg("reset", "//////////////////////////////////////// RESET MSG RECEIVED! resetNo: %u \n", m->resetNo);
        resetNo = m->resetNo;
        
        /* Reset the list with the colors of the descendants */
        atomic {
          for (i = 0; i < N_COLORS; i++) {
            descendantsColors[i] = 0;
          }
        } 
        
        call ResetQueue.enqueue(*m);
        post broadcastReset();
        
        /* Send again the node's color */
        if (!call ReactiveColor.isRunning()) {
          call ReactiveColor.startOneShot(1000 + call Random.rand16()%2000);
        }
      }
    }
    return msg;
  }
  
  event void TimerColor.fired() {
    post sendColor();
  }
  
  event void TimerData.fired() {
    /* if (!call CtpRetransmit.isRunning()) { */
    /*   call CtpRetransmit.startOneShot(call Random.rand16() % WAKE_UP_PERIOD); */
    /* } */
    if (TOS_NODE_ID == 11) {
       post sendData();
    }
  }
  
  event void TimerReset.fired() {
    /* Reactive update mechanism: periodically broadcast a ResetMsg */
    if (!sendBusy) {
      ResetMsg* m = (ResetMsg*) call Packet.getPayload(&packet, sizeof(ResetMsg));
      uint8_t i;
      
      dbg("reset", "//////////////////////////////////////// IT'S TIME TO RESET! \n");
      atomic {
        /* Reset the sequence number */
        if (resetNo == 255) {
          resetNo = 0;
        }
        resetNo++;
        m->resetNo = resetNo;
        
        /* Reset the list with the colors of the descendants */
        for (i = 0; i < N_COLORS; i++) {
          descendantsColors[i] = 0;
        }
      }
      
      /* Broadcast the ResetMsg */
      call ResetQueue.enqueue(*m);
      post broadcastReset();  
    }
  }
  
  event void ReactiveColor.fired() {
    post sendColor();
  }
  
  event void CtpRetransmit.fired() {
    post sendData();
  }
    
  event void AMRetransmit.fired() {
    post broadcastData();
  }
}