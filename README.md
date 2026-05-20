# intel-platform

B2B lead monitoring and signal detection platform.

System weryfikuje, klasyfikuje i monitoruje bazę leadów biznesowych pod kątem sygnałów sprzedażowych. Zaprojektowany dla rynku B2B (producenci dmuchańców, karuzel, budownictwa modułowego), ale architektura jest neutralna domenowo.

## Status

W aktywnym rozwoju. Obecnie: setup infrastruktury + Faza 1 (import danych z Jitbita).

Plan działania: [`docs/action-plan.md`](docs/action-plan.md)

## Stack

- **Python 3.13** — pipeline, walidatory, raporty
- **MariaDB 10.6** (hosted on Zenbox) — baza `vivcom_intel`
- **LXC** w Proxmox — środowisko runtime
- **MSSQL** (Jitbit) — źródło danych do importu

## Struktura

```
intel-platform/
├── README.md
├── requirements.txt
├── .env.example              # szablon zmiennych (skopiuj do .env, uzupełnij)
├── .gitignore
├── configs/
│   └── .env.example          # docelowo można symlinkować lub trzymać tu
├── docs/
│   └── action-plan.md        # plan fazowy
├── sql/
│   └── migrations/
│       └── 001_initial_schema.sql
├── scripts/                  # standalone skrypty (import, weryfikacja, raporty)
├── intel/                    # właściwy kod modułów (collectors, verifiers)
└── tests/
```

## Uruchomienie (LXC `intel-monitor`)

```bash
# 1. Sklonuj repo
git clone https://github.com/rwojcikviv/intel-platform.git /opt/intel-platform
cd /opt/intel-platform

# 2. Wirtualne środowisko Pythona
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# 3. Konfiguracja sekretów
cp .env.example .env
nano .env   # uzupełnij credentials MariaDB, MSSQL Jitbit itd.

# 4. Apply schema na bazę
mysql -h $DB_HOST -u $DB_USER -p$DB_PASSWORD $DB_NAME --ssl=0 < sql/migrations/001_initial_schema.sql

# 5. Weryfikacja
mysql -h $DB_HOST -u $DB_USER -p$DB_PASSWORD $DB_NAME --ssl=0 -e "SHOW TABLES;"
```

## Konfiguracja sekretów

Wszystkie wrażliwe dane (credentials, klucze API) trzymane w `.env` lokalnie na LXC.
**Nigdy nie commituj `.env` do repo** — `.gitignore` to wymusza.

## Licencja

MIT
