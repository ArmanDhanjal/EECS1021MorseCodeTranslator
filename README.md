# Morse Code Translator (EECS 1021 Final Project) – Pico (RP2040/RP2350) + Java (jSerialComm)


## Toolchain setup (JDK, Maven, Arduino CLI / IDE)

### Maven
If Maven is missing, the scripts can download a portable copy into `./.tools/` (enabled by default).

### JDK
The scripts detect an installed JDK automatically.
If missing (or too old), they can download a portable JDK into `./.tools/` (Temurin via Adoptium API).

The scripts require at least Java 25 by default (and will still honor a higher version from `pom.xml` if configured).

### Arduino CLI (recommended for uploads)
For consistent installs and automation, the project uses `arduino-cli` for:
- installing the RP2040 board package (Earle Philhower core)
- compiling and uploading the firmware sketch

If `arduino-cli` is not installed, the scripts can download a portable copy into `./.tools/`.

### Arduino IDE (optional)
The scripts can detect the Arduino IDE install path (useful for students), but the automated upload path uses `arduino-cli`.

### Environment helpers (portable installs + detection)
These scripts detect tools and optionally install missing ones, then output the environment variables the rest of the repo uses:
- Bash: `scripts/env.sh`
- PowerShell: `scripts/env.ps1`
- Cmd wrapper: `scripts/env.cmd` (calls PowerShell and sets env vars in `cmd.exe`)

Common flags:
- `--install-missing` / `-InstallMissing`: offer to download portable tools into `./.tools/` (default)
- `--yes` / `-Yes`: non-interactive install (auto-accept installs)
- `--require-arduino-cli` / `-RequireArduinoCli`: fail (or install) if `arduino-cli` is missing

Examples:
- Export into your current shell (macOS/Linux): `eval "$(./scripts/env.sh --emit)"`
- Set env vars in `cmd.exe` (Windows): `call scripts\\env.cmd`

Environment variables you’ll commonly see:
- `JAVA_HOME`, `JAVA_BIN`, `JAVAC_BIN`, `JAVA_MAJOR`
- `MVN_BIN` (portable Maven under `./.tools/` or system `mvn`)
- `ARDUINO_CLI` (path to `arduino-cli` if found)
- `ARDUINO_IDE_PATH` (detected IDE install location if found)

## Scripts reference (what each script does)

### End-to-end runners
- `runme.sh`: macOS/Linux end-to-end flow (setup → Arduino core install → upload firmware → run Java).
  - `--java-only` / `--skip-arduino` skips Arduino steps.
  - `--run <MainClass>` runs a specific Java main (default: `BLANK`).
- `runme.bat`: Windows equivalent (drives PowerShell scripts for Arduino parts).

### Setup scripts
- `setup_environment.sh`: macOS/Linux tool detection + Maven dependency download + compile verification.
  - Supports `--require-arduino-cli` if you plan to upload firmware.
- `setup_environment.bat`: Windows setup entrypoint (uses `scripts\\env.cmd` and a portable Maven if needed).

### Arduino CLI scripts (firmware)
- `install_arduino_pico_board_manager.sh` / `install_arduino_pico_board_manager.ps1`:
  - Installs the RP2040 board package for Arduino CLI (Earle Philhower).
- `compile_and_upload_pico.sh` / `compile_and_upload_pico.ps1`:
  - Compiles `pico_serial_bridge_v1.0/` and uploads it to the Pico.
  - Prompts for board type/FQBN and attempts to auto-detect the upload port.

### Java run scripts
- `run_java.sh` / `run_java.ps1` / `run_java.bat`:
  - Builds/compiles the Maven project and runs a specified Java main class.
  - On Java 24+, automatically adds the required native-access flag for `jSerialComm`.
  - If `native-libs/` contains a host-native `jSerialComm` library, it will be preferred.

Options:
- `--install-missing` (default), `--yes` (forwarded to tool detection)
- `--native-access ALL-UNNAMED` (or `--native-access com.fazecast.jSerialComm`) for Java 24+


