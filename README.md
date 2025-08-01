# SwiftAIS

**SwiftAIS** lets you turn your Mac into a mobile AIS receiver using cheap, simple hardware! Utilizing an RTL-SDR, this software will demodulate AIS signals from vessels within range and output them as NMEA 0183 sentences. These sentences can be plugged into AIS decoders to reveal what information a vessel is broadcasting.

## Example Output

Here's an example NMEA sentence captured in Scituate, MA:
```
!AIVDM,1,1,,A,E>k`HC0VTah9QTb:Pb2h0ab0P00=N97j<4dDP00000<020,4*6C
```

And here's the output when decoded on https://ccgibbons.com/ais:

<img width="300" alt="AIS decoder output" src="https://github.com/user-attachments/assets/d9456ba9-6bcc-41e7-8e6a-a0adc0aa89f7" />

*(This site is a work in progress! Certain less common message types can cause it to crash. If you find one, let me know! connor@ccgibbons.com)*

## Requirements

- An ARM-based Mac running macOS 15 or newer *(subject to change - hoping to add support for Intel & older macOS versions soon!)*
- [Xcode Command Line Tools](https://developer.apple.com/xcode/resources/)
- RTL-SDR & an antenna (antennas designed for the VHF range are ideal, but not strictly required)
- Be located near marine activity (unfortunately, reception will be too weak if not in a coastal area)

## Building and Running

1. Navigate to the directory in Terminal and run:
   ```bash
   swift build
   ```

2. Navigate to `.build/debug` and run:
   ```bash
   ./SwiftAIS [args]
   ```

## Launch Arguments

| Argument | Description |
|----------|-------------|
| `-d` | Enables extra output for debugging (demodulation time, errors, etc.) |
| `-ot` | Runs the demodulator on a prerecorded .wav file (must be in 16-bit interleaved IQ format). Modify file path & behavior in `OfflineTesting.swift` |
| `-n` | Prints valid NMEA packets to the console when received |
| `-agc` | Enables Automatic Gain Control on the RTL-SDR |
| `-b [Int]` | Controls the bandwidth of the RTL-SDR |
| `-di [Int/IP:Port]` | Choose device index of your RTL-SDR (useful if multiple are present). If IP:Port is entered, SwiftAIS will connect to an rtl_tcp server. Example: `-di 127.0.0.1:1234` |
| `-tcp [Int]` | Makes SwiftAIS act as a TCP server, broadcasting NMEA 0183 packets. Enter port (1-65535). Example: `-tcp 50100` |
| `-ec [Int]` | Enables error correction up to a defined number of bits. Max allowed is 15. Keep <3 bits for best results to avoid false corrections |

## Planned Features

### Multi-Sentence Messages
Some AIS messages are too long for the NMEA 0183 82-character maximum and need to be split across multiple sentences. Currently these will be output as one long sentence (technically invalid) until proper logic is implemented.

### ~~Error Correction~~
- **Update:** This is implemented but untested. Real-world testing coming soon.

### Older macOS Support
Currently uses macOS 15-specific Accelerate library features. Working on supporting older versions back to High Sierra and Intel Macs.
- **Update:** SwiftAIS **should** run on macOS 10.15 (Catalina) on Intel Macs.

### ~~Networking~~
- **Update:** TCP networking is implemented! Try adding SwiftAIS as a connection in OpenCPN to visualize your captured data.

### Decoder/Visualizer
Future plans include a Swift-based decoder and live ship visualizer for the NMEA output.

## Contact

If you have any issues or suggestions, please reach out: connor@ccgibbons.com

## Important Notice

**Testing for this tool is limited and it is not certified by any official bodies. It should not be relied upon as a navigational aid or safety tool. SwiftAIS is created for hobbyist/educational use only.**
