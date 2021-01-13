# Adalight-FastLED

![Adalight-Rainbow](http://i.imgur.com/sHygxq9.jpg)

## Synopsis

This project modifies the Adalight protocol to use [FastLED](https://github.com/FastLED/FastLED) ([fastled.io](http://fastled.io)). This expands Adalight to, in theory, work with *[any supported FastLED strip](https://github.com/FastLED/FastLED/wiki/Chipset-reference)* including WS2812B (aka Adafruit NeoPixels).

In addition to ambilight setups, the protocol can be used to stream any color data over serial from a computer to supported LED strips.

For this sketch to work, you'll need to have a copy of the FastLED library. You can download FastLED [from GitHub](https://github.com/FastLED/FastLED) or through the libraries manager of the Arduino IDE. This program was writen using FastLED 3 - note that earlier versions of FastLED are untested and may not work properly.

For more information on my own ambilight setup, see [the project page](https://www.partsnotincluded.com/diy-ambilight-ws2812b/) on [PartsNotIncluded.com](http://www.partsnotincluded.com/).

## Basic Setup

Open the LEDstream_FastLED file in the Arduino IDE and customize the settings at the top for your setup. You will need to change:

- Number of LEDs
- LED data pin
- LED type

If you are using a 4-wire LED chipset like APA102 or SK9822, you will need to uncomment the `PIN_CLOCK` line and set that as well.

Upload to your Arduino and use a corresponding PC application to stream color data. You can get the Processing files from the [main Adalight repository](https://github.com/adafruit/Adalight), though I would recommend using Patrick Siegler's fork of Lightpacks's Prismatik, which you can find [here](https://github.com/psieg/Lightpack/releases).

## Additional Settings

There are additional settings to allow for adjusting:

- Max brightness
- LED color order
- Serial speed
- Serial timeout length

There are also optional settings to clear the LEDs on reset or flush the incoming serial buffer after every latch. This latter option is enabled by default to help with flickering when using WS2812B LEDs.

## Debug Settings

The code includes two debugging options:
- DEBUG_LED
- DEBUG_FPS

`DEBUG_LED` will turn on the Arduino's built-in LED on a successful header match, and off when the LEDs latch. If your LEDs aren't working, this will help confirm that the Arduino is receiving properly formatted serial data.

`DEBUG_FPS`, similarly, will toggle a given pin when the LEDs latch. This is useful for measuring framerate with external hardware, like a logic analyzer.

To enable either of these settings, uncomment their respective `#define` lines.

## Issues and LED-types

I've only tested the code with the WS2812B strips I have on hand, but so far it performs flawlessly. If you find an issue with the code or can confirm that it works with another chipset, please let me know!

## Credits and Contributions

Thanks to Adafruit for the initial code and for developing the Adalight protocol. The base for the original FastLED modifications is [this gist](https://gist.github.com/jamesabruce/09d79a56d270ed37870c) by [James Bruce](https://github.com/jamesabruce). Thanks James!

Pull requests to improve this software are always welcome!

## License

Adalight is free software: you can redistribute it and/or modify
it under the terms of the GNU Lesser General Public License as
published by the Free Software Foundation, either version 3 of
the License, or (at your option) any later version.

Adalight is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public
License along with Adalight.  If not, see <http://www.gnu.org/licenses/>.
