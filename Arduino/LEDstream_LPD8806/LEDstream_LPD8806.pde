// Arduino bridge code between host computer and LPD8806-based digital
// addressable RGB LEDs (e.g. Adafruit product ID #306).  LED data is
// streamed, not buffered, making this suitable for larger installations
// (e.g. video wall, etc.) than could otherwise be contained within the
// Arduino's limited RAM.  Intended for use with USB-native boards such
// as Teensy or Adafruit 32u4 Breakout; also works on normal serial
// Arduinos (Uno, etc.), but speed will be limited by the serial port.

// LED data and clock lines are connected to the Arduino's SPI output.
// On traditional Arduino boards (e.g. Uno), SPI data out is digital pin
// 11 and clock is digital pin 13.  On both Teensy and the 32u4 Breakout,
// data out is pin B2, clock is B1.  On Arduino Mega, 51=data, 52=clock.
// LEDs should be externally powered -- trying to run any more than just
// a few off the Arduino's 5V line is generally a Bad Idea.  LED ground
// should also be connected to Arduino ground.

// Elsewhere, the WS2801 version of this code was specifically designed
// to avoid buffer underrun conditions...the WS2801 pixels automatically
// latch when the data stream stops for 500 microseconds or more, whether
// intentional or not.  The LPD8806 pixels are fundamentally different --
// the latch condition is indicated within the data stream, not by pausing
// the clock -- and buffer underruns are therefore a non-issue.  In theory
// it would seem this could allow the code to be much simpler and faster
// (there's no need to sync up with a start-of-frame header), but in
// practice the difference was not as pronounced as expected -- such code
// soon ran up against a USB throughput limit anyway.  So, rather than
// break compatibility in the quest for speed that will never materialize,
// this code instead follows the same header format as the WS2801 version.
// This allows the same host-side code (e.g. Adalight, Adavision, etc.)
// to run with either type of LED pixels.  Huzzah!

#include <SPI.h>

// A 'magic word' precedes each block of LED data; this assists the
// microcontroller in syncing up with the host-side software and latching
// frames at the correct time.  You may see an initial glitchy frame or
// two until the two come into alignment.  Immediately following the
// magic word are three bytes: a 16-bit count of the number of LEDs (high
// byte first) followed by a simple checksum value (high byte XOR low byte
// XOR 0x55).  LED data follows, 3 bytes per LED, in order R, G, B, where
// 0 = off and 255 = max brightness.  LPD8806 pixels only have 7-bit
// brightness control, so each value is divided by two; the 8-bit format
// is used to maintain compatibility with the protocol set forth by the
// WS2801 streaming code (those LEDs use 8-bit values).
static const uint8_t magic[] = { 'A','d','a' };
#define MAGICSIZE  sizeof(magic)
#define HEADERSIZE (MAGICSIZE + 3)
static uint8_t
  buffer[HEADERSIZE], // Serial input buffer
  bytesBuffered = 0;  // Amount of data in buffer

// If no serial data is received for a while, the LEDs are shut off
// automatically.  This avoids the annoying "stuck pixel" look when
// quitting LED display programs on the host computer.
static const unsigned long serialTimeout = 15000; // 15 seconds
static unsigned long       lastByteTime, lastAckTime;

void setup() {
  byte c;
  int  i, p;

  Serial.begin(115200); // 32u4 will ignore BPS and run full speed

  // SPI is run at 2 MHz.  LPD8806 can run much faster,
  // but unshielded wiring is susceptible to interference.
  // Feel free to experiment with other divider ratios.
  SPI.begin();
  SPI.setBitOrder(MSBFIRST);
  SPI.setDataMode(SPI_MODE0);
  SPI.setClockDivider(SPI_CLOCK_DIV8); // 2 MHz

  // Issue dummy byte to "prime" the SPI bus.  This later simplifies
  // the task of doing useful work during SPI transfers.  Rather than
  // the usual issue-and-wait-loop, code can instead wait-and-issue --
  // with other operations occurring between transfers, the wait is
  // then shortened or eliminated.  The SPSR register is read-only,
  // so this flag can't be forced -- SOMETHING must be issued.
  SPDR = 0;

  // Issue initial latch to LEDs.  This flushes any undefined data that
  // may exist on powerup, and prepares the LEDs to receive the first
  // frame of data.  Actual number of LEDs isn't known yet (this arrives
  // later in frame header packets), so just latch a large number:
  latch(10000);

  // Issue test pattern to LEDs on startup.  This helps verify that
  // wiring between the Arduino and LEDs is correct.  Again not knowing
  // the actual number of LEDs, this writes data for an arbitrarily
  // large number (10K).  If wiring is correct, LEDs will all light
  // red, green, blue on startup, then off.  Once you're confident
  // everything is working end-to-end, it's OK to comment this out and
  // re-upload the sketch to the Arduino.
  const uint8_t testColor[]  = { 0x80, 0x80, 0xff, 0x80, 0x80, 0x80 },
                testOffset[] = { 1, 2, 0, 3 };
  for(c=0; c<4; c++) {  // for each test sequence color...
    for(p=0; p<10000; p++) { // for each pixel...
      for(i=0; i<3; i++) {   // for each R,G,B...
        while(!(SPSR & _BV(SPIF)));          // Wait for prior byte out
        SPDR = testColor[testOffset[c] + i]; // Issue next byte
      }
    }
    latch(10000);
    if(c < 3) delay(250);
  }

  Serial.print("Ada\n");                 // Send ACK string to host
  lastByteTime = lastAckTime = millis(); // Initialize timers
}