## Project architecture (Java ↔ Pico)

### Firmware: `pico_serial_bridge_v1.0/pico_serial_bridge_v1.0.ino`
This sketch runs on the Pico and listens for newline-delimited commands over USB serial.
It responds with:
- `OK` / `OK:<data>` on success
- `ERROR:<message>` on failure

Key command groups:
- LED control: `LED_ON`, `LED_OFF`, `LED_TOGGLE`, `LED_BLINK,<ms>`, `LED_STATE`
- FILL IN NEW FILE METHODS
- Utilities: `PING` (returns `OK:PONG`), `INFO`, `HELP`

### Java: `src/main/java/`
The Java side opens the serial port (via `jSerialComm`) and sends the above commands.

Files:
- `PicoController.java`: the library students use (connects to the Pico, sends commands, parses replies).
  - Connection handshake: it enumerates available ports, tries to open each, sends `PING`, and looks for `PONG`.
  - Includes helper APIs for LED control + the BLANK FILE NAME timer APIs.

## jSerialComm notes (dependency, native libraries, Java 24+)

### Maven dependency
`pom.xml` uses a version range so Maven can select a compatible 2.x release:
```xml
<dependency>
  <groupId>com.fazecast</groupId>
  <artifactId>jSerialComm</artifactId>
  <version>[2.0.0,3.0.0)</version>
</dependency>
```

### Native libraries
`jSerialComm` uses a JNI native library (`libjSerialComm.*` / `jSerialComm.dll`) under the hood.
There are two supported ways to run:

1) Default behavior (no local native build):
  - the jar extracts the correct native library for your OS/CPU into a temp directory and loads it
2) Local native library (preferred if present):
  - if `native-libs/` contains a built host-native `libjSerialComm.*`, our scripts set:
    - 

If you built a native library and later jSerialComm updates (because of the version range), you may need to rebuild the native library to match.
If you suspect a mismatch, remove `native-libs/libjSerialComm.*` to force the jar-extraction path.

### Java 24+ native-access restrictions
Starting with Java 24, running code that calls native libraries may require an explicit flag.
The `run_java.*` scripts do this automatically on Java 24+:
- default: `--enable-native-access=ALL-UNNAMED` (recommended for classpath apps)
- optional override: `--native-access com.fazecast.jSerialComm`

### macOS security / quarantine notes
If macOS blocks a JNI library load (Gatekeeper/quarantine), common fixes are:
- ensure the native library is under your project folder (not a restricted location)
- remove quarantine attribute if present: `xattr -dr com.apple.quarantine native-libs`

## Troubleshooting

### Pico not detected / cannot connect
- Ensure the firmware is uploaded: `pico_serial_bridge_v1.0/pico_serial_bridge_v1.0.ino`.
- List serial ports:
  - macOS/Linux: `ls /dev/cu.* /dev/tty.*`
  - Arduino CLI: `arduino-cli board list`
- If `BLANK` prints “Could not connect”, run `PicoController.listPorts()` (already done on failure).

### Upload issues
- Put the board in BOOTSEL mode (hold BOOTSEL while plugging in USB).
- Re-run: `./compile_and_upload_pico.sh`

### Native library errors (jSerialComm)
- If you built a local native library, rebuild it for the exact resolved jSerialComm version:
  - check resolved version (use the same Maven as the scripts): `"$MVN_BIN" dependency:list -DincludeGroupIds=com.fazecast -DincludeArtifactIds=jSerialComm -DexcludeTransitive=true`
  - rebuild native lib: `cd native-libs/jSerialComm && ./build.sh --ref vX.Y.Z`

### “sun.misc.Unsafe” warnings while running Maven
You may see warnings like “A terminally deprecated method in sun.misc.Unsafe has been called” when Maven runs.
These come from Maven’s dependencies (e.g., Guice) and do not affect the Java code.
