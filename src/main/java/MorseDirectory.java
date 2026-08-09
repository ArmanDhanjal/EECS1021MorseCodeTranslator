import java.util.HashMap;
import java.util.Map;

public class MorseDirectory {
    // Hash map encapsulated as private to avoid modification from outside the class, and final to stop any attempts to
    // change the variable.
    private final Map<Character, String> morseMap;

    // Constructor to allow other classes to initialize the hash map as an object.
    public MorseDirectory(){
        this.morseMap = new HashMap<>();
        initializeDirectory();
    }

    // Populates the hash map with each character and their corresponding morse code.
    private void initializeDirectory(){
        // All entries are lowercase for mapping and lookup.
        morseMap.put('a', ".-");
        morseMap.put('b', "-...");
        morseMap.put('c', "-.-.");
        morseMap.put('d', "-..");
        morseMap.put('e', ".");
        morseMap.put('f', "..-.");
        morseMap.put('g', "--.");
        morseMap.put('h', "....");
        morseMap.put('i', "..");
        morseMap.put('j', ".---");
        morseMap.put('k', "-.-");
        morseMap.put('l', ".-..");
        morseMap.put('m', "--");
        morseMap.put('n', "-.");
        morseMap.put('o', "---");
        morseMap.put('p', ".--.");
        morseMap.put('q', "--.-");
        morseMap.put('r', ".-.");
        morseMap.put('s', "...");
        morseMap.put('t', "-");
        morseMap.put('u', "..-");
        morseMap.put('v', "...-");
        morseMap.put('w', ".--");
        morseMap.put('x', "-..-");
        morseMap.put('y', "-.--");
        morseMap.put('z', "--..");

        // Numerical entries for robustness.
        morseMap.put('0', "-----");
        morseMap.put('1', ".----");
        morseMap.put('2', "..---");
        morseMap.put('3', "...--");
        morseMap.put('4', "....-");
        morseMap.put('5', ".....");
        morseMap.put('6', "-....");
        morseMap.put('7', "--...");
        morseMap.put('8', "---..");
        morseMap.put('9', "----.");
    }

    // Public getter method that allows any class that uses the hash map to search for values using the given key.
    public String getMorseSequence(char c){
        return morseMap.getOrDefault(c, null);
    }
}