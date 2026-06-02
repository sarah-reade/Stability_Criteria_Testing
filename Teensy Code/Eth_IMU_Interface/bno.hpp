#ifndef BNO_HPP
#define BNO_HPP

#define DEBUG_BNO

#include <Wire.h>
#include "SparkFun_BNO08x_Arduino_Library.h" 
#include "SparkFun_BNO08x_Arduino_Library_Copy.h" 
#include "ethernet.hpp"

bool set_reports(BNO08x_Copy *bno)
{
  
  if (bno->enableReports == true)
  {
#ifdef DEBUG_BNO
    Serial.println(F("Gyroscope enabled"));
#endif
  }
#ifdef DEBUG_BNO
  Serial.println("Could not enable gyroscope");
#endif

  if (bno->enableReport(SH2_LINEAR_ACCELERATION) == true)
  {
#ifdef DEBUG_BNO
    Serial.println(F("Linear Acceleration enabled"));
#endif
    return true;
  }
#ifdef DEBUG_BNO
  Serial.println("Could not enable linear acceleration");
#endif

  return false;
}

bool set_reports(BNO08x *bno)
{
  
  if (bno->enableReport(SH2_GYROSCOPE_CALIBRATED) == true)
  {
#ifdef DEBUG_BNO
    Serial.println(F("Gyroscope enabled"));
#endif
  }
#ifdef DEBUG_BNO
  Serial.println("Could not enable gyroscope");
#endif

  if (bno->enableReport(SH2_LINEAR_ACCELERATION) == true)
  {
#ifdef DEBUG_BNO
    Serial.println(F("Linear Acceleration enabled"));
#endif
    return true;
  }
#ifdef DEBUG_BNO
  Serial.println("Could not enable linear acceleration");
#endif
  return false;
}

bool initialise_bno(BNO08x_Copy *bno, uint8_t address, TwoWire &wirePort, int8_t intpin, int8_t rstpin)
{

  // Calling wirePort.begin() here is OK, but small delay after reset helps.
  //wirePort.begin();
  delay(200);
  if (!bno->begin(address, wirePort, intpin, rstpin)) {
    Serial.printf("BNO08x not detected at address 0x%02X on bus. Check wiring.\n", address);
    return false;
  }
  Serial.printf("BNO08x found at 0x%02X\n", address);
  delay(10);
  if (!set_reports(bno)) {
    Serial.println("BNO08x: could not enable reports");
    return false;
  }
  delay(10);
  return true;
  
}

bool initialise_bno(BNO08x *bno, uint8_t address, TwoWire &wirePort, int8_t intpin, int8_t rstpin)
{

  // Calling wirePort.begin() here is OK, but small delay after reset helps.
  //wirePort.begin();
  delay(200);
  if (!bno->begin(address, wirePort, intpin, rstpin)) {
    Serial.printf("BNO08x not detected at address 0x%02X on bus. Check wiring.\n", address);
    return false;
  }
  Serial.printf("BNO08x found at 0x%02X\n", address);
  delay(10);
  if (!set_reports(bno)) {
    Serial.println("BNO08x: could not enable reports");
    return false;
  }
  delay(10);
  return true;
}

struct BnoData
{
  float linX,linY,linZ,gyrX,gyrY,gyrZ;
  uint8_t linAcc,gyrAcc;

  // Define min/max for each value 
  bool flag;

  BnoData (BNO08x *bno):  linX(0),
                          linY(0),
                          linZ(0),
                          gyrX(0),
                          gyrY(0),
                          gyrZ(0),
                          linAcc(0),
                          gyrAcc(0)
  {
    if (bno->wasReset()) {
      Serial.println("sensor was reset ");
      if(!set_reports(bno))
      {
        return;
      };
      
    }

    // Has a new event come in on the Sensor Hub Bus?
    if (bno->getSensorEvent() == true) {

      // is it the correct sensor data we want?
      if (bno->getSensorEventID() == SH2_LINEAR_ACCELERATION) {

        linX = bno->getLinAccelX();
        linY = bno->getLinAccelY();
        linZ = bno->getLinAccelZ();
        linAcc = bno->getLinAccelAccuracy();
        flag = true;

      }
      else if (bno->getSensorEventID() == SH2_GYROSCOPE_CALIBRATED) {

        gyrX = bno->getGyroX();
        gyrY = bno->getGyroX();
        gyrZ = bno->getGyroX();
        gyrAcc = bno->getGyroAccuracy();
        flag = true;

      }
      else
      {
        flag = false;
      }

    }

    return;
  }

  BnoData (BNO08x_Copy *bno):  linX(0),
                          linY(0),
                          linZ(0),
                          gyrX(0),
                          gyrY(0),
                          gyrZ(0),
                          linAcc(0),
                          gyrAcc(0)
  {
    if (bno->wasReset()) {
      Serial.println("sensor was reset ");
      if(!set_reports(bno))
      {
        return;
      };
      
    }

    // Has a new event come in on the Sensor Hub Bus?
    if (bno->getSensorEvent() == true) {

      // is it the correct sensor data we want?
      if (bno->getSensorEventID() == SH2_LINEAR_ACCELERATION) {

        linX = bno->getLinAccelX();
        linY = bno->getLinAccelY();
        linZ = bno->getLinAccelZ();
        linAcc = bno->getLinAccelAccuracy();
        flag = true;

      }
      else if (bno->getSensorEventID() == SH2_GYROSCOPE_CALIBRATED) {

        gyrX = bno->getGyroX();
        gyrY = bno->getGyroX();
        gyrZ = bno->getGyroX();
        gyrAcc = bno->getGyroAccuracy();
        flag = true;

      }
      else
      {
        flag = false;
      }

    }

    return;
  }


  // Map float to int16_t dynamically
  int16_t scaleToInt16(float value, float minVal, float maxVal) {
      if (value < minVal) value = minVal;
      if (value > maxVal) value = maxVal;
      float normalized = (value - minVal) / (maxVal - minVal); // 0..1
      return (int16_t)(normalized * 65535.0f - 32768.0f);     // scale to int16_t range
  }

  // Map float to uint8_t
  uint8_t scaleToUInt8(float value, float minVal, float maxVal) {
      if (value < minVal) value = minVal;
      if (value > maxVal) value = maxVal;
      float normalized = (value - minVal) / (maxVal - minVal); // 0..1
      return (uint8_t)(normalized * 255.0f);
  }

  bool packIMUtoEth(EthernetWrapperMsg &msg, uint8_t sensorID) {
    if (!flag) {return false;}

#ifdef DEBUG_BNO
    Serial.println("Obtained Reading");
#endif  
    
    // total payload size
    constexpr size_t payloadSize =
        sizeof(sensorID) +
        6 * sizeof(float) +
        2 * sizeof(uint8_t);

    if (msg.data == nullptr) return false;

    // IMPORTANT: ensure buffer is large enough externally
    // (no heap safety here)

    uint8_t* p = msg.data;

    // optional header
    *p++ = sensorID;

    // IMU floats
    memcpy(p, &linX, sizeof(float)); p += sizeof(float);
    memcpy(p, &linY, sizeof(float)); p += sizeof(float);
    memcpy(p, &linZ, sizeof(float)); p += sizeof(float);

    memcpy(p, &gyrX, sizeof(float)); p += sizeof(float);
    memcpy(p, &gyrY, sizeof(float)); p += sizeof(float);
    memcpy(p, &gyrZ, sizeof(float)); p += sizeof(float);

    // uint8_t fields
    *p++ = linAcc;
    *p++ = gyrAcc;

    // final length
    msg.length = payloadSize;

    return true;
    
  }
};



#endif