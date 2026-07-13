# README – Bacheloroppgave: Economic MPC for ice temperature control in a curling rink

Dette prosjektet inneholder MATLAB- og Python-filer brukt i bacheloroppgaven om Economic Model Predictive Control (MPC) for temperaturstyring av is i en curlinghall.

Prosjektet er delt inn i to hovedmapper:

```text
data/     # CSV- og MAT-filer
scripts/  # MATLAB- og Python-kode
```

Etter at prosjektet er lastet ned som en ZIP-fil eller klonet lokalt, kan MPC-kodene kjøres fra MATLAB så lenge **Current Folder** er satt til prosjektets rotmappe, altså mappen som inneholder `README.md`, `data/` og `scripts/`.

---

## Kjøring av MPC-kodene

Kjør ønsket MPC-versjon fra MATLAB Command Window:

```matlab
run('scripts/MPC_v10.m')
```

for hovedversjonen med AR(1)-støy.

```matlab
run('scripts/MPC_v10_UtenStoy.m')
```

for versjonen uten AR(1)-støy.

```matlab
run('scripts/MPC_v10_flereBookinger.m')
```

for scenarioet med flere bookinger på `2-lane`.

---

## Hovedfiler: tre MPC-versjoner

| Filnavn | Beskrivelse |
|---|---|
| `scripts/MPC_v10.m` | Hovedversjonen av MPC-koden med AR(1)-støy |
| `scripts/MPC_v10_UtenStoy.m` | Samme MPC-oppsett, men uten AR(1)-støy |
| `scripts/MPC_v10_flereBookinger.m` | MPC-versjon med flere bookinger på `2-lane` |

---

## 1. `scripts/MPC_v10.m` – hovedversjon med støy

Dette er hovedversjonen av MPC-simuleringen. Den inkluderer AR(1)-støy i prosessmodellsimuleringen for å gjøre simuleringen mer realistisk.

Denne filen bruker fire hovedinputfiler:

### `data/plant_model_lane2_3input.mat`

Inneholder den håndtunede 3-input prosessmodellen og normaliseringsparametere.

Filen inneholder blant annet:

```matlab
sys_tf
mu_u
sig_u
mu_y
sig_y
Ts
```

`sys_tf` er prosessmodellen som beskriver sammenhengen mellom:

1. ventilsetpunkt → istemperatur
2. halltemperatur → istemperatur
3. pumpefrekvens → istemperatur

---

### `data/MergedData_NEW.csv`

Dette er datasettet som brukes i de endelige MPC-simuleringene.

Filen dekker perioden:

```text
08.02.2026 til 26.03.2026
```

Datasettet brukes blant annet til historiske setpunkter, halltemperatur, pumpefrekvens, istemperaturmålinger, kompressor-/viftesignaler og glycoltemperaturer.

Denne kortere perioden brukes i MPC-kodene for å redusere kjøretiden.

---

### `data/2026_simulerte_bookinger.csv`

Dette er standard bookingfil for hovedscenarioet.

Filen inneholder:

```text
dato
starttid
sluttid
brukergruppe
lane
```

MPC-koden filtrerer ut bookinger der `lane = 2-lane` og lager temperaturreferanser basert på brukergruppen.

---

### `data/strompris_lane2_2026.csv`

Dette er strømprisfilen som brukes til å beregne energikostnad i MPC-simuleringen.

Filen inneholder minst:

```text
time
price
```

---

## 2. `scripts/MPC_v10_UtenStoy.m` – versjon uten støy

Denne filen er lik hovedversjonen, men AR(1)-støyen er fjernet.

Det betyr at simulert istemperatur beregnes uten leddet:

```matlab
d_noise(k)
```

Denne versjonen bruker samme hovedinputfiler som `MPC_v10.m`.

---

## 3. `scripts/MPC_v10_flereBookinger.m` – scenario med flere bookinger

Denne filen brukes for et alternativt scenario med flere bookinger på `2-lane`.

Den bruker samme type inputfiler som hovedversjonen, men med en annen bookingfil:

```text
data/Flere_2026_simulerte_bookinger.csv
```

Denne bookingfilen har høyere sannsynlighet for at bookinger legges på `2-lane`.

---

## Andre viktige filer

### `scripts/Hand_tuned_model_V1.m`

Dette scriptet ble brukt til å lage prosessmodellen:

```text
data/plant_model_lane2_3input.mat
```

Scriptet leser inn:

```text
data/MergedData_NEW_V2.csv
```

`Hand_tuned_model_V1.m` trenger ikke kjøres før MPC-kodene, fordi `.mat`-filen allerede er lagt ved i `data/`.

---

### `data/MergedData_NEW_V2.csv`

Dette er et større datasett enn `MergedData_NEW.csv`.

