# Cómo instalar y jugar — Tower Defense Cooperativo

## 1. Cómo instalar el juego (una sola vez)

1. Hacé doble clic en **`TowerDefenseSetup.exe`**.
2. En la pantalla de componentes adicionales:
   - Dejá marcado **Instalar Radmin VPN** (necesario para conectarte con tus amigos).
   - Dejá marcado **Instalar Docker Desktop** solo si vos vas a **crear partidas** (si solo te vas a unir a la partida de un amigo, no lo necesitás).
3. Hacé clic en **Siguiente** → **Instalar** y esperá a que termine de descargar y configurar todo.

---

## 2. Cómo jugar con amigos

### Paso previo: Conectarse a Radmin VPN
1. Abrí **Radmin VPN** y encendelo (el botón grande debe quedar encendido).
2. Uno de los jugadores entra en **Red → Crear red** y elige un nombre y contraseña.
3. Los demás jugadores entran en **Red → Unirse a una red existente** y escriben ese mismo nombre y contraseña.

### Dentro del juego
1. Abrí el juego desde el acceso directo **Tower Defense Cooperative** en tu Escritorio.
2. **Si vos creás la partida (Anfitrión):**
   - Escribí tu nombre, presioná **Crear partida** y esperá unos segundos hasta que aparezca la sala lista.
   - Tocá **Copiar** y pasale ese código (`IP:5000`) a tus amigos.
   - Podés jugar solo o esperar hasta **4 jugadores**. Cuando quieras empezar, presioná **Iniciar partida**.
3. **Si te unís a la partida de un amigo (Invitado):**
   - Escribí tu nombre, pegá el código (`IP:5000`) que te pasó tu amigo y presioná **Unirse**.
4. **Inicio del juego:**
   - Al tocar **Iniciar partida**, aparece una cuenta regresiva (`3, 2, 1, ¡YA!`) y empiezan las 5 oleadas.

---

## 3. Cómo desinstalar el juego

1. Ejecutá **`DesinstalarTowerDefense.exe`** (o buscá **Desinstalar Tower Defense Cooperative** en el Menú Inicio / Configuración de Windows).
2. Confirmá la desinstalación del juego.
3. El desinstalador te va a preguntar si también querés desinstalar **Docker Desktop** y **Radmin VPN** (elegí **Sí** o **No** según prefieras).

---

## Para desarrolladores: compilar el instalador

Para generar `installer\output\TowerDefenseSetup.exe` con Inno Setup 6:

```powershell
ISCC.exe .\installer\TowerDefense.iss
```
