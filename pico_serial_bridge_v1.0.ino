/**
 * =============================================================================
 *                EECS 1021 - PICO SERIAL BRIDGE FIRMWARE V1.0
 *                    Java-to-Pico Communication Layer
 * =============================================================================
 *
 * This firmware turns the Raspberry Pi Pico 2 / Pico 2 W into a "peripheral"
 * that can be controlled from Java code running on your computer.
 *
 * COMPATIBILITY:
 * --------------
 * This code works on BOTH Pico and Pico W boards automatically!
 *
 * HOW IT WORKS:
 * -------------
 *   1. Upload this firmware to your Pico (do this ONCE)
 *   2. Write Java code using the PicoController library
 *   3. Your Java program sends commands over USB serial
 *   4. The Pico receives and executes those commands
 *
 * SUPPORTED COMMANDS:
 * -------------------
 *   LED_ON           - Turn the onboard LED on
 *   LED_OFF          - Turn the onboard LED off
 *   LED_TOGGLE       - Toggle the LED state
 *   LED_BLINK,<ms>   - Blink LED with specified delay (e.g., LED_BLINK,500)
 *   LED_STATE        - Get current LED state (returns "ON" or "OFF")
 *   TIMER_START,<ms>,<action> - Start hardware timer (action: TOGGLE, ON, OFF, NONE)
 *   TIMER_STOP       - Stop hardware timer
 *   TIMER_STATUS     - Get timer status
 *   TIMER_INTERVAL,<ms> - Change timer interval while running
 *   TIMER_ACTION,<action> - Change timer action while running
 *   GPIO_HIGH,<pin>  - Set a GPIO pin HIGH (e.g., GPIO_HIGH,15)
 *   GPIO_LOW,<pin>   - Set a GPIO pin LOW
 *   GPIO_READ,<pin>  - Read a GPIO pin value (returns "HIGH" or "LOW")
 *   GPIO_MODE,<pin>,<mode> - Set pin mode (mode: INPUT, OUTPUT, INPUT_PULLUP)
 *   SERVO_ATTACH,<pin> - Attach servo to a GPIO pin (e.g., SERVO_ATTACH,9)
 *   SERVO_WRITE,<angle> - Set servo angle 0-180 degrees (e.g., SERVO_WRITE,90)
 *   SERVO_READ       - Get current servo position (returns angle)
 *   SERVO_DETACH     - Detach servo and release pin
 *   DHT_ATTACH,<pin> - Attach DHT11 sensor (e.g., DHT_ATTACH,16)
 *   DHT_READ         - Read temperature and humidity (returns "temp,humidity")
 *   DHT_TEMP         - Read only temperature in Celsius
 *   DHT_HUMIDITY     - Read only humidity percentage
 *   DHT_DETACH       - Detach DHT11 sensor
 *   PING             - Test connection (returns "PONG")
 *   INFO             - Get board information
 *   HELP             - List all commands
 *
 **/

#include <Arduino.h>
#include <Servo.h>
#include "pico/stdlib.h"
#include "hardware/timer.h"
#include "hardware/irq.h"

// =============================================================================
//                              CONSTANTS
// =============================================================================

// LED_BUILTIN is automatically defined by Arduino-Pico framework:
//   - On Pico: GPIO 25
//   - On Pico W: CYW43 WiFi chip LED

#define SERIAL_BAUD       115200
#define COMMAND_BUFFER    64      // Max command length

// =============================================================================
//                           GLOBAL STATE
// =============================================================================

bool ledState = false;
bool blinkMode = false;
int blinkDelay = 500;
String inputBuffer = "";

// Hardware Timer State
volatile bool timerActive = false;
volatile bool timerLedState = false;
volatile int timerInterval = 500;
volatile int timerAction = 0;  // 0=TOGGLE, 1=ON, 2=OFF, 3=NONE
struct repeating_timer hardwareTimer;

// Servo State
Servo myServo;
bool servoAttached = false;
int currentServoPin = -1;
int currentServoAngle = 90;

