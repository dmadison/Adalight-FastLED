// "Adalight" is a do-it-yourself facsimile of the Philips Ambilight concept
// for desktop computers and home theater PCs.  This is the host PC-side code
// written in Processing, intended for use with a USB-connected Arduino
// microcontroller running the accompanying LED streaming code.  Requires one
// or more strands of Digital RGB LED Pixels (Adafruit product ID #322,
// specifically the newer WS2801-based type, strand of 25) and a 5 Volt power
// supply (such as Adafruit #276).  You may need to adapt the code and the
// hardware arrangement for your specific display configuration.
// Screen capture adapted from code by Cedrik Kiefer (processing.org forum)

// --------------------------------------------------------------------
//   This file is part of Adalight.

//   Adalight is free software: you can redistribute it and/or modify
//   it under the terms of the GNU Lesser General Public License as
//   published by the Free Software Foundation, either version 3 of
//   the License, or (at your option) any later version.

//   Adalight is distributed in the hope that it will be useful,
//   but WITHOUT ANY WARRANTY; without even the implied warranty of
//   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//   GNU Lesser General Public License for more details.

//   You should have received a copy of the GNU Lesser General Public
//   License along with Adalight.  If not, see
//   <http://www.gnu.org/licenses/>.
// --------------------------------------------------------------------

import java.awt.*;
import java.awt.image.*;
import processing.serial.*;

// CONFIGURABLE PROGRAM CONSTANTS --------------------------------------------

// Minimum LED brightness; some users prefer a small amount of backlighting
// at all times, regardless of screen content.  Higher values are brighter,
// or set to 0 to disable this feature.

static final short minBrightness = 120;

// LED transition speed; it's sometimes distracting if LEDs instantaneously
// track screen contents (such as during bright flashing sequences), so this
// feature enables a gradual fade to each new LED state.  Higher numbers yield
// slower transitions (max of 255), or set to 0 to disable this feature
// (immediate transition of all LEDs).

static final short fade = 75;

// Pixel size for the live preview image.

static final int pixelSize = 20;

// Depending on many factors, it may be faster either to capture full
// screens and process only the pixels needed, or to capture multiple
// smaller sub-blocks bounding each region to be processed.  Try both,
// look at the reported frame rates in the Processing output console,
// and run with whichever works best for you.

static final boolean useFullScreenCaps = true;

// Serial device timeout (in milliseconds), for locating Arduino device
// running the corresponding LEDstream code.  See notes later in the code...
// in some situations you may want to entirely comment out that block.

static final int timeout = 5000; // 5 seconds

// PER-DISPLAY INFORMATION ---------------------------------------------------

// This array contains details for each display that the software will
// process.  If you have screen(s) attached that are not among those being
// "Adalighted," they should not be in this list.  Each triplet in this
// array represents one display.  The first number is the system screen
// number...typically the "primary" display on most systems is identified
// as screen #1, but since arrays are indexed from zero, use 0 to indicate
// the first screen, 1 to indicate the second screen, and so forth.  This
// is the ONLY place system screen numbers are used...ANY subsequent
// references to displays are an index into this list, NOT necessarily the
// same as the system screen number.  For example, if you have a three-
// screen setup and are illuminating only the third display, use '2' for
// the screen number here...and then, in subsequent section, '0' will be
// used to refer to the first/only display in this list.
// The second and third numbers of each triplet represent the width and
// height of a grid of LED pixels attached to the perimeter of this display.
// For example, '9,6' = 9 LEDs across, 6 LEDs down.

static final int displays[][] = new int[][] {
   {0,9,6} // Screen 0, 9 LEDs across, 6 LEDs down
//,{1,9,6} // Screen 1, also 9 LEDs across and 6 LEDs down
};

// PER-LED INFORMATION -------------------------------------------------------

// This array contains the 2D coordinates corresponding to each pixel in the
// LED strand, in the order that they're connected (i.e. the first element
// here belongs to the first LED in the strand, second element is the second
// LED, and so forth).  Each triplet in this array consists of a display
// number (an index into the display array above, NOT necessarily the same as
// the system screen number) and an X and Y coordinate specified in the grid
// units given for that display.  {0,0,0} is the top-left corner of the first
// display in the array.
// For our example purposes, the coordinate list below forms a ring around
// the perimeter of a single screen, with a one pixel gap at the bottom to
// accommodate a monitor stand.  Modify this to match your own setup:

static final int leds[][] = new int[][] {
  {0,3,5}, {0,2,5}, {0,1,5}, {0,0,5}, // Bottom edge, left half
  {0,0,4}, {0,0,3}, {0,0,2}, {0,0,1}, // Left edge
  {0,0,0}, {0,1,0}, {0,2,0}, {0,3,0}, {0,4,0}, // Top edge
           {0,5,0}, {0,6,0}, {0,7,0}, {0,8,0}, // More top edge
  {0,8,1}, {0,8,2}, {0,8,3}, {0,8,4}, // Right edge
  {0,8,5}, {0,7,5}, {0,6,5}, {0,5,5}  // Bottom edge, right half

/* Hypothetical second display has the same arrangement as the first.
   But you might not want both displays completely ringed with LEDs;
   the screens might be positioned where they share an edge in common.
 ,{1,3,5}, {1,2,5}, {1,1,5}, {1,0,5}, // Bottom edge, left half
  {1,0,4}, {1,0,3}, {1,0,2}, {1,0,1}, // Left edge
  {1,0,0}, {1,1,0}, {1,2,0}, {1,3,0}, {1,4,0}, // Top edge
           {1,5,0}, {1,6,0}, {1,7,0}, {1,8,0}, // More top edge
  {1,8,1}, {1,8,2}, {1,8,3}, {1,8,4}, // Right edge
  {1,8,5}, {1,7,5}, {1,6,5}, {1,5,5}  // Bottom edge, right half
*/
};

// GLOBAL VARIABLES ---- You probably won't need to modify any of this -------

byte[]           serialData  = new byte[6 + leds.length * 3];
short[][]        ledColor    = new short[leds.length][3],
                 prevColor   = new short[leds.length][3];
byte[][]         gamma       = new byte[256][3];
int              nDisplays   = displays.length;
Robot[]          bot         = new Robot[displays.length];
Rectangle[]      dispBounds  = new Rectangle[displays.length],
                 ledBounds;  // Alloc'd only if per-LED captures
int[][]          pixelOffset = new int[leds.length][256],
                 screenData; // Alloc'd only if full-screen captures
PImage[]         preview     = new PImage[displays.length];
Serial           port;
DisposeHandler   dh; // For disabling LEDs on exit

// INITIALIZATION ------------------------------------------------------------

