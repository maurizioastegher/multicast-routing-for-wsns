using namespace std;
#include <iostream>
#include <fstream>
#include <cstdlib>
#include <iomanip>

int main (int argc, char* argv[]) {
  fstream myin;
  
  if (argc!=2) {
    cout << "Usage: ./a.out, file" << endl;
    exit(0);
  }

  myin.open(argv[1], ios::in);
  if (myin.fail()) {
    cout << "Input file does not exist!" << endl;
    exit(0);
  }

  int blueNodes = 2, greenNodes = 3, redNodes = 4, yellowNodes = 4;
  cout << endl << "BLUE nodes: " << blueNodes << ", GREEN nodes: " << greenNodes << ", RED nodes: " << redNodes << ", YELLOW nodes: "  << yellowNodes << endl;
  
  char commType;
  cout << "Is this a multicast (m) or anycast (a) test case?" << endl;
  while (commType != 'm' && commType != 'a') {
    cin >> commType;
  }

  float totalComm = 0;
  float completeComm = 0;

  float startingTime;
  float receivingTime;
  float singleTransmissionTime = 0;
  float totalTransmissionTime = 0;

  float avgDelay = 0;
  float pdr = 0;

  int firstChar;
  myin >> firstChar;

  while (!myin.eof()) {
    totalComm++;
    
    char color;
    myin >> color;
    myin >> startingTime;
    myin >> receivingTime;
    
    int correctlyDelivered = 0;
    int target = 0;
 	
    if (commType == 'a') {
      target = 1;
    } else {
      switch (color) {
        case ('B') :
          target = blueNodes;
          break;
        case ('G') :
          target = greenNodes;
          break;
        case ('R') :
          target = redNodes;
          break;
        case ('Y') :
          target = yellowNodes;
          break;
        default : break;
      }
    }	

    while(!myin.eof() && receivingTime != 0) {
      if ((commType == 'm') || (commType == 'a' && correctlyDelivered < target)) { 	
        correctlyDelivered++;
        if (correctlyDelivered == target) { 
          singleTransmissionTime = receivingTime - startingTime;
          totalTransmissionTime = totalTransmissionTime + singleTransmissionTime;
          completeComm++;
        }
      } 

      myin >> receivingTime;
    }
  }

  if (completeComm != 0) {
    avgDelay = totalTransmissionTime / completeComm;
    cout << endl << "AVERAGE DELAY: " << setprecision(4) << avgDelay << "ms" << endl;  
  } else {
    cout << endl << "AVERAGE DELAY: -" << endl;  
  }

  pdr = (completeComm / totalComm) * 100;
  cout << "Total communications: " << totalComm << " - Completed communications: "<< completeComm << " -> PDR: " << setprecision(3) << pdr << "%" << endl << endl;
  
  myin.close();
  return 0;
}
