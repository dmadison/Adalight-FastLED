// Slightly modified Adalight protocol implementation that uses FastLED
// library (http://fastled.io) for driving WS2811/WS2812 led stripe
// Was tested only with Prismatik software from Lightpack project

#include "FastLED.h"

#define NUM_LEDS 114 // Max LED count
#define LED_PIN 6 // arduino output pin
#define GROUND_PIN 10
#define BRIGHTNESS 255 // maximum brightness
#define SPEED 115200 // virtual serial port speed, must be the same in boblight_config 

CRGB leds[NUM_LEDS];
uint8_t * ledsRaw = (uint8_t *)leds;

// A 'magic word' (along with LED count & checksum) precedes each block
// of LED data; this assists the microcontroller in syncing up with the
// host-side software and properly issuing the latch (host I/O is
// likely buffered, making usleep() unreliable for latch).  You may see
// an initial glitchy frame or two until the two come into alignment.
// The magic word can be whatever sequence you like, but each character
// should be unique, and frequent pixel values like 0 and 255 are
// avoided -- fewer false positives.  The host software will need to
// generate a compatible header: immediately following the magic word
// are three bytes: a 16-bit count of the number of LEDs (high byte
// first) followed by a simple checksum value (high byte XOR low byte
// XOR 0x55).  LED data follows, 3 bytes per LED, in order R, G, B,
// where 0 = off and 255 = max brightness.

static const uint8_t magic[] = {
  'A','d','a'};
#define MAGICSIZE  sizeof(magic)
#define HEADERSIZE (MAGICSIZE + 3)

#define MODE_HEADER 0
#define MODE_DATA   2

// If no serial data is received for a while, the LEDs are shut off
// automatically.  This avoids the annoying "stuck pixel" look when
// quitting LED display programs on the host computer.
static const unsigned long serialTimeout = 150000; // 150 seconds

void setup()
{
  pinMode(GROUND_PIN, OUTPUT); 
  digitalWrite(GROUND_PIN, LOW);
  FastLED.addLeds<WS2812B, LED_PIN, GRB>(leds, NUM_LEDS);

  // Dirty trick: the circular buffer for serial data is 256 bytes,
  // and the "in" and "out" indices are unsigned 8-bit types -- this
  // much simplifies the cases where in/out need to "wrap around" the
  // beginning/end of the buffer.  Otherwise there'd be a ton of bit-
  // masking and/or conditional code every time one of these indices
  // needs to change, slowing things down tremendously.
  uint8_t
    buffer[256],
  indexIn       = 0,
  indexOut      = 0,
  mode          = MODE_HEADER,
  hi, lo, chk, i, spiFlag;
  int16_t
    bytesBuffered = 0,
  hold          = 0,
  c;
  int32_t
    bytesRemaining;
  unsigned long
    startTime,
  lastByteTime,
  lastAckTime,
  t;
  int32_t outPos = 0;

  Serial.begin(SPEED); // Teensy/32u4 disregards baud rate; is OK!

  Serial.print("Ada\n"); // Send ACK string to host

    startTime    = micros();
  lastByteTime = lastAckTime = millis();

  // loop() is avoided as even that small bit of function overhead
  // has a measurable impact on this code's overall throughput.

  for(;;) {

    // Implementation is a simple finite-state machine.
    // Regardless of mode, check for serial input each time:
    t = millis();
    if((bytesBuffered < 256) && ((c = Serial.read()) >= 0)) {
      buffer[indexIn++] = c;
      bytesBuffered++;
      lastByteTime = lastAckTime = t; // Reset timeout counters
    } 
    else {
      // No data received.  If this persists, send an ACK packet
      // to host once every second to alert it to our presence.
      if((t - lastAckTime) > 1000) {
        Serial.print("Ada\n"); // Send ACK string to host
        lastAckTime = t; // Reset counter
      }
      // If no data received for an extended time, turn off all LEDs.
      if((t - lastByteTime) > serialTimeout) {
        memset(leds, 0,  NUM_LEDS * sizeof(struct CRGB)); //filling Led array by zeroes
        FastLED.show();
        lastByteTime = t; // Reset counter
      }
    }

    switch(mode) {

    case MODE_HEADER:

      // In header-seeking mode.  Is there enough data to check?
      if(bytesBuffered >= HEADERSIZE) {
        // Indeed.  Check for a 'magic word' match.
        for(i=0; (i<MAGICSIZE) && (buffer[indexOut++] == magic[i++]););
        if(i == MAGICSIZE) {
          // Magic word matches.  Now how about the checksum?
          hi  = buffer[indexOut++];
          lo  = buffer[indexOut++];
          chk = buffer[indexOut++];
          if(chk == (hi ^ lo ^ 0x55)) {
            // Checksum looks valid.  Get 16-bit LED count, add 1
            // (# LEDs is always > 0) and multiply by 3 for R,G,B.
            bytesRemaining = 3L * (256L * (long)hi + (long)lo + 1L);
            bytesBuffered -= 3;
            outPos = 0;
            memset(leds, 0,  NUM_LEDS * sizeof(struct CRGB));
            mode           = MODE_DATA; // Proceed to latch wait mode
          } 
          else {
            // Checksum didn't match; search resumes after magic word.
            indexOut  -= 3; // Rewind
          }
        } // else no header match.  Resume at first mismatched byte.
        bytesBuffered -= i;
      }
      break;

    case MODE_DATA:

      if(bytesRemaining > 0) {
        if(bytesBuffered > 0) {
          if (outPos < sizeof(leds))
            ledsRaw[outPos++] = buffer[indexOut++];   // Issue next byte
          bytesBuffered--;
          bytesRemaining--;
        }
        // If serial buffer is threatening to underrun, start
        // introducing progressively longer pauses to allow more
        // data to arrive (up to a point).
      } 
      else {
        // End of data -- issue latch:
        startTime  = micros();
        mode       = MODE_HEADER; // Begin next header search
        FastLED.show();
      }
    } // end switch
  } // end for(;;)
}

void loop()
{
  // Not used.  See note in setup() function.
}
