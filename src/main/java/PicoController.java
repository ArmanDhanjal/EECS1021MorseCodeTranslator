import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.PrintWriter;

import com.fazecast.jSerialComm.SerialPort;

/**
 * =============================================================================
 *                    EECS 1021 - Pico Controller Library
 *                  Control your Raspberry Pi Pico from Java!
 * =============================================================================
 * This library allows you to control a Raspberry Pi Pico / Pico W from your
 * Java program. The Pico must have the pico_serial_bridge.ino firmware uploaded.
 * COMPATIBILITY:
 * --------------
 * Works with both Pico and Pico W boards automatically!
 * QUICK START EXAMPLE:
 * --------------------
 *     PicoController pico = new PicoController();
 *     pico.connect();           // Connect to the Pico
 *     pico.ledOn();             // Turn on the LED
 *     pico.sleep(1000);         // Wait 1 second
 *     pico.ledOff();            // Turn off the LED
 *     pico.disconnect();        // Disconnect when done
 *
 * @author Navid Mohaghegh, Amin Mohammadi
 * @version 1.0
 */
public class PicoController {

    // =========================================================================
    //                          INSTANCE VARIABLES
    // =========================================================================

    private SerialPort serialPort;          // The serial connection to the Pico
    private PrintWriter writer;              // For sending commands
    private BufferedReader reader;           // For reading responses
    private boolean connected = false;       // Are we currently connected?
    private boolean debugMode = false;       // Print debug messages?

    // Serial communication settings
    private static final int BAUD_RATE = 115200;
    private static final int TIMEOUT_MS = 2000;

    // =========================================================================
    //                          CONSTRUCTORS
    // =========================================================================

    /**
     * Create a new PicoController.
     * You must call connect() before using other methods.
     */
    public PicoController() {
        // Empty constructor - connection happens in connect()
    }

    /**
     * Create a new PicoController with debug mode enabled.
     *
     * @param debug If true, print debug messages to console
     */
    public PicoController(boolean debug) {
        this.debugMode = debug;
    }

    // =========================================================================
    //                       CONNECTION METHODS
    // =========================================================================

    /**
     * Connect to the Pico automatically (finds the correct port).
     *
     * @return true if connection successful, false otherwise
     */
    public boolean connect() {
        // Get all available serial ports
        SerialPort[] ports = SerialPort.getCommPorts();

        if (ports.length == 0) {
            System.err.println("ERROR: No serial ports found!");
            System.err.println("Make sure your Pico is connected via USB.");
            return false;
        }

        // On macOS, prioritize cu.* ports (call-out ports) over tty.* ports (dial-in)
        // Also prioritize ports with "Pico" in the description
        // Support Windows (COM*), macOS (cu.*), and Linux (ttyACM*, ttyUSB*)
        java.util.Arrays.sort(ports, (a, b) -> {
            String aName = a.getSystemPortName();
            String bName = b.getSystemPortName();
            String aDesc = a.getDescriptivePortName().toLowerCase();
            String bDesc = b.getDescriptivePortName().toLowerCase();
            
            // First priority: ports with "Pico" in description
            boolean aIsPico = aDesc.contains("pico");
            boolean bIsPico = bDesc.contains("pico");
            if (aIsPico && !bIsPico) return -1;
            if (!aIsPico && bIsPico) return 1;
            
            // Second priority: cu.* ports (macOS call-out ports for serial)
            boolean aIsCu = aName.startsWith("cu.");
            boolean bIsCu = bName.startsWith("cu.");
            if (aIsCu && !bIsCu) return -1;
            if (!aIsCu && bIsCu) return 1;
            
            // Third priority: Linux ports (ttyACM*, ttyUSB*)
            boolean aIsLinux = aName.startsWith("/dev/ttyACM") || aName.startsWith("/dev/ttyUSB") || 
                              aName.startsWith("ttyACM") || aName.startsWith("ttyUSB");
            boolean bIsLinux = bName.startsWith("/dev/ttyACM") || bName.startsWith("/dev/ttyUSB") || 
                              bName.startsWith("ttyACM") || bName.startsWith("ttyUSB");
            if (aIsLinux && !bIsLinux) return -1;
            if (!aIsLinux && bIsLinux) return 1;
            
            // Fourth priority: COM ports (Windows)
            boolean aIsCom = aName.startsWith("COM");
            boolean bIsCom = bName.startsWith("COM");
            if (aIsCom && !bIsCom) return -1;
            if (!aIsCom && bIsCom) return 1;
            
            return 0;
        });

        // Try each port to find the Pico
        for (SerialPort port : ports) {
            debug("Trying port: " + port.getSystemPortName());

            if (tryConnect(port)) {
                return true;
            }
        }

        System.err.println("ERROR: Could not find Pico on any port.");
        System.err.println("Available ports:");
        for (SerialPort port : ports) {
            System.err.println("  - " + port.getSystemPortName() +
                             " (" + port.getDescriptivePortName() + ")");
        }
        return false;
    }

