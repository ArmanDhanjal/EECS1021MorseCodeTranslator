/*****************************************************************************************
 * Pico 2W + Arduino-Pico Dual-core + USB Serial + Timer Blink
 *
 * Goal:
 *   - Core 0: runs normal Arduino setup()/loop() AND a Pico SDK repeating timer callback
 *            that toggles LED_BUILTIN every LED_DELAY_MS.
 *   - Core 1: runs a custom entry function (core1_entry) launched via Pico SDK multicore.
 *            It periodically prints a heartbeat message.
 *   - Serial output is protected with a Pico SDK mutex to avoid interleaved/corrupted logs.
 *
 * Notes:
 *   - In this Arduino core, setup()/loop() always run on Core 0.
 *   - Core 1 must be started manually with multicore_launch_core1().
 *   - If USB Serial (CDC) is shared without a lock, concurrent prints can interleave badly.
 *****************************************************************************************/


/* -------------------------- Arduino headers (C/C++ framework) ------------------------- */
// Arduino core header: provides pinMode(), digitalWrite(), delay(), Serial, HIGH/LOW, etc.
#include <Arduino.h>
// Servo library for PWM-based servo motor control.
#include <Servo.h>
/* --------------------------- Standard C headers (optional) ---------------------------- */
// Standard I/O facilities (printf, etc.). Usually not required when using Arduino Serial.
#include <stdio.h>
// Standard library utilities (malloc/free, rand, etc.). Not used in the current sketch.
#include <stdlib.h>
/* --------------------------- Pico SDK headers (RP2350/RP2040) ------------------------- */
// Pico SDK base utilities (sleep_ms, absolute_time, etc.). We use sleep_ms() on Core 1.
#include "pico/stdlib.h"
// Pico SDK printf helpers. Typically used when configuring stdio over UART/USB.
#include "pico/printf.h"
// Pico SDK double-precision helpers. Rarely needed unless doing special float formatting.
#include "pico/double.h"
// Multicore support (launching code on Core 1).
#include "pico/multicore.h"
// CPU register/platform helpers. Useful for low-level debugging / reading core regs.
#include "pico/platform/cpu_regs.h"
// Hardware timer support (repeating timers).
#include "hardware/timer.h"
// IRQ support (interrupt controller / enabling/disabling). Not used directly here.
#include "hardware/irq.h"
/* ------------------------------ Configuration section -------------------------------- */
// LED_BUILTIN is defined by the Arduino-Pico core:
//   - Pico 2 : GPIO 25
//   - Pico 2W: CYW43 "WiFi chip LED" GPIO (Arduino core abstracts it as LED_BUILTIN)

// Blink period for the Core 0 repeating timer callback, in milliseconds.
#define LED_DELAY_MS 500

// 'volatile' because it is accessed/modified in a timer callback context.
// This tells the compiler: "do not optimize away reads/writes; value may change unexpectedly".
volatile bool core0_led_state = false;

/* ---------------------- Mutex for Serial (shared across cores) ----------------------- */
// mutex_t is a Pico SDK type (a lightweight lock primitive).
// We'll use it to serialize access to the shared Serial object across Core 0 and Core 1.
static mutex_t serial_mutex;

// Inline helper that prints one line safely, protected by the mutex.
// 'inline' hints to the compiler to embed the function body at call sites (small/fast).
inline void serial_println(const char* msg)
{
    // Block until we acquire the mutex. Guarantees exclusive access to Serial.
    mutex_enter_blocking(&serial_mutex);

    // Print the message using Arduino's Serial (USB CDC).
    // With the mutex held, output from different cores won't interleave mid-line.
    Serial.println(msg);

    // Release the mutex so other code (other core) can print.
    mutex_exit(&serial_mutex);
}


/* -------------------------- Core 0 repeating timer callback -------------------------- */

// This function is called by the Pico SDK repeating timer machinery.
// Signature is fixed by the SDK: it receives a pointer to repeating_timer.
//
// IMPORTANT constraints (good practice):
//   - Keep timer callbacks short (avoid heavy work).
//   - Avoid blocking operations (especially Serial printing) inside callbacks.
//   - Avoid dynamic allocation inside callbacks.
bool toggleCore0LED(struct repeating_timer *t)
{
    // Toggle the state variable.
    core0_led_state = !core0_led_state;

    // Apply the new state to the built-in LED.
    // HIGH turns LED on, LOW turns it off.
    digitalWrite(LED_BUILTIN, core0_led_state ? HIGH : LOW);

    // Return true to keep the timer repeating.
    // If false were returned, the repeating timer would stop.
    return true;
}


