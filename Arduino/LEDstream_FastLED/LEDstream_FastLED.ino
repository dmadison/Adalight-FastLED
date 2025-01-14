/*
 *  Project     Adalight FastLED
 *  @author     David Madison
 *  @link       github.com/dmadison/Adalight-FastLED
 *  @license    LGPL - Copyright (c) 2017 David Madison
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#include <Arduino.h>

// --- General Settings
const uint16_t 
	Num_Leds   =  80;         // strip length
const uint8_t
	Brightness =  255;        // maximum brightness

// --- FastLED Setings
#define LED_TYPE     WS2812B  // led strip type for FastLED
#define COLOR_ORDER  GRB      // color order for bitbang
#define PIN_DATA     6        // led data output pin
// #define PIN_CLOCK  7       // led data clock pin (uncomment if you're using a 4-wire LED type)

// --- Serial Settings
const unsigned long
	SerialSpeed    = 115200;  // serial port speed
const uint16_t
	SerialTimeout  = 60;      // time before LEDs are shut off if no data (in seconds), 0 to disable

// --- Group Settings (uncomment to add)
// Grouping will set a group of LEDs to the data received for a single one. This
// lets you send less data to the device, increasing throughput and therefore
// framerate - at the cost of resolution. Grouping only works if your strip is
// evenly divisible by the amount of data sent.
// #define GROUPING           // enable the automatic grouping feature

// --- Optional Settings (uncomment to add)
#define SERIAL_FLUSH          // Serial buffer cleared on LED latch
// #define CLEAR_ON_START     // LEDs are cleared on reset

// --- Debug Settings (uncomment to add)
// #define DEBUG_LED 13       // toggles the Arduino's built-in LED on header match
// #define DEBUG_FPS 8        // enables a pulse on LED latch

// --------------------------------------------------------------------

#include <FastLED.h>

CRGB leds[Num_Leds];

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

const uint8_t magic[] = {
	'A','d','a'};
#define MAGICSIZE  sizeof(magic)

// Check values are header byte # - 1, as they are indexed from 0
#define HICHECK    (MAGICSIZE)
#define LOCHECK    (MAGICSIZE + 1)
#define CHECKSUM   (MAGICSIZE + 2)

enum processModes_t {Header, Data} mode = Header;

uint32_t ledIndex;           // current index in the LED array
uint32_t ledsRemaining;      // count of LEDs still to write, set by checksum (u16 + 1)

unsigned long lastByteTime;  // ms timestamp, last byte received
unsigned long lastAckTime;   // ms timestamp, lask acknowledge to the host

unsigned long (*const now)(void) = millis;  // timing function
const unsigned long Timebase     = 1000;    // time units per second

void headerMode(uint8_t c);
void dataMode(uint8_t c);
void groupProcessing();
void timeouts();

// Macros initialized
#ifdef SERIAL_FLUSH
	#undef SERIAL_FLUSH
	#define SERIAL_FLUSH while(Serial.available() > 0) { Serial.read(); }
#else
	#define SERIAL_FLUSH
#endif

#ifdef DEBUG_LED
	#define D_LED(x) do {digitalWrite(DEBUG_LED, x);} while(0)
#else
	#define D_LED(x)
#endif

#ifdef DEBUG_FPS
	#define D_FPS do {digitalWrite(DEBUG_FPS, HIGH); digitalWrite(DEBUG_FPS, LOW);} while (0)
#else
	#define D_FPS
#endif

void setup(){
	#ifdef DEBUG_LED
		pinMode(DEBUG_LED, OUTPUT);
		digitalWrite(DEBUG_LED, LOW);
	#endif

	#ifdef DEBUG_FPS
		pinMode(DEBUG_FPS, OUTPUT);
	#endif

	#if defined(PIN_CLOCK) && defined(PIN_DATA)
		FastLED.addLeds<LED_TYPE, PIN_DATA, PIN_CLOCK, COLOR_ORDER>(leds, Num_Leds);
	#elif defined(PIN_DATA)
		FastLED.addLeds<LED_TYPE, PIN_DATA, COLOR_ORDER>(leds, Num_Leds);
	#else
		#error "No LED output pins defined. Check your settings at the top."
	#endif
	
	FastLED.setBrightness(Brightness);

	#ifdef CLEAR_ON_START
		FastLED.show();
	#endif

	Serial.begin(SerialSpeed);
	Serial.print("Ada\n"); // Send ACK string to host

	lastByteTime = lastAckTime = millis(); // Set initial counters
}

void loop(){ 
	const int c = Serial.read();  // read one byte

	// if there is data available
	if(c >= 0){
		lastByteTime = lastAckTime = now(); // Reset timeout counters

		switch(mode) {
			case Header:
				headerMode(c);
				break;
			case Data:
				dataMode(c);
				break;
		}
	}
	else {
		// No new data
		timeouts();
	}
}

void headerMode(uint8_t c){
	static uint8_t
		headPos,
		hi, lo, chk;

	if(headPos < MAGICSIZE){
		// Check if magic word matches
		if(c == magic[headPos]) {headPos++;}
		else {headPos = 0;}
	}
	else{
		// Magic word matches! Now verify checksum
		switch(headPos){
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
				if(chk == (hi ^ lo ^ 0x55)) {
					// Checksum looks valid. Get 16-bit LED count, add 1
					// (# of LEDs is always > 0), save and reset data
					D_LED(HIGH);
					ledIndex = 0;
					ledsRemaining = (256UL * (uint32_t)hi + (uint32_t)lo + 1UL);
					memset(leds, 0, Num_Leds * sizeof(struct CRGB));
					mode = Data; // Proceed to latch wait mode
				}
				headPos = 0; // Reset header position regardless of checksum result
				break;
		}
	}
}

void dataMode(uint8_t c){
	static uint8_t channelIndex = 0;

	// if LED data is not full, save the byte
	if (ledIndex < Num_Leds) {
		leds[ledIndex].raw[channelIndex] = c;
	}
	channelIndex++;  // increment regardless, for oversized data

	// if we've filled this LED, move to the next
	if (channelIndex >= 3) {
		// reset the channel index so we can get ready to write
		// the next LED, starting on the first channel (R/G/B)
		channelIndex = 0;

		// allow this to max out at Num_Leds, so that it represents which
		// LEDs have data in them when the strip is ready to write
		if (ledIndex < Num_Leds) ledIndex++;

		// finished writing one LED, decrement the counter
		ledsRemaining--;
	}

	// if all data has been read, write the output
	if (ledsRemaining == 0) {
		#if defined(GROUPING)
		groupProcessing();
		#endif

		FastLED.show();
		channelIndex = 0;  // reset channel tracking
		mode = Header;     // begin next header search

		D_FPS;
		D_LED(LOW);
		SERIAL_FLUSH;
	}
}

void groupProcessing() {
	// if we've received the same amount of data as there
	// are LEDs in the strip, don't do any group processing
	if (Num_Leds == ledIndex) return;

	const uint16_t GroupSize      = Num_Leds / ledIndex;
	const uint16_t GroupRemainder = Num_Leds - (ledIndex * GroupSize);

	// if the value isn't evenly divisible, don't bother trying to group
	// (it won't look right without significant processing, i.e. overhead)
	if (GroupRemainder != 0) return;

	// otherwise, iterate backwards through the array, copying each LED color
	// forwards to the rest of its group
	for (uint16_t group = 1; group <= ledIndex; ++group) {
		const CRGB     GroupColor = leds[ledIndex - group];
		const uint16_t GroupStart = Num_Leds - (group * GroupSize);
		fill_solid(&leds[GroupStart], GroupSize, GroupColor);
	}
}

void timeouts(){
	const unsigned long t = now();

	// No data received. If this persists, send an ACK packet
	// to host once every second to alert it to our presence.
	if((t - lastAckTime) >= Timebase) {
		Serial.print("Ada\n"); // Send ACK string to host
		lastAckTime = t; // Reset counter

		// If no data received for an extended time, turn off all LEDs.
		if(SerialTimeout != 0 && (t - lastByteTime) >= (uint32_t) SerialTimeout * Timebase) {
			memset(leds, 0, Num_Leds * sizeof(struct CRGB)); //filling Led array by zeroes
			FastLED.show();
			mode = Header;
			lastByteTime = t; // Reset counter
		}
	}
}