// DHT11 Sensor State
bool dhtAttached = false;
int currentDhtPin = -1;
float lastTemperature = NAN;
float lastHumidity = NAN;

// =============================================================================
//                         COMMAND HANDLERS
// =============================================================================

/**
 * Send an OK response with optional data
 */
void respondOK(const char* data = nullptr) {
    if (data) {
        Serial.print("OK:");
        Serial.println(data);
    } else {
        Serial.println("OK");
    }
    Serial.flush();
}

/**
 * Send an error response with message
 */
void respondError(const char* message) {
    Serial.print("ERROR:");
    Serial.println(message);
    Serial.flush();
}

/**
 * Turn onboard LED on
 */
void cmdLedOn() {
    ledState = true;
    blinkMode = false;
    digitalWrite(LED_BUILTIN, HIGH);
    respondOK("LED_ON");
}

/**
 * Turn onboard LED off
 */
void cmdLedOff() {
    ledState = false;
    blinkMode = false;
    digitalWrite(LED_BUILTIN, LOW);
    respondOK("LED_OFF");
}

/**
 * Toggle onboard LED
 */
void cmdLedToggle() {
    ledState = !ledState;
    blinkMode = false;
    digitalWrite(LED_BUILTIN, ledState ? HIGH : LOW);
    respondOK(ledState ? "LED_ON" : "LED_OFF");
}

/**
 * Start blinking with specified delay
 */
void cmdLedBlink(int delayMs) {
    if (delayMs < 10 || delayMs > 10000) {
        respondError("DELAY_OUT_OF_RANGE (10-10000)");
        return;
    }
    blinkMode = true;
    blinkDelay = delayMs;
    char response[32];
    snprintf(response, sizeof(response), "BLINKING,%d", delayMs);
    respondOK(response);
}

/**
 * Get current LED state
 */
void cmdLedState() {
    if (blinkMode) {
        respondOK("BLINKING");
    } else {
        respondOK(ledState ? "ON" : "OFF");
    }
}

/**
 * GPIO control commands
 */
void cmdGpioHigh(int pin) {
    if (pin < 0 || pin > 28) {
        respondError("INVALID_PIN (0-28)");
        return;
    }
    digitalWrite(pin, HIGH);
    respondOK();
}

void cmdGpioLow(int pin) {
    if (pin < 0 || pin > 28) {
        respondError("INVALID_PIN (0-28)");
        return;
    }
    digitalWrite(pin, LOW);
    respondOK();
}

void cmdGpioRead(int pin) {
    if (pin < 0 || pin > 28) {
        respondError("INVALID_PIN (0-28)");
        return;
    }
    int value = digitalRead(pin);
    respondOK(value == HIGH ? "HIGH" : "LOW");
}

void cmdGpioMode(int pin, const String& mode) {
    if (pin < 0 || pin > 28) {
        respondError("INVALID_PIN (0-28)");
        return;
    }

    if (mode == "INPUT") {
        pinMode(pin, INPUT);
        respondOK();
    } else if (mode == "OUTPUT") {
        pinMode(pin, OUTPUT);
        respondOK();
    } else if (mode == "INPUT_PULLUP") {
        pinMode(pin, INPUT_PULLUP);
        respondOK();
    } else {
        respondError("INVALID_MODE (INPUT, OUTPUT, INPUT_PULLUP)");
    }
}

/**
 * Info and utility commands
 */
void cmdPing() {
    respondOK("PONG");
}

void cmdInfo() {
    respondOK("PICO,pico_serial_bridge,V1.0");
}

void cmdHelp() {
    Serial.println("COMMANDS:");
    Serial.println("  LED_ON, LED_OFF, LED_TOGGLE, LED_BLINK,<ms>, LED_STATE");
    Serial.println("  TIMER_START,<ms>,<action>, TIMER_STOP, TIMER_STATUS");
    Serial.println("  TIMER_INTERVAL,<ms>, TIMER_ACTION,<action>");
    Serial.println("  Timer actions: TOGGLE, ON, OFF, NONE");
    Serial.println("  GPIO_HIGH,<pin>, GPIO_LOW,<pin>, GPIO_READ,<pin>");
    Serial.println("  GPIO_MODE,<pin>,<INPUT|OUTPUT|INPUT_PULLUP>");
    Serial.println("  SERVO_ATTACH,<pin>, SERVO_WRITE,<angle>, SERVO_READ, SERVO_DETACH");
    Serial.println("  DHT_ATTACH,<pin>, DHT_READ, DHT_TEMP, DHT_HUMIDITY, DHT_DETACH");
    Serial.println("  PING, INFO, HELP");
    Serial.flush();
}