/* --------------------------------- Core 1 entry point -------------------------------- */

// This function will run on Core 1 after we call multicore_launch_core1().
// It is NOT Arduino loop1(); it's a raw Pico SDK core entry function.
void core1_entry()
{
    // Wait a bit so USB Serial has time to enumerate and settle.
    // Using Pico SDK sleep_ms() is preferred for Core 1 
    sleep_ms(2000);

    // Infinite loop: Core 1 prints a heartbeat every 3 seconds.
    while (true)
    {
        // Print a heartbeat message in a thread-safe way (mutex-protected).
        serial_println("[Core 1] is alive");

        // Sleep 3000 ms before next heartbeat. Again: use sleep_ms() on Core 1.
        sleep_ms(3000);
    }
}


/* ----------------------------- Arduino setup() (Core 0) ------------------------------ */

// Arduino runtime calls setup() once at boot on Core 0.
void setup()
{
    // Configure the built-in LED pin as an output.
    pinMode(LED_BUILTIN, OUTPUT);

    // Turn LED on immediately to indicate booting / waiting for serial.
    digitalWrite(LED_BUILTIN, HIGH);   // LED on until serial ready


    // Initialize USB CDC serial at 115200 baud (baud is nominal for USB CDC).
    Serial.begin(115200);


    // Maximum amount of time (in milliseconds) that we are willing to wait
    // for the USB Serial port to become available.
    // - On USB-based boards (Pico / Pico 2W), Serial only becomes "true"
    //   after the host PC enumerates the USB device AND opens the port.
    // - In headless or battery-powered deployments, this may never happen.
    // - Without a timeout, the firmware could block forever during boot.
    const uint32_t SERIAL_TIMEOUT_MS = 2000;  // Wait up to 2 seconds

    // Record the time (in milliseconds since boot) at which we started waiting.
    // millis():
    // - Provided by the Arduino core
    // - Returns an unsigned 32-bit counter that increments every millisecond
    // - Wraps around after ~49 days (handled safely by subtraction below)
    uint32_t start = millis();


    // Loop while BOTH conditions are true:
    //   1) The USB Serial port is not yet open (!Serial)
    //   2) We have not exceeded the allowed timeout window
    // This ensures:
    // - We exit immediately if the PC opens the serial port
    // - We exit automatically after SERIAL_TIMEOUT_MS even if no host connects
    while (
        !Serial &&                                 // USB CDC not opened by host yet
        (millis() - start < SERIAL_TIMEOUT_MS)     // Timeout window not expired
    ) {
        // Yield execution for a short time to:
        // - Avoid busy-waiting (wasting CPU cycles)
        // - Allow USB and background tasks to progress
        // - Keep the system responsive during startup
        // delay(10) pauses for ~10 milliseconds.
        // On Core 0, delay() is safe and uses Arduino timing infrastructure.
        delay(10);
    }

    // Execution continues here regardless of whether:
    // - Serial connected successfully within the timeout
    // - OR the timeout expired without a host connection
    // From this point on:
    // - You may safely print to Serial conditionally (if Serial is true)
    // - Or continue running headless without USB attached


    // Now that serial is ready, turn the LED off (your "ready" indicator).
    digitalWrite(LED_BUILTIN, LOW);

    // Initialize the mutex. Must happen before any concurrent use.
    // After this point, serial_println() is safe to use on both cores.
    mutex_init(&serial_mutex);

    // Declare a repeating_timer struct with static storage duration.
    // It must remain valid for the lifetime of the timer.
    static struct repeating_timer core0_timer;

    // Register a repeating timer:
    //   - interval: LED_DELAY_MS milliseconds
    //   - callback: toggleCore0LED
    //   - user_data: NULL (unused here)
    //   - out: address of core0_timer (timer state storage)
    add_repeating_timer_ms(
        LED_DELAY_MS,          // period in ms
        toggleCore0LED,        // callback function
        NULL,                  // user_data passed to callback (unused)
        &core0_timer           // storage for timer state
    );

    // Launch Core 1, starting execution at core1_entry().
    // From now on, Core 1 runs concurrently with Core 0.
    multicore_launch_core1(core1_entry);

    // Print a message from Core 0, using the mutex-safe wrapper.
    serial_println("[Core 0] setup complete");
}


/* ------------------------------ Arduino loop() (Core 0) ------------------------------ */

// Arduino runtime repeatedly calls loop() on Core 0 forever.
void loop()
{
    // Print a periodic heartbeat from Core 0.
    serial_println("[Core 0] is alive");

    // Sleep 1000 ms. Here delay() is fine because we are on Core 0 in Arduino context.
    delay(1000);
}

