import java.io.IOException;

public class Main {
    private static final int TREE_LIFETIME_MS = 60_000;

    public static void main(String[] args) {
        String classpath = System.getProperty("java.class.path");

        ProcessBuilder processBuilderB = new ProcessBuilder(
                "java", "-cp", classpath, "ChildProcess", "B");
        processBuilderB.redirectErrorStream(true);
        processBuilderB.inheritIO();

        try {
            System.out.println(getInfoProcess());

            Process processB = processBuilderB.start();
            processB.waitFor();

            Thread.sleep(TREE_LIFETIME_MS); // Pausa de 60s para poder ver el pstree
        } catch (IOException | InterruptedException ex) {
            System.out.println("Error en Proceso A: " + ex.getMessage());
        }
    }

    public static String getInfoProcess() {
        ProcessHandle processHandle = ProcessHandle.current();
        long pid = processHandle.pid();
        long ppid = processHandle.parent().isPresent() ? processHandle.parent().get().pid() : 1;
        return String.format("Proceso A | PID: %s | PPID: %s", pid, ppid);
    }
}

/*cd "C:\Users\diarco\Desktop\AXEL\Ej1 JAVA"
mvn clean compile
PARA COMPILAR */
/* 
java -cp target\classes Main 
PARA EJECUTAR
*/