void setup() {
  GraphicsEnvironment     ge;
  GraphicsConfiguration[] gc;
  GraphicsDevice[]        gd;
  int                     d, i, totalWidth, maxHeight, row, col, rowOffset;
  int[]                   x = new int[16], y = new int[16];
  float                   f, range, step, start;

  dh = new DisposeHandler(this); // Init DisposeHandler ASAP

  // Open serial port.  As written here, this assumes the Arduino is the
  // first/only serial device on the system.  If that's not the case,
  // change "Serial.list()[0]" to the name of the port to be used:
  port = new Serial(this, Serial.list()[0], 115200);
  // Alternately, in certain situations the following line can be used
  // to detect the Arduino automatically.  But this works ONLY with SOME
  // Arduino boards and versions of Processing!  This is so convoluted
  // to explain, it's easier just to test it yourself and see whether
  // it works...if not, leave it commented out and use the prior port-
  // opening technique.
  // port = openPort();
  // And finally, to test the software alone without an Arduino connected,
  // don't open a port...just comment out the serial lines above.

  // Initialize screen capture code for each display's dimensions.
  dispBounds = new Rectangle[displays.length];
  if(useFullScreenCaps == true) {
    screenData = new int[displays.length][];
    // ledBounds[] not used
  } else {
    ledBounds  = new Rectangle[leds.length];
    // screenData[][] not used
  }
  ge = GraphicsEnvironment.getLocalGraphicsEnvironment();
  gd = ge.getScreenDevices();
  if(nDisplays > gd.length) nDisplays = gd.length;
  totalWidth = maxHeight = 0;
  for(d=0; d<nDisplays; d++) { // For each display...
    try {
      bot[d] = new Robot(gd[displays[d][0]]);
    }
    catch(AWTException e) {
      System.out.println("new Robot() failed");
      continue;
    }
    gc              = gd[displays[d][0]].getConfigurations();
    dispBounds[d]   = gc[0].getBounds();
    dispBounds[d].x = dispBounds[d].y = 0;
    preview[d]      = createImage(displays[d][1], displays[d][2], RGB);
    preview[d].loadPixels();
    totalWidth     += displays[d][1];
    if(d > 0) totalWidth++;
    if(displays[d][2] > maxHeight) maxHeight = displays[d][2];
  }

  // Precompute locations of every pixel to read when downsampling.
  // Saves a bunch of math on each frame, at the expense of a chunk
  // of RAM.  Number of samples is now fixed at 256; this allows for
  // some crazy optimizations in the downsampling code.
  for(i=0; i<leds.length; i++) { // For each LED...
    d = leds[i][0]; // Corresponding display index

    // Precompute columns, rows of each sampled point for this LED
    range = (float)dispBounds[d].width / (float)displays[d][1];
    step  = range / 16.0;
    start = range * (float)leds[i][1] + step * 0.5;
    for(col=0; col<16; col++) x[col] = (int)(start + step * (float)col);
    range = (float)dispBounds[d].height / (float)displays[d][2];
    step  = range / 16.0;
    start = range * (float)leds[i][2] + step * 0.5;
    for(row=0; row<16; row++) y[row] = (int)(start + step * (float)row);

    if(useFullScreenCaps == true) {
      // Get offset to each pixel within full screen capture
      for(row=0; row<16; row++) {
        for(col=0; col<16; col++) {
          pixelOffset[i][row * 16 + col] =
            y[row] * dispBounds[d].width + x[col];
        }
      }
    } else {
      // Calc min bounding rect for LED, get offset to each pixel within
      ledBounds[i] = new Rectangle(x[0], y[0], x[15]-x[0]+1, y[15]-y[0]+1);
      for(row=0; row<16; row++) {
        for(col=0; col<16; col++) {
          pixelOffset[i][row * 16 + col] =
            (y[row] - y[0]) * ledBounds[i].width + x[col] - x[0];
        }
      }
    }
  }

  for(i=0; i<prevColor.length; i++) {
    prevColor[i][0] = prevColor[i][1] = prevColor[i][2] =
      minBrightness / 3;
  }

  // Preview window shows all screens side-by-side
  size(totalWidth * pixelSize, maxHeight * pixelSize, JAVA2D);

  // A special header / magic word is expected by the corresponding LED
  // streaming code running on the Arduino.  This only needs to be initialized
  // once (not in draw() loop) because the number of LEDs remains constant:
  serialData[0] = 'A';                              // Magic word
  serialData[1] = 'd';
  serialData[2] = 'a';
  serialData[3] = (byte)((leds.length - 1) >> 8);   // LED count high byte
  serialData[4] = (byte)((leds.length - 1) & 0xff); // LED count low byte
  serialData[5] = (byte)(serialData[3] ^ serialData[4] ^ 0x55); // Checksum

  // Pre-compute gamma correction table for LED brightness levels:
  for(i=0; i<256; i++) {
    f           = pow((float)i / 255.0, 2.8);
    gamma[i][0] = (byte)(f * 255.0);
    gamma[i][1] = (byte)(f * 240.0);
    gamma[i][2] = (byte)(f * 220.0);
  }
}

// Open and return serial connection to Arduino running LEDstream code.  This
// attempts to open and read from each serial device on the system, until the
// matching "Ada\n" acknowledgement string is found.  Due to the serial
// timeout, if you have multiple serial devices/ports and the Arduino is late
// in the list, this can take seemingly forever...so if you KNOW the Arduino
// will always be on a specific port (e.g. "COM6"), you might want to comment
// out most of this to bypass the checks and instead just open that port
// directly!  (Modify last line in this method with the serial port name.)

Serial openPort() {
  String[] ports;
  String   ack;
  int      i, start;
  Serial   s;

  ports = Serial.list(); // List of all serial ports/devices on system.

  for(i=0; i<ports.length; i++) { // For each serial port...
    System.out.format("Trying serial port %s\n",ports[i]);
    try {
      s = new Serial(this, ports[i], 115200);
    }
    catch(Exception e) {
      // Can't open port, probably in use by other software.
      continue;
    }
    // Port open...watch for acknowledgement string...
    start = millis();
    while((millis() - start) < timeout) {
      if((s.available() >= 4) &&
        ((ack = s.readString()) != null) &&
        ack.contains("Ada\n")) {
          return s; // Got it!
      }
    }
    // Connection timed out.  Close port and move on to the next.
    s.stop();
  }

  // Didn't locate a device returning the acknowledgment string.
  // Maybe it's out there but running the old LEDstream code, which
  // didn't have the ACK.  Can't say for sure, so we'll take our
  // changes with the first/only serial device out there...
  return new Serial(this, ports[0], 115200);
}


// PER_FRAME PROCESSING ------------------------------------------------------

