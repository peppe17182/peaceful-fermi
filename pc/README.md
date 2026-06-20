# Componente PC: Setup di `vpcd` e del Bridge Python

Questa cartella contiene lo script bridge per collegare l'iPhone (che funge da relay APDU) al driver **vpcd** (Virtual Card Reader) del progetto **vsmartcard**.

## 1. Installazione di `vpcd` sul PC

Il componente `vpcd` si presenta al sistema operativo come un lettore smart card virtuale tramite le API standard PC/SC.

### Su Windows
1. Scarica l'installer precompilato o i file binari di `vsmartcard` (driver `vpcd`) dal repository ufficiale: [github.com/frankmorgner/vsmartcard/releases](https://github.com/frankmorgner/vsmartcard/releases).
2. Segui le istruzioni di installazione del driver UMDF2.
3. Il driver avvierà un servizio di sistema che si mette in ascolto sulla porta standard TCP `35963` su `127.0.0.1` in attesa di una smart card virtuale (`vpicc`).

### Su Linux (Ubuntu/Debian)
1. Installa il demone smart card:
   ```bash
   sudo apt update
   sudo apt install pcscd libpcsclite-dev python3
   ```
2. Installa o compila il modulo `vpcd` seguendo la documentazione ufficiale di `vsmartcard`:
   - Configura `/etc/reader.conf.d/vpcd` o il file di configurazione pcscd per registrare il lettore virtuale.
   - Di default, il driver si metterà in ascolto sulla porta `35963` su `127.0.0.1`.

---

## 2. Esecuzione del Bridge di Rete (`vpicc_bridge.py`)

Poiché il driver `vpcd` ascolta localmente su `127.0.0.1` per motivi di sicurezza, l'iPhone in rete locale non può connettersi ad esso direttamente. Lo script `vpicc_bridge.py` fa da intermediario (bridge) convogliando i pacchetti TCP in entrambe le direzioni.

È possibile eseguire il bridge in due modalità:

### A. Modalità Client (Consigliata)
L'iPhone fa da Server TCP sulla sua porta locale 35963 (l'IP viene mostrato sullo schermo dell'app). Il PC si connette sia all'iPhone che a `vpcd`:

```bash
python vpicc_bridge.py --phone-ip <IP_DELL_IPHONE>
```
*Sostituisci `<IP_DELL_IPHONE>` con l'indirizzo IP mostrato sull'applicazione iOS (es. `192.168.1.45`).*

### B. Modalità Server (Inversa)
Se l'iPhone non può fare da server (es. restrizioni del firewall iOS/Wi-Fi), puoi configurare il bridge sul PC per fare da server. L'iPhone dovrà essere configurato per connettersi all'IP del PC:

```bash
python vpicc_bridge.py --server --phone-port 35963
```
Una volta avviato, connetti l'iPhone inserendo l'IP del PC nelle impostazioni dell'app.

---

## 3. Verifica del Funzionamento

Una volta che il bridge indica che entrambi i lati sono connessi (`Connected to iPhone` e `Connected to vpcd`), puoi verificare che il lettore virtuale sia visibile ed operativo:

### Su Windows
Utilizza l'utility **CIE ID** ufficiale italiana o un tool generico PC/SC (es. `Smart Card ToolSet PRO`) per verificare che un lettore virtuale `Virtual Smart Card Reader 0` sia registrato e che la carta (CIE/TS-CNS) inserita via NFC sia letta correttamente.

### Su Linux
Usa `pcsc_scan` per monitorare lo stato del lettore virtuale:
```bash
pcsc_scan
```
Dovresti vedere apparire il lettore virtuale e, non appena appoggi la CIE/CNS all'iPhone, vedrai l'ATR della carta riflesso sul terminale del PC.
