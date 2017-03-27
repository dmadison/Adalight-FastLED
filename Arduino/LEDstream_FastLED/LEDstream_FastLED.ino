/* LEDstream_FastLED
 * 
 * Modified version of Adalight protocol that uses the FastLED
 * library (http://fastled.io) for driving led strips.
 * 
 * http://github.com/dmadison/Adalight-FastLED
 * Last Updated: 2017-03-27
 */

// --- General Settings
static const uint8_t 
	Num_Leds   =  80,        // strip length
	Led_Pin    =  6,         // Arduino data output pin
	Brightness =  255;       // maximum brightness

// --- FastLED Setings
#define LED_TYPE     WS2812B // led strip type for FastLED
#define COLOR_ORDER  GRB     // color order for bitbang

// --- Serial Settings
static const unsigned long
	SerialSpeed    = 115200, // serial port speed, max available
	SerialTimeout  = 150000; // time before LEDs are shut off, if no data
							 // (150 seconds)

// --- Optional Settings (uncomment to add)
//#define CLEAR_ON_START     // LEDs are cleared on reset
//#define GROUND_PIN 10      // additional grounding pin (optional)
//#define CALIBRATE          // sets all LEDs to the color of the first

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
	'A','d','a'};
#define MAGICSIZE  sizeof(magic)
#define HEADERSIZE (MAGICSIZE + 3)

#define MODE_HEADER 0
#define MODE_DATA   2

void setup(){
	#ifdef GROUND_PIN
		pinMode(GROUND_PIN, OUTPUT);
		digitalWrite(GROUND_PIN, LOW);
	#endif

	FastLED.addLeds<LED_TYPE, Led_Pin, COLOR_ORDER>(leds, Num_Leds);
	FastLED.setBrightness(Brightness);

	#ifdef CLEAR_ON_START
		FastLED.show();
	#endif

	Serial.begin(SerialSpeed);

	adalight();
}

void adalight(){ 
	// Dirty trick: the circular buffer for serial data is 256 bytes,
	// and the "in" and "out" indices are unsigned 8-bit types -- this
	// much simplifies the cases where in/out need to "wrap around" the
	// beginning/end of the buffer. Otherwise there'd be a ton of bit-
	// masking and/or conditional code every time one of these indices
	// needs to change, slowing things down tremendously.

	uint8_t
		buffer[256],
		indexIn       = 0,
		indexOut      = 0,
		mode          = MODE_HEADER,
		hi, lo, chk, i;
	int16_t
		c;
	uint16_t
		bytesBuffered = 0;
	uint32_t
		bytesRemaining,
		outPos;
	unsigned long
		lastByteTime,
		lastAckTime,
		t;

	Serial.print("Ada\n"); // Send ACK string to host

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
			// No data received. If this persists, send an ACK packet
			// to host once every second to alert it to our presence.
			if((t - lastAckTime) > 1000) {
				Serial.print("Ada\n"); // Send ACK string to host
				lastAckTime = t; // Reset counter
			}
			// If no data received for an extended time, turn off all LEDs.
			if((t - lastByteTime) > SerialTimeout) {
				memset(leds, 0, Num_Leds * sizeof(struct CRGB)); //filling Led array by zeroes
				FastLED.show();
				lastByteTime = t; // Reset counter
			}
		}

		switch(mode) {

		case MODE_HEADER:

			// In header-seeking mode. Is there enough data to check?
			if(bytesBuffered >= HEADERSIZE) {
				// Indeed. Check for a 'magic word' match.
				for(i=0; (i<MAGICSIZE) && (buffer[indexOut++] == magic[i++]););
				if(i == MAGICSIZE) {
					// Magic word matches. Now how about the checksum?
					hi  = buffer[indexOut++];
					lo  = buffer[indexOut++];
					chk = buffer[indexOut++];
					if(chk == (hi ^ lo ^ 0x55)) {
						// Checksum looks valid. Get 16-bit LED count, add 1
						// (# LEDs is always > 0) and multiply by 3 for R,G,B.
						bytesRemaining = 3L * (256L * (long)hi + (long)lo + 1L);
						bytesBuffered -= 3;
						outPos = 0;
						memset(leds, 0, Num_Leds * sizeof(struct CRGB));
						mode           = MODE_DATA; // Proceed to latch wait mode
					} 
					else {
						// Checksum didn't match; search resumes after magic word.
						indexOut -= 3; // Rewind
					}
				} // else no header match. Resume at first mismatched byte.
				bytesBuffered -= i;
			}
			break;

		case MODE_DATA:

			if(bytesRemaining > 0) {
				if(bytesBuffered > 0) {
					if (outPos < sizeof(leds)){
						#ifdef CALIBRATE
							if(outPos < 3)
								ledsRaw[outPos++] = buffer[indexOut++];
							else{
								ledsRaw[outPos] = ledsRaw[outPos%3]; // Sets RGB data to first LED color
								outPos++;
								indexOut++;
							}
						#else
							ledsRaw[outPos++] = buffer[indexOut++]; // Issue next byte
						#endif
					}
					bytesBuffered--;
					bytesRemaining--;
				}
			}
			else {
				// End of data -- issue latch:
				mode       = MODE_HEADER; // Begin next header search
				FastLED.show();
			}
		} // end switch
	} // end for(;;)
}

void loop()
{
	// Not used. See note in adalight() function.
}