// =============================================================================
//                         SERVO CONTROL COMMANDS
// =============================================================================

/**
 * Attach servo to a GPIO pin
 */
void cmdServoAttach(int pin) {
    if (pin < 0 || pin > 28) {
        respondError("INVALID_PIN (0-28)");
        return;
    }
    
    // Detach existing servo if attached
    if (servoAttached) {
        myServo.detach();
    }
    
    // Attach servo with standard pulse widths (544-2400 microseconds)
    myServo.attach(pin, 544, 2400);
    servoAttached = true;
    currentServoPin = pin;
    
    // Set to center position
    myServo.write(90);
    currentServoAngle = 90;
    
    char response[32];
    snprintf(response, sizeof(response), "SERVO_ATTACHED,%d", pin);
    respondOK(response);
}

/**
 * Set servo angle (0-180 degrees)
 */
void cmdServoWrite(int angle) {
    if (!servoAttached) {
        respondError("NO_SERVO_ATTACHED");
        return;
    }
    
    if (angle < 0 || angle > 180) {
        respondError("ANGLE_OUT_OF_RANGE (0-180)");
        return;
    }
    
    myServo.write(angle);
    currentServoAngle = angle;
    
    char response[32];
    snprintf(response, sizeof(response), "SERVO_POSITION,%d", angle);
    respondOK(response);
}

/**
 * Read current servo position
 */
void cmdServoRead() {
    if (!servoAttached) {
        respondError("NO_SERVO_ATTACHED");
        return;
    }
    
    char response[16];
    snprintf(response, sizeof(response), "%d", currentServoAngle);
    respondOK(response);
}

/**
 * Detach servo and release the pin
 */
void cmdServoDetach() {
    if (!servoAttached) {
        respondError("NO_SERVO_ATTACHED");
        return;
    }
    
    myServo.detach();
    servoAttached = false;
    currentServoPin = -1;
    
    respondOK("SERVO_DETACHED");
}

// =============================================================================
//                         DHT11 SENSOR COMMANDS
//                     NO EXTERNAL LIBRARY - GPIO BIT-BANGING
// =============================================================================

/**
 * Read raw data from DHT11 sensor using GPIO bit-banging
 * This implements the DHT11 protocol manually without external libraries!
 * 
 * DHT11 Protocol:
 * 1. MCU pulls line LOW for 18ms (start signal)
 * 2. MCU pulls line HIGH for 20-40 microseconds
 * 3. DHT11 responds with 40 bits of data (5 bytes):
 *    - Byte 0: Humidity integer part
 *    - Byte 1: Humidity decimal part
 *    - Byte 2: Temperature integer part
 *    - Byte 3: Temperature decimal part (+ sign bit)
 *    - Byte 4: Checksum (sum of bytes 0-3)
 * 
 * Each bit timing:
 * - 0: 26-28 microseconds HIGH pulse
 * - 1: 70 microseconds HIGH pulse
 */
