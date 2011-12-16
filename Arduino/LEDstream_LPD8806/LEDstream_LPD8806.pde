// Arduino "bridge" code between host computer and LPD8806-based digital
// addressable RGB LEDs (e.g. Adafruit product ID #306).  Intended for
// use with USB-native boards such as Teensy or Adafruit 32u4 Breakout;
// works on normal serial Arduinos, but throughput is severely limited.
// LED data is streamed, not buffered, making this suitable for larger
// installations (e.g. video wall, etc.) than could otherwise be held
// in the Arduino's limited RAM.

// The LPD8806 latch condition is indicated through the data protocol,
// not through a pause in the data clock as with the WS2801.  Buffer
// underruns are thus a non-issue and the code can be vastly simpler.
// Data is merely routed from serial in to SPI out.

// LED data and clock lines are connected to the Arduino's SPI output.
// On traditional Arduino boards, SPI data out is digital pin 11 and
// clock is digital pin 13.  On both Teensy and the 32u4 Breakout,
// data out is pin B2, clock is B1.  LEDs should be externally
// powered -- trying to run any more than just a few off the Arduino's
// 5V line is generally a Bad Idea.  LED ground should also be
// connected to Arduino ground.

#include <SPI.h>

// If no serial data is received for a while, the LEDs are shut off
// automatically.  This avoids the annoying "stuck pixel" look when
// quitting LED display programs on the host computer.
static const unsigned long serialTimeout = 15000; // 15 seconds

void setup() {
  int i, c;
  unsigned long
    lastByteTime,
    lastAckTime,
    t;

  Serial.begin(115200); // 32u4 ignores BPS, runs full speed

  // SPI is run at 2 MHz.  LPD8806 can run much faster,
  // but unshielded wiring is susceptible to interference.
  // Feel free to experiment with other divider ratios.
  SPI.begin();
  SPI.setBitOrder(MSBFIRST);
  SPI.setDataMode(SPI_MODE0);
  SPI.setClockDivider(SPI_CLOCK_DIV8); // 2 MHz

  // Issue test pattern to LEDs on startup.  This helps verify that
  // wiring between the Arduino and LEDs is correct.  Not knowing the
  // actual number of LEDs connected, this sets all of them (well, up
  // to the first 25,000, so as not to be TOO time consuming) to green,
  // red, blue, then off.  Once you're confident everything is working
  // end-to-end, it's OK to comment this out and reprogram the Arduino.
  uint8_t testcolor[] = { 0x80, 0x80, 0x80, 0xff, 0x80, 0x80 };
  for(char n=3; n>=0; n--) {
    for(c=0; c<25000; c++) {
      for(i=0; i<3; i++) {
        for(SPDR = testcolor[n + i]; !(SPSR & _BV(SPIF)); );
      }
    }
    for(c=0; c<400; c++) {
      for(SPDR=0; !(SPSR & _BV(SPIF)); );
    }
  }

  Serial.print("Ada\n"); // Send ACK string to host
  SPDR = 0; // Dummy byte out to "prime" the SPI status register

  lastByteTime = lastAckTime = millis();

  // loop() is avoided as even that small bit of function overhead
  // has a measurable impact on this code's overall throughput.

  for(;;) {
    t = millis();
    if((c = Serial.read()) >= 0) {
      while(!(SPSR & (1<<SPIF)));     // Wait for prior SPI byte out
      SPDR = c;                       // Issue new SPI byte out
      lastByteTime = lastAckTime = t; // Reset timeout counters
    } else {
      // No data received.  If this persists, send an ACK packet
      // to host once every second to alert it to our presence.
      if((t - lastAckTime) > 1000) {
        Serial.print("Ada\n"); // Send ACK string to host
        lastAckTime = t; // Reset counter
      }
      // If no data received for an extended time, turn off all LEDs.
      if((t - lastByteTime) > serialTimeout) {
        for(c=0; c<32767; c++) {
          for(SPDR=0x80; !(SPSR & _BV(SPIF)); );
        }
        for(c=0; c<512; c++) {
          for(SPDR=0; !(SPSR & _BV(SPIF)); );
        }
        lastByteTime = t; // Reset counter
      }
    }
  }
}

void loop() {
  // Not used.  See note in setup() function.
}