    /**
     * Connect to the Pico on a specific port.
     *
     * @param portName The port name (e.g., "COM3" on Windows, "/dev/ttyACM0" on Linux, "cu.usbmodem1101" on macOS)
     * @return true if connection successful, false otherwise
     */
    public boolean connect(String portName) {
        if (portName == null || portName.trim().isEmpty()) {
            System.err.println("ERROR: Port name cannot be null or empty");
            return false;
        }
        SerialPort port = SerialPort.getCommPort(portName);
        if (port == null) {
            System.err.println("ERROR: Port '" + portName + "' not found");
            return false;
        }
        return tryConnect(port);
    }

    /**
     * Attempt to connect to a specific serial port.
     */
    private boolean tryConnect(SerialPort port) {
        try {
            // Configure the port
            port.setBaudRate(BAUD_RATE);
            port.setNumDataBits(8);
            port.setNumStopBits(1);
            port.setParity(SerialPort.NO_PARITY);
            port.setComPortTimeouts(SerialPort.TIMEOUT_READ_SEMI_BLOCKING,
                                   TIMEOUT_MS, TIMEOUT_MS);

            // Try to open the port
            if (!port.openPort()) {
                debug("Could not open port: " + port.getSystemPortName());
                return false;
            }

            // Set up streams
            this.serialPort = port;
            this.writer = new PrintWriter(port.getOutputStream(), true);
            this.reader = new BufferedReader(
                new InputStreamReader(port.getInputStream()));

            // Wait for the Pico to be ready
            Thread.sleep(500);

            // Clear any startup messages
            while (reader.ready()) {
                reader.readLine();
            }

            // Temporarily set connected to true so sendCommand works for PING
            this.connected = true;

            // Test the connection with PING
            String response = sendCommand("PING");

            if (response != null && response.contains("PONG")) {
                System.out.println("Connected to Pico on " + port.getSystemPortName());
                return true;
            } else {
                this.connected = false;
                port.closePort();
                return false;
            }

        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            debug("Connection interrupted: " + e.getMessage());
            this.connected = false;
            if (port.isOpen()) {
                port.closePort();
            }
            return false;
        } catch (IOException e) {
            debug("Connection I/O error: " + e.getMessage());
            this.connected = false;
            if (port.isOpen()) {
                port.closePort();
            }
            return false;
        } catch (Exception e) {
            debug("Connection error: " + e.getMessage());
            this.connected = false;
            if (port.isOpen()) {
                port.closePort();
            }
            return false;
        }
    }

    /**
     * Disconnect from the Pico.
     */
    public void disconnect() {
        if (serialPort != null && serialPort.isOpen()) {
            try {
                if (writer != null) {
                    writer.close();
                }
                if (reader != null) {
                    reader.close();
                }
            } catch (IOException e) {
                // Ignore - port may already be closed
            }
            serialPort.closePort();
            connected = false;
            System.out.println("Disconnected from Pico.");
        } else if (connected) {
            // Connection flag was set but port is null or closed
            connected = false;
            System.out.println("Disconnected from Pico.");
        }
    }

    /**
     * Check if currently connected to the Pico.
     *
     * @return true if connected, false otherwise
     */
    public boolean isConnected() {
        return connected && serialPort != null && serialPort.isOpen();
    }

    // =========================================================================
    //                         LED CONTROL METHODS
    // =========================================================================

    /**
     * Turn the onboard LED ON.
     * Works on both Pico and Pico W boards!
     *
     * @return true if successful
     */
    public boolean ledOn() {
        return sendAndVerify("LED_ON");
    }

