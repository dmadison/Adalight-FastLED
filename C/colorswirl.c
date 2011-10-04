/*
"Colorswirl" LED demo.  This is the host PC-side code written in C;
intended for use with a USB-connected Arduino microcontroller running the
accompanying LED streaming code.  Requires one strand of Digital RGB LED
Pixels (Adafruit product ID #322, specifically the newer WS2801-based type,
strand of 25) and a 5 Volt power supply (such as Adafruit #276).  You may
need to adapt the code and the hardware arrangement for your specific
configuration.

This is a command-line program.  It expects a single parameter, which is
the serial port device name, e.g.:

	./colorswirl /dev/tty.usbserial-A60049KO

*/

#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <termios.h>
#include <time.h>
#include <math.h>

#define N_LEDS 25 // Max of 65536

int main(int argc,char *argv[])
{
	int            fd, i, bytesToGo, bytesSent, totalBytesSent = 0,
	               frame = 0, hue1, hue2, brightness;
	unsigned char  buffer[6 + (N_LEDS * 3)], // Header + 3 bytes per LED
	               lo, r, g, b;
	double         sine1, sine2;
	time_t         t, start, prev;
	struct termios tty;

	if(argc < 2) {
		(void)printf("Usage: %s device\n", argv[0]);
		return 1;
	}

	if((fd = open(argv[1],O_RDWR | O_NOCTTY | O_NONBLOCK)) < 0) {
		(void)printf("Can't open device '%s'.\n", argv[1]);
		return 1;
	}

	// Serial port config swiped from RXTX library (rxtx.qbang.org):
	tcgetattr(fd, &tty);
        tty.c_iflag       = INPCK;
        tty.c_lflag       = 0;
        tty.c_oflag       = 0;
        tty.c_cflag       = CREAD | CS8 | CLOCAL;
        tty.c_cc[ VMIN ]  = 0;
        tty.c_cc[ VTIME ] = 0;
	cfsetispeed(&tty, B115200);
	cfsetospeed(&tty, B115200);
	tcsetattr(fd, TCSANOW, &tty);

	bzero(buffer, sizeof(buffer));  // Clear LED buffer

	// Header only needs to be initialized once, not
	// inside rendering loop -- number of LEDs is constant:
	buffer[0] = 'A';                          // Magic word
	buffer[1] = 'd';
	buffer[2] = 'a';
	buffer[3] = (N_LEDS - 1) >> 8;            // LED count high byte
	buffer[4] = (N_LEDS - 1) & 0xff;          // LED count low byte
	buffer[5] = buffer[3] ^ buffer[4] ^ 0x55; // Checksum

	sine1 = 0.0;
	hue1  = 0;
	prev = start = time(NULL); // For bandwidth statistics

	for(;;) {
		sine2 = sine1;
		hue2  = hue1;

		// Start at position 6, after the LED header/magic word
		for(i = 6; i < sizeof(buffer); ) {
			// Fixed-point hue-to-RGB conversion.  'hue2' is an
			// integer in the range of 0 to 1535, where 0 = red,
			// 256 = yellow, 512 = green, etc.  The high byte
			// (0-5) corresponds to the sextant within the color
			// wheel, while the low byte (0-255) is the
			// fractional part between primary/secondary colors.
			lo = hue2 & 255;
			switch((hue2 >> 8) % 6) {
			   case 0:
				r = 255;
				g = lo;
				b = 0;
				break;
			   case 1:
				r = 255 - lo;
				g = 255;
				b = 0;
				break;
			   case 2:
				r = 0;
				g = 255;
				b = lo;
				break;
			   case 3:
				r = 0;
				g = 255 - lo;
				b = 255;
				break;
			   case 4:
				r = lo;
				g = 0;
				b = 255;
				break;
			   case 5:
				r = 255;
				g = 0;
				b = 255 - lo;
				break;
			}

			// Resulting hue is multiplied by brightness in the
			// range of 0 to 255 (0 = off, 255 = brightest).
			// Gamma corrrection (the 'pow' function here) adjusts
			// the brightness to be more perceptually linear.
			brightness  = (int)(pow(0.5+sin(sine2)*0.5,3.0)*255.0);
			buffer[i++] = (r * brightness) / 255;
			buffer[i++] = (g * brightness) / 255;
			buffer[i++] = (b * brightness) / 255;

			// Each pixel is offset in both hue and brightness
			hue2  += 40;
			sine2 += 0.3;
		}

		// Slowly rotate hue and brightness in opposite directions
		hue1   = (hue1 + 5) % 1536;
		sine1 -= .03;

		// Issue color data to LEDs.  Each OS is fussy in different
		// ways about serial output.  This arrangement of drain-and-
		// write-loop seems to be the most relable across platforms:
		tcdrain(fd);
		for(bytesSent=0, bytesToGo=sizeof(buffer); bytesToGo > 0;) {
			if((i=write(fd,&buffer[bytesSent],bytesToGo)) > 0) {
				bytesToGo -= i;
				bytesSent += i;
			}
		}
		// Keep track of byte and frame counts for statistics
		totalBytesSent += sizeof(buffer);
		frame++;

		// Update statistics once per second
		if((t = time(NULL)) != prev) {
			(void)printf(
			  "Average frames/sec: %d, bytes/sec: %d\n",
			  (int)((float)frame / (float)(t - start)),
			  (int)((float)totalBytesSent / (float)(t - start)));
			prev = t;
		}
	}

	close(fd);
	return 0;
}
