import java.io.IOException;

public class ChildProcess {
    private static final int TREE_LIFETIME_MS = 60_000;

    public static void main(String[] args) {
        if (args.length == 0)
            return;
        String processName = args[0];

        System.out.println("Proceso " + processName + " | " + getInfoProcess());

        // Lógica exacta según el diagrama de tu práctica
        switch (processName) {
            case "B":
                createChild("C", "D");
                break;
            case "C":
                createChild("E");
                break;
            case "D":
                createChild("F", "G");
                break;
            case "E":
                createChild("H", "I");
                break;
            default:
                // F, G, H, I son hojas, no crean hijos
                break;
        }

        // Pausa larga para mantener vivo el árbol y permitir que pstree lo capture
        try {
            Thread.sleep(TREE_LIFETIME_MS);
        } catch (InterruptedException ex) {
            System.out.println("Error en sleep: " + ex.getMessage());
        }
    }

    public static String getInfoProcess() {
        ProcessHandle processHandle = ProcessHandle.current();
        long pid = processHandle.pid();
        long ppid = processHandle.parent().isPresent() ? processHandle.parent().get().pid() : 1;
        return String.format("PID: %s | PPID: %s", pid, ppid);
    }

    private static void createChild(String... hijos) {
        try {
            for (String hijo : hijos) {
                String classpath = System.getProperty("java.class.path");

                ProcessBuilder processBuilder = new ProcessBuilder(
                        "java", "-cp", classpath, "ChildProcess", hijo);
                processBuilder.redirectErrorStream(true);
                processBuilder.inheritIO();
                processBuilder.start();
            }
        } catch (IOException ex) {
            System.out.println("Error al crear hijos: " + ex.getMessage());
        }
    }
}