    /**
     * Turn the onboard LED OFF.
     * Works on both Pico and Pico W boards!
     *
     * @return true if successful
     */
    public boolean ledOff() {
        return sendAndVerify("LED_OFF");
    }

    /**
     * Toggle the LED (if on, turn off; if off, turn on).
     * Works on both Pico and Pico W boards!
     *
     * @return true if successful
     */
    public boolean ledToggle() {
        return sendAndVerify("LED_TOGGLE");
    }

    /**
     * Make the LED blink with the specified delay.
     * Works on both Pico and Pico W boards!
     *
     * @param delayMs Delay between blinks in milliseconds (10-10000)
     * @return true if successful
     */
    public boolean ledBlink(int delayMs) {
        if (delayMs < 10 || delayMs > 10000) {
            System.err.println("ERROR: Delay must be between 10 and 10000 milliseconds");
            return false;
        }
        return sendAndVerify("LED_BLINK," + delayMs);
    }

    /**
     * Get the current LED state.
     *
     * @return "ON", "OFF", "BLINKING", or null if error
     */
    public String getLedState() {
        String response = sendCommand("LED_STATE");
        if (response != null && response.startsWith("OK:")) {
            return response.substring(3);
        }
        return null;
    }

    // =========================================================================
    //                    HARDWARE TIMER METHODS
    // =========================================================================

    /**
     * Start a hardware timer with specified interval and action.
     * 
     * This is a general-purpose timer - similar to Arduino's add_repeating_timer_ms().
     * The timer runs on the Pico's hardware, using interrupts for precise timing.
     * 
     * ACTIONS:
     * - "TOGGLE": LED toggles (ON→OFF or OFF→ON) each interval - creates blinking
     * - "ON": LED turns ON each interval - creates pulses with custom duty cycle
     * - "OFF": LED turns OFF each interval - can be used for timing without LED
     * - "NONE": No LED action - pure timing (for advanced use)
     * 
     * What happens:
     * - Timer starts and runs independently on the Pico
     * - Every 'intervalMs' milliseconds, the specified action executes
     * - Your Java program is FREE to do other work while this happens!
     * 
     * Example - Simple blink with TOGGLE:
     *     pico.timerStart(500, "TOGGLE");  // Toggle every 500ms = blinking
     * 
     * Example - Pulse effect with ON:
     *     pico.ledOff();                   // Start with LED off
     *     pico.timerStart(100, "ON");      // LED turns ON every 100ms
     *     pico.sleep(20);                  // Let it stay on briefly
     *     pico.timerStop();                // Creates a short pulse!
     * 
     * Example - Complex pattern:
     *     pico.timerStart(200, "TOGGLE");  // Fast blink
     *     pico.sleep(3000);
     *     pico.timerSetInterval(1000);     // Slow blink (keep TOGGLE action)
     *     pico.sleep(3000);
     *     pico.timerStop();
     *
     * @param intervalMs Interval in milliseconds (10-10000)
     * @param action Action to perform: "TOGGLE", "ON", "OFF", or "NONE"
     * @return true if successful
     */
    public boolean timerStart(int intervalMs, String action) {
        if (intervalMs < 10 || intervalMs > 10000) {
            System.err.println("ERROR: Interval must be between 10 and 10000 milliseconds");
            return false;
        }
        if (action == null || action.trim().isEmpty()) {
            System.err.println("ERROR: Action cannot be null or empty");
            return false;
        }
        return sendAndVerify("TIMER_START," + intervalMs + "," + action);
    }

    /**
     * Start a hardware timer with TOGGLE action (default for blinking).
     * This is a convenience method - same as timerStart(intervalMs, "TOGGLE").
     * 
     * @param intervalMs Interval in milliseconds (10-10000)
     * @return true if successful
     */
    public boolean timerStart(int intervalMs) {
        return timerStart(intervalMs, "TOGGLE");
    }

    /**
     * Stop the hardware timer.
     * The LED will remain in whatever state it was in when stopped.
     * 
     * TIP: Call ledOff() after timerStop() if you want to ensure LED is off.
     *
     * @return true if successful
     */
    public boolean timerStop() {
        return sendAndVerify("TIMER_STOP");
    }

