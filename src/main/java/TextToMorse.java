import java.util.ArrayList;
import java.util.List;
import java.util.Scanner;

public class TextToMorse {
    // Constants for displaying morse code.
    private static final int DOT_TIME = 200; // Time the LED is on for a dot.
    private static final int DASH_TIME = 600;// Time the LED is on for a dash.
    private static final int BETWEEN_CHARACTERS = 600; // Time the LED is off between letters/numbers.
    private static final int BETWEEN_ELEMENTS = 200; // Time the LED is off between dots/dashes of the same letter.
    private static final int BETWEEN_WORDS = 1400; // Time the LED is off between whole words (spaces).

    public static void main(String[] args) {
        Scanner scanner = new Scanner(System.in); // Initialize the scanner.

        MorseDirectory directory = new MorseDirectory(); // Create the morse code directory as an object.

        PicoController pico = new PicoController(); // Create the pico object.

        // Ensure proper connection to the pico.
        System.out.println("Connecting to Pico...");
        if (!pico.connect()) {
            System.err.println("ERROR: Could not connect to Pico.");
            PicoController.listPorts();
            return;
        }
        System.out.println("Connected successfully.\n");

        // Initialize variables for user control over the continued use of the application.
        boolean cont = true;
        boolean valid;
        String contAns;

        while (cont) {
            valid = false;

            // Ask the user to input a string of what they want translated to morse code.

            System.out.println("Please input the message you wish to translate to morse code (no special characters):");
            String message = scanner.nextLine();

            // Clean string input and convert it into a character array for easier iteration.

            char[] cleanMessage = (cleanInput(message)).toCharArray();

            // Use a loop to iterate through the string and get the corresponding character value in morse code.
            //       - Saves each new value as an array of strings (implement in convertToMorse() method).
            //       - If encounter a space: save it in the same position as where it is in the original string.
            //       - If encounter a special character (ex $, %, etc.): getter method will return null;
            //              - Program will not add character to the array and will inform user of this issue.

            List<String> morseMessage = convertToMorse(cleanMessage, directory);

            // Iterate through new array and use the pico's onboard LED to blink, using the constants above.
            //       - If encountering a space: ensure led is off and pause for BETWEEN_WORDS ms.

            for (String currentSequence : morseMessage) {
                sequence(pico, currentSequence);
            }

            // Ask user if they would like to continue.
            while (!valid)
            {
                System.out.println("Do you wish to continue (y/n)?");
                contAns = cleanInput(scanner.nextLine());

                if (contAns.equals("y") || contAns.equals("n")) {
                    if (contAns.equals("n")) {
                        cont = false;
                        System.out.println("Exiting Application...");
                    }
                    valid = true;
                }
                else  {
                    System.out.println("Invalid input. Try again.");
                }
            }
        }
    }

    // Method is used to clean the string input, then convert it into a character array for simpler iterate.
    private static String cleanInput(String s){
        return s.toLowerCase().trim();
    }

    // Method returns a list so to allow program to differentiate between each letter/number.
    //      - Each original letter (char) gets converted to a string, and each string is an individual entry.
    //      - One loop for each list entry, the other for iterate through the string.
    private static List<String> convertToMorse(char[] c, MorseDirectory directory){
        List<String> translated = new ArrayList<>();

        for (char currentChar : c) {
            if (currentChar == ' ') {
                translated.add(" ");
            }
            else {
                String temp = directory.getMorseSequence(currentChar);

                if (temp != null) {
                    translated.add(temp);
                }
                else {
                    System.out.println("Invalid character element detected, skipping to next character...");
                }
            }
        }
        return translated;
    }

    // Method to coordinate the LED blinks with the passed morse sequence.
    private static void sequence(PicoController pico, String s) {
        if (s.equals(" ")) {
            pico.ledOff();
            pico.sleep(BETWEEN_WORDS);
        }
        else {
            for (int i = 0; i < s.length(); i++) {
                char currentSymbol = s.charAt(i);

                if (currentSymbol == '.') {
                    shortBlink(pico);
                }
                else if (currentSymbol == '-') {
                    longBlink(pico);
                }
            }
            pico.sleep(BETWEEN_CHARACTERS);
        }
    }

    // Method to tell pico to execute a short blink for dots.
    private static void shortBlink(PicoController pico){
        pico.ledOn();
        pico.sleep(DOT_TIME);

        pico.ledOff();
        pico.sleep(BETWEEN_ELEMENTS);
    }

    // Method to tell pico to execute a short blink for dashes.
    private static void longBlink(PicoController pico){
        pico.ledOn();
        pico.sleep(DASH_TIME);

        pico.ledOff();
        pico.sleep(BETWEEN_ELEMENTS);
    }
}