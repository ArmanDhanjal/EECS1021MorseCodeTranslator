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
        Scanner scanner = new Scanner(System.in);

        MorseDirectory directory = new MorseDirectory();

        PicoController pico = new PicoController();

        System.out.println("Connecting to Pico...");
        if (!pico.connect()) {
            System.err.println("ERROR: Could not connect to Pico.");
            PicoController.listPorts();
            return;
        }
        System.out.println("Connected successfully.\n");

        boolean cont = true;
        boolean valid;
        String contAns;

        while (cont) {
            valid = false;

            // (Complete) TODO 1: Ask user to input a string of what they want translated to morse code.

            System.out.println("Please input the message you wish to translate to morse code (no special characters):");
            String message = scanner.nextLine();

            // (Complete) TODO 2: clean string input (use created method).

            char[] cleanMessage = cleanInput(message);

            // (Complete) TODO 3: for loop to iterate through the string and get the corresponding character value in morse code.
            //       save each new value as an array of strings (implement in convertToMorse() method).
            //       if encounter a space: save it in the same position as where it is in the original string.
            //       if encounter a special character (ex $, %, etc): getter method will return null; do not add to array.

            List<String> morseMessage = convertToMorse(cleanMessage, directory);

            // TODO 4: iterate through new array and use the pico's onboard LED to blink, using the constants above.
            //       if encounter a space: ensure led is off and pause for BETWEEN_WORDS ms.

            for (String currentSequence : morseMessage) {
                sequence(pico, currentSequence);
            }

            // Ask user if they would like to continue.
            while (!valid)
            {
                System.out.println("Do you wish to continue (y/n)?");
                contAns = scanner.nextLine();

                if (contAns.equals("y") ||  contAns.equals("n")) {
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
    private static char[] cleanInput(String s){
        return s.toLowerCase().trim().toCharArray();
    }

    // Method returns a list so to allow program to differentiate between each letter/number.
    //      - each original letter (char) gets converted to a string, and each string is an individual entry.
    //      - can use nexted for loops: 1 loop for each list entry, the other for iterate through the string.
    public static List<String> convertToMorse(char[] c, MorseDirectory directory){
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

    // Method to instruct the pico of what the blink sequence will be.
    public static void sequence(PicoController pico, String s) {
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
    public static void shortBlink(PicoController pico){
        pico.timerStart(DOT_TIME, "TOGGLE");
        pico.sleep(DOT_TIME);

        pico.timerStop();
        pico.ledOff();
        pico.sleep(BETWEEN_ELEMENTS);
    }

    // Method to tell pico to execute a short blink for dashes.
    public static void longBlink(PicoController pico){
        pico.timerStart(DASH_TIME, "TOGGLE");
        pico.sleep(DASH_TIME);

        pico.timerStop();
        pico.ledOff();
        pico.sleep(BETWEEN_ELEMENTS);
    }
}
