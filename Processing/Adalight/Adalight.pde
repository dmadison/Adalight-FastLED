// "Adalight" is a do-it-yourself facsimile of the Philips Ambilight concept
// for desktop computers and home theater PCs.  This is the host PC-side code
// written in Processing; intended for use with a USB-connected Arduino
// microcontroller running the accompanying LED streaming code.  Requires one
// strand of Digital RGB LED Pixels (Adafruit product ID #322, specifically
// the newer WS2801-based type, strand of 25) and a 5 Volt power supply (such
// as Adafruit #276).  You may need to adapt the code and the hardware
// arrangement for your specific display configuration.
// Screen capture adapted from code by Cedrik Kiefer (processing.org forum)

import java.awt.*;
import java.awt.image.*;
import processing.serial.*;

// This array contains the 2D image coordinates corresponding to each pixel
// in the LED strand, which forms a ring around the perimeter of the screen
// (with a one pixel gap at the bottom to accommodate the monitor stand).

static final int coord[][] = new int[][] {
  {3,5}, {2,5}, {1,5}, {0,5},                       // Bottom edge, left half
  {0,4}, {0,3}, {0,2}, {0,1},                                    // Left edge
  {0,0}, {1,0}, {2,0}, {3,0}, {4,0}, {5,0}, {6,0}, {7,0}, {8,0}, // Top edge
  {8,1}, {8,2}, {8,3}, {8,4},                                    // Right edge
  {8,5}, {7,5}, {6,5}, {5,5}                        // Bottom edge, right half
};

static final int arrayWidth  = 9,  // Width of Adalight array, in LED pixels
                 arrayHeight = 6,  // Height of Adalight array, in LED pixels
                 imgScale    = 20, // Size of displayed preview
                 samples     = 20, // Samples (per axis) when down-scaling
                 s2          = samples * samples;

byte[]           buffer  = new byte[6 + coord.length * 3];
byte[][]         gamma   = new byte[256][3];
GraphicsDevice[] gs;
PImage           preview = createImage(arrayWidth, arrayHeight, RGB);
Rectangle        bounds;
Serial           port;

void setup() {
  GraphicsEnvironment ge;
  DisplayMode         mode;
  int                 i;
  float               f;

  port = new Serial(this, Serial.list()[0], 115200);

  size(arrayWidth * imgScale, arrayHeight * imgScale, JAVA2D);

  // Initialize capture code for full screen dimensions:
  ge     = GraphicsEnvironment.getLocalGraphicsEnvironment();
  gs     = ge.getScreenDevices();
  mode   = gs[0].getDisplayMode();
  bounds = new Rectangle(0, 0, screen.width, screen.height);

  // A special header / magic word is expected by the corresponding LED
  // streaming code running on the Arduino.  This only needs to be initialized
  // once (not in draw() loop) because the number of LEDs remains constant:
  buffer[0] = 'A';                                // Magic word
  buffer[1] = 'd';
  buffer[2] = 'a';
  buffer[3] = byte((coord.length - 1) >> 8);      // LED count high byte
  buffer[4] = byte((coord.length - 1) & 0xff);    // LED count low byte
  buffer[5] = byte(buffer[3] ^ buffer[4] ^ 0x55); // Checksum

  // Pre-compute gamma correction table for LED brightness levels:
  for(i = 0; i < 256; i++) {
    f           = pow(float(i) / 255.0, 2.8);
    gamma[i][0] = byte(f * 255.0);
    gamma[i][1] = byte(f * 240.0);
    gamma[i][2] = byte(f * 220.0);
  }
}

void draw () {
  BufferedImage desktop;
  PImage        screenShot;
  int           i, j, c;

  // Capture screen
  try {
    desktop = new Robot(gs[0]).createScreenCapture(bounds);
  }
  catch(AWTException e) {
    System.err.println("Screen capture failed.");
    return;
  }
  screenShot = new PImage(desktop);  // Convert Image to PImage
  screenShot.loadPixels();           // Make pixel array readable

  // Downsample blocks of interest into LED output buffer:
  preview.loadPixels();  // Also display in preview image
  j = 6;  // Data follows LED header / magic word
  for(i = 0; i < coord.length; i++) {  // For each LED...
    c           = block(screenShot, coord[i][0], coord[i][1]);
    buffer[j++] = gamma[(c >> 16) & 0xff][0];
    buffer[j++] = gamma[(c >>  8) & 0xff][1];
    buffer[j++] = gamma[ c        & 0xff][2];
    preview.pixels[coord[i][1] * arrayWidth + coord[i][0]] = c;
  }
  preview.updatePixels();

  // Show preview image
  scale(imgScale);
  image(preview,0,0);
  println(frameRate);

  port.write(buffer);
}

// This method computes a single pixel value filtered down from a rectangular
// section of the screen.  While it would seem tempting to use the native
// image scaling in Processing, in practice this didn't look very good -- the
// extreme downsampling, coupled with the native interpolation mode, results
// in excessive scintillation with video content.  An alternate approach
// using the Java AWT AreaAveragingScaleFilter filter produces wonderfully
// smooth results, but is too slow for filtering full-screen video.  So
// instead, a "manual" downsampling method is used here.  In the interest of
// speed, it doesn't actually sample every pixel within a block, just a 20x20
// grid...the results still look reasonably smooth and are handled quickly
// enough for video.  Scaling the full screen image also wastes a lot of
// cycles on center pixels that are never used for the LED output; this
// method gets called only for perimeter pixels.  Even then, you may want to
// set your monitor for a lower resolution before running this sketch.

color block(PImage image, int x, int y) {
  int   c, r, g, b, row, col, rowOffset;
  float startX, curX, curY, incX, incY;

  startX = float(screen.width  / arrayWidth ) *
    (float(x) + (0.5 / float(samples)));
  curY   = float(screen.height / arrayHeight) *
    (float(y) + (0.5 / float(samples)));
  incX   = float(screen.width  / arrayWidth ) /  float(samples);
  incY   = float(screen.height / arrayHeight) /  float(samples);

  r = g = b = 0;
  for(row = 0; row < samples; row++) {
    rowOffset = int(curY) * screen.width;
    curX      = startX;
    for(col = 0; col < samples; col++) {
      c     = image.pixels[rowOffset + int(curX)];
      r    += (c >> 16) & 0xff;
      g    += (c >>  8) & 0xff;
      b    +=  c        & 0xff;
      curX += incX;
    }
    curY += incY;
  }

  return color(r / s2, g / s2, b / s2);
}

