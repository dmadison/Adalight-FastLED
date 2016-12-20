## Synopsis

This is the standard Adalight library, modified to work with the FastLED library ([fastled.io](http://fastled.io)) and 3-pin WS2812B LED strips (2016-era Adafruit NeoPixels).

In addition to ambilight setups, the protocol can be used to stream any color data from a computer to a WS2812B strip (data rate limited by serial throughput).


## Configuration

Open the WS2812B file in the Arduino IDE and edit the definitions at the top for your setup. Specifically:

- Number of LEDs
- LED data pin
- LED grounding pin (optional)
- Brightness
- Serial speed
- Serial timeout length

Upload to your Arduino and use a corresponding PC application to stream color data. The Processing files are included, though I would recommend using Patrick Siegler's (@psieg) fork of Lightpacks's Prismatik, which you can find [here](https://github.com/psieg/Lightpack).

## Tutorial

If you'd like you can follow Adafruit's tutorial, which is fairly comprehensive for the WS2801 they use but is otherwise out of date. You can find the tutorial here:

<https://learn.adafruit.com/adalight-diy-ambient-tv-lighting>


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
