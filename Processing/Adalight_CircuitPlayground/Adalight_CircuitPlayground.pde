// IMPORTANT: change 'serialPortIndex' to make this work on your system.

// This is a slightly pared-down version of Adalight specifically for
// Circuit Playground, configured for a single screen and 10 LEDs.

// "Adalight" is a do-it-yourself facsimile of the Philips Ambilight concept
// for desktop computers and home theater PCs.  This is the host PC-side code
// written in Processing, intended for use with a USB-connected Circuit
// Playground microcontroller running the accompanying LED streaming code.
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

// This selects from the list of serial devices connected to the system.
// Use print(Serial.list()); to get a list of ports.  Then, counting from 0,
// set this value to the index corresponding to the Circuit Playground port:

static final byte serialPortIndex = 2;

// For multi-screen systems, set this to the index (counting from 0) of the
// display which will have ambient lighting:

static final byte screenNumber = 0;

// Minimum LED brightness; some users prefer a small amount of backlighting
// at all times, regardless of screen content.  Higher values are brighter,
// or set to 0 to disable this feature.

static final short minBrightness = 100;

// LED transition speed; it's sometimes distracting if LEDs instantaneously
// track screen contents (such as during bright flashing sequences), so this
// feature enables a gradual fade to each new LED state.  Higher numbers yield
// slower transitions (max of 255), or set to 0 to disable this feature
// (immediate transition of all LEDs).

static final short fade = 60;

// Depending on many factors, it may be faster either to capture full
// screens and process only the pixels needed, or to capture multiple
// smaller sub-blocks bounding each region to be processed.  Try both,
// look at the reported frame rates in the Processing output console,
// and run with whichever works best for you.

static final boolean useFullScreenCaps = true;

// PER-LED INFORMATION -------------------------------------------------------

// The Circuit Playground version of Adalight operates on a fixed 5x5 grid
// encompassing the full display.  10 elements from this grid correspond to
// the 10 NeoPixels on the Circuit Playground board.  The following array
// contains the 2D coordinates of each NeoPixel within that 5x5 grid (0,0 is
// top left); board assumed facing away from display, with USB at bottom:
// .4.5.
// 3...6
// 2...7
// 1...8
// .0.9.

static final int leds[][] = new int[][] {
  {1,4}, {0,3}, {0,2}, {0,1}, {1,0},
  {3,0}, {4,1}, {4,2}, {4,3}, {3,4}
};

// GLOBAL VARIABLES ---- You probably won't need to modify any of this -------

byte      serialData[]    = new byte[6 + leds.length * 3],
          gamma[][]       = new byte[256][3];
short[][] ledColor        = new short[leds.length][3],
          prevColor       = new short[leds.length][3];
Robot     bot;
Rectangle dispBounds, ledBounds[];
int       pixelOffset[][] = new int[leds.length][256],
          screenData[];
PImage    preview;
Serial    port;

// INITIALIZATION ------------------------------------------------------------

void setup() {
  GraphicsEnvironment     ge;
  GraphicsConfiguration[] gc;
  GraphicsDevice[]        gd;
  int                     i, row, col;
  int[]                   x = new int[16], y = new int[16];
  float                   f, range, step, start;

  this.registerMethod("dispose", this);
  print(Serial.list()); // Show list of serial devices/ports
  // Open serial port.  Change serialPortIndex in the globals to
  // select a different port:
  port = new Serial(this, Serial.list()[serialPortIndex], 38400);

  // Initialize screen capture code for the display's dimensions.
  if(useFullScreenCaps == false) ledBounds = new Rectangle[leds.length];
  ge = GraphicsEnvironment.getLocalGraphicsEnvironment();
  gd = ge.getScreenDevices();

  try {
    bot = new Robot(gd[screenNumber]);
  }
  catch(AWTException e) {
    System.out.println("new Robot() failed");
    exit();
  }
  gc           = gd[screenNumber].getConfigurations();
  dispBounds   = gc[0].getBounds();
  dispBounds.x = dispBounds.y = 0;
  preview      = createImage(5, 5, RGB);
  preview.loadPixels();

  // Precompute locations of every pixel to read when downsampling.
  // Saves a bunch of math on each frame, at the expense of a chunk
  // of RAM.  Number of samples is now fixed at 256; this allows for
  // some crazy optimizations in the downsampling code.
  for(i=0; i<leds.length; i++) { // For each LED...
    // Precompute columns, rows of each sampled point for this LED
    range = (float)dispBounds.width / 5.0;
    step  = range / 16.0;
    start = range * (float)leds[i][0] + step * 0.5;
    for(col=0; col<16; col++) x[col] = (int)(start + step * (float)col);
    range = (float)dispBounds.height / 5.0;
    step  = range / 16.0;
    start = range * (float)leds[i][1] + step * 0.5;
    for(row=0; row<16; row++) y[row] = (int)(start + step * (float)row);
  
    if(useFullScreenCaps == true) {
      // Get offset to each pixel within full screen capture
      for(row=0; row<16; row++) {
        for(col=0; col<16; col++) {
          pixelOffset[i][row * 16 + col] =
            y[row] * dispBounds.width + x[col];
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

  size(200, 200, JAVA2D); // Preview window for 5x5 grid at 40X scale
  noSmooth();

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
    gamma[i][0] = (byte)(f * 255.0 + 0.5);
    gamma[i][1] = (byte)(f * 240.0 + 0.5);
    gamma[i][2] = (byte)(f * 220.0 + 0.5);
  }
}

// PER_FRAME PROCESSING ------------------------------------------------------

void draw () {
  BufferedImage img;
  int           i, j, o, c, weight, rb, g, sum, deficit, s2;
  int[]         pxls, offs;

  if(useFullScreenCaps == true ) {
    img = bot.createScreenCapture(dispBounds);
    // Get location of source pixel data
    screenData =
      ((DataBufferInt)img.getRaster().getDataBuffer()).getData();
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
    if(useFullScreenCaps == true) {
      // Get location of source data from prior full-screen capture:
      pxls = screenData;
    } else {
      // Capture section of screen (LED bounds rect) and locate data::
      img  = bot.createScreenCapture(ledBounds[i]);
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
    preview.pixels[leds[i][1] * 5 + leds[i][0]] = 0xFF000000 |
     (ledColor[i][0] << 16) | (ledColor[i][1] << 8) | ledColor[i][2];
  }

  if(port != null) port.write(serialData); // Issue data to Arduino

  // Show live preview image
  preview.updatePixels();
  scale(40);
  image(preview, 0, 0);

  println(frameRate); // How are we doing?

  // Copy LED color data to prior frame array for next pass
  arraycopy(ledColor, 0, prevColor, 0, ledColor.length);
}

// CLEANUP -------------------------------------------------------------------

// The DisposeHandler is called on program exit (but before the Serial library
// is shutdown), in order to turn off the LEDs (reportedly more reliable than
// stop()).  Seems to work for the window close box and escape key exit, but
// not the 'Quit' menu option.  Thanks to phi.lho in the Processing forums.

void dispose() {
    // Fill serialData (after header) with 0's, and issue to Arduino...
    java.util.Arrays.fill(serialData, 6, serialData.length, (byte)0);
    if(port != null) port.write(serialData);
}