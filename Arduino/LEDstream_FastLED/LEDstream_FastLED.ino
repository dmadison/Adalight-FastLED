/* LEDstream_FastLED

   Modified version of Adalight that uses the FastLED
   library (http://fastled.io) for driving led strips.

   http://github.com/dmadison/Adalight-FastLED

   --------------------------------------------------------------------
   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU Lesser General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public License
   along with this program.  If not, see <http://www.gnu.org/licenses/>.
   --------------------------------------------------------------------
*/

// Better accuracy on low brightness
#define FASTLED_USE_GLOBAL_BRIGHTNESS 2

// --- General Settings
static const uint16_t Num_Leds   =  336;      // strip length
static const uint8_t Brightness =  64;       // maximum brightness
static const uint8_t LEDS_GROUP =  4;         // number of leds in group

// --- FastLED Setings
#define LED_TYPE     SK9822  // led strip type for FastLED
#define COLOR_ORDER  BGR     // color order for bitbang
#define PIN_DATA     11       // led data output pin
#define PIN_CLOCK    12       // led data clock pin (uncomment if you're using a 4-wire LED type)

// --- Serial Settings
static const unsigned long SerialSpeed    = 250000; // serial port speed
static const uint16_t SerialTimeout  = 300;     // time before LEDs are shut off if no data (in seconds), 0 to disable

// --- Optional Settings (uncomment to add)
#define SERIAL_FLUSH         // Serial buffer cleared on LED latch
//#define CLEAR_ON_START     // LEDs are cleared on reset
//#define GROUND_PIN 10      // additional grounding pin (optional)
//#define CALIBRATE          // sets all LEDs to the color of the first

// --- Debug Settings (uncomment to add)
//#define DEBUG_LED 13       // toggles the Arduino's built-in LED on header match
//#define DEBUG_FPS 8        // enables a pulse on LED latch

// --------------------------------------------------------------------

#include <FastLED.h>

CRGB leds[Num_Leds];
uint8_t * ledsRaw = (uint8_t *)leds;

// A 'magic word' (along with LED count & checksum) precedes each block
// of LED data; this assists the microcontroller in syncing up with the
// host-side software and properly issuing the latch (host I/O is
// likely buffered, making usleep() unreliable for latch). You may see
// an initial glitchy frame or two until the two come into alignment.
// The magic word can be whatever sequence you like, but each character
// should be unique, and frequent pixel values like 0 and 255 are
// avoided -- fewer false positives. The host software will need to
// generate a compatible header: immediately following the magic word
// are three bytes: a 16-bit count of the number of LEDs (high byte
// first) followed by a simple checksum value (high byte XOR low byte
// XOR 0x55). LED data follows, 3 bytes per LED, in order R, G, B,
// where 0 = off and 255 = max brightness.

static const uint8_t magic[] = {
  'A', 'd', 'a'
};
#define MAGICSIZE  sizeof(magic)

// Check values are header byte # - 1, as they are indexed from 0
#define HICHECK    (MAGICSIZE)
#define LOCHECK    (MAGICSIZE + 1)
#define CHECKSUM   (MAGICSIZE + 2)

enum processModes_t {Header, Data} mode = Header;

static int16_t c = 0;
static uint16_t outPos = 0;
static uint16_t ledPos = 0;
static uint8_t ledClrIndex = 0;
static uint32_t bytesRemaining = 0;
static unsigned long t = 0L;
static unsigned long lastByteTime = 0L;
static unsigned long lastAckTime = 0L;

// Debug macros initialized
#ifdef DEBUG_LED
#define ON  1
#define OFF 0

#define D_LED(x) do {digitalWrite(DEBUG_LED, x);} while(0)
#else
#define D_LED(x)
#endif

#ifdef DEBUG_FPS
#define D_FPS do {digitalWrite(DEBUG_FPS, HIGH); digitalWrite(DEBUG_FPS, LOW);} while (0)
#else
#define D_FPS
#endif

