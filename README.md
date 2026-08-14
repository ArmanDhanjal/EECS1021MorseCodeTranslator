# Alphanumeric Morse Code Hardware Translator (EECS 1021 Final Project)
### Raspberry Pi Pico (RP2040/RP2350) + Java 21 (jSerialComm)

An object-oriented Java application that captures dynamic user console strings, strips structural margins, extracts character sets, and drives a physical Raspberry Pi Pico onboard LED using highly efficient, direct serial stream communication layers.

Link to video demonstration and explanation:
https://youtu.be/hCXxWO8D-ws
Link to GitHub repository and downloadable files:
https://github.com/ArmanDhanjal/EECS1021MorseCodeTranslator

---

## Toolchain Setup (JDK, Maven, Arduino CLI / IDE)

### Maven
If Maven is missing, the integrated environment helper scripts can download a fully portable copy into `./.tools/` (enabled by default).

### JDK
The execution scripts detect your local system JDK automatically. If it is missing or too old, they will fetch a portable JDK into `./.tools/` (Temurin via the Adoptium API). The codebase requires at least Java 21 to run and execute virtual threads.

### Arduino CLI (Recommended for Uploads)
For consistent installs and firmware automation, the project leverages `arduino-cli` to automatically:
* Install the target RP2040 board compiler package (Earle Philhower core).
* Compile and upload the C++ serial bridge sketch to the physical board.
  If `arduino-cli` is missing on your host machine, the scripts can configure a portable copy under `./.tools/`.

### Environment Helpers (Portable Installs + Detection)
These helper tools detect available developer kits, configure missing libraries, and export the exact environment variables the repository requires:
* **Bash**: `scripts/env.sh`
* **PowerShell**: `scripts/env.ps1`
* **Windows CMD Wrapper**: `scripts/env.cmd`

---

## Project Architecture & Layout

The codebase enforces a strict separation of concerns, decoupling abstract algorithmic token translations from blocking hardware serial tracking threads:

Project Directory Blueprint
```text 
EECS1021MorseCodeTranslator
  pico_serialridge_v1.0
    pico_serial_bridge_v1.0.ino              # Arduino Serial Bridge Communication program
  src/ 
    main/
      java/              # Source Root Folder
        MorseDirectory.java # Immutable lookup mapping dictionary
        PicoController.java # Streamlined hardware driver wrapper
        TextToMorse.java    # System entry point and orchestration layer
      resources/         # Project asset folder (empty)
    test/
      java/              # Unit testing directory (empty)
  TESTING.txt                # Hardware verification logs & bug diagnostics
  pom.xml                    # Maven dependency & Java compiler declarations
```

### 1. Firmware Layer (`pico_serial_bridge_v1.0.ino`)
This lightweight sketch flashes directly onto the Pi Pico chip. It continuously listens for newline-delimited ASCII strings crossing the USB serial connection wire, flashing the pin high/low and responding back with `OK` or `ERROR` packets.

### 2. Encapsulated Data Layer (`MorseDirectory.java`)
Houses a heavily protected private `HashMap` data structure containing your international alphanumeric Morse definitions. It exposes an immutable, public \(O(1)\) lookup complexity gateway (`getMorseSequence`) to prevent external manipulation of the alphabet maps.

### 3. Application Orchestration Layer (`TextToMorse.java`)
Manages the continuous operational user loop, monitors continuation validation gateways, feeds string inputs through your custom `cleanInput` filtering method, and processes the translated collections sequentially.

---

## 🔬 Critical Design Decision: Resolving Hardware Clock Drift

During initial hardware integration tests using asynchronous background timers (`pico.timerStart`), a significant physical latency conflict was isolated.

### The Problem: Asynchronous Timer Overlaps
Because your host laptop CPU and the Pico chip operate on separate, independent clock crystals, sending toggle packets across a USB serial wire introduces an inescapable **transmission latency (~2ms to 5ms)**. Your laptop CPU would wake up from its sleep timer slightly faster than the serial port cleared, issuing a stop command *before* the Pico completed its autonomous blink cycle, clipping the flashes and cluttering the serial buffer register streams.

### The Solution: Synchronous Direct State Control
To guarantee absolute timing accuracy, the background timer loops were removed. The codebase was transitioned to a **Direct Synchronous Output Pattern** utilizing **`pico.ledOn()`** and **`pico.ledOff()`** exclusively. Because the laptop retains absolute custody over both the pauses and the pin voltage updates concurrently, any cable transmission latency affects the start-packet and stop-packet equally. This eliminates clock drift entirely, producing crisp, perfectly proportioned international Morse signals.

```java
// Professional Direct State Pattern implemented inside TextToMorse
public static void shortBlink(PicoController pico) {
    pico.ledOn();
    pico.sleep(DOT_TIME);
    pico.ledOff();
    pico.sleep(BETWEEN_ELEMENTS);
}
```

---

## Absolute Morse Timing Specifications

The physical playback script matches standard international radio transmission requirements:
*   **Dot Duration (`DOT_TIME`)**: 200 ms (LED high voltage state)
*   **Dash Duration (`DASH_TIME`)**: 600 ms (LED high voltage state)
*   **Element Boundary (`BETWEEN_ELEMENTS`)**: 200 ms pause (LED low voltage state between symbols inside a letter)
*   **Character Boundary (`BETWEEN_CHARACTERS`)**: 600 ms pause (LED low voltage state separating complete letters)
*   **Word Boundary (`BETWEEN_WORDS`)**: 1400 ms pause (LED low voltage state separating complete words/spaces)

---

## Robustness & Error-Handling Pipelines

*   **User Input Sanitization**: Strings are piped through `.trim().toLowerCase()` prior to array conversion, eliminating execution loops caused by accidental capitalization or trailing spaces.
*   **Illegal Key Trapping**: If an invalid character symbol is input (e.g., `$`, `%`, `#`), your code filters the value, prints a tracking alert to the console window, and safely skips the index to prevent a application-wide `NullPointerException` crash.
*   **Graceful Shuts Downs**: The system monitors exit strings to cleanly close open USB serial channels (`pico.disconnect()`), preventing background memory port locks.

---

## Verified Execution Trace 

To review comprehensive historical troubleshooting logs, boundary checks, and diagnostic data patterns, examine the tracked [TESTING.txt](./TESTING.txt) log file.

### Successful System Playback Output (`"sos"`)
```text
Connecting to Pico...
Connected to Pico on COM4
Connected successfully.

Please input the message you wish to translate to morse code (no special characters):
sos
...
---
...
Do you wish to continue (y/n)?
n
Exiting Application...
```