    /**
     * Change the timer interval while it's running.
     * This lets you create dynamic patterns without stopping/restarting.
     * The action remains the same.
     * 
     * Example - Accelerating blink:
     *     pico.timerStart(1000, "TOGGLE");
     *     pico.sleep(2000);
     *     pico.timerSetInterval(500);   // Speed up!
     *     pico.sleep(2000);
     *     pico.timerSetInterval(200);   // Even faster!
     *
     * @param intervalMs New interval in milliseconds (10-10000)
     * @return true if successful
     */
    public boolean timerSetInterval(int intervalMs) {
        if (intervalMs < 10 || intervalMs > 10000) {
            System.err.println("ERROR: Interval must be between 10 and 10000 milliseconds");
            return false;
        }
        return sendAndVerify("TIMER_INTERVAL," + intervalMs);
    }

    /**
     * Change the timer action while it's running.
     * This lets you switch behaviors without stopping/restarting.
     * The interval remains the same.
     * 
     * Example - Switch from blinking to pulsing:
     *     pico.timerStart(200, "TOGGLE");    // Blinking
     *     pico.sleep(2000);
     *     pico.timerSetAction("ON");          // Now creates pulses
     *     pico.sleep(2000);
     *
     * @param action New action: "TOGGLE", "ON", "OFF", or "NONE"
     * @return true if successful
     */
    public boolean timerSetAction(String action) {
        if (action == null || action.trim().isEmpty()) {
            System.err.println("ERROR: Action cannot be null or empty");
            return false;
        }
        return sendAndVerify("TIMER_ACTION," + action);
    }

    /**
     * Get the hardware timer status.
     *
     * @return Status string (e.g., "RUNNING,500,TOGGLE" or "STOPPED"), or null if error
     */
    public String timerStatus() {
        String response = sendCommand("TIMER_STATUS");
        if (response != null && response.startsWith("OK:")) {
            return response.substring(3);
        }
        return null;
    }

    /**
     * Check if hardware timer is currently running.
     *
     * @return true if timer is running, false otherwise
     */
    public boolean isTimerRunning() {
        String status = timerStatus();
        return status != null && status.startsWith("RUNNING");
    }
    
    /**
     * Get the current timer interval in milliseconds.
     * Returns 0 if timer is not running.
     *
     * @return Current interval in ms, or 0 if timer is stopped
     */
    public int getTimerInterval() {
        String status = timerStatus();
        if (status != null && status.startsWith("RUNNING,")) {
            try {
                String[] parts = status.split(",");
                return Integer.parseInt(parts[1]);
            } catch (NumberFormatException | ArrayIndexOutOfBoundsException e) {
                return 0;
            }
        }
        return 0;
    }

    /**
     * Get the current timer action.
     * Returns null if timer is not running.
     *
     * @return Current action ("TOGGLE", "ON", "OFF", "NONE"), or null if stopped
     */
    public String getTimerAction() {
        String status = timerStatus();
        if (status != null && status.startsWith("RUNNING,")) {
            try {
                String[] parts = status.split(",");
                return parts[2];
            } catch (ArrayIndexOutOfBoundsException e) {
                return null;
            }
        }
        return null;
    }

    // =========================================================================
    //                         GPIO CONTROL METHODS
    // =========================================================================

    /**
     * Set a GPIO pin to OUTPUT mode.
     *
     * @param pin The GPIO pin number (0-28)
     * @return true if successful
     */
    public boolean setPinOutput(int pin) {
        if (pin < 0 || pin > 28) {
            System.err.println("ERROR: Pin number must be between 0 and 28");
            return false;
        }
        return sendAndVerify("GPIO_MODE," + pin + ",OUTPUT");
    }

    /**
     * Set a GPIO pin to INPUT mode.
     *
     * @param pin The GPIO pin number (0-28)
     * @return true if successful
     */
    public boolean setPinInput(int pin) {
        if (pin < 0 || pin > 28) {
            System.err.println("ERROR: Pin number must be between 0 and 28");
            return false;
        }
        return sendAndVerify("GPIO_MODE," + pin + ",INPUT");
    }

    /**
     * Set a GPIO pin to INPUT_PULLUP mode.
     *
     * @param pin The GPIO pin number (0-28)
     * @return true if successful
     */
    public boolean setPinInputPullup(int pin) {
        if (pin < 0 || pin > 28) {
            System.err.println("ERROR: Pin number must be between 0 and 28");
            return false;
        }
        return sendAndVerify("GPIO_MODE," + pin + ",INPUT_PULLUP");
    }