// Program flow is simpler than the WS2801 code.  No need for a state
// machine...instead, software just alternates between two conditions:
// a header-seeking mode (looking for the 'magic word' at the start
// of each frame of data), and a data-forwarding mode (moving bytes
// from serial input to SPI output).  A proper data stream will
// consist only of alternating valid headers and valid data, so the
// loop() function is simply divided into these two parts, and repeats
// forever.

// LPD8806 pixels expect colors in G,R,B order vs. WS2801's R,G,B.
// This is used to shuffle things around later.
static const uint8_t byteOrder[] = { 2, 0, 1 };

void loop() {
  uint8_t       i, hi, lo, byteNum;
  int           c;
  long          nLEDs, remaining;
  unsigned long t;

  // HEADER-SEEKING BLOCK: locate 'magic word' at start of frame.

  // If any data in serial buffer, shift it down to starting position.
  for(i=0; i<bytesBuffered; i++)
    buffer[i] = buffer[HEADERSIZE - bytesBuffered + i];

  // Read bytes from serial input until there's a full header's worth.
  while(bytesBuffered < HEADERSIZE) {
    t = millis();
    if((c = Serial.read()) >= 0) {    // Data received?
      buffer[bytesBuffered++] = c;    // Store in buffer
      lastByteTime = lastAckTime = t; // Reset timeout counters
    } else {                          // No data, check for timeout...
      if(timeout(t, 10000) == true) return; // Start over
    }
  }

  // Have a header's worth of data.  Check for 'magic word' match.
  for(i=0; i<MAGICSIZE; i++) {
    if(buffer[i] != magic[i]) {      // No match...
      if(i == 0) bytesBuffered -= 1; // resume search at next char
      else       bytesBuffered -= i; // resume at non-matching char
      return;
    }
  }

  // Magic word matches.  Now how about the checksum?
  hi = buffer[MAGICSIZE];
  lo = buffer[MAGICSIZE + 1];
  if(buffer[MAGICSIZE + 2] != (hi ^ lo ^ 0x55)) {
    bytesBuffered -= MAGICSIZE; // No match, resume after magic word
    return;
  }

  // Checksum appears valid.  Get 16-bit LED count, add 1 (nLEDs always > 0)
  nLEDs = remaining = 256L * (long)hi + (long)lo + 1L;
  bytesBuffered = 0; // Clear serial buffer
  byteNum = 0;

  // DATA-FORWARDING BLOCK: move bytes from serial input to SPI output.

  // Unfortunately can't just forward bytes directly.  The data order is
  // different on LPD8806 (G,R,B), so bytes are buffered in groups of 3
  // and issued in the revised order.

  while(remaining > 0) { // While more LED data is expected...
    t = millis();
    if((c = Serial.read()) >= 0) {    // Successful read?
      lastByteTime = lastAckTime = t; // Reset timeout counters
      buffer[byteNum++] = c;          // Store in data buffer
      if(byteNum == 3) {              // Have a full LED's worth?
        while(byteNum > 0) {          // Issue data in LPD8806 order...
          i = 0x80 | (buffer[byteOrder[--byteNum]] >> 1);
          while(!(SPSR & _BV(SPIF))); // Wait for prior byte out
          SPDR = i;                   // Issue new byte
        }
        remaining--;
      }
    } else { // No data, check for timeout...
      if(timeout(t, nLEDs) == true) return; // Start over
    }
  }

  // Normal end of data.  Issue latch, return to header-seeking mode.
  latch(nLEDs);
}

static void latch(int n) {      // Pass # of LEDs
  n = ((n + 63) / 64) * 3;      // Convert to latch length (bytes)
  while(n--) {                  // For each latch byte...
    while(!(SPSR & _BV(SPIF))); // Wait for prior byte out
    SPDR = 0;                   // Issue next byte
  }
}

// Function is called when no pending serial data is available.
static boolean timeout(
  unsigned long t,       // Current time, milliseconds
  int           nLEDs) { // Number of LEDs

  // If condition persists, send an ACK packet to host once every
  // second to alert it to our presence.
  if((t - lastAckTime) > 1000) {
    Serial.print("Ada\n"); // Send ACK string to host
    lastAckTime = t;       // Reset counter
  }

  // If no data received for an extended time, turn off all LEDs.
  if((t - lastByteTime) > serialTimeout) {
    long bytes = nLEDs * 3L;
    latch(nLEDs);      // Latch any partial/incomplete data in strand
    while(bytes--) {   // Issue all new data to turn off strand
      while(!(SPSR & _BV(SPIF))); // Wait for prior byte out
      SPDR = 0x80;                // Issue next byte (0x80 = LED off)
    }
    latch(nLEDs);      // Latch 'all off' data
    lastByteTime  = t; // Reset counter
    bytesBuffered = 0; // Clear serial buffer
    return true;
  }

  return false; // No timeout
}