bool dht11ReadRaw(uint8_t data[5]) {
    uint8_t j = 0, i;

    // Clear data array
    data[0] = data[1] = data[2] = data[3] = data[4] = 0;

    // === STEP 1: Send start signal ===
    // Pull pin LOW for 18ms
    pinMode(currentDhtPin, OUTPUT);
    digitalWrite(currentDhtPin, LOW);
    delay(18);
    
    // Pull pin HIGH for 40 microseconds
    digitalWrite(currentDhtPin, HIGH);
    delayMicroseconds(40);
    
    // === STEP 2: Switch to input mode to read response ===
    pinMode(currentDhtPin, INPUT_PULLUP);
    
    // === STEP 3: DHT11 pulls LOW for ~80 microseconds, then HIGH for ~80 microseconds (response) ===
    // Wait for DHT11 to pull LOW
    uint32_t timeout = micros();
    while (digitalRead(currentDhtPin) == HIGH) {
        if ((micros() - timeout) > 100) return false;  // Timeout
    }
    
    // Wait for DHT11 to pull HIGH
    timeout = micros();
    while (digitalRead(currentDhtPin) == LOW) {
        if ((micros() - timeout) > 100) return false;  // Timeout
    }
    
    // Wait for DHT11 to pull LOW (start of data)
    timeout = micros();
    while (digitalRead(currentDhtPin) == HIGH) {
        if ((micros() - timeout) > 100) return false;  // Timeout
    }

    // === STEP 4: Read 40 bits (5 bytes) ===
    for (i = 0; i < 40; i++) {
        // Wait for pin to go HIGH (start of bit transmission)
        timeout = micros();
        while (digitalRead(currentDhtPin) == LOW) {
            if ((micros() - timeout) > 100) return false;  // Timeout
        }
        
        // Measure how long pin stays HIGH
        uint32_t bitStart = micros();
        timeout = micros();
        while (digitalRead(currentDhtPin) == HIGH) {
            if ((micros() - timeout) > 100) return false;  // Timeout
        }
        uint32_t bitDuration = micros() - bitStart;
        
        // Shift data and add new bit
        data[j / 8] <<= 1;
        
        // If HIGH pulse > 40 microseconds, it's a '1' bit (typically 70 microseconds)
        // If HIGH pulse < 40 microseconds, it's a '0' bit (typically 26-28 microseconds)
        if (bitDuration > 40) {
            data[j / 8] |= 1;
        }
        
        j++;
    }

    // === STEP 5: Verify checksum ===
    uint8_t checksum = data[0] + data[1] + data[2] + data[3];
    if (data[4] != checksum) {
        return false;  // Checksum mismatch
    }

    return true;
}

/**
 * Attach DHT11 sensor to a GPIO pin
 */
void cmdDhtAttach(int pin) {
    if (pin < 0 || pin > 28) {
        respondError("INVALID_PIN (0-28)");
        return;
    }
    
    dhtAttached = true;
    currentDhtPin = pin;
    
    // Initialize pin
    pinMode(currentDhtPin, INPUT_PULLUP);
    
    // Give sensor time to initialize
    delay(1000);
    
    char response[32];
    snprintf(response, sizeof(response), "DHT11_ATTACHED,%d", pin);
    respondOK(response);
}

/**
 * Read both temperature and humidity from DHT11 sensor
 * Returns: "temperature,humidity" or error
 */
void cmdDhtRead() {
    if (!dhtAttached) {
        respondError("NO_DHT_ATTACHED");
        return;
    }
    
    uint8_t data[5];
    
    // Try reading up to 3 times (DHT11 can be unreliable)
    bool success = false;
    for (int attempt = 0; attempt < 3; attempt++) {
        if (dht11ReadRaw(data)) {
            success = true;
            break;
        }
        delay(100);  // Wait before retry
    }
    
    if (!success) {
        respondError("READ_FAILED");
        return;
    }
    
    // Parse DHT11 data
    // DHT11 format: Integer.Decimal for both humidity and temperature
    float humidity = data[0] + (data[1] & 0x0F) * 0.1;
    float temperature = data[2] + (data[3] & 0x0F) * 0.1;
    
    // Check for negative temperature (bit 7 of data[3])
    if (data[3] & 0x80) {
        temperature = -temperature;
    }
    
    // Validate ranges (DHT11 specs: 0-50°C, 20-90% RH)
    if (humidity < 0 || humidity > 100 || temperature < -40 || temperature > 80) {
        respondError("INVALID_DATA");
        return;
    }
    
    // Store last valid readings
    lastTemperature = temperature;
    lastHumidity = humidity;
    
    // Format response: "temp,humidity"
    char response[32];
    snprintf(response, sizeof(response), "%.1f,%.1f", temperature, humidity);
    respondOK(response);
}

