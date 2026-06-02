// Ethernet Interface
#include "ethernet.hpp"

byte mac[] = {
  0xDE, 0xAD, 0xBE, 0xEF, 0xFE, 0xED
};
IPAddress ip(192, 168, 1, 177);
IPAddress myDns(192, 168, 1, 1);
IPAddress gateway(192, 168, 1, 1);
IPAddress subnet(255, 255, 255, 0);
IPAddress cmd_ip(192, 168, 1, 2);
int port = 23;

EthernetWrapper ethernet (port,cmd_ip);


// IMU Interface
#include "bno.hpp"
BNO08x bno_1;
BNO08x_Copy bno_2;

void setup() {
  // put your setup code here, to run once:
  while (!ethernet.setup(mac,ip,myDns, gateway, subnet))
  {
    delay(100);
  }

  Wire.begin();

  delay(10);

  if (!initialise_bno(&bno_1, 75, Wire, 1, 2)) {
    Serial.println("ERROR: bno_1 failed to initialize");
  }

  Wire1.begin();

  delay(10);

  if (!initialise_bno(&bno_2, 75, Wire1, 8, 7)) {
    Serial.println("ERROR: bno_2 failed to initialize");
  }

}

void loop() {
  // put your main code here, to run repeatedly:
  EthernetWrapperMsg msg;

  BnoData bno_1_data(&bno_1);
  if (bno_1_data.packIMUtoEth(msg,1)){
    // Write to Ethernet Interface
    ethernet.send_packets(msg);
  }

  // msg = EthernetWrapperMsg();
  // BnoData bno_2_data(&bno_1);
  // if (bno_2_data.packIMUtoEth(msg,2)){
  //   // Write to Ethernet Interface
  //   ethernet.send_packets(msg);
  // }

}