    /**
     * Set a GPIO pin HIGH (3.3V) or LOW (0V).
     *
     * @param pin The GPIO pin number (0-28)
     * @param high true for HIGH (3.3V), false for LOW (0V)
     * @return true if successful
     */
    public boolean digitalWrite(int pin, boolean high) {
        if (pin < 0 || pin > 28) {
            System.err.println("ERROR: Pin number must be between 0 and 28");
            return false;
        }
        if (high) {
            return sendAndVerify("GPIO_HIGH," + pin);
        } else {
            return sendAndVerify("GPIO_LOW," + pin);
        }
    }

    /**
     * Read the value of a GPIO pin.
     *
     * @param pin The GPIO pin number (0-28)
     * @return true if HIGH, false if LOW or error
     */
    public boolean digitalRead(int pin) {
        if (pin < 0 || pin > 28) {
            System.err.println("ERROR: Pin number must be between 0 and 28");
            return false;
        }
        String response = sendCommand("GPIO_READ," + pin);
        return response != null && response.contains("HIGH");
    }

    // =========================================================================
    //                         SERVO CONTROL METHODS (LAB 3)
    // =========================================================================

    /**
     * Attach a servo motor to a GPIO pin.
     * 
     * This initializes the servo and sets it to 90 degrees (center position).
     * Only one servo can be attached at a time.
     * 
     * Example:
     *     pico.servoAttach(9);  // Attach servo to GPIO 9
     *
     * @param pin The GPIO pin number (0-28, recommend GP9)
     * @return true if successful
     */
    public boolean servoAttach(int pin) {
        if (pin < 0 || pin > 28) {
            System.err.println("ERROR: Pin number must be between 0 and 28");
            return false;
        }
        return sendAndVerify("SERVO_ATTACH," + pin);
    }

    /**
     * Set the servo to a specific angle.
     * 
     * The servo will move to the specified angle:
     * - 0° = fully counter-clockwise
     * - 90° = center position
     * - 180° = fully clockwise
     * 
     * The servo moves at its own speed (usually ~60°/0.1s for SG90).
     * If you need smooth animation, use small angle steps with delays.
     * 
     * Example - Simple movement:
     *     pico.servoWrite(0);     // Move to 0 degrees
     *     pico.sleep(1000);       // Wait for servo to reach position
     *     pico.servoWrite(180);   // Move to 180 degrees
     * 
     * Example - Smooth sweep:
     *     for (int angle = 0; angle <= 180; angle++) {
     *         pico.servoWrite(angle);
     *         pico.sleep(15);  // Small delay for smooth motion
     *     }
     *
     * @param angle The angle in degrees (0-180)
     * @return true if successful
     */
    public boolean servoWrite(int angle) {
        if (angle < 0 || angle > 180) {
            System.err.println("ERROR: Angle must be 0-180 degrees");
            return false;
        }
        return sendAndVerify("SERVO_WRITE," + angle);
    }

    /**
     * Get the current servo position.
     * 
     * Returns the last angle that was written to the servo.
     * Note: This returns the commanded position, not the actual position
     * (the servo might still be moving to this position).
     *
     * @return Current servo angle (0-180), or -1 if error
     */
    public int servoRead() {
        String response = sendCommand("SERVO_READ");
        if (response != null && response.startsWith("OK:")) {
            try {
                return Integer.parseInt(response.substring(3));
            } catch (NumberFormatException e) {
                return -1;
            }
        }
        return -1;
    }

    /**
     * Detach the servo and release the pin.
     * 
     * This stops sending control pulses to the servo, allowing it to move freely.
     * The servo will no longer hold its position.
     * 
     * Always detach when done to save power and prevent servo jitter.
     *
     * @return true if successful
     */
    public boolean servoDetach() {
        return sendAndVerify("SERVO_DETACH");
    }