/**
 * Read only temperature from DHT11 sensor
 * Returns: temperature in Celsius
 */
void cmdDhtTemp() {
    if (!dhtAttached) {
        respondError("NO_DHT_ATTACHED");
        return;
    }
    
    uint8_t data[5];
    
    if (!dht11ReadRaw(data)) {
        respondError("READ_FAILED");
        return;
    }
    
    // Parse temperature from DHT11 data
    float temperature = data[2] + (data[3] & 0x0F) * 0.1;
    
    // Check for negative temperature
    if (data[3] & 0x80) {
        temperature = -temperature;
    }
    
    lastTemperature = temperature;
    
    char response[16];
    snprintf(response, sizeof(response), "%.1f", temperature);
    respondOK(response);
}

/**
 * Read only humidity from DHT11 sensor
 * Returns: humidity percentage
 */
void cmdDhtHumidity() {
    if (!dhtAttached) {
        respondError("NO_DHT_ATTACHED");
        return;
    }
    
    uint8_t data[5];
    
    if (!dht11ReadRaw(data)) {
        respondError("READ_FAILED");
        return;
    }
    
    // Parse humidity from DHT11 data
    float humidity = data[0] + (data[1] & 0x0F) * 0.1;
    
    lastHumidity = humidity;
    
    char response[16];
    snprintf(response, sizeof(response), "%.1f", humidity);
    respondOK(response);
}

/**
 * Detach DHT11 sensor and release resources
 */
void cmdDhtDetach() {
    if (!dhtAttached) {
        respondError("NO_DHT_ATTACHED");
        return;
    }
    
    dhtAttached = false;
    currentDhtPin = -1;
    lastTemperature = NAN;
    lastHumidity = NAN;
    
    respondOK("DHT11_DETACHED");
}

// =============================================================================
//                    HARDWARE TIMER CALLBACKS
// =============================================================================

/**
 * General-purpose timer callback - executes the specified action
 * Actions can be: TOGGLE, ON, OFF, or NONE
 * This makes the timer's behavior EXPLICIT for students
 */
bool timerCallback(struct repeating_timer *t) {
    switch (timerAction) {
        case 0:  // TOGGLE
            timerLedState = !timerLedState;
            digitalWrite(LED_BUILTIN, timerLedState ? HIGH : LOW);
            break;
        case 1:  // ON
            digitalWrite(LED_BUILTIN, HIGH);
            timerLedState = true;
            break;
        case 2:  // OFF
            digitalWrite(LED_BUILTIN, LOW);
            timerLedState = false;
            break;
        case 3:  // NONE (just timing, no LED action)
            // Do nothing - could be used for timing other operations
            break;
    }
    return true;  // Keep repeating
}

/**
 * Parse action string to action code
 */
int parseAction(const String& action) {
    if (action == "TOGGLE") return 0;
    if (action == "ON") return 1;
    if (action == "OFF") return 2;
    if (action == "NONE") return 3;
    return -1;  // Invalid
}

/**
 * Get action name from code
 */
const char* getActionName(int action) {
    switch (action) {
        case 0: return "TOGGLE";
        case 1: return "ON";
        case 2: return "OFF";
        case 3: return "NONE";
        default: return "UNKNOWN";
    }
}

/**
 * Start hardware timer with specified interval and action
 * Actions: TOGGLE (default), ON, OFF, NONE
 * This makes the timer's behavior explicit for students
 */
