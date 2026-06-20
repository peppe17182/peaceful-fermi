# Lettore NFC CIE / TS-CNS via iPhone (Relay APDU)

Questo progetto permette di utilizzare l'interfaccia NFC di un iPhone come lettore smart card virtuale collegato in rete locale ad un PC Windows, Linux o macOS. Questo consente di autenticarsi con la **CIE (Carta d'Identità Elettronica 3.0)** o accedere ai dati di una **TS-CNS (Tessera Sanitaria - Carta Nazionale dei Servizi)** (se contactless attiva) usando il software CIEID o il middleware della Pubblica Amministrazione sul PC.

Il flusso dei dati è:
```
Carta (CIE/CNS) --NFC--> iPhone (CoreNFC) --TCP (vpicc)--> PC (vpicc_bridge.py -> driver vpcd) --PC/SC--> Applicazioni PC
```

---

## 1. Come ottenere l'applicazione (.ipa) senza Mac

La build dell'applicazione è completamente automatizzata tramite GitHub Actions. **Non devi configurare alcun certificato o chiave segreta su GitHub.**

1. Carica il codice di questo repository sul tuo account GitHub (puoi fare un fork o un nuovo repository privato).
2. Ad ogni push sul branch principale, si avvierà il workflow che compila l'app ed esporta un file `.ipa` non firmato (unsigned).
3. Vai sulla scheda **Actions** del tuo repository GitHub.
4. Clicca sulla build più recente (es. *Build Unsigned IPA*).
5. Scorri a fondo pagina, sotto **Artifacts** scarica il file **NFCRelay-Unsigned-IPA.zip** ed estrailo per ottenere l'`.ipa`.

---

## 2. Guida al Sideloading su Windows

Dato che l'`.ipa` scaricato non è firmato, devi installarlo sul tuo iPhone firmandolo con il tuo Apple ID gratuito tramite uno strumento di sideloading sul tuo PC Windows.

### Opzione A: TrollStore (Consigliata - Con Supporto NFC Completo)
Se il tuo iPhone ha una versione di iOS compatibile con **TrollStore** (iOS 14.0 - 16.6.1, o alcune versioni di iOS 17.0):
1. Invia il file `NFCRelay-unsigned.ipa` al tuo iPhone (tramite AirDrop, iCloud Drive, Telegram, ecc.).
2. Apri il file con TrollStore sul telefono.
3. TrollStore installerà l'applicazione fake-firmandola localmente. In questo modo **l'entitlement NFC funzionerà al 100%** bypassando le limitazioni dell'account gratuito di Apple.

### Opzione B: Sideloadly o AltStore (Account Apple Developer Free)
Se installi l'app con strumenti come Sideloadly o AltStore da Windows usando un account Apple ID gratuito:
1. Collega il telefono al PC, apri **Sideloadly**, trascina il file `.ipa` e inserisci il tuo Apple ID per installarlo.
2. **Nota Importante sulle Limitazioni di Apple**: Apple limita l'uso dell'entitlement NFC (`com.apple.developer.nfc.readersession.formats`) ai soli account sviluppatore **a pagamento ($99/anno)**. Se provi ad avviare la sessione NFC su un'applicazione firmata con un Apple ID gratuito tramite Sideloadly/AltStore, iOS potrebbe bloccare l'accesso al chip NFC mostrando un errore (es. *NFC Reader Session Not Supported*).
3. **Soluzioni alternative**: Se non hai TrollStore, per usare l'NFC dovrai utilizzare un servizio di firma a pagamento economico (es. *Signulous*, *UDID Registrations*, *MapleSign*, circa $10-$20 all'anno) che registra l'UDID del tuo dispositivo in un account sviluppatore a pagamento, consentendo la firma dell'app con l'entitlement NFC abilitato.

---

## 3. Guida all'Uso del Relay

Una volta installata l'applicazione sul telefono:

1. **Avvia l'app iOS**: 
   - Premi su **Start Server**. L'app mostrerà lo stato `LISTENING` e indicherà il suo indirizzo IP locale (es: `192.168.1.45`).

2. **Configura il PC**:
   - Installa il driver `vpcd` sul tuo PC seguendo le istruzioni in [pc/README.md](file:///C:/Users/alemu/Documents/antigravity/peaceful-fermi/pc/README.md).

3. **Esegui il Bridge**:
   - Apri il terminale (Command Prompt o PowerShell) sul tuo PC e lancia lo script [vpicc_bridge.py](file:///C:/Users/alemu/Documents/antigravity/peaceful-fermi/pc/vpicc_bridge.py) specificando l'IP dell'iPhone:
     ```bash
     python pc/vpicc_bridge.py --phone-ip 192.168.1.45
     ```

4. **Accosta la Carta**:
   - Appoggia la tua CIE 3.0 sul retro dell'iPhone. I comandi APDU del software sul PC verranno trasmessi all'iPhone in tempo reale e vedrai scorrere i log di debug sullo schermo dell'app.