    /**
     * Smoothly move servo from current position to target angle.
     * 
     * This is a helper method that creates smooth servo animation by moving
     * in small steps. The servo will take approximately:
     *   - stepDelay * |currentAngle - targetAngle| milliseconds
     * 
     * Example:
     *     pico.servoSmoothMove(180, 15);  // Smooth move to 180° with 15ms steps
     *
     * @param targetAngle The target angle (0-180)
     * @param stepDelay Delay between each degree step in ms (recommend 10-20)
     * @return true if successful
     */
    public boolean servoSmoothMove(int targetAngle, int stepDelay) {
        int currentAngle = servoRead();
        if (currentAngle < 0) {
            System.err.println("ERROR: Cannot read current servo position");
            return false;
        }
        
        if (targetAngle < 0 || targetAngle > 180) {
            System.err.println("ERROR: Target angle must be 0-180 degrees");
            return false;
        }
        
        // Determine direction
        int step = (currentAngle < targetAngle) ? 1 : -1;
        
        // Move smoothly
        for (int angle = currentAngle; 
             (step > 0 && angle <= targetAngle) || (step < 0 && angle >= targetAngle); 
             angle += step) {
            if (!servoWrite(angle)) {
                return false;
            }
            sleep(stepDelay);
        }
        
        return true;
    }

    /**
     * Perform a servo sweep from start angle to end angle.
     * 
     * This is a helper method for creating sweep animations.
     * 
     * Example - Full sweep:
     *     pico.servoSweep(0, 180, 10);  // Sweep from 0° to 180° with 10ms steps
     *
     * @param startAngle Starting angle (0-180)
     * @param endAngle Ending angle (0-180)
     * @param stepDelay Delay between each degree step in ms
     * @return true if successful
     */
    public boolean servoSweep(int startAngle, int endAngle, int stepDelay) {
        if (!servoWrite(startAngle)) {
            return false;
        }
        sleep(500);  // Let servo reach start position
        
        return servoSmoothMove(endAngle, stepDelay);
    }

    // =========================================================================
    //                    DHT SENSOR METHODS (LAB 5)
    // =========================================================================

    /**
     * Attach a DHT11 temperature/humidity sensor to a GPIO pin.
     * 
     * DHT11 is a common low-cost sensor that measures:
     * - Temperature: 0-50°C (±2°C accuracy)
     * - Humidity: 20-90% RH (±5% accuracy)
     * 
     * The sensor needs 1 second to initialize after attachment.
     * 
     * WIRING (DHT11):
     * - Pin 1 (leftmost) → 3.3V or 5V
     * - Pin 2 → GPIO data pin (e.g., GP16)
     * - Pin 3 → Not connected
     * - Pin 4 (rightmost) → GND
     * 
     * Note: A 10k ohm pull-up resistor between data pin and VCC is recommended
     * (some DHT11 modules have this built-in).
     * 
     * Example:
     *     pico.dhtAttach(16);  // Attach DHT11 to GPIO 16
     *
     * @param pin The GPIO pin number (0-28, recommend GP16)
     * @return true if successful
     */
    public boolean dhtAttach(int pin) {
        if (pin < 0 || pin > 28) {
            System.err.println("ERROR: Pin number must be between 0 and 28");
            return false;
        }
        return sendAndVerify("DHT_ATTACH," + pin);
    }

    /**
     * Read both temperature and humidity from the DHT sensor.
     * 
     * Returns an array with two values:
     * - [0] = temperature in Celsius
     * - [1] = humidity in percentage (0-100)
     * 
     * Reading takes about 250ms, so don't call this too frequently!
     * Recommended: Wait at least 2 seconds between readings.
     * 
     * Example:
     *     float[] data = pico.dhtRead();
     *     if (data != null) {
     *         System.out.println("Temperature: " + data[0] + "°C");
     *         System.out.println("Humidity: " + data[1] + "%");
     *     }
     *
     * @return Array [temperature, humidity], or null if error
     */
    public float[] dhtRead() {
        String response = sendCommand("DHT_READ");
        if (response != null && response.startsWith("OK:")) {
            try {
                String data = response.substring(3);
                String[] parts = data.split(",");
                if (parts.length == 2) {
                    float temp = Float.parseFloat(parts[0]);
                    float humidity = Float.parseFloat(parts[1]);
                    return new float[]{temp, humidity};
                }
            } catch (NumberFormatException | ArrayIndexOutOfBoundsException e) {
                System.err.println("ERROR: Failed to parse DHT data: " + e.getMessage());
            }
        }
        return null;
    }