void cmdTimerStart(int intervalMs, const String& actionStr) {
    // Stop existing timer if running
    if (timerActive) {
        cancel_repeating_timer(&hardwareTimer);
        timerActive = false;
    }
    
    // Validate interval
    if (intervalMs < 10 || intervalMs > 10000) {
        respondError("INTERVAL_OUT_OF_RANGE (10-10000)");
        return;
    }
    
    // Parse and validate action
    int action = parseAction(actionStr);
    if (action < 0) {
        respondError("INVALID_ACTION (TOGGLE, ON, OFF, NONE)");
        return;
    }
    
    // Disable software blink mode
    blinkMode = false;
    
    // Set parameters
    timerInterval = intervalMs;
    timerAction = action;
    
    // Start the timer with our general callback
    bool success = add_repeating_timer_ms(intervalMs, timerCallback, NULL, &hardwareTimer);
    
    if (success) {
        timerActive = true;
        char response[64];
        snprintf(response, sizeof(response), "TIMER_STARTED,%d,%s", 
                intervalMs, getActionName(action));
        respondOK(response);
    } else {
        respondError("TIMER_START_FAILED");
    }
}

/**
 * Change timer action while running
 */
void cmdTimerAction(const String& actionStr) {
    if (!timerActive) {
        respondError("NO_TIMER_RUNNING");
        return;
    }
    
    int action = parseAction(actionStr);
    if (action < 0) {
        respondError("INVALID_ACTION (TOGGLE, ON, OFF, NONE)");
        return;
    }
    
    timerAction = action;
    char response[32];
    snprintf(response, sizeof(response), "ACTION_CHANGED,%s", getActionName(action));
    respondOK(response);
}

/**
 * Change timer interval while running
 * Useful for creating dynamic patterns
 */
void cmdTimerInterval(int intervalMs) {
    if (!timerActive) {
        respondError("NO_TIMER_RUNNING");
        return;
    }
    
    if (intervalMs < 10 || intervalMs > 10000) {
        respondError("INTERVAL_OUT_OF_RANGE (10-10000)");
        return;
    }
    
    // Stop current timer
    cancel_repeating_timer(&hardwareTimer);
    
    // Start new timer with updated interval
    timerInterval = intervalMs;
    bool success = add_repeating_timer_ms(intervalMs, timerCallback, NULL, &hardwareTimer);
    
    if (success) {
        char response[32];
        snprintf(response, sizeof(response), "INTERVAL_CHANGED,%d", intervalMs);
        respondOK(response);
    } else {
        timerActive = false;
        respondError("INTERVAL_CHANGE_FAILED");
    }
}

/**
 * Stop hardware timer
 */
void cmdTimerStop() {
    if (timerActive) {
        cancel_repeating_timer(&hardwareTimer);
        timerActive = false;
        digitalWrite(LED_BUILTIN, LOW);
        ledState = false;
        respondOK("TIMER_STOPPED");
    } else {
        respondError("NO_TIMER_RUNNING");
    }
}

/**
 * Get timer status
 */
void cmdTimerStatus() {
    if (timerActive) {
        char response[64];
        snprintf(response, sizeof(response), "RUNNING,%d,%s", 
                timerInterval, getActionName(timerAction));
        respondOK(response);
    } else {
        respondOK("STOPPED");
    }
}

// =============================================================================
//                         COMMAND PARSER
// =============================================================================

/**
 * Parse and execute a command string
 */