void setup() {
#ifdef GROUND_PIN
  pinMode(GROUND_PIN, OUTPUT);
  digitalWrite(GROUND_PIN, LOW);
#endif

#ifdef DEBUG_LED
  pinMode(DEBUG_LED, OUTPUT);
  digitalWrite(DEBUG_LED, LOW);
#endif

#ifdef DEBUG_FPS
  pinMode(DEBUG_FPS, OUTPUT);
#endif

#ifdef PIN_CLOCK
  FastLED.addLeds<LED_TYPE, PIN_DATA, PIN_CLOCK, COLOR_ORDER>(leds, Num_Leds);
#else
  FastLED.addLeds<LED_TYPE, PIN_DATA, COLOR_ORDER>(leds, Num_Leds);
#endif

  FastLED.setCorrection(0xFFFDFE);
  //FastLED.setCorrection(TypicalLEDStrip);
  //FastLED.setCorrection(0xFFFFFF);

  FastLED.setBrightness(Brightness);

#ifdef CLEAR_ON_START
  FastLED.show();
#endif

  Serial.begin(SerialSpeed);
  Serial.print("Ada\n"); // Send ACK string to host

  lastByteTime = lastAckTime = millis(); // Set initial counters
}

void loop() {
  adalight();
}

void adalight() {
  t = millis(); // Save current time

  // If there is new serial data
  if ((c = Serial.read()) >= 0) {
    lastByteTime = lastAckTime = t; // Reset timeout counters

    switch (mode) {
      case Header:
        headerMode();
        break;
      case Data:
        dataMode();
        break;
    }
  }
  else {
    // No new data
    timeouts();
  }
}

void headerMode() {
  static uint8_t
  headPos,
  hi, lo, chk;

  if (headPos < MAGICSIZE) {
    // Check if magic word matches
    if (c == magic[headPos]) {
      headPos++;
    }
    else {
      headPos = 0;
    }
  }
  else {
    // Magic word matches! Now verify checksum
    switch (headPos) {
      case HICHECK:
        hi = c;
        headPos++;
        break;
      case LOCHECK:
        lo = c;
        headPos++;
        break;
      case CHECKSUM:
        chk = c;
        if (chk == (hi ^ lo ^ 0x55)) {
          // Checksum looks valid. Get 16-bit LED count, add 1
          // (# LEDs is always > 0) and multiply by 3 for R,G,B.
          D_LED(ON);
          bytesRemaining = 3L * (256L * (long)hi + (long)lo + 1L);
          outPos = 0;
          ledPos = 0;
          ledClrIndex = 0;
          memset(leds, 0, Num_Leds * sizeof(struct CRGB));
          mode = Data; // Proceed to latch wait mode
        }
        headPos = 0; // Reset header position regardless of checksum result
        break;
    }
  }
}

void dataMode() {
  // If LED data is not full
  if (outPos < sizeof(leds)) {
    dataSet();
  }
  bytesRemaining--;

  if (bytesRemaining == 0) {
    // End of data -- issue latch:
    mode = Header; // Begin next header search
    calcIntermediatePixels();
    FastLED.show();
    D_FPS;
    D_LED(OFF);
#ifdef SERIAL_FLUSH
    serialFlush();
#endif
  }
}

void dataSet() {
  ledsRaw[LEDS_GROUP * ledPos * 3 + ledClrIndex] = c;
  if (++ledClrIndex == 3)
  {
    ledClrIndex = 0;
    ++ledPos;
  }
  ++outPos;
}

void calcIntermediatePixels() {
  if (LEDS_GROUP <= 1) return;
  CRGB* pFirst = leds;
  const CRGB* pSecond = leds + LEDS_GROUP;
  uint8_t fraction;
  for (uint16_t i = 0; i < Num_Leds; i += LEDS_GROUP)
  {
    for (uint8_t j = 1; j < LEDS_GROUP; ++j)
    {
      fraction = 0xFF * j / LEDS_GROUP;
      pFirst[j] = pFirst->lerp8(*pSecond, fraction);
    }
    pFirst += LEDS_GROUP;
    pSecond += LEDS_GROUP;
    if (pSecond == leds + Num_Leds) pSecond = leds;
  }
}

void timeouts() {
  // No data received. If this persists, send an ACK packet
  // to host once every second to alert it to our presence.
  if ((t - lastAckTime) >= 1000) {
    Serial.print("Ada\n"); // Send ACK string to host
    lastAckTime = t; // Reset counter

    // If no data received for an extended time, turn off all LEDs.
    if (SerialTimeout != 0 && (t - lastByteTime) >= (uint32_t) SerialTimeout * 1000) {
      memset(leds, 0, Num_Leds * sizeof(struct CRGB)); //filling Led array by zeroes
      FastLED.show();
      mode = Header;
      lastByteTime = t; // Reset counter
    }
  }
}

void serialFlush() {
  while (Serial.available() > 0) {
    Serial.read();
  }
}