Filen dekker perioden:

```text
23.01.2026 til 16.04.2026
```

Forskjellen er:

- `MergedData_NEW_V2.csv` brukes til å lage prosessmodellen i `Hand_tuned_model_V1.m`
- `MergedData_NEW.csv` brukes i de endelige MPC-simuleringene

---

### `scripts/Strompriser_2026.m`

Dette scriptet ble brukt til å lage:

```text
data/strompris_lane2_2026.csv
```

Scriptet trenger ikke kjøres før MPC-kodene, fordi strømprisfilen allerede er lagt ved i `data/`.

Ved ny kjøring kreves internettforbindelse.

---

### `scripts/Bookingsim.py`

Python-script som ble brukt til å generere:

```text
data/2026_simulerte_bookinger.csv
```

---

### `scripts/Flere_sim_bookinger.py`

Python-script som ble brukt til å generere:

```text
data/Flere_2026_simulerte_bookinger.csv
```

---

### `scripts/Energimodell_Valideringsskript.m`

Script for visualisering og validering av energimodellen.

Scriptet leser `data/MergedData_NEW.csv`, bygger samme lineære energimodell som brukes i MPC-kodene, utfører 5-fold kryssvalidering og lager figurer for predikert vs observert energiproxy.

Scriptet er ikke nødvendig for å kjøre MPC-simuleringene, men er inkludert som dokumentasjon av energimodellen.

---

## Temperaturgrupper

| Gruppe | Temperaturintervall | Referanse |
|---|---:|---:|
| Idle | -3.90 °C til -3.70 °C | -3.80 °C |
| Hobby | -4.30 °C til -4.10 °C | -4.20 °C |
| Elite | -4.50 °C til -4.30 °C | -4.40 °C |

Hobby og elite får forkjøling før bookingstart.

---

## OBS: MATLAB-toolboxer

Hvis kodene ikke kjører, kan det skyldes at nødvendige MATLAB-toolboxer mangler eller at MATLAB ikke får tilgang til lisensen.

For å kjøre MPC-kodene bør følgende MATLAB-toolboxer være tilgjengelige:

```text
Required MATLAB toolboxes:
- Control System Toolbox
- Optimization Toolbox
- Statistics and Machine Learning Toolbox
```

### Control System Toolbox

Brukes blant annet til:

```matlab
tf
lsim
step
ss
c2d
ssdata
```

### Optimization Toolbox

Brukes til QP-løsningen i MPC-en:

```matlab
quadprog
optimoptions
```

### Statistics and Machine Learning Toolbox

Brukes blant annet til:

```matlab
corr
```

I koden med AR(1)-støy brukes `corr` for å beregne lag-1-korrelasjon i residualene.

---

## Sjekke toolboxes i MATLAB

For å se hvilke toolboxes som er installert:

```matlab
ver
```

For å sjekke lisensstatus:

```matlab
license('test','Control_Toolbox')
license('test','Optimization_Toolbox')
license('test','Statistics_Toolbox')
```

Resultat `1` betyr at lisensen er tilgjengelig. Resultat `0` betyr at MATLAB ikke har tilgang til den aktuelle toolboxen.

---

## Vanlige feil

### MATLAB finner ikke filen

Sjekk at MATLAB sin **Current Folder** er satt til prosjektets rotmappe, altså mappen som inneholder:

```text
README.md
data/
scripts/
```

Hvis filene ligger i iCloud, OneDrive eller lignende, må de være lastet ned lokalt før MATLAB kan lese dem.

---

### Feil bookingfil i scenario med flere bookinger

For `MPC_v10_flereBookinger.m` skal bookingfilen være:

```matlab
bookingFile = fullfile(dataDir, 'Flere_2026_simulerte_bookinger.csv');
```

Hvis den peker til:

```matlab
bookingFile = fullfile(dataDir, '2026_simulerte_bookinger.csv');
```

kjøres standardscenarioet i stedet.

---

## Output fra MPC-kodene

Når en MPC-kode kjøres, printes blant annet:

- energimodell og R²
- antall bookinger
- strømprisstatistikk
- simuleringstid og QP-feil
- energikostnad
- besparelse
- RMSE mot referanse
- tid innenfor temperaturintervall
- gruppespesifikke KPI-er

Kodene genererer også figurer for blant annet:

- istemperatur
- ventilsetpunkt
- pumpefrekvens
- strømpris
- kumulativ energikostnad
- step-respons
- gruppespesifikke KPI-er

---

## Kommentar

Koden er utviklet som del av en bacheloroppgave og er primært ment for simulering og analyse. Resultatene avhenger av den håndtunede prosessmodellen, bookingdataene, strømprisdataene og antakelsene i energimodellen.