    /**
     * Read only the temperature from the DHT sensor.
     * 
     * Returns temperature in Celsius.
     * Reading takes about 250ms.
     * 
     * Example:
     *     float temp = pico.dhtGetTemperature();
     *     System.out.println("Temperature: " + temp + "°C");
     *
     * @return Temperature in Celsius, or Float.NaN if error
     */
    public float dhtGetTemperature() {
        String response = sendCommand("DHT_TEMP");
        if (response != null && response.startsWith("OK:")) {
            try {
                return Float.parseFloat(response.substring(3));
            } catch (NumberFormatException e) {
                return Float.NaN;
            }
        }
        return Float.NaN;
    }

    /**
     * Read only the humidity from the DHT sensor.
     * 
     * Returns humidity as a percentage (0-100).
     * Reading takes about 250ms.
     * 
     * Example:
     *     float humidity = pico.dhtGetHumidity();
     *     System.out.println("Humidity: " + humidity + "%");
     *
     * @return Humidity percentage (0-100), or Float.NaN if error
     */
    public float dhtGetHumidity() {
        String response = sendCommand("DHT_HUMIDITY");
        if (response != null && response.startsWith("OK:")) {
            try {
                return Float.parseFloat(response.substring(3));
            } catch (NumberFormatException e) {
                return Float.NaN;
            }
        }
        return Float.NaN;
    }

    /**
     * Detach the DHT sensor and release resources.
     * 
     * Always detach when done to free up the GPIO pin and memory.
     *
     * @return true if successful
     */
    public boolean dhtDetach() {
        return sendAndVerify("DHT_DETACH");
    }

    // =========================================================================
    //                         UTILITY METHODS
    // =========================================================================

    /**
     * Test the connection to the Pico.
     *
     * @return true if Pico responds correctly
     */
    public boolean ping() {
        String response = sendCommand("PING");
        return response != null && response.contains("PONG");
    }

    /**
     * Get information about the connected Pico.
     *
     * @return Information string, or null if error
     */
    public String getInfo() {
        String response = sendCommand("INFO");
        if (response != null && response.startsWith("OK:")) {
            return response.substring(3);
        }
        return null;
    }

    /**
     * Wait for a specified time (convenience method).
     *
     * @param milliseconds Time to wait in milliseconds
     */
    public void sleep(int milliseconds) {
        try {
            Thread.sleep(milliseconds);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    // =========================================================================
    //                    INTERNAL COMMUNICATION METHODS
    // =========================================================================

    /**
     * Send a command and return the response.
     */
    private String sendCommand(String command) {
        if (!isConnected()) {
            System.err.println("ERROR: Not connected to Pico!");
            return null;
        }

        try {
            debug("Sending: " + command);

            // Clear any pending input
            while (reader.ready()) {
                reader.readLine();
            }

            // Send the command
            writer.println(command);
            writer.flush();

            // Read the response
            // NOTE: When the port opens, the Pico may reboot and print a READY line.
            // If that READY line arrives right after we send a command, it can be read
            // here instead of the actual response. We'll skip READY/blank lines.
            String response = reader.readLine();
            int skips = 0;
            while (response != null &&
                   (response.isBlank() || response.startsWith("READY:")) &&
                   skips < 5) {
                debug("Skipping non-response line: " + response);
                response = reader.readLine();
                skips++;
            }
            debug("Received: " + response);

            return response;

        } catch (IOException e) {
            System.err.println("Communication error: " + e.getMessage());
            return null;
        }
    }

    /**
     * Send a command and verify it succeeded.
     */
    private boolean sendAndVerify(String command) {
        String response = sendCommand(command);
        if (response == null) {
            return false;
        }
        if (response.startsWith("ERROR:")) {
            System.err.println("Pico error: " + response);
            return false;
        }
        return response.startsWith("OK");
    }

    /**
     * Print a debug message if debug mode is enabled.
     */
    private void debug(String message) {
        if (debugMode) {
            System.out.println("[DEBUG] " + message);
        }
    }

    // =========================================================================
    //                         STATIC UTILITY METHODS
    // =========================================================================

    /**
     * List all available serial ports.
     * Useful for troubleshooting connection issues.
     */
    public static void listPorts() {
        SerialPort[] ports = SerialPort.getCommPorts();
        System.out.println("Available serial ports:");
        if (ports.length == 0) {
            System.out.println("  (none found)");
        } else {
            for (SerialPort port : ports) {
                System.out.println("  " + port.getSystemPortName() +
                                 " - " + port.getDescriptivePortName());
            }
        }
    }
}
