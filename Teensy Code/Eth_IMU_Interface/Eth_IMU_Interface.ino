#define DEBUG

// Ethernet Interface
#include "ethernet.hpp"

byte mac[] = {
  0xDE, 0xAD, 0xBE, 0xEF, 0xFE, 0xED
};
IPAddress ip(192, 168, 1, 177);
IPAddress myDns(192, 168, 1, 1);
IPAddress gateway(192, 168, 1, 1);
IPAddress subnet(255, 255, 0, 0);
IPAddress cmd_ip(192, 168, 1, 2);
int port = 23;

EthernetWrapper ethernet (port,cmd_ip);


// IMU Interface
#include "bno.hpp"
BNO08x bno_1;
BNO08x_Copy bno_2;

void setup() {

  Serial.begin(115200);
#ifdef DEBUG
  while(!Serial)
  {
    delay(10);
  }
#endif

  Wire.begin();
  Wire2.begin();

  while (!initialise_bno(&bno_1, 75, Wire, 1, 2)) {
#ifdef DEBUG
    Serial.println("ERROR: bno_1 failed to initialize");
#endif
    delay(10);
  }

  if (!initialise_bno(&bno_2, 75, Wire2, 8, 7)) {
#ifdef DEBUG
    Serial.println("ERROR: bno_2 failed to initialize");
#endif
  }

  // put your setup code here, to run once:
  while (!ethernet.setup(mac,ip,myDns, gateway, subnet))
  {
    delay(100);
  }
}

void loop() {
  // put your main code here, to run repeatedly:
  EthernetWrapperMsg msg;

  BnoData bno_1_data(&bno_1);
  
#ifdef DEBUG
  Serial.println("BOOP1");
#endif
  
  if (bno_1_data.packIMUtoEth(msg,1)){
    // Write to Ethernet Interface
    ethernet.send_packets(msg);
  }


  delay(1);

  // msg = EthernetWrapperMsg();
  // BnoData bno_2_data(&bno_1);
  // if (bno_2_data.packIMUtoEth(msg,2)){
  //   // Write to Ethernet Interface
  //   ethernet.send_packets(msg);
  // }

}