void processCommand(String cmd) {
    cmd.trim();
    cmd.toUpperCase();

    if (cmd.length() == 0) return;

    // Simple commands (no parameters)
    if (cmd == "LED_ON") { cmdLedOn(); return; }
    if (cmd == "LED_OFF") { cmdLedOff(); return; }
    if (cmd == "LED_TOGGLE") { cmdLedToggle(); return; }
    if (cmd == "LED_STATE") { cmdLedState(); return; }
    if (cmd == "TIMER_STOP") { cmdTimerStop(); return; }
    if (cmd == "TIMER_STATUS") { cmdTimerStatus(); return; }
    if (cmd == "SERVO_READ") { cmdServoRead(); return; }
    if (cmd == "SERVO_DETACH") { cmdServoDetach(); return; }
    if (cmd == "DHT_READ") { cmdDhtRead(); return; }
    if (cmd == "DHT_TEMP") { cmdDhtTemp(); return; }
    if (cmd == "DHT_HUMIDITY") { cmdDhtHumidity(); return; }
    if (cmd == "DHT_DETACH") { cmdDhtDetach(); return; }
    if (cmd == "PING") { cmdPing(); return; }
    if (cmd == "INFO") { cmdInfo(); return; }
    if (cmd == "HELP") { cmdHelp(); return; }

    // Commands with parameters (comma-separated)
    int commaIndex = cmd.indexOf(',');

    if (commaIndex > 0) {
        String command = cmd.substring(0, commaIndex);
        String param1 = cmd.substring(commaIndex + 1);

        // LED_BLINK,<delay>
        if (command == "LED_BLINK") {
            int delayMs = param1.toInt();
            cmdLedBlink(delayMs);
            return;
        }

        // GPIO_HIGH,<pin>
        if (command == "GPIO_HIGH") {
            int pin = param1.toInt();
            cmdGpioHigh(pin);
            return;
        }

        // GPIO_LOW,<pin>
        if (command == "GPIO_LOW") {
            int pin = param1.toInt();
            cmdGpioLow(pin);
            return;
        }

        // GPIO_READ,<pin>
        if (command == "GPIO_READ") {
            int pin = param1.toInt();
            cmdGpioRead(pin);
            return;
        }

        // GPIO_MODE,<pin>,<mode>
        if (command == "GPIO_MODE") {
            int secondComma = param1.indexOf(',');
            if (secondComma > 0) {
                int pin = param1.substring(0, secondComma).toInt();
                String mode = param1.substring(secondComma + 1);
                cmdGpioMode(pin, mode);
                return;
            }
        }

        // TIMER_START,<interval>,<action>
        if (command == "TIMER_START") {
            int secondComma = param1.indexOf(',');
            if (secondComma > 0) {
                int intervalMs = param1.substring(0, secondComma).toInt();
                String action = param1.substring(secondComma + 1);
                cmdTimerStart(intervalMs, action);
            } else {
                // Default to TOGGLE if no action specified
                int intervalMs = param1.toInt();
                cmdTimerStart(intervalMs, "TOGGLE");
            }
            return;
        }

        // TIMER_INTERVAL,<interval>
        if (command == "TIMER_INTERVAL") {
            int intervalMs = param1.toInt();
            cmdTimerInterval(intervalMs);
            return;
        }

        // TIMER_ACTION,<action>
        if (command == "TIMER_ACTION") {
            cmdTimerAction(param1);
            return;
        }

        // SERVO_ATTACH,<pin>
        if (command == "SERVO_ATTACH") {
            int pin = param1.toInt();
            cmdServoAttach(pin);
            return;
        }

        // SERVO_WRITE,<angle>
        if (command == "SERVO_WRITE") {
            int angle = param1.toInt();
            cmdServoWrite(angle);
            return;
        }

        // DHT_ATTACH,<pin>
        if (command == "DHT_ATTACH") {
            int pin = param1.toInt();
            cmdDhtAttach(pin);
            return;
        }
    }

    // Unknown command
    respondError("UNKNOWN_COMMAND");
}

// =============================================================================
//                              MAIN PROGRAM
// =============================================================================

void setup() {
    // Initialize LED pin (works for both Pico and Pico W!)
    pinMode(LED_BUILTIN, OUTPUT);
    digitalWrite(LED_BUILTIN, LOW);

    // Initialize serial
    Serial.begin(SERIAL_BAUD);

    // Wait for serial connection
    while (!Serial) {
        delay(10);
    }

    // Ready signal
    Serial.println("READY:EECS1021_PICO_BRIDGE");
    Serial.flush();
}

void loop() {
    // Handle blinking mode
    if (blinkMode) {
        ledState = !ledState;
        digitalWrite(LED_BUILTIN, ledState ? HIGH : LOW);
        delay(blinkDelay);
    }

    // Check for incoming serial data
    while (Serial.available() > 0) {
        char c = Serial.read();

        if (c == '\n' || c == '\r') {
            if (inputBuffer.length() > 0) {
                processCommand(inputBuffer);
                inputBuffer = "";
            }
        } else if (inputBuffer.length() < COMMAND_BUFFER) {
            inputBuffer += c;
        }
    }

    // Small delay to prevent busy-waiting (only when not blinking)
    if (!blinkMode) {
        delay(1);
    }
}