void draw () {
  BufferedImage img;
  int           d, i, j, o, c, weight, rb, g, sum, deficit, s2;
  int[]         pxls, offs;

  if(useFullScreenCaps == true ) {
    // Capture each screen in the displays array.
    for(d=0; d<nDisplays; d++) {
      img = bot[d].createScreenCapture(dispBounds[d]);
      // Get location of source pixel data
      screenData[d] =
        ((DataBufferInt)img.getRaster().getDataBuffer()).getData();
    }
  }

  weight = 257 - fade; // 'Weighting factor' for new frame vs. old
  j      = 6;          // Serial led data follows header / magic word

  // This computes a single pixel value filtered down from a rectangular
  // section of the screen.  While it would seem tempting to use the native
  // image scaling in Processing/Java, in practice this didn't look very
  // good -- either too pixelated or too blurry, no happy medium.  So
  // instead, a "manual" downsampling is done here.  In the interest of
  // speed, it doesn't actually sample every pixel within a block, just
  // a selection of 256 pixels spaced within the block...the results still
  // look reasonably smooth and are handled quickly enough for video.

  for(i=0; i<leds.length; i++) {  // For each LED...
    d = leds[i][0]; // Corresponding display index
    if(useFullScreenCaps == true) {
      // Get location of source data from prior full-screen capture:
      pxls = screenData[d];
    } else {
      // Capture section of screen (LED bounds rect) and locate data::
      img  = bot[d].createScreenCapture(ledBounds[i]);
      pxls = ((DataBufferInt)img.getRaster().getDataBuffer()).getData();
    }
    offs = pixelOffset[i];
    rb = g = 0;
    for(o=0; o<256; o++) {
      c   = pxls[offs[o]];
      rb += c & 0x00ff00ff; // Bit trickery: R+B can accumulate in one var
      g  += c & 0x0000ff00;
    }

    // Blend new pixel value with the value from the prior frame
    ledColor[i][0]  = (short)((((rb >> 24) & 0xff) * weight +
                               prevColor[i][0]     * fade) >> 8);
    ledColor[i][1]  = (short)(((( g >> 16) & 0xff) * weight +
                               prevColor[i][1]     * fade) >> 8);
    ledColor[i][2]  = (short)((((rb >>  8) & 0xff) * weight +
                               prevColor[i][2]     * fade) >> 8);

    // Boost pixels that fall below the minimum brightness
    sum = ledColor[i][0] + ledColor[i][1] + ledColor[i][2];
    if(sum < minBrightness) {
      if(sum == 0) { // To avoid divide-by-zero
        deficit = minBrightness / 3; // Spread equally to R,G,B
        ledColor[i][0] += deficit;
        ledColor[i][1] += deficit;
        ledColor[i][2] += deficit;
      } else {
        deficit = minBrightness - sum;
        s2      = sum * 2;
        // Spread the "brightness deficit" back into R,G,B in proportion to
        // their individual contribition to that deficit.  Rather than simply
        // boosting all pixels at the low end, this allows deep (but saturated)
        // colors to stay saturated...they don't "pink out."
        ledColor[i][0] += deficit * (sum - ledColor[i][0]) / s2;
        ledColor[i][1] += deficit * (sum - ledColor[i][1]) / s2;
        ledColor[i][2] += deficit * (sum - ledColor[i][2]) / s2;
      }
    }

    // Apply gamma curve and place in serial output buffer
    serialData[j++] = gamma[ledColor[i][0]][0];
    serialData[j++] = gamma[ledColor[i][1]][1];
    serialData[j++] = gamma[ledColor[i][2]][2];
    // Update pixels in preview image
    preview[d].pixels[leds[i][2] * displays[d][1] + leds[i][1]] =
     (ledColor[i][0] << 16) | (ledColor[i][1] << 8) | ledColor[i][2];
  }

  if(port != null) port.write(serialData); // Issue data to Arduino

  // Show live preview image(s)
  scale(pixelSize);
  for(i=d=0; d<nDisplays; d++) {
    preview[d].updatePixels();
    image(preview[d], i, 0);
    i += displays[d][1] + 1;
  }

  println(frameRate); // How are we doing?

  // Copy LED color data to prior frame array for next pass
  arraycopy(ledColor, 0, prevColor, 0, ledColor.length);
}


// CLEANUP -------------------------------------------------------------------

// The DisposeHandler is called on program exit (but before the Serial library
// is shutdown), in order to turn off the LEDs (reportedly more reliable than
// stop()).  Seems to work for the window close box and escape key exit, but
// not the 'Quit' menu option.  Thanks to phi.lho in the Processing forums.

public class DisposeHandler {
  DisposeHandler(PApplet pa) {
    pa.registerDispose(this);
  }
  public void dispose() {
    // Fill serialData (after header) with 0's, and issue to Arduino...
    Arrays.fill(serialData, 6, serialData.length, (byte)0);
    if(port != null) port.write(serialData);
  }
